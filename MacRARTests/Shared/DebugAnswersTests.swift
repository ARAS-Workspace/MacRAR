import XCTest
@testable import MacRAR

/// A test run never shows an open or save panel, or the RAR tool's question: with MACRAR_DEBUG_CONFIRM a panel's
/// title goes to stdout as "choose <title>" and MACRAR_DEBUG_CHOOSE answers it with a path, or it is cancelled; the
/// RAR tool's question goes to stdout and is cancelled, so no test reaches the user's tool.
final class DebugAnswersTests: XCTestCase {
    override func setUp() { setDebugAnswers() }
    override func tearDown() { clearDebugAnswers() }

    func testPanelsAnswerThroughTheDebugVariables() {
        var folder: String? = "unset"
        var files: [String] = ["unset"]
        let asked = printed {
            folder = Dialogs.chooseFolder(title: "Pick a folder", prompt: "Choose")
            files = Dialogs.chooseFiles(title: "Pick files", prompt: "Open", archivesOnly: true)
        }
        XCTAssertTrue(asked.contains("choose Pick a folder") && asked.contains("choose Pick files"), asked)
        XCTAssertNil(folder, "the folder panel was not cancelled")
        XCTAssertEqual(files, [])

        withEnvironment(["MACRAR_DEBUG_CHOOSE": "/tmp/chosen"]) {
            XCTAssertEqual(Dialogs.chooseFolder(title: "Pick a folder", prompt: "Choose"), "/tmp/chosen")
            XCTAssertEqual(Dialogs.chooseFiles(title: "Pick files", prompt: "Open", archivesOnly: false), ["/tmp/chosen"])
        }
    }

    /// Create Archive's Browse button asks with the save panel.
    func testCreateArchivesSavePanelAnswersThroughTheDebugVariables() throws {
        let dialog = CompressDialog(options: CompressOptions(archivePath: "/a/x.zip", format: .zip), itemCount: 1)
        let content = try XCTUnwrap(dialog.window?.contentView)
        let path = try XCTUnwrap(fields(in: content).first { $0.stringValue == "/a/x.zip" })
        let asked = printed { dialog.browse() }
        XCTAssertTrue(asked.contains("choose \(loc.t("compress_save_panel_title"))"), asked)
        XCTAssertEqual(path.stringValue, "/a/x.zip", "a cancelled panel changed the path")
        withEnvironment(["MACRAR_DEBUG_CHOOSE": "/b/y.zip"]) { dialog.browse() }
        XCTAssertEqual(path.stringValue, "/b/y.zip")
        dialog.close()
    }

    func testTheRarToolsQuestionAnswersThroughTheDebugVariables() throws {
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(arguments.merging(["RarPath": "/nonexistent/rar"]) { $1 }, forName: UserDefaults.argumentDomain)
        guard !RarTools.available else { throw XCTSkip("a RAR tool is installed on this Mac outside the tests' reach") }
        var answered = true
        let asked = printed { answered = RarTools.ensureAvailable() }
        XCTAssertFalse(answered)
        XCTAssertTrue(asked.contains(loc.t("rar_tool_required_title")), asked)
    }

    private func fields(in root: NSView) -> [NSTextField] {
        root.subviews.flatMap { child in [child].compactMap { $0 as? NSTextField } + fields(in: child) }
    }
}
