import CryptoKit
import XCTest

/// The large files External/generate-large-files.sh makes in External/test-large-files: 256 MiB each, incompressible
/// like the media archives people pack, the same on every machine, and one named with a space and Turkish letters. CI
/// generates them before the tests; on a Mac, run the script once. Without them the tests that pack them skip.
enum LargeFiles {
    static let folder = Repository.external.appendingPathComponent("test-large-files")

    /// Their absolute paths, in name order.
    static func locate() throws -> [String] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".bin") }
        guard !names.isEmpty else { throw XCTSkip("the large test files are not generated; run External/generate-large-files.sh") }
        return names.sorted().map { folder.appendingPathComponent($0).path }
    }

    /// Copies of them in a folder of the workspace, under their composed names as the originals have them: for flows
    /// that write next to what they pack, such as the Quick Action. APFS clones, so they take no space; a plain copy
    /// where the workspace is on another volume.
    static func clone(into workspace: Workspace, folder: String) throws -> [String] {
        let target = try workspace.makeComposedDirectory(folder)
        return try locate().map { source in
            let copy = "\(target)/\((source as NSString).lastPathComponent.precomposedStringWithCanonicalMapping)"
            if clonefile(source, copy, 0) != 0 {
                guard errno == EXDEV, copyfile(source, copy, nil, copyfile_flags_t(COPYFILE_ALL)) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
            return copy
        }
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
