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
    /// The switch that has rar ask for the password, which RarJob writes to its standard input. Given on the command
    /// line it reached rar decomposed, as Process passes arguments, so a password holding letters such as ü or ş locked
    /// the archive with other bytes than the ones typed, and it showed in the process list. No switch at all when there
    /// is no password: given "-p-", rar takes "-" for the password.
    static func passwordSwitch(_ pw: String?, encryptHeaders: Bool = false) -> [String] {
        guard let pw, !pw.isEmpty else { return [] }
        return [encryptHeaders ? "-hp" : "-p"]
    }

    /// rar's add command for the chosen items: each under its own name (-ep1), without asking (-y). Never -r: with it rar
    /// reads every chosen file name as a mask for the folders below it, so it also added (and with -df deleted)
    /// same-named files nobody chose, and it missed a file whose name holds letters such as ü or ş composed on disk, as
    /// Process hands names over decomposed and rar compares bytes. A chosen folder is added with everything in it all the
    /// same.
    static let addArguments = ["a", "-ep1", "-y"]

    /// Names inside an archive, written for rar to read with "-scfl @list": UTF-8, one a line, byte for byte as the archive
    /// holds them. Given as arguments they reached rar decomposed, as Process passes them, so a name stored with letters
    /// such as ü or ş composed matched nothing. The list's argument, and the folder to remove once rar is done.
    static func nameList(_ names: [String]) throws -> (argument: String, folder: String) {
        let folder = TempDirs.make("rar-names")
        let list = (folder as NSString).appendingPathComponent("names.txt")
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try Data(names.map { $0 + "\n" }.joined().utf8).write(to: URL(fileURLWithPath: list))
        return ("@" + list, folder)
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

// MARK: - RAR tool output

/// What rar prints while it works, read into progress events however the bytes arrive. rar rewrites the end of a line
/// with backspaces: "Adding <file>" is followed on the same line by its percentages ("  0%", "  1%"…) and the line ends
/// only with "OK", while the pipe hands over whatever rar has written so far. The text before a line's first backspace
/// names the file and its last piece is the percentage. The percentage never goes back while the same file is named
/// (rar sweeps a packed file's share once more); a new name, such as the recovery record, counts on its own.
struct RarOutput {
    /// The finished lines as they ended up on screen, without the percentages: what a failed run reports
    private(set) var log = ""
    /// The line rar is still writing
    private var line = Data()
    private var file: String?
    private var percent = -1

    private static let verbs = [
        "Extracting", "Adding", "Testing", "Updating", "Creating", "Deleting", "Compressing", "Fresh", "Calculating",
    ]
    // swiftlint:disable force_try
    private static let percentRegex = try! NSRegularExpression(pattern: #"^(\d{1,3})%( \d+)?$"#)
    private static let tailRegex = try! NSRegularExpression(pattern: #"\s*(\d{1,3}%|OK|Failed|CRC failed)\s*$"#)
    // swiftlint:enable force_try

    /// The events in `data`, read after everything that came before it.
    mutating func read(_ data: Data) -> [RarJob.Event] {
        line.append(data)
        var events: [RarJob.Event] = []
        while let newline = line.firstIndex(of: 0x0A) {
            let text = Self.text(line[line.startIndex..<newline])
            line.removeSubrange(line.startIndex...newline)
            log += Self.screen(text) + "\n"
            events += parse(text, finished: true)
        }
        guard !line.isEmpty else { return events }
        events += parse(Self.text(line), finished: false)
        // A long run rewrites the percentage many times: keep the start of the line, which names the file, and the latest
        // state
        if line.count > 64 * 1024, let first = line.firstIndex(of: 0x08), let last = line.lastIndex(of: 0x08), first < last {
            line.removeSubrange(line.index(after: first)...last)
        }
        return events
    }

    /// The end of the output: a line rar left without a newline goes to the log as well.
    mutating func finish() {
        guard !line.isEmpty else { return }
        log += Self.screen(Self.text(line))
        line.removeAll()
    }

    private mutating func parse(_ text: String, finished: Bool) -> [RarJob.Event] {
        let pieces = Self.pieces(of: text)
        guard let head = pieces.first else { return [] }
        var events: [RarJob.Event] = []
        let rewritten = text.contains("\u{8}")
        // A name is whole once something follows it: rar pads it with the spaces its percentage writes over
        if finished || rewritten || text.hasSuffix("    "),
           let named = Self.name(in: head, endsWithStatus: finished && !rewritten), !continues(named) {
            file = named.name
            percent = -1
            events.append(.file(named.name))
        }
        // The latest percentage, also when the line has already ended with OK
        if let value = pieces.reversed().lazy.compactMap(Self.percentage).first, value > percent {
            percent = value
            events.append(.progress(value))
        }
        return events
    }

    /// Whether a line names the file already named: the same name, or the file going on in the next volume, which rar
    /// names without its folder
    private func continues(_ named: (name: String, nextVolume: Bool)) -> Bool {
        guard let file else { return false }
        return file == named.name || (named.nextVolume && file.hasSuffix("/" + named.name))
    }

    /// The file a line names before its first backspace: "Adding <file>", or "... <file>" when a file goes on in the
    /// next volume. None for the archive itself ("Creating archive", "Deleting from") or any other line. A line that
    /// ends with its status instead of rewriting it ("Adding <file>  OK", from older rar versions) loses that status;
    /// otherwise a name may well end with "100%" or "OK" itself.
    private static func name(in head: String, endsWithStatus: Bool) -> (name: String, nextVolume: Bool)? {
        let text = head.trimmingCharacters(in: .whitespaces)
        var candidate: String?
        let nextVolume = text.hasPrefix("... ")
        if nextVolume {
            candidate = String(text.dropFirst(4))
        } else if let verb = verbs.first(where: { text.hasPrefix($0 + " ") }) {
            let rest = text.dropFirst(verb.count).trimmingCharacters(in: .whitespaces)
            guard !rest.hasPrefix("from "), !rest.hasPrefix("archive ") else { return nil }
            candidate = rest
        }
        guard var name = candidate else { return nil }
        while endsWithStatus, let match = tailRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
            name = (name as NSString).substring(to: match.range.location)
        }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : (name, nextVolume)
    }

    private static func percentage(in piece: String) -> Int? {
        let text = piece.trimmingCharacters(in: .whitespaces)
        guard let match = percentRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }

    /// A line cut where rar wrote backspaces, without the empty pieces
    private static func pieces(of text: String) -> [String] {
        text.components(separatedBy: "\u{8}").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// What a line finally shows, without the percentages it went through
    private static func screen(_ text: String) -> String {
        pieces(of: text).filter { percentage(in: $0) == nil }.joined(separator: " ")
    }

    private static func text(_ bytes: Data) -> String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: bytes, as: UTF8.self)
    }
}

// MARK: - RAR tool job (progress tracking)

final class RarJob {
    enum Event: Equatable {
        case file(String)       // a new file is being processed
        case progress(Int)      // percentage (overall)
    }

    private var process: Process?
    private let queue = DispatchQueue(label: "macrar.job")
    private var reader = RarOutput()
    private(set) var cancelled = false
    var onEvent: ((Event) -> Void)?   // called on the main queue

    /// `password` answers the question RarRunner.passwordSwitch makes rar ask, byte for byte as typed.
    func start(_ args: [String], cwd: String? = nil, password: String? = nil, completion: @escaping (RarResult) -> Void) {
        let process = RarRunner.makeProcess(args, cwd: cwd)
        if let password {
            // rar reads one line, whatever the command. Written before rar starts, the pipe holds it until rar asks, and
            // nothing is ever written to a rar that has already gone, which would end the app with SIGPIPE
            let input = Pipe()
            try? input.fileHandleForWriting.write(contentsOf: Data((password + "\n").utf8))
            try? input.fileHandleForWriting.close()
            process.standardInput = input
        }
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
                self.reader.finish()
                let result = RarResult(code: proc.terminationStatus, output: self.reader.log, cancelled: self.cancelled)
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
        let events = reader.read(data)
        guard !events.isEmpty, let onEvent else { return }
        DispatchQueue.main.async { events.forEach(onEvent) }
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
