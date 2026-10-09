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
}
