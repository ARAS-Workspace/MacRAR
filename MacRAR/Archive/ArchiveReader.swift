import Foundation

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
