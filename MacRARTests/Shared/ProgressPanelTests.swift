import XCTest
@testable import MacRAR

/// An operation that finishes at once must not put the progress panel on screen: ordering it in
/// and out within a few milliseconds left the following result alert returning without the user.
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
}
