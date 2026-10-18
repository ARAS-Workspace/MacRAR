import XCTest
@testable import MacRAR

/// An archive in volumes cannot be changed (7-Zip answers "Not implemented", rar refuses to modify a volume): it is
/// offered no additions or deletions, and asked for one anyway, the app says why, in words about volumes, where it
/// used to run the engine into its error.
final class VolumeSetChangeTests: XCTestCase {
    private var workspace: Workspace!

    override func setUpWithError() throws {
        workspace = try Workspace()
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        workspace = nil
    }

    func testAVolumeSetTakesNoAdditionsOrDeletions() throws {
        var options = SevenZipBridge.UpdateOptions(format: "7z")
        options.volumeSize = 256 * 1024
        update(workspace.path("parts.7z"), workspace.sources, options)
        guard case .ok(let info) = ArchiveReader.list(workspace.path("parts.7z.001"), password: nil) else {
            return XCTFail("the set did not list")
        }
        XCTAssertGreaterThan(info.volumes, 1)
        XCTAssertFalse(info.supportsModification)

        var deleted = true, added = true
        let told = printed {
            deleted = finished { Ops.delete(info: info, names: ["a.txt"], password: nil, host: nil, completion: $0) }
            added = finished { Ops.add(info: info, items: [workspace.path("src/a.txt")], password: nil, host: nil, completion: $0) }
        }
        XCTAssertFalse(deleted || added)
        XCTAssertTrue(told.contains(loc.t("delete_split_unsupported")) && told.contains(loc.t("add_split_unsupported")), told)

        // A compressed tar is still told about in its own words
        let tar = workspace.path("kept.tar")
        update(tar, workspace.sources, SevenZipBridge.UpdateOptions(format: "tar"))
        update(workspace.path("kept.tar.gz"), [tar], SevenZipBridge.UpdateOptions(format: "gzip"))
        guard case .ok(let tgz) = ArchiveReader.list(workspace.path("kept.tar.gz"), password: nil) else { return XCTFail("no tgz") }
        let toldTar = printed { _ = finished { Ops.delete(info: tgz, names: ["a.txt"], password: nil, host: nil, completion: $0) } }
        XCTAssertTrue(toldTar.contains(loc.t("delete_tar_compressed_unsupported")), toldTar)
    }
}
