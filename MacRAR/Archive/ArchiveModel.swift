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
            let top = entry.name.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? entry.name
            if seen.insert(top).inserted { out.append(top) }
        }
        return out
    }
    /// Are adding / deleting files supported?
    var supportsModification: Bool { !tarCompressed }
}
