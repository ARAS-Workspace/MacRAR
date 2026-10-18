import XCTest
@testable import MacRAR

/// The debug variables' names are written in DebugVariable alone, but the scheme in project.yml sets its variables by
/// name: each name it sets is one of DebugVariable's, or an action would set a variable the app never reads.
final class DebugVariableTests: XCTestCase {
    func testTheSchemeSetsOnlyTheAppsVariables() throws {
        let project = try String(contentsOf: Repository.root.appendingPathComponent("project.yml"), encoding: .utf8)
        let names = NSRegularExpression(literal: "MACRAR_[A-Z_]+")
            .matches(in: project, range: NSRange(project.startIndex..., in: project))
            .compactMap { Range($0.range, in: project).map { String(project[$0]) } }
        XCTAssertEqual(Set(names), [DebugVariable.noUpdateCheck.rawValue, DebugVariable.unseen.rawValue])
    }
}
