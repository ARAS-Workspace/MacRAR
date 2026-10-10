import CryptoKit
import XCTest

/// The large files External/generate-large-files.sh makes in External/test-large-files: 256 MiB each, incompressible
/// like the media archives people pack, the same on every machine, and one named with a space and Turkish letters. CI
/// generates them before the tests; on a Mac, run the script once. Without them the tests that pack them skip.
enum LargeFiles {
    static let folder = RarTool.external.appendingPathComponent("test-large-files")

    /// Their absolute paths, in name order.
    static func locate() throws -> [String] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".bin") }
        guard !names.isEmpty else { throw XCTSkip("the large test files are not generated; run External/generate-large-files.sh") }
        return names.sorted().map { folder.appendingPathComponent($0).path }
    }

    /// The SHA-256 of a file, read a piece at a time: what came out of an archive is compared with what went in
    /// without holding either in memory.
    static func digest(_ path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hash = SHA256()
        while let piece = try handle.read(upToCount: 8 << 20), !piece.isEmpty {
            hash.update(data: piece)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
