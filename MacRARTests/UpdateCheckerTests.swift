import XCTest
@testable import MacRAR

/// Releases are tagged mac-v<original release>+ARAS.Patch.<n>; the update check reads them as versions
/// and orders the patch rounds, which semver's build metadata leaves unordered.
final class UpdateCheckerTests: XCTestCase {
    private let keys = [UpdateChecker.skipKey, UpdateChecker.lastCheckKey]
    private var saved: [String: Any] = [:]

    override func setUp() {
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        for key in keys { UserDefaults.standard.set(saved[key], forKey: key) }
    }

    private let release: [String: Any] = [
        "tag_name": "mac-v9.9.9+ARAS.Patch.1",
        "html_url": "https://github.com/ARAS-Workspace/MacRAR/releases/tag/mac-v9.9.9%2BARAS.Patch.1",
        "body": "## MacRAR 9.9.9+ARAS.Patch.1\n- a line only the release page shows",
    ]

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

    /// The update alert names the new version and the one in use, without the release notes, and its first button
    /// opens the new version's release page, where its DMGs are listed first.
    func testTheUpdateAlertOpensTheNewVersionsReleasePage() {
        withEnvironment(["MACRAR_DEBUG_VERSION": "1.0.0+ARAS.Patch.1", "MACRAR_DEBUG_UPDATE": "download"]) {
            let output = printed { UpdateChecker.handle(release: release, manual: true) }
            XCTAssertTrue(output.contains(loc.t("update_available_title", "9.9.9+ARAS.Patch.1")), output)
            XCTAssertTrue(output.contains(loc.t("update_available_message", "1.0.0+ARAS.Patch.1")), output)
            XCTAssertFalse(output.contains("only the release page shows"), "the alert shows the release notes")
            XCTAssertTrue(output.contains("open https://github.com/ARAS-Workspace/MacRAR/releases/tag/mac-v9.9.9%2BARAS.Patch.1"), output)
        }
        let alert = UpdateChecker.alert(latest: "9.9.9+ARAS.Patch.1")
        XCTAssertEqual(alert.buttons.map(\.title), [loc.t("update_open_download_page"), loc.t("later"), loc.t("update_skip_version")])
    }

    /// Without the address GitHub gives, the page of the release's tag opens; it used to be the latest release's.
    func testWithoutAnAddressTheTagsPageOpens() {
        let tag = "mac-v9.9.9+ARAS.Patch.1"
        XCTAssertEqual(UpdateChecker.page(of: ["tag_name": tag], tag: tag).absoluteString,
                       "https://github.com/ARAS-Workspace/MacRAR/releases/tag/mac-v9.9.9+ARAS.Patch.1")
        XCTAssertEqual(UpdateChecker.page(of: release, tag: tag).absoluteString, release["html_url"] as? String)
    }
}
