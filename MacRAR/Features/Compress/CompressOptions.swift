import AppKit

enum ArchiveFormat: Int, CaseIterable {
    case rar5 = 0, sevenZip = 2, zip = 3, tar = 4, tgz = 5, txz = 6, tbz2 = 7

    var title: String {
        switch self {
        case .rar5: return RarTools.available ? "RAR 5" : loc.t("format_rar5")
        case .sevenZip: return "7z"
        case .zip: return "ZIP"
        case .tar: return loc.t("format_tar")
        case .tgz: return "TAR.GZ"
        case .txz: return "TAR.XZ"
        case .tbz2: return "TAR.BZ2"
        }
    }
    var ext: String {
        switch self {
        case .rar5: return "rar"
        case .sevenZip: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        case .tgz: return "tar.gz"
        case .txz: return "tar.xz"
        case .tbz2: return "tar.bz2"
        }
    }
    var isRar: Bool { self == .rar5 }
    var isTarFamily: Bool { self == .tar || self == .tgz || self == .txz || self == .tbz2 }
    var supportsPassword: Bool { isRar || self == .sevenZip || self == .zip }
    var supportsEncryptNames: Bool { isRar || self == .sevenZip }
    var supportsSolid: Bool { isRar || self == .sevenZip }
    var supportsRecovery: Bool { isRar }
    var supportsSFX: Bool { isRar }
    var supportsVolumes: Bool { isRar || self == .sevenZip || self == .zip }
    var supportsLevel: Bool { self != .tar }
    var supportsAppend: Bool { !isTarFamily || self == .tar }

    static func detect(fromPath path: String) -> ArchiveFormat? {
        let lower = path.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") { return .tgz }
        if lower.hasSuffix(".tar.xz") || lower.hasSuffix(".txz") { return .txz }
        if lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tbz2") || lower.hasSuffix(".tbz") { return .tbz2 }
        switch (lower as NSString).pathExtension {
        case "rar": return .rar5
        case "7z": return .sevenZip
        case "zip": return .zip
        case "tar": return .tar
        default: return nil
        }
    }

    /// Changes the path's archive extension to match this format
    func replacingExtension(in path: String) -> String {
        var base = path
        let lower = base.lowercased()
        for suf in [".tar.gz", ".tar.xz", ".tar.bz2", ".tgz", ".txz", ".tbz2", ".tbz", ".rar", ".sfx", ".7z", ".zip", ".tar"]
        where lower.hasSuffix(suf) {
            base = String(base.dropLast(suf.count)); break
        }
        return base + "." + ext
    }
}

struct CompressOptions {
    var archivePath: String
    var format: ArchiveFormat = .rar5
    var level: Int = 3                 // 0-5
    var password: String?
    var encryptNames: Bool = false
    var solid: Bool = false
    var recoveryRecord: Bool = false
    var volumeSize: String?      // e.g. "100M"
    var sfx: Bool = false
    var deleteAfter: Bool = false

    enum StepWork {
        /// rar's arguments, and the password it asks for on its standard input
        case rar([String], password: String?)
        case sevenZip(SevenZipBridge.Operation)
    }

    struct Step {
        let title: String
        let work: StepWork
        var cleanup: (() -> Void)?
    }

    /// The archive file the tool writes. rar names a self-extracting archive .sfx whatever it was asked for, so the
    /// app asks for that name and reports it.
    var writtenPath: String {
        guard format.isRar, sfx else { return archivePath }
        return ((archivePath as NSString).deletingPathExtension as NSString).appendingPathExtension("sfx") ?? archivePath
    }

    /// Whether the archive is written as volumes (name.part1.rar, name.7z.001…) rather than as one file.
    var isSplit: Bool {
        guard format.supportsVolumes, let size = volumeSize?.trimmingCharacters(in: .whitespaces), !size.isEmpty else { return false }
        return format.isRar || (volumeBytes ?? 0) > 0
    }

    /// The archive name the Create Archive dialog shows and uses: a name that already fits the format stays, another
    /// takes the format's extension, and a self-extracting RAR is named .sfx, the file rar writes.
    static func archivePath(_ path: String, format: ArchiveFormat, sfx: Bool) -> String {
        let named = ArchiveFormat.detect(fromPath: path) == format ? path : format.replacingExtension(in: path)
        var options = CompressOptions(archivePath: named)
        options.format = format
        options.sfx = sfx
        return options.writtenPath
    }

    /// Maps the 0-5 level to the 7-Zip -mx value
    private var mx: Int32 { [0, 1, 3, 5, 7, 9][max(0, min(5, level))] }

    /// The split size in bytes, read the way 7-Zip reads -v: a number with an optional
    /// b, k, m or g suffix in powers of 1024. 0 for no split, nil when the text is not a size.
    var volumeBytes: UInt64? {
        guard let text = volumeSize?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return 0 }
        guard let match = text.range(of: #"^\d+\s*[bBkKmMgG]?$"#, options: .regularExpression), match == text.startIndex..<text.endIndex
        else { return nil }
        let digits = text.prefix { $0.isNumber }
        let suffix = text.last.map { $0.isNumber ? "b" : String($0).lowercased() } ?? "b"
        let shift: UInt64 = ["b": 0, "k": 10, "m": 20, "g": 30][suffix] ?? 0
        guard let value = UInt64(digits), value > 0, value <= (UInt64.max >> shift) else { return nil }
        return value << shift
    }

    func buildSteps(items: [String]) -> [Step] {
        let password = self.password.flatMap { $0.isEmpty ? nil : $0 }
        let split = format.supportsVolumes ? (volumeBytes ?? 0) : 0

        func update(_ archive: String, _ sources: [String], _ options: SevenZipBridge.UpdateOptions) -> StepWork {
            .sevenZip(.update(archive: archive, sources: sources, options: options))
        }

        switch format {
        case .rar5:
            var args = RarRunner.addArguments + ["-m\(level)", "-ma5"]
            if solid { args.append("-s") }
            if recoveryRecord { args.append("-rr3") }
            if let v = volumeSize, !v.isEmpty { args.append("-v\(v)") }
            if sfx { args.append("-sfx" + (RarTools.sfxModule?.path ?? "")) }
            args += RarRunner.passwordSwitch(password, encryptHeaders: encryptNames)
            return [Step(title: loc.t("progress_compressing"), work: .rar(args + ["--", writtenPath] + items, password: password))]

        case .sevenZip:
            var sevenZip = SevenZipBridge.UpdateOptions(format: "7z", level: mx, solid: solid ? 1 : 0, password: password)
            sevenZip.encryptHeaders = password != nil && encryptNames
            sevenZip.volumeSize = split
            return [Step(title: loc.t("progress_compressing"), work: update(archivePath, items, sevenZip))]

        case .zip:
            var zip = SevenZipBridge.UpdateOptions(format: "zip", level: mx, password: password)
            zip.zipAES256 = password != nil
            zip.volumeSize = split
            return [Step(title: loc.t("progress_compressing"), work: update(archivePath, items, zip))]

        case .tar:
            let tar = SevenZipBridge.UpdateOptions(format: "tar")
            return [Step(title: loc.t("progress_packing"), work: update(archivePath, items, tar))]

        case .tgz, .txz, .tbz2:
            let outer: String = format == .tgz ? "gzip" : (format == .txz ? "xz" : "bzip2")
            // The tar takes the archive's name, in a folder of its own: gzip keeps that name in the archive, which
            // gunzip -N and other tools restore, and the progress window shows it while the tar is compressed
            let folder = TempDirs.make()
            let tmpTar = (folder as NSString).appendingPathComponent(
                ArchiveFormat.tar.replacingExtension(in: (archivePath as NSString).lastPathComponent))
            let tar = SevenZipBridge.UpdateOptions(format: "tar")
            let stream = SevenZipBridge.UpdateOptions(format: outer, level: mx)
            return [
                Step(title: loc.t("progress_packing"), work: update(tmpTar, items, tar)),
                Step(
                    title: loc.t("progress_compressing"), work: update(archivePath, [tmpTar], stream),
                    cleanup: { try? FileManager.default.removeItem(atPath: folder) }),
            ]
        }
    }

    /// Options object with the defaults from Settings
    static func withDefaults(for items: [String]) -> CompressOptions {
        var options = CompressOptions(archivePath: defaultArchivePath(for: items, format: Prefs.defaultFormat))
        options.format = Prefs.defaultFormat
        options.level = Prefs.defaultLevel
        options.solid = Prefs.solid && options.format.supportsSolid
        options.recoveryRecord = Prefs.recoveryRecord && options.format.supportsRecovery
        return options
    }

    static func defaultArchivePath(for items: [String], format: ArchiveFormat = .zip) -> String {
        guard let first = items.first else { return loc.t("compress_default_archive_name") + "." + format.ext }
        let parent = (first as NSString).deletingLastPathComponent
        var base: String
        if items.count == 1 {
            base = (first as NSString).lastPathComponent
            if !isDirectoryPath(first) { base = (base as NSString).deletingPathExtension }
        } else {
            base = (parent as NSString).lastPathComponent
        }
        if base.isEmpty || base == "/" { base = loc.t("compress_default_archive_name") }
        return (parent as NSString).appendingPathComponent(base + "." + format.ext)
    }
}
