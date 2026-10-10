import XCTest
@testable import MacRAR

/// Every Finder Quick Action calls the app with a command-line mode it understands.
final class QuickActionsTests: XCTestCase {
    func testEveryQuickActionFlagIsAMode() {
        for flag in QuickActions.actions.compactMap(\.flag) {
            XCTAssertNotNil(LaunchArguments([flag, "/a/x.zip"]).command, flag)
        }
    }

    func testInstallWritesAWorkflowPerAction() throws {
        let workspace = try Workspace()
        let directory = try workspace.makeDirectory("Services")
        XCTAssertEqual(QuickActions.installAll(in: directory, registerWithFinder: false), QuickActions.actions.count)
        for action in QuickActions.actions {
            let workflow = try String(contentsOfFile: "\(directory)/\(action.name).workflow/Contents/document.wflow", encoding: .utf8)
            XCTAssertTrue(workflow.contains(Bundle.main.bundlePath), action.name)
            XCTAssertTrue(workflow.contains(action.flag.map { "--args \($0) " } ?? "open -a "), action.name)
        }
    }
}
