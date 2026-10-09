import XCTest
@testable import MacRAR

/// Releases are tagged mac-v<original release>+ARAS.Patch.<n>; the update check reads them as versions
/// and orders the patch rounds, which semver's build metadata leaves unordered.
final class UpdateCheckerTests: XCTestCase {
    func testReleaseTagsNameTheirVersion() {
        XCTAssertEqual(UpdateChecker.version(fromTag: "mac-v1.4.2+ARAS.Patch.1"), "1.4.2+ARAS.Patch.1")
        XCTAssertEqual(UpdateChecker.version(fromTag: "v1.4.2"), "1.4.2")
        XCTAssertEqual(UpdateChecker.version(fromTag: "1.4.2"), "1.4.2")
    }

    func testPatchRoundsAreOrderedAfterTheOriginalRelease() {
        XCTAssertTrue(UpdateChecker.isNewer("1.4.2+ARAS.Patch.2", than: "1.4.2+ARAS.Patch.1"))
        XCTAssertTrue(UpdateChecker.isNewer("1.4.2+ARAS.Patch.10", than: "1.4.2+ARAS.Patch.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.4.3+ARAS.Patch.1", than: "1.4.2+ARAS.Patch.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.4.2+ARAS.Patch.1", than: "1.4.2"))
        XCTAssertFalse(UpdateChecker.isNewer("1.4.2+ARAS.Patch.1", than: "1.4.2+ARAS.Patch.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.4.2+ARAS.Patch.9", than: "1.4.3+ARAS.Patch.1"))
        XCTAssertFalse(UpdateChecker.isNewer(UpdateChecker.version(fromTag: "mac-v1.4.2+ARAS.Patch.3"), than: "1.4.2+ARAS.Patch.3"))
    }

    func testTheBundleCarriesBothVersions() throws {
        let release = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let distribution = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "ARASDistributionVersion") as? String)
        XCTAssertNotNil(release.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression), release)
        XCTAssertNotNil(distribution.range(of: #"^\d+\.\d+\.\d+\+ARAS\.Patch\.\d+$"#, options: .regularExpression), distribution)
        XCTAssertTrue(distribution.hasPrefix(release + "+"), "\(distribution) is not based on \(release)")
        XCTAssertEqual(AppInfo.version, distribution)
    }
}
