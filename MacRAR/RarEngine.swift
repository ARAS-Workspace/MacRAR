import Foundation

// MARK: - Model

enum ArchiveKind {
    case rar        // read with 7-Zip, written (optionally) with the user's RAR tool
    case other      // 7-Zip (zip, 7z, tar, gz, xz, bz2, zst, iso, cab, ...)
}

struct ArchiveEntry {
    var name: String            // full path inside the archive
    var isDirectory: Bool
    var size: Int64 = 0
    var packedSize: Int64 = 0
    var ratio: String = ""
    var mtime: String = ""
    var crc: String = ""
    var encrypted: Bool = false
    var attributes: String = ""
    var compression: String = ""

    var displayName: String { (name as NSString).lastPathComponent }
    var parentPath: String { (name as NSString).deletingLastPathComponent }
}

struct ArchiveInfo {
    var path: String
    var kind: ArchiveKind
    var details: String
    var entries: [ArchiveEntry]
    var headersEncrypted: Bool = false
    /// 7-Zip's name for the format ("7z", "zip", "tar", "Rar5", …); the type passed back when adding files
    var type: String = ""
    /// A tar inside a compression stream (tar.gz, tar.xz, …)
    var tarCompressed: Bool = false

    var hasEncryptedFiles: Bool { headersEncrypted || entries.contains { $0.encrypted } }
    var isSolid: Bool { details.contains("solid") }
    var fileCount: Int { entries.filter { !$0.isDirectory }.count }
    var totalSize: Int64 { entries.reduce(0) { $0 + $1.size } }
    var totalPacked: Int64 { entries.reduce(0) { $0 + $1.packedSize } }
    var topLevelNames: [String] {
        var seen = Set<String>(); var out: [String] = []
        for entry in entries {
            let top = entry.name.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? entry.name
            if seen.insert(top).inserted { out.append(top) }
        }
        return out
    }
    /// Are adding / deleting files supported?
    var supportsModification: Bool { !tarCompressed }
}

struct RarResult {
    let code: Int32
    let output: String
    var cancelled: Bool = false
    var passwordProblem: Bool = false
    var notAnArchive: Bool = false

    var ok: Bool { code == 0 || code == 1 }
    var wrongPassword: Bool {
        passwordProblem || code == 11 || output.contains("Incorrect password") || output.contains("Wrong password")
            || output.contains("Cannot open encrypted archive")
    }
    var notArchive: Bool {
        notAnArchive || output.contains("is not RAR archive") || output.contains("Cannot open the file as archive")
    }

    /// Short error text to show the user
    var errorSummary: String {
        let lines = output.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\u{8}", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter {
                !$0.hasPrefix("UNRAR ") && !$0.hasPrefix("RAR ") && !$0.hasPrefix("Trial version") && !$0.hasPrefix("Evaluation copy")
            }
        let interesting = lines.filter { line in
            line.contains("error") || line.contains("Error") || line.contains("ERROR") || line.contains("Incorrect")
                || line.contains("Wrong")
                || line.contains("failed") || line.contains("Failed") || line.contains("not RAR") || line.contains("Cannot")
                || line.contains("Can not")
                || line.contains("No files") || line.contains("Checksum") || line.contains("CRC") || line.contains("denied")
                || line.contains("Total errors")
                || line.contains("Unexpected end") || line.contains("Data Error") || line.contains("Unsupported")
        }
        let chosen = interesting.isEmpty ? Array(lines.suffix(6)) : Array(interesting.suffix(8))
        return chosen.joined(separator: "\n")
    }
}

extension RarResult {
    /// The 7-Zip library's outcome in the shape the operations already handle.
    init(_ outcome: SevenZipBridge.Outcome) {
        var lines = outcome.messages
        if !outcome.error.isEmpty, !lines.contains(where: { $0.contains(outcome.error) }) {
            lines.append("ERROR: " + outcome.error)
        }
        let code: Int32
        switch outcome.code {
        case .ok: code = 0
        case .warning: code = 1
        default: code = 2
        }
        self.init(code: code, output: lines.joined(separator: "\n"),
                  cancelled: outcome.code == .cancelled,
                  passwordProblem: outcome.code.isPasswordProblem,
                  notAnArchive: outcome.code == .notArchive)
    }
}

// MARK: - Format info

enum Formats {
    /// Extensions the app can open
    static let openable: Set<String> = [
        "rar", "zip", "7z", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst", "tzst", "lz4", "lzma", "tlz", "z",
        "cab", "arj", "lzh", "lha", "cpio", "iso", "wim", "swm", "esd", "deb", "rpm", "jar", "war", "ear", "apk", "ipa",
        "xpi", "crx", "nupkg", "msi", "chm", "udf", "vhd", "vhdx", "vmdk", "qcow2", "squashfs", "cramfs", "ext", "ext2", "ext3", "ext4",
        "hfs", "hfsx", "dmg", "xar", "pkg", "ar", "a", "lib", "zipx", "br", "001", "lz", "uue", "bzip2", "gzip", "sfx",
    ]

    static func isArchive(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        if openable.contains(ext) { return true }
        return ext.range(of: #"^r\d\d$"#, options: .regularExpression) != nil
    }

    static func kind(of path: String) -> ArchiveKind {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "rar" || ext.range(of: #"^r\d\d$"#, options: .regularExpression) != nil { return .rar }
        return .other
    }

    static func isMultiVolume(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name.range(of: #"\.part\d+\.rar$|\.\d{3}$|\.r\d\d$|\.z\d\d$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isTarCompressed(_ path: String) -> Bool {
        let lower = (path as NSString).lastPathComponent.lowercased()
        let ext = (lower as NSString).pathExtension
        if ["tgz", "tbz", "tbz2", "txz", "tzst", "tlz"].contains(ext) { return true }
        for suffix in [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tar.lz4", ".tar.z", ".tar.lzma", ".tar.lz", ".tar.br"]
        where lower.hasSuffix(suffix) {
            return true
        }
        return false
    }
}

// MARK: - Listing

enum ArchiveReader {
    enum ListOutcome {
        case ok(ArchiveInfo)
        case wrongPassword
        case error(RarResult)
    }

    static func list(_ path: String, password: String?) -> ListOutcome {
        switch SevenZipBridge.list(path, password: password) {
        case .failure(let failure):
            if failure.code.isPasswordProblem { return .wrongPassword }
            return .error(RarResult(code: 2, output: "ERROR: " + failure.message, notAnArchive: failure.code == .notArchive))
        case .success(let listing):
            return .ok(info(from: listing, path: path))
        }
    }

    private static let modifiedFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// RAR by what 7-Zip found inside ("Rar", "Rar5"), not by the name: a self-extracting x.sfx is RAR and goes to rar
    /// for adding and deleting, a ZIP named x.rar is not. The name decides only when 7-Zip names no type.
    static func kind(type: String, path: String) -> ArchiveKind {
        switch type.lowercased() {
        case "rar", "rar5": return .rar
        case "": return Formats.kind(of: path)
        default: return .other
        }
    }

    private static func info(from listing: SevenZipBridge.Listing, path: String) -> ArchiveInfo {
        let entries = listing.items.map { item -> ArchiveEntry in
            let name = item.path.hasSuffix("/") ? String(item.path.dropLast()) : item.path
            var entry = ArchiveEntry(name: name, isDirectory: item.isDirectory)
            entry.size = Int64(clamping: item.size)
            entry.packedSize = Int64(clamping: item.packedSize)
            if entry.size > 0, entry.packedSize > 0 { entry.ratio = "\(Int(Double(entry.packedSize) * 100 / Double(entry.size)))%" }
            entry.mtime = item.modified.map { modifiedFormat.string(from: $0) } ?? ""
            entry.crc = item.crc.map { String(format: "%08X", $0) } ?? ""
            entry.encrypted = item.encrypted
            entry.compression = item.method
            return entry
        }

        let tarCompressed = !listing.container.isEmpty && listing.type.lowercased() == "tar"
        var parts: [String]
        if tarCompressed {
            parts = ["tar + \(listing.container.lowercased())"]
        } else {
            switch listing.type.lowercased() {
            case "": parts = [loc.t("archive_format_generic")]
            case "rar5": parts = ["RAR 5"]
            case "rar": parts = ["RAR 4"]
            case "7z": parts = ["7z"]
            default: parts = [listing.type.uppercased()]
            }
        }
        if listing.solid { parts.append("solid") }
        if listing.volumes > 1 { parts.append("\(listing.volumes) volume") }

        var info = ArchiveInfo(
            path: path, kind: kind(type: listing.type, path: path), details: parts.joined(separator: ", "), entries: entries)
        info.headersEncrypted = listing.headersEncrypted
        info.type = listing.type
        info.tarCompressed = tarCompressed
        return info
    }
}

// MARK: - RAR tool runner

enum RarRunner {
    /// Password arguments for rar (a / d). CAUTION: given "-p-", rar uses the "-" character as the password;
    /// so no switch at all is passed when there is no password.
    static func rarPasswordArgs(_ pw: String?, encryptHeaders: Bool = false) -> [String] {
        guard let pw, !pw.isEmpty else { return [] }
        return [(encryptHeaders ? "-hp" : "-p") + pw]
    }

    static func makeProcess(_ args: [String], cwd: String?) -> Process {
        let process = Process()
        process.executableURL = RarTools.rarURL ?? URL(fileURLWithPath: "/nonexistent/rar")
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        process.environment = env
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        process.standardInput = FileHandle.nullDevice
        return process
    }
}

// MARK: - RAR tool job (progress tracking)

final class RarJob {
    enum Event {
        case file(String)       // a new file is being processed
        case progress(Int)      // percentage (overall)
    }

    private var process: Process?
    private let queue = DispatchQueue(label: "macrar.job")
    private var buffer = Data()
    private var output = ""
    private(set) var cancelled = false
    var onEvent: ((Event) -> Void)?   // called on the main queue

    private static let verbs = [
        "Extracting", "Adding", "Testing", "Updating", "Creating", "Deleting", "Compressing", "Fresh", "Calculating",
    ]
    // swiftlint:disable force_try
    private static let percentRegex = try! NSRegularExpression(pattern: #"(\d{1,3})%"#)
    private static let tailRegex = try! NSRegularExpression(pattern: #"\s*(\d{1,3}%|OK|Failed|CRC failed)\s*$"#)
    // swiftlint:enable force_try

    func start(_ args: [String], cwd: String? = nil, completion: @escaping (RarResult) -> Void) {
        let process = RarRunner.makeProcess(args, cwd: cwd)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let self else { return }
            self.queue.async { self.consume(data) }
        }
        process.terminationHandler = { [weak self] proc in
            handle.readabilityHandler = nil
            let rest = handle.readDataToEndOfFile()
            guard let self else { return }
            self.queue.async {
                self.consume(rest)
                self.flushPartial()
                let result = RarResult(code: proc.terminationStatus, output: self.output, cancelled: self.cancelled)
                DispatchQueue.main.async { completion(result) }
            }
        }
        self.process = process
        do { try process.run() } catch {
            DispatchQueue.main.async {
                completion(RarResult(code: -1, output: loc.t("could_not_run", error.localizedDescription)))
            }
        }
    }

    func cancel() {
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            // swiftlint:disable:next optional_data_string_conversion
            let line = String(decoding: lineData, as: UTF8.self)
            output += Self.lastSegment(line, keepAll: true) + "\n"
            parse(Self.lastSegment(line))
        }
        // Progress updated with backspaces (\u{8}) before a newline arrives: read only the latest state
        if !buffer.isEmpty {
            // swiftlint:disable:next optional_data_string_conversion
            let tail = String(decoding: buffer.suffix(512), as: UTF8.self)
            parse(Self.lastSegment(tail))
            // Keep the buffer from growing on a long single file: drop everything before the last backspace run
            if buffer.count > 64 * 1024, let cut = buffer.lastIndex(of: 0x08) {
                buffer.removeSubrange(buffer.startIndex...cut)
            }
        }
    }

    /// What a line overwritten with backspaces finally shows on screen
    private static func lastSegment(_ s: String, keepAll: Bool = false) -> String {
        let parts = s.components(separatedBy: "\u{8}").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if keepAll {
            // For the log: drop the repeated percentage fragments, keep the meaningful text
            let meaningful = parts.filter {
                $0.trimmingCharacters(in: .whitespaces).range(of: #"^\d{1,3}%( \d+)?$"#, options: .regularExpression) == nil
            }
            return meaningful.joined(separator: " ")
        }
        return parts.last ?? ""
    }

    private func flushPartial() {
        if !buffer.isEmpty {
            // swiftlint:disable:next optional_data_string_conversion
            output += String(decoding: buffer, as: UTF8.self).replacingOccurrences(of: "\u{8}", with: "")
            buffer.removeAll()
        }
    }

    private func parse(_ raw: String) {
        let line = raw.replacingOccurrences(of: "\u{8}", with: "").trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        var pct: Int?
        var fileName: String?

        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let m = Self.percentRegex.matches(in: line, range: full).last {
            pct = Int(ns.substring(with: m.range(at: 1)))
        }
        var candidate: String?
        if line.hasPrefix("... ") {
            candidate = String(line.dropFirst(4))        // file continued after a volume change
        } else {
            for verb in Self.verbs where line.hasPrefix(verb + " ") {
                let rest = String(line.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix("from ") || rest.hasPrefix("archive ") { break }
                candidate = rest
                break
            }
        }
        if let candidate {
            var name = candidate.trimmingCharacters(in: .whitespaces)
            while let m = Self.tailRegex.firstMatch(in: name, range: NSRange(location: 0, length: (name as NSString).length)) {
                name = (name as NSString).substring(to: m.range.location)
            }
            fileName = name.trimmingCharacters(in: .whitespaces)
        }

        guard fileName != nil || pct != nil, let onEvent else { return }
        DispatchQueue.main.async {
            if let f = fileName, !f.isEmpty { onEvent(.file(f)) }
            if let pct { onEvent(.progress(pct)) }
        }
    }
}

// MARK: - Helpers

/// Temporary folders created during the session; removed on quit
enum TempDirs {
    private static var created: [String] = []
    private static let lock = NSLock()
    static func make(_ prefix: String = "Archiver") -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)").path
        lock.lock(); created.append(path); lock.unlock()
        return path
    }
    static func cleanupAll() {
        lock.lock(); let list = created; created = []; lock.unlock()
        for path in list { try? FileManager.default.removeItem(atPath: path) }
    }
}

enum Fmt {
    static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()
    static func size(_ byteCount: Int64) -> String { bytes.string(fromByteCount: byteCount) }
}

func isDirectoryPath(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
}

func uniquePath(_ path: String, taken: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
    guard taken(path) else { return path }
    let ns = path as NSString
    let dir = ns.deletingLastPathComponent
    let ext = ns.pathExtension
    let base = (ns.deletingPathExtension as NSString).lastPathComponent
    var i = 2
    while true {
        let candidate = (dir as NSString).appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
        if !taken(candidate) { return candidate }
        i += 1
    }
}
