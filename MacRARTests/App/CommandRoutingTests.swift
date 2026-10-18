import XCTest
@testable import MacRAR

/// Every command item sends performCommand(_:) with its Command: the app's to the app delegate, the window's up the
/// responder chain to the archive window in front. The app delegate runs the app's commands and refuses the window's,
/// and a command runs only when its responder allows it. The questions the commands ask get the debug answers.
final class CommandRoutingTests: XCTestCase {
    override func setUp() {
        setDebugAnswers()
    }

    override func tearDown() {
        PreferencesWindowController.shared.window?.orderOut(nil)
        clearDebugAnswers()
    }

    /// Every item of the menu bar's menus, and of a new archive window's context menu.
    private func items() throws -> (bar: [NSMenuItem], context: [NSMenuItem]) {
        let bar = try XCTUnwrap(NSApp.mainMenu?.items).flatMap { $0.submenu?.items ?? [] }
        return (bar, try XCTUnwrap(ArchiveWindowController().outline.menu?.items))
    }

    private func barItem(_ command: Command) throws -> NSMenuItem {
        try XCTUnwrap(try items().bar.first { Command(sender: $0) == command }, command.rawValue)
    }

    func testEveryCommandItemSendsItsCommandToItsResponder() throws {
        let (bar, context) = try items()
        for item in bar + context {
            guard let command = Command(sender: item) else {
                XCTAssertNotEqual(item.action, .performCommand, "\(item.title) sends a command without carrying one")
                continue
            }
            XCTAssertEqual(item.action, .performCommand, item.title)
            if command.scope == .app {
                XCTAssertTrue(item.target === AppDelegate.shared, "\(command) is not sent to the app delegate")
            } else {
                XCTAssertNil(item.target, "\(command) does not go up the responder chain")
            }
        }
        let inBar = bar.compactMap { Command(sender: $0) }
        XCTAssertEqual(inBar.sorted { $0.rawValue < $1.rawValue },
                       Command.allCases.filter { $0 != .openSelected }.sorted { $0.rawValue < $1.rawValue })
        XCTAssertEqual(context.compactMap { Command(sender: $0) }.filter { $0 == .openSelected }.count, 1)
    }

    /// With no archive window in front, a window's command reaches the app delegate, which refuses it; an item that is
    /// not a command keeps AppKit's answer, enabled when it has an action.
    func testTheAppDelegateAnswersOnlyTheAppsCommands() throws {
        let delegate = try XCTUnwrap(AppDelegate.shared)
        for command in Command.allCases {
            XCTAssertEqual(delegate.canPerform(command), command.scope == .app, command.rawValue)
        }
        let recent = NSMenuItem(title: "a.zip", action: #selector(AppDelegate.openRecent(_:)), keyEquivalent: "")
        XCTAssertTrue(delegate.validateMenuItem(recent))
        XCTAssertFalse(delegate.validateMenuItem(NSMenuItem(title: "none", action: nil, keyEquivalent: "")))
    }

    /// The app's commands, sent from their items as AppKit sends them, reach their methods: Help and Release Notes
    /// print their pages, Install Quick Actions says a copy outside Applications installs none, File Associations
    /// prints its question, and Settings opens its window, unseen.
    func testTheAppsCommandsReachTheirMethods() throws {
        func send(_ command: Command) throws -> String {
            let item = try barItem(command)
            return printed { XCTAssertTrue(NSApp.sendAction(.performCommand, to: item.target, from: item), command.rawValue) }
        }
        let readme = loc.current == .tr ? "README_TR.md" : "README.md"
        XCTAssertEqual(try send(.openHelp), "open https://github.com/ARAS-Workspace/MacRAR/blob/main/\(readme)\n")
        XCTAssertEqual(try send(.openReleaseNotes), "open https://github.com/ARAS-Workspace/MacRAR/blob/main/CHANGELOG\n")
        try withEnvironment(["MACRAR_DEBUG_PLACEMENT": "elsewhere"]) {
            let said = try send(.installQuickActions)
            XCTAssertTrue(said.hasPrefix(loc.t("quick_actions_need_applications_title", AppInfo.name) + ": "), said)
        }
        let asked = try send(.showAssociations)
        XCTAssertTrue(asked.hasPrefix(loc.t("assoc_title", AppInfo.name) + ": "), asked)
        XCTAssertEqual(try send(.showSettings), "")
        let window = try XCTUnwrap(PreferencesWindowController.shared.window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.alphaValue, 0)
    }

    /// A command its responder refuses is not run, even if it is sent; one it allows is.
    func testARefusedCommandIsNotPerformed() {
        final class Recorder: NSObject, CommandResponder {
            var performed: [Command] = []
            @objc func performCommand(_ sender: Any?) { performCommand(from: sender) }
            func canPerform(_ command: Command) -> Bool { command.scope == .app }
            func perform(_ command: Command) { performed.append(command) }
        }
        let recorder = Recorder()
        recorder.performCommand(NSMenuItem(.extractHere, title: "Extract Here", appTarget: recorder))
        recorder.performCommand(NSMenuItem(.openHelp, title: "Help", appTarget: recorder))
        XCTAssertEqual(recorder.performed, [.openHelp])
    }
}
