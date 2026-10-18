import Foundation

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
            guard let top = Self.topName(of: entry.name) else { continue }
            if seen.insert(top).inserted { out.append(top) }
        }
        return out
    }

    /// The first part of `name` as 7-Zip writes it into a folder: "." and ".." are dropped, so "../a.txt" lands as
    /// "a.txt", and a leading "/" too. Nil for a name with nothing else.
    static func topName(of name: String) -> String? {
        name.split(separator: "/").lazy.map(String.init).first { $0 != "." && $0 != ".." }
    }
    /// The volumes the archive is split into; 1 for an archive in one file
    var volumes = 1
    /// Are adding / deleting files supported? Not for a compressed tar, nor for an archive in volumes, which neither
    /// 7-Zip nor rar can change.
    var supportsModification: Bool { !tarCompressed && volumes <= 1 }
}
