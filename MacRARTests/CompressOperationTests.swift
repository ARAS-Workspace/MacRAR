import XCTest
@testable import MacRAR

/// What Ops.compress reports when it finishes: the archive file the Create Archive dialog reveals in Finder and the
/// window opens. A split archive has no file under its own name, so its first volume is reported.
final class CompressOperationTests: XCTestCase {
    private var workspace: Workspace!

    override func setUpWithError() throws {
        workspace = try Workspace()
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        workspace = nil
    }

    private func options(_ format: ArchiveFormat, _ name: String, split: String? = nil) -> CompressOptions {
        var options = CompressOptions(archivePath: workspace.path(name))
        options.format = format
        options.level = 0
        options.volumeSize = split
        return options
    }

    /// A compressed tar is packed into a tar in the temporary folder first. That tar takes the archive's name, which gzip
    /// keeps in the archive, and goes away once it is compressed; it used to be Archiver-<UUID>.tar.
    func testCompressedTarsPackATarNamedAfterThem() throws {
        let temporary = NSTemporaryDirectory()
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: temporary))
        for format in [ArchiveFormat.tgz, .txz, .tbz2] {
            var options = options(format, "packed.\(format.ext)")
            options.level = 1
            let made = compress(workspace.sources, options)
            XCTAssertTrue(made.ok, format.ext)
            guard case .ok(let info) = ArchiveReader.list(made.path, password: nil) else { return XCTFail("\(made.path) did not list") }
            XCTAssertEqual(Set(info.entries.map(\.name)), ["a.txt", "sub", "sub/b.bin", "sub/çalışma ğüş.txt"], format.ext)
        }
        XCTAssertEqual(try gzipName(workspace.path("packed.tar.gz")), "packed.tar")
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: temporary)).subtracting(before)
        XCTAssertEqual(left.filter { $0.hasPrefix("Archiver-") }, [])
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

    /// An earlier split set under the same name is left alone: the question it raises, answered with Create New by
    /// MACRAR_DEBUG_CONFIRM, gives the new set a free name. 7-Zip used to fail with "Updating for multivolume
    /// archives is not implemented".
    func testSplittingOverAnEarlierSetMakesANewOne() throws {
        XCTAssertTrue(compress(workspace.sources, options(.sevenZip, "set.7z", split: "200k")).ok)
        let earlier = try workspace.files(startingWith: "set.7z.")
        XCTAssertGreaterThan(earlier.count, 2)

        let again = compress(workspace.sources, options(.sevenZip, "set.7z", split: "700k"))
        XCTAssertTrue(again.ok)
        XCTAssertEqual(again.path, workspace.path("set 2.7z.001"))
        XCTAssertEqual(try workspace.files(startingWith: "set.7z."), earlier, "the earlier set changed")
        guard case .ok = ArchiveReader.list(again.path, password: nil) else { return XCTFail("\(again.path) did not list") }
    }

    /// rar numbers its volumes with as many digits as their count needs, and a self-extracting set starts with .sfx.
    func testRarVolumeNames() throws {
        for volume in ["many.part01.rar", "sfx.part1.sfx"] {
            try Data().write(to: workspace.url(volume))
        }
        XCTAssertEqual(Ops.firstVolume(of: workspace.path("many.rar")), workspace.path("many.part01.rar"))
        XCTAssertEqual(Ops.firstVolume(of: workspace.path("sfx.sfx")), workspace.path("sfx.part1.sfx"))
        XCTAssertEqual(Ops.firstVolume(of: workspace.path("none.rar")), workspace.path("none.rar"))
        XCTAssertTrue(Ops.isTaken(workspace.path("many.rar")))
        XCTAssertFalse(Ops.isTaken(workspace.path("none.rar")))
    }
}
