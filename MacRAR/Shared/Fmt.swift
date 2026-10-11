import Foundation

enum Fmt {
    static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()
    static func size(_ byteCount: Int64) -> String { bytes.string(fromByteCount: byteCount) }
}
