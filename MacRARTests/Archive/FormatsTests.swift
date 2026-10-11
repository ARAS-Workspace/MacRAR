import XCTest
@testable import MacRAR

final class FormatsTests: XCTestCase {
    func testArchiveKinds() {
        XCTAssertEqual(Formats.kind(of: "/a/b.rar"), .rar)
        XCTAssertEqual(Formats.kind(of: "/a/b.r01"), .rar)
        XCTAssertEqual(Formats.kind(of: "/a/b.7z"), .other)
        XCTAssertTrue(Formats.isArchive("/a/b.R07"))
        XCTAssertFalse(Formats.isArchive("/a/b.txt"))
    }

    func testMultiVolumeNames() {
        for name in ["x.part1.rar", "x.part02.RAR", "x.7z.001", "x.r00", "x.z01"] {
            XCTAssertTrue(Formats.isMultiVolume(name), name)
        }
        XCTAssertFalse(Formats.isMultiVolume("x.rar"))
    }

    func testFolderNamedAfterArchive() {
        XCTAssertEqual(Ops.folderNamedAfterArchive("/a/photos.zip"), "/a/photos")
        XCTAssertEqual(Ops.folderNamedAfterArchive("/a/photos.part1.rar"), "/a/photos")
        XCTAssertEqual(Ops.folderNamedAfterArchive("/a/photos.7z.001"), "/a/photos")
        XCTAssertEqual(Ops.folderNamedAfterArchive("/a/photos.tar.gz"), "/a/photos")
    }

    func testFirstVolumesOnly() {
        let picked = AppDelegate.dedupeVolumes(["/a/x.part2.rar", "/a/x.part1.rar", "/a/y.7z.002", "/a/y.7z.001", "/a/z.zip"])
        XCTAssertEqual(Set(picked), ["/a/x.part1.rar", "/a/y.7z.001", "/a/z.zip"])
    }

    /// Upstream 1.4.3 (533ce7e): a set named the old way, x.rar with x.r00, x.r01 … or x.zip with x.z01 …, chosen
    /// together came out as one archive per piece; only x.rar and x.zip are left. A piece whose set has no first
    /// volume, here or on the disk, stays.
    func testOldStyleVolumeSetsComeDownToTheFirst() {
        let picked = AppDelegate.dedupeVolumes(["/a/x.rar", "/a/x.r00", "/a/x.R01", "/a/y.z01", "/a/y.zip", "/a/z.r00", "/a/w.zip"])
        XCTAssertEqual(picked, ["/a/x.rar", "/a/y.zip", "/a/z.r00", "/a/w.zip"])
    }

    /// Later volumes chosen without the first, which sits beside them on the disk, come down to the first: read on
    /// their own they failed with "Headers Error".
    func testLaterVolumesComeDownToTheFirstOnTheDisk() throws {
        let workspace = try Workspace()
        let names = ["x.rar", "x.r00", "x.r01", "v.part1.rar", "v.part2.rar", "v.part3.rar", "s.7z.001", "s.7z.002"]
            + (1...12).map { String(format: "w.part%02d.rar", $0) }
        for name in names { try Data().write(to: workspace.url(name)) }
        let chosen = ["x.r00", "x.r01", "v.part3.rar", "v.part2.rar", "s.7z.002", "w.part05.rar"]
        let picked = AppDelegate.dedupeVolumes(chosen.map(workspace.path))
        XCTAssertEqual(picked, ["x.rar", "v.part1.rar", "s.7z.001", "w.part01.rar"].map(workspace.path))
    }
}
