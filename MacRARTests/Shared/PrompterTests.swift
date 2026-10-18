import XCTest
@testable import MacRAR

/// The questions are values the app hands one prompter, Dialogs.prompter: the debug answers in front of the alerts and
/// panels. Here an unseen screen stands in for those, so what the app asks can be read without an alert.
final class PrompterTests: XCTestCase {
    func testTheAppAsksThroughTheDebugAnswersInFrontOfTheScreen() throws {
        let prompter = try XCTUnwrap(Dialogs.prompter as? DebugPrompter)
        XCTAssertTrue(prompter.base is AppKitPrompter)
    }

    /// With the debug answers set, an unseen screen stands behind them: a question they leave unanswered is held there
    /// and fails the test, rather than coming up as an alert or panel that waits for a click. Clearing them puts the
    /// alerts and panels back.
    func testTheTestsHoldBackUnansweredQuestions() throws {
        setDebugAnswers()
        // Unwrapped rather than asserted: without the screen, the question below would come up as a real alert
        let held = try XCTUnwrap(Dialogs.prompter as? DebugPrompter)
        _ = try XCTUnwrap(held.base as? UnseenScreen)
        withoutEnvironment(["MACRAR_DEBUG_CONFIRM"]) { XCTAssertFalse(Dialogs.confirm("Delete?", "a.txt")) }
        XCTExpectFailure("the confirmation no variable answered is reported") { clearDebugAnswers() }
        let restored = try XCTUnwrap(Dialogs.prompter as? DebugPrompter)
        XCTAssertTrue(restored.base is AppKitPrompter)
    }

    /// Without the debug variables, everything goes on to the screen, as it is.
    func testWithoutTheVariablesEverythingReachesTheScreen() throws {
        let screen = UnseenScreen()
        let prompter = DebugPrompter(base: screen, environment: { [:] })
        let page = try XCTUnwrap(URL(string: "https://example.com"))
        let question = Question(topic: .question, title: "t", message: "m", buttons: ["OK", "Cancel"])
        XCTAssertEqual(prompter.ask(question), Answer(button: 1))
        prompter.report(Report(kind: .error, title: "e", detail: "d"))
        XCTAssertNil(prompter.askPassword(archiveName: "x.7z", wrong: false))
        XCTAssertEqual(prompter.askOverwrite(existing: ["a"], dest: "/tmp"), .cancel)
        XCTAssertEqual(prompter.choose(Panel(title: "p")), [])
        prompter.openInBrowser(page)
        XCTAssertEqual(screen.reached, [
            .ask(question), .report(Report(kind: .error, title: "e", detail: "d")), .password(archiveName: "x.7z", wrong: false),
            .overwrite(existing: ["a"], dest: "/tmp"), .choose(Panel(title: "p")), .open(page),
        ])
    }

    func testAConfirmationIsAQuestionWithItsButtons() {
        let screen = UnseenScreen()
        withPrompter(screen) {
            XCTAssertFalse(Dialogs.confirm("Delete?", "a.txt", okTitle: loc.t("delete"), destructive: true))
            XCTAssertFalse(Dialogs.confirm("Extract?", "b.txt"))
        }
        XCTAssertEqual(screen.reached, [
            .ask(Question(topic: .confirmation, title: "Delete?", message: "a.txt", style: .warning,
                          buttons: [loc.t("delete"), loc.t("cancel")], destructive: true)),
            .ask(Question(topic: .confirmation, title: "Extract?", message: "b.txt", buttons: [loc.t("ok"), loc.t("cancel")])),
        ])
    }

    /// The associations question lists every group of types, ticked as it starts, without an alert to look into.
    func testTheAssociationsQuestionListsTheGroups() throws {
        let screen = UnseenScreen()
        withPrompter(screen) { XCTAssertFalse(Associations.show()) }
        guard case .ask(let question) = try XCTUnwrap(screen.reached.first) else { return XCTFail("\(screen.reached)") }
        XCTAssertEqual(question.topic, .associations)
        XCTAssertEqual(question.buttons, [loc.t("assoc_make_default"), loc.t("assoc_not_now")])
        XCTAssertEqual(question.choices.map(\.title), Associations.groups.map(\.title))
        XCTAssertEqual(question.choices.map(\.warns), Associations.groups.map { $0.warning != nil })
    }

    /// The debug answers are read in DebugPrompter alone, and alerts, panels and web pages come up in AppKitPrompter
    /// alone: a question that read a variable of its own or built its own alert would come up in a test the variable
    /// was not set for. MACRAR_DEBUG_PASSWORD is also the password --compress makes an archive with under
    /// MACRAR_DEBUG_FORMAT, so the scan leaves it out; a window run modally, NSApp.runModal(for:), is not an alert, and a
    /// file opened in its app, NSWorkspace.shared.open(URL(fileURLWithPath:)), is not a page.
    func testTheQuestionsAreAnsweredAndShownInOnePlace() throws {
        let answer = NSRegularExpression(literal: #""MACRAR_DEBUG_(CONFIRM|PASSWORD_RETRY|OVERWRITE|UPDATE|CHOOSE|RARTOOL)""#)
        let shown = NSRegularExpression(
            literal: #"NSAlert\(|NSOpenPanel\(|NSSavePanel\(|\.runModal\(\)|NSWorkspace\.shared\.open\((?!URL\(fileURLWithPath:)"#)
        var answering = Set<String>(), showing = Set<String>()
        let files = try XCTUnwrap(FileManager.default.enumerator(at: Repository.sources, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            if answer.firstMatch(in: text, range: range) != nil { answering.insert(url.lastPathComponent) }
            if shown.firstMatch(in: text, range: range) != nil { showing.insert(url.lastPathComponent) }
        }
        XCTAssertEqual(answering, ["DebugPrompter.swift"])
        XCTAssertEqual(showing, ["AppKitPrompter.swift"])
    }

    /// Without RARLAB's rar, one question comes first: choose the tool already downloaded, open the download page, or
    /// cancel. The screen cancels it here, so neither the page nor a panel opens.
    func testTheRarToolQuestionIsAValue() {
        let screen = UnseenScreen()
        withPrompter(screen) { XCTAssertFalse(RarTools.askForTool()) }
        XCTAssertEqual(screen.reached, [
            .ask(Question(topic: .rarToolMissing, title: loc.t("rar_tool_required_title"), message: loc.t("rar_tool_required_message"),
                          buttons: [loc.t("rar_tool_choose_downloaded"), loc.t("rar_tool_open_download_page"), loc.t("cancel")])),
        ])
    }

    func testThePanelsAreValues() {
        let screen = UnseenScreen()
        withPrompter(screen) {
            XCTAssertNil(Dialogs.chooseFolder(title: "Extract to", prompt: "Extract", initial: "/tmp"))
            XCTAssertEqual(Dialogs.chooseFiles(title: "Open", prompt: "Open", archivesOnly: true), [])
        }
        XCTAssertEqual(screen.reached, [
            .choose(Panel(title: "Extract to", message: "Extract to", prompt: "Extract", files: false, folders: true,
                          createFolders: true, directory: URL(fileURLWithPath: "/tmp"))),
            .choose(Panel(title: "Open", message: "Open", prompt: "Open", folders: false, multiple: true, archivesOnly: true)),
        ])
    }
}
