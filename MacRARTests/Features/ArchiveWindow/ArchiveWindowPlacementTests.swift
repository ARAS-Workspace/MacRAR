import XCTest
@testable import MacRAR

/// Where an archive window opens: at the frame the user's archive windows saved, as large as it was saved, or in the
/// middle when nothing is saved, and one step down and right of an archive window already up. The tests give the
/// saved frame themselves, as AppKit writes one; a test run saves none and reads none. The archive windows up when a
/// test starts, the one the test host opened among them, are put out of the way and back.
final class ArchiveWindowPlacementTests: XCTestCase {
    private var putAway: [NSWindow] = []

    override func setUp() {
        putAway = NSApp.windows.filter { $0.isVisible && $0.windowController is ArchiveWindowController }
        for window in putAway { window.orderOut(nil) }
    }

    override func tearDown() {
        for window in putAway { window.orderFront(nil) }
        putAway = []
    }

    /// What an archive window moved to `frame` saves, as AppKit writes it into the defaults (without the toolbar's
    /// height, which a window with the toolbar adds back), and the frame the window had.
    private func saved(at frame: NSRect) throws -> (descriptor: NSWindow.PersistableFrameDescriptor, frame: NSRect) {
        let saving = ArchiveWindowController()
        defer { saving.close() }
        let window = try XCTUnwrap(saving.window)
        window.setFrame(frame, display: false)
        return (window.frameDescriptor, window.frame)
    }

    private func screen() throws -> NSRect { try XCTUnwrap(NSScreen.main).visibleFrame }

    private func frame(in screen: NSRect) -> NSRect {
        NSRect(x: screen.minX + 100, y: screen.minY + 60, width: 900, height: min(640, screen.height - 120))
    }

    /// A window comes up where an archive window saved its frame, and as tall. It took the saved frame before its
    /// toolbar, which then added 66 pt where the saved frame leaves out 51, so each window came up 15 pt taller, and it
    /// was centred after.
    func testAWindowOpensAtTheFrameSavedAndAsLarge() throws {
        let saved = try saved(at: frame(in: try screen()))
        let controller = ArchiveWindowController(savedFrame: saved.descriptor)
        defer { controller.close() }
        XCTAssertEqual(controller.window?.frame, saved.frame)
        controller.showWindow(nil)
        XCTAssertEqual(controller.window?.frame, saved.frame)
    }

    func testAWindowWithNothingSavedOpensInTheMiddle() throws {
        let screen = try screen()
        let controller = ArchiveWindowController()
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.frame.midX, screen.midX, accuracy: 1)
        XCTAssertGreaterThan(window.frame.minY, screen.minY)
        XCTAssertLessThan(window.frame.maxY, screen.maxY)
    }

    /// A second window opens one step down and right of the one in front, as large; a third, a step from the second.
    /// Skipped where the window server makes windows main.
    func testANewWindowCascadesFromTheOneInFront() throws {
        let saved = try saved(at: frame(in: try screen())).descriptor
        var windows: [NSWindow] = []
        var controllers: [ArchiveWindowController] = []
        defer { for controller in controllers { controller.close() } }
        for _ in 0..<3 {
            let controller = ArchiveWindowController(savedFrame: saved)
            controllers.append(controller)
            controller.showWindow(nil)
            windows.append(try XCTUnwrap(controller.window))
        }
        try skipWhereTheWindowServerMakesOneMain()
        for (earlier, later) in zip(windows, windows.dropFirst()) {
            XCTAssertEqual(later.frame.size, earlier.frame.size)
            XCTAssertGreaterThan(later.frame.minX, earlier.frame.minX, "not to the right")
            XCTAssertLessThan(later.frame.maxY, earlier.frame.maxY, "not down")
            XCTAssertLessThan(later.frame.minX - earlier.frame.minX, 60, "more than a step")
        }
    }

    /// Skips a test where the window server makes an archive window main on its own, as on CI, where the test host is
    /// the app in front: it hands main to a window while the test opens the next ones, the app follows it
    /// (`windowDidBecomeMain`), and the third window cascades from the first. On a Mac the test host is in the
    /// background and no window becomes main. Several archives opened at once from Finder, with the app in front, came
    /// up each a step from the last.
    private func skipWhereTheWindowServerMakesOneMain() throws {
        try XCTSkipIf(NSApp.mainWindow?.windowController is ArchiveWindowController,
                      "the window server made an archive window main while the test opened them")
    }

    /// Opens `count` archive windows at `saved`, one after another, as `showWindow` puts them up.
    private func open(_ count: Int, at saved: NSWindow.PersistableFrameDescriptor) -> [ArchiveWindowController] {
        (0..<count).map { _ in
            let controller = ArchiveWindowController(savedFrame: saved)
            controller.showWindow(nil)
            return controller
        }
    }

    /// A new window cascades from the one placed last, whatever order the window server keeps: here the first window
    /// goes back to the front of that order, where the window to cascade from was once taken. Skipped where the window
    /// server makes windows main.
    func testANewWindowCascadesFromTheOnePlacedLastWhateverTheWindowServersOrder() throws {
        let saved = try saved(at: frame(in: try screen())).descriptor
        var controllers = open(2, at: saved)
        defer { for controller in controllers { controller.close() } }
        controllers[0].window?.orderFront(nil)
        controllers += open(1, at: saved)
        try skipWhereTheWindowServerMakesOneMain()
        let second = try XCTUnwrap(controllers[1].window), placed = try XCTUnwrap(controllers[2].window)
        XCTAssertGreaterThan(placed.frame.minX, second.frame.minX, "not to the right of the window placed last")
        XCTAssertLessThan(placed.frame.maxY, second.frame.maxY, "not below the window placed last")
    }

    /// A window the user makes main, by clicking it, is the one a new window cascades from: it comes up a step from the
    /// first window, where the second came up.
    func testANewWindowCascadesFromTheOneMadeMainLast() throws {
        let saved = try saved(at: frame(in: try screen())).descriptor
        var controllers = open(2, at: saved)
        defer { for controller in controllers { controller.close() } }
        let second = try XCTUnwrap(controllers[1].window).frame
        NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: controllers[0].window)
        controllers += open(1, at: saved)
        XCTAssertEqual(controllers[2].window?.frame, second)
    }

    /// With the window in front closed, a new window cascades from the one in front before it: it comes up where the
    /// closed one was, not on top of the first window.
    func testANewWindowCascadesFromTheOneBeforeTheWindowClosed() throws {
        let saved = try saved(at: frame(in: try screen())).descriptor
        var controllers = open(2, at: saved)
        defer { for controller in controllers { controller.close() } }
        let second = try XCTUnwrap(controllers[1].window).frame
        controllers[1].close()
        controllers += open(1, at: saved)
        XCTAssertEqual(controllers[2].window?.frame, second)
    }
}
