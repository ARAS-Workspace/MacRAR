import XCTest
@testable import MacRAR

/// Where a copy of the app runs from decides whether it installs the Finder Quick Actions and offers the file
/// associations: only the copy in the Applications folder does. A downloaded copy, run before it was moved there, says
/// why at launch; any other copy says so when the Quick Actions are asked for from the menu, instead of pointing the
/// user's Quick Actions at itself. Adapted from MacRAR 1.4.3, which offered to move the copy instead.
final class PlacementTests: XCTestCase {
    private var workspace: Workspace!

    override func setUpWithError() throws {
        workspace = try Workspace()
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        workspace = nil
    }

    func testWhereTheCopyRunsFrom() {
        let home = "/Users/kullanıcı"
        let cases: [(String, QuickActions.Placement)] = [
            ("/Applications/MacRAR.app", .applications),
            ("/Applications/Utilities/MacRAR.app", .applications),
            ("\(home)/Applications/MacRAR.app", .applications),
            ("/Volumes/MacRAR/MacRAR.app", .downloaded),
            ("/private/var/folders/x1/abc/T/AppTranslocation/8D2C5F7A/d/MacRAR.app", .downloaded),
            ("\(home)/Downloads/MacRAR.app", .downloaded),
            ("\(home)/Desktop/MacRAR.app", .downloaded),
            ("\(home)/Library/Developer/Xcode/DerivedData/MacRAR/Build/Products/Debug/MacRAR.app", .elsewhere),
            ("\(home)/Tools/MacRAR.app", .elsewhere),
            ("/Users/other/Applications/MacRAR.app", .elsewhere),
            ("/Applications/../Users/x/MacRAR.app", .elsewhere),
        ]
        for (path, expected) in cases {
            XCTAssertEqual(QuickActions.placement(bundlePath: path, home: home), expected, path)
        }
        XCTAssertEqual(QuickActions.placement, .elsewhere, Bundle.main.bundlePath)
    }

    /// Asked for from the menu, a copy outside the Applications folder writes no workflow, so the user's Quick Actions
    /// keep calling the copy there; it says why instead.
    func testACopyOutsideApplicationsInstallsNoQuickActionsFromTheMenu() throws {
        let directory = try workspace.makeDirectory("Services")
        try XCTUnwrap(AppDelegate.shared).installQuickActions(in: directory, registerWithFinder: false)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory), [])
        withEnvironment(["MACRAR_DEBUG_PLACEMENT": "downloaded"]) {
            AppDelegate.shared.installQuickActions(in: directory, registerWithFinder: false)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory), [])
    }

    /// A second copy started the way a user opens it, which with MACRAR_SNAPSHOT saves its windows and quits. The copy
    /// reads the user's own settings, so "Don't show this again" goes to it as off unless a test passes it on.
    private func launch(_ arguments: [String] = ["-\(QuickActions.placementWarningOffKey)", "NO"],
                        placement: String? = nil) throws -> AppExit {
        var environment = ["MACRAR_SNAPSHOT": workspace.path("shot"), "MACRAR_SNAPSHOT_DELAY": "2"]
        environment["MACRAR_DEBUG_PLACEMENT"] = placement
        let exit = try launchApp(arguments, environment: environment)
        XCTAssertEqual(exit.status, 0, exit.output)
        return exit
    }

    func testADownloadedCopySaysWhyAtLaunch() throws {
        let warning = try english("quick_actions_need_applications_message").replacingOccurrences(of: "%@", with: "MacRAR")
        XCTAssertTrue(try launch(placement: "downloaded").output.contains(warning), "no warning")
        XCTAssertFalse(try launch(placement: "elsewhere").output.contains(warning), "a copy elsewhere warned")
        XCTAssertFalse(try launch().output.contains(warning), "the test build warned")
        let declined = try launch(["-\(QuickActions.placementWarningOffKey)", "YES"], placement: "downloaded")
        XCTAssertFalse(declined.output.contains(warning), "warned after Don't show this again")
    }
}
