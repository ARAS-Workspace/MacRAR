import XCTest
@testable import MacRAR

/// A volume set comes down to one archive, its first volume, wherever volumes are chosen: Quick Actions, opening and
/// dropping (VolumeSets.firstVolumes).
final class VolumeSetsTests: XCTestCase {
    func testFirstVolumesOnly() {
        let picked = VolumeSets.firstVolumes(["/a/x.part2.rar", "/a/x.part1.rar", "/a/y.7z.002", "/a/y.7z.001", "/a/z.zip"])
        XCTAssertEqual(Set(picked), ["/a/x.part1.rar", "/a/y.7z.001", "/a/z.zip"])
    }

    /// Upstream 1.4.3 (533ce7e): a set named the old way, x.rar with x.r00, x.r01 … or x.zip with x.z01 …, chosen
    /// together came out as one archive per piece; only x.rar and x.zip are left. A piece whose set has no first
    /// volume, here or on the disk, stays.
    func testOldStyleVolumeSetsComeDownToTheFirst() {
        let picked = VolumeSets.firstVolumes(["/a/x.rar", "/a/x.r00", "/a/x.R01", "/a/y.z01", "/a/y.zip", "/a/z.r00", "/a/w.zip"])
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
        let picked = VolumeSets.firstVolumes(chosen.map(workspace.path))
        XCTAssertEqual(picked, ["x.rar", "v.part1.rar", "s.7z.001", "w.part01.rar"].map(workspace.path))
    }

    /// The set's first volume keeps the spelling of the volume chosen, names with more dots keep them, and files that
    /// are no volume stay where they were chosen.
    func testVolumeNamesKeepTheirSpelling() throws {
        let workspace = try Workspace()
        for name in ["X.PART1.RAR", "X.PART2.RAR", "a.b.rar", "a.b.r00", "notes.txt"] { try Data().write(to: workspace.url(name)) }
        let chosen = ["notes.txt", "X.PART2.RAR", "a.b.r00", "other.zip"].map(workspace.path)
        XCTAssertEqual(VolumeSets.firstVolumes(chosen), ["notes.txt", "X.PART1.RAR", "a.b.rar", "other.zip"].map(workspace.path))
    }
}
