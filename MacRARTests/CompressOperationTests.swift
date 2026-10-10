import XCTest
@testable import MacRAR

/// What Ops.compress reports when it finishes: the archive file the Create Archive dialog reveals in Finder and the
/// window opens. A split archive has no file under its own name, so its first volume is reported.
final class CompressOperationTests: XCTestCase {
    private var workspace: Workspace!

    override func setUpWithError() throws {
        workspace = try Workspace()
    }

    override func tearDown() {
        workspace = nil
    }

    private func options(_ format: ArchiveFormat, _ name: String, split: String? = nil) -> CompressOptions {
        var options = CompressOptions(archivePath: workspace.path(name))
        options.format = format
        options.level = 0
        options.volumeSize = split
        return options
    }

    func testWholeArchiveIsReportedAsIs() {
        let made = compress(workspace.sources, options(.sevenZip, "whole.7z"))
        XCTAssertTrue(made.ok)
        XCTAssertEqual(made.path, workspace.path("whole.7z"))
    }

    func testSplitArchivesReportTheirFirstVolume() throws {
        for (format, name) in [(ArchiveFormat.sevenZip, "split.7z"), (.zip, "split.zip")] {
            let made = compress(workspace.sources, options(format, name, split: "300k"))
            XCTAssertTrue(made.ok, name)
            XCTAssertEqual(made.path, workspace.path(name + ".001"))
            XCTAssertFalse(workspace.exists(name))
            guard case .ok(let info) = ArchiveReader.list(made.path, password: nil) else { return XCTFail("\(made.path) did not list") }
            XCTAssertTrue(info.details.contains("volume"), info.details)
        }
    }

    /// rar numbers its volumes with as many digits as their count needs, and a self-extracting set starts with .sfx.
    func testRarVolumeNames() throws {
        for volume in ["many.part01.rar", "sfx.part1.sfx"] {
            try Data().write(to: workspace.url(volume))
        }
        XCTAssertEqual(Ops.firstVolume(of: workspace.path("many.rar")), workspace.path("many.part01.rar"))
        XCTAssertEqual(Ops.firstVolume(of: workspace.path("sfx.sfx")), workspace.path("sfx.part1.sfx"))
        XCTAssertEqual(Ops.firstVolume(of: workspace.path("none.rar")), workspace.path("none.rar"))
    }
}
