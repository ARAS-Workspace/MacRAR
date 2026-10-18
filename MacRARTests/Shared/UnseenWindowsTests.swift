import XCTest
@testable import MacRAR

/// MACRAR_DEBUG_UNSEEN keeps every window the app builds transparent and deaf to the mouse while the tests run, the
/// archives they open out of Open Recent, and their frames, columns, sort order and toolbars out of what AppKit saves
/// in the app's defaults: the scheme's test action sets it for the test host from its launch on, and launchApp for the
/// copies it starts. Without it, the windows are the ones a user sees, and save their state.
@MainActor
final class UnseenWindowsTests: XCTestCase {
    private func isUnseen(_ window: NSWindow?) -> Bool { window?.alphaValue == 0 && window?.ignoresMouseEvents == true }

    /// What AppKit saves for archive windows in the app's defaults: the frame, the columns and sort order, the toolbar.
    private static let savedStateKeys = [
        "NSWindow Frame ArchiveWindow", "NSTableView Sort Ordering v2 ArchiveOutline", "NSTableView Columns v3 ArchiveOutline",
        "NSTableView Supports v2 ArchiveOutline", "NSToolbar Configuration MainToolbar",
    ]

    /// The saved state as the app's defaults hold it now.
    private func savedState() throws -> [String: NSObject] {
        let domain = UserDefaults.standard.persistentDomain(forName: try XCTUnwrap(Bundle.main.bundleIdentifier)) ?? [:]
        return domain.filter { Self.savedStateKeys.contains($0.key) }.compactMapValues { $0 as? NSObject }
    }

    /// Runs `body` and puts back the saved state it found, so that a window built as a user's leaves the user's alone.
    private func keepingSavedState(_ body: () throws -> Void) throws {
        let found = try savedState()
        defer { for key in Self.savedStateKeys { UserDefaults.standard.set(found[key], forKey: key) } }
        try body()
    }

    /// The archive, progress and Create Archive windows as the app builds them, none of them shown. The controllers
    /// are returned with their windows, which they are the delegates of.
    private func builtWindows() -> [(name: String, controller: NSWindowController)] {
        [("archive", ArchiveWindowController()), ("progress", ProgressPanel(title: "unseen")),
         ("Create Archive", CompressDialog(options: CompressOptions(archivePath: "/a/x.zip"), itemCount: 1))]
    }

    func testTheTestRunKeepsEveryWindowOfTheAppUnseen() throws {
        XCTAssertTrue(UnseenWindows.isOn, "the scheme's test action does not set MACRAR_DEBUG_UNSEEN")
        let launched = try XCTUnwrap(AppDelegate.shared).windows
        XCTAssertFalse(launched.isEmpty)
        for controller in launched {
            XCTAssertTrue(isUnseen(controller.window), "the window the test host opened at launch shows")
        }
        let settings: (name: String, controller: NSWindowController) = ("Settings", PreferencesWindowController.shared)
        for (name, controller) in builtWindows() + [settings] {
            XCTAssertTrue(isUnseen(controller.window), "the \(name) window shows")
        }
    }

    func testAUserSeesTheWindows() throws {
        try keepingSavedState {
            withoutEnvironment(["MACRAR_DEBUG_UNSEEN"]) {
                XCTAssertFalse(UnseenWindows.isOn)
                for (name, controller) in builtWindows() {
                    XCTAssertEqual(controller.window?.alphaValue, 1, "the \(name) window")
                    XCTAssertEqual(controller.window?.ignoresMouseEvents, false, "the \(name) window")
                }
                let archive = ArchiveWindowController()
                XCTAssertEqual(archive.window?.frameAutosaveName, "ArchiveWindow")
                XCTAssertEqual(archive.outline.autosaveName, "ArchiveOutline")
                XCTAssertEqual(archive.window?.toolbar?.autosavesConfiguration, true)
            }
        }
    }

    /// A copy started by launchApp opens its empty window unseen, and MACRAR_SNAPSHOT still draws it.
    func testACopyOfTheAppKeepsItsWindowsUnseen() throws {
        let workspace = try Workspace()
        let exit = try launchApp([], environment: ["MACRAR_SNAPSHOT": workspace.path("shot"), "MACRAR_SNAPSHOT_DELAY": "2"])
        XCTAssertEqual(exit.status, 0, exit.output)
        XCTAssertTrue(workspace.exists("shot-0.png"), exit.output)
        XCTAssertTrue(exit.output.contains("alpha 0.0"), exit.output)
        XCTAssertFalse(exit.output.contains("alpha 1.0"), exit.output)
    }

    /// An archive a test opens stays out of the user's Open Recent. The tests had filled it with archives deleted right
    /// after, which the menu leaves out, so it showed nothing.
    func testTheArchivesATestOpensStayOutOfOpenRecent() throws {
        let workspace = try Workspace()
        let archive = workspace.path("recent.zip")
        update(archive, workspace.sources, SevenZipBridge.UpdateOptions(format: "zip"))
        let controller = ArchiveWindowController()
        controller.open(archive)
        XCTAssertNotNil(controller.info)
        let recent = NSDocumentController.shared.recentDocumentURLs.map { $0.resolvingSymlinksInPath().path }
        XCTAssertFalse(recent.contains(URL(fileURLWithPath: archive).resolvingSymlinksInPath().path), "\(recent)")
    }

    /// An archive window a test opens leaves the frame, columns, sort order and toolbar the user's windows saved as
    /// they were. AppKit saves them in the app's own defaults under the window's, the outline's and the toolbar's
    /// autosave names, and every test that opened an archive window rewrote the user's saved frame, a little taller
    /// each time (measured: 990 × 1187 became 990 × 1202 in one run).
    func testTheWindowsATestOpensLeaveTheSavedWindowStateAsItWas() throws {
        try keepingSavedState {
            let before = try savedState()
            let controller = ArchiveWindowController()
            XCTAssertEqual(controller.window?.frameAutosaveName, "")
            XCTAssertNil(controller.outline.autosaveName)
            XCTAssertEqual(controller.window?.toolbar?.autosavesConfiguration, false)
            controller.showWindow(nil)
            controller.outline.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]
            controller.close()
            XCTAssertEqual(try savedState(), before)
        }
    }
}
