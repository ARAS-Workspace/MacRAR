import XCTest
@testable import MacRAR

/// The questions the app asks on its own as it starts, the file associations and the update alert, wait until no
/// other question, sheet or progress window is up instead of coming up over it (Dialogs.whenIdle). With
/// MACRAR_DEBUG_CONFIRM they print and answer instead of waiting for a click: the associations question Not Now, the
/// update alert as MACRAR_DEBUG_UPDATE says. Each test puts back the settings it changes.
final class LaunchQuestionsTests: XCTestCase {
    private let keys = [Associations.shownKey, UpdateChecker.skipKey, UpdateChecker.lastCheckKey]
    private var saved: [String: Any] = [:]
    private var sheets: [(host: NSWindow, sheet: NSWindow)] = []

    override func setUp() {
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
        UpdateChecker.announced = []
        setDebugAnswers()
    }

    override func tearDown() {
        closeSheets()
        // A block a failed test left waiting runs now, while its questions still print instead of showing
        XCTAssertTrue(eventually { Dialogs.waiting == 0 }, "a block is still waiting")
        clearDebugAnswers()
        for key in keys { UserDefaults.standard.set(saved[key], forKey: key) }
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    /// Runs the main loop until `condition` holds or `timeout` passes, and says whether it held.
    private func eventually(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let end = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < end { spin(0.05) }
        return condition()
    }

    /// A window of the test's own, fully transparent: it counts as up for the app while the user sees nothing.
    /// (Placed off the screens instead, AppKit moves it back on.)
    private func window(width: CGFloat, height: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        hide(window)
        return window
    }

    private func hide(_ window: NSWindow?) {
        window?.alphaValue = 0
        window?.ignoresMouseEvents = true
    }

    private func isUnseen(_ window: NSWindow?) -> Bool { window?.alphaValue == 0 }

    /// A window on screen with a sheet on it, as an operation's progress or the overwrite question puts there.
    private func openSheet() -> (host: NSWindow, sheet: NSWindow) {
        let host = window(width: 300, height: 200)
        host.orderFront(nil)
        let sheet = window(width: 200, height: 100)
        host.beginSheet(sheet)
        spin(0.1)
        XCTAssertTrue(isUnseen(host) && isUnseen(sheet), "a window of the test can be seen")
        sheets.append((host, sheet))
        return (host, sheet)
    }

    private func closeSheets() {
        for (host, sheet) in sheets {
            host.endSheet(sheet)
            host.orderOut(nil)
        }
        sheets = []
    }

    // MARK: Dialogs.whenIdle

    func testNothingUpRunsAtOnce() {
        XCTAssertFalse(Dialogs.isBusy)
        var ran = false
        Dialogs.whenIdle { ran = true }
        XCTAssertTrue(ran)
    }

    func testASheetIsWaitedFor() {
        _ = openSheet()
        var ran = false
        Dialogs.whenIdle { ran = true }
        spin(2)
        XCTAssertFalse(ran, "ran while a sheet was up")
        closeSheets()
        XCTAssertTrue(eventually { ran })
    }

    func testAModalWindowIsWaitedFor() {
        let modal = window(width: 200, height: 100)
        let session = NSApp.beginModalSession(for: modal)
        XCTAssertTrue(isUnseen(modal), "a window of the test can be seen")
        var ran = false
        Dialogs.whenIdle { ran = true }
        spin(2)
        XCTAssertFalse(ran, "ran while a modal window was up")
        NSApp.endModalSession(session)
        modal.orderOut(nil)
        XCTAssertTrue(eventually { ran })
    }

    /// An operation started without a window to sit on, such as one for files Finder opened the app with, shows its
    /// progress in a window of its own, which is neither modal nor a sheet. MacRAR 1.4.3 did not wait for it.
    func testAProgressWindowIsWaitedFor() {
        let panel = ProgressPanel(title: "long")
        hide(panel.window)
        panel.show(on: nil)
        spin(ProgressPanel.showDelay + 0.3)
        XCTAssertEqual(panel.window?.isVisible, true)
        XCTAssertTrue(isUnseen(panel.window), "the progress window can be seen")
        var ran = false
        Dialogs.whenIdle { ran = true }
        spin(2)
        XCTAssertFalse(ran, "ran while a progress window was up")
        panel.dismiss()
        XCTAssertTrue(eventually { ran })
    }

    /// An operation shows its progress window only after ProgressPanel.showDelay, and runs all the same until then:
    /// a question that came up in that time sat over its start, and with runModal called from a queued block, the
    /// operation's own main-queue updates waited for the question to be answered. It now waits for the operation.
    func testAnOperationIsWaitedForBeforeItsProgressWindowIsUp() {
        let panel = ProgressPanel(title: "starting")
        hide(panel.window)
        panel.show(on: nil)
        var ran = false
        Dialogs.whenIdle { ran = true }
        XCTAssertFalse(ran, "ran while the operation was starting")
        XCTAssertEqual(panel.window?.isVisible, false)
        panel.dismiss()
        XCTAssertTrue(eventually { ran })
        XCTAssertEqual(ProgressPanel.running, 0)
    }

    // MARK: The questions

    /// Upstream 1.4.3 (533ce7e): the associations question of the first launch came up over whatever was open, such
    /// as the password question for the archive the app was opened with.
    func testTheAssociationsQuestionWaitsForAnOpenSheet() throws {
        UserDefaults.standard.removeObject(forKey: Associations.shownKey)
        _ = openSheet()
        try XCTUnwrap(AppDelegate.shared).askAssociationsWhenIdle()
        spin(2.5)
        XCTAssertFalse(Associations.alreadyShown, "asked while a sheet was up")
        closeSheets()
        XCTAssertTrue(eventually { Associations.alreadyShown }, "never asked")
    }

    /// The update alert the daily check brings waits the same way; skipping the version is what it is answered with
    /// here, so that it shows when the alert came.
    func testTheUpdateAlertWaitsForAnOpenSheet() {
        UserDefaults.standard.removeObject(forKey: UpdateChecker.skipKey)
        withEnvironment([.version: "1.0.0+ARAS.Patch.1", .update: "skip"]) {
            _ = openSheet()
            UpdateChecker.handle(release: ["tag_name": "mac-v9.9.9+ARAS.Patch.1"], manual: false)
            spin(2)
            XCTAssertNil(UserDefaults.standard.string(forKey: UpdateChecker.skipKey), "the alert came over the sheet")
            closeSheets()
            XCTAssertTrue(eventually { UserDefaults.standard.string(forKey: UpdateChecker.skipKey) == "9.9.9+ARAS.Patch.1" })
        }
    }

    /// Asked for from the menu, the check answers at once, open sheet or not.
    func testAnUpdateCheckFromTheMenuAnswersAtOnce() {
        withEnvironment([.version: "1.0.0+ARAS.Patch.1", .update: "skip"]) {
            UserDefaults.standard.set("9.9.9+ARAS.Patch.1", forKey: UpdateChecker.skipKey)
            UpdateChecker.handle(release: ["tag_name": "mac-v9.9.9+ARAS.Patch.2"], manual: false)
            XCTAssertTrue(eventually(timeout: 1) { UserDefaults.standard.string(forKey: UpdateChecker.skipKey) == "9.9.9+ARAS.Patch.2" })
            _ = openSheet()
            UpdateChecker.handle(release: ["tag_name": "mac-v9.9.9+ARAS.Patch.3"], manual: true)
            XCTAssertEqual(UserDefaults.standard.string(forKey: UpdateChecker.skipKey), "9.9.9+ARAS.Patch.3")
        }
    }

    /// A version the user skipped stays away from the daily check and still comes when the user asks from the menu.
    func testASkippedVersionStaysAwayOnlyFromTheDailyCheck() {
        let release: [String: Any] = ["tag_name": "mac-v9.9.9+ARAS.Patch.1"]
        let title = loc.t("update_available_title", "9.9.9+ARAS.Patch.1")
        UserDefaults.standard.set("9.9.9+ARAS.Patch.1", forKey: UpdateChecker.skipKey)
        withEnvironment([.version: "1.0.0+ARAS.Patch.1"]) {
            XCTAssertFalse(printed { UpdateChecker.handle(release: release, manual: false) }.contains(title), "the daily check showed it")
            XCTAssertTrue(printed { UpdateChecker.handle(release: release, manual: true) }.contains(title), "the menu's check hid it")
        }
    }

    /// The daily check's alert waits for an open sheet. If the user meanwhile asks from the menu and skips that version,
    /// or only says Later, the waiting alert stays away: it used to come as well.
    func testAWaitingUpdateAlertStaysAwayOnceTheMenuShowedIt() {
        UserDefaults.standard.removeObject(forKey: UpdateChecker.skipKey)
        for (answer, version) in [("skip", "9.9.9+ARAS.Patch.1"), ("later", "9.9.9+ARAS.Patch.2")] {
            let release: [String: Any] = ["tag_name": "mac-v" + version]
            let title = loc.t("update_available_title", version)
            withEnvironment([.version: "1.0.0+ARAS.Patch.1", .update: answer]) {
                let output = printed {
                    _ = openSheet()
                    UpdateChecker.handle(release: release, manual: false)
                    UpdateChecker.handle(release: release, manual: true)
                    closeSheets()
                    spin(2.5)
                }
                XCTAssertEqual(output.components(separatedBy: title).count - 1, 1, "\(answer): \(output)")
            }
        }
    }
}
