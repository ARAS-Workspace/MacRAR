import XCTest
@testable import MacRAR

/// An operation that finishes at once must not put the progress panel on screen: ordering it in
/// and out within a few milliseconds left the following result alert returning without the user. And an operation lets
/// go of its progress window once it ends.
final class ProgressPanelTests: XCTestCase {
    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    func testInstantOperationNeverShowsThePanel() throws {
        let panel = ProgressPanel(title: "instant")
        let window = try XCTUnwrap(panel.window)
        panel.show(on: nil)
        XCTAssertFalse(window.isVisible, "the panel went on screen before the operation had run for showDelay")
        panel.dismiss()
        spin(ProgressPanel.showDelay + 0.3)
        XCTAssertFalse(window.isVisible)
    }

    func testLongOperationShowsThePanelUntilDismissed() throws {
        let panel = ProgressPanel(title: "long")
        panel.show(on: nil)
        spin(ProgressPanel.showDelay + 0.3)
        let window = try XCTUnwrap(panel.window)
        XCTAssertTrue(window.isVisible)
        panel.dismiss()
        XCTAssertFalse(window.isVisible)
    }

    /// The progress windows the app has made and not let go of: a window still in NSApp.windows once closed.
    private func progressWindows() -> Int { NSApp.windows.filter { $0.windowController is ProgressPanel }.count }

    private func wait(until done: () -> Bool) {
        let end = Date(timeIntervalSinceNow: 30)
        while !done(), Date() < end { spin(0.05) }
    }

    /// An operation lets go of its progress window once it ends, through 7-Zip and through rar when it is fetched. The
    /// window and the job held each other, so every operation left its window behind, with the name of every file it
    /// worked on: three tests of an archive left three windows.
    func testAnOperationLetsGoOfItsProgressWindow() throws {
        setDebugAnswers()
        defer { clearDebugAnswers() }
        let workspace = try Workspace()
        let archive = workspace.path("kept.zip")
        update(archive, workspace.sources, SevenZipBridge.UpdateOptions(format: "zip"))
        guard case .ok(let info) = ArchiveReader.list(archive, password: nil) else { return XCTFail("\(archive) does not list") }
        spin(0.3)
        let before = progressWindows()
        var tested = false
        _ = printed {
            Ops.test(info: info, password: nil, host: nil) { _, _ in tested = true }
            wait { tested }
        }
        XCTAssertTrue(tested)
        if let rar = try? RarTool.locate() {
            let defaults = UserDefaults.standard
            let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(arguments.merging(["RarPath": rar.url.path]) { $1 }, forName: UserDefaults.argumentDomain)
            defer {
                defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
                defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            }
            var ran = false
            Ops.runRar(title: "rar", args: ["-iver"], host: nil) { _ in ran = true }
            wait { ran }
            XCTAssertTrue(ran)
        }
        spin(0.3)
        XCTAssertEqual(progressWindows(), before)
    }

    /// Every percentage rar can print reads as itself, though floating point leaves some just under it (0.29 × 100
    /// is 28.999…, which read 28%), and a fraction is rounded down: the window says 100% only once all is done.
    func testThePercentageReadsAsRarPrintsIt() {
        for percent in 0...100 {
            XCTAssertEqual(ProgressPanel.percent(Double(percent) / 100), percent, "\(percent)%")
        }
        XCTAssertEqual(ProgressPanel.percent(0.995), 99)
        XCTAssertEqual(ProgressPanel.percent(1 - 1e-6), 99)
        XCTAssertEqual(ProgressPanel.percent(-0.5), 0)
        XCTAssertEqual(ProgressPanel.percent(1.5), 100)
        // The window's line reads that percentage
        let panel = ProgressPanel(title: "percent")
        panel.setFraction(0.29)
        XCTAssertEqual(panel.readout.detail, loc.t("progress_percent", 29))
        panel.close()
    }
}
