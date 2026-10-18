import XCTest
@testable import MacRAR

/// The questions are values the app hands one prompter, Dialogs.prompter: the debug answers in front of the alerts and
/// panels. Here an unseen screen stands in for those, so what the app asks can be read without an alert.
final class PrompterTests: XCTestCase {
    /// The app asks through the debug answers; behind them stand the alerts and panels, or in a test run
    /// UnansweredPrompter (testATestRunNeverShowsAQuestion).
    func testTheAppAsksThroughTheDebugAnswersInFrontOfTheScreen() throws {
        let prompter = try XCTUnwrap(Dialogs.prompter as? DebugPrompter)
        XCTAssertTrue(prompter.base is UnansweredPrompter)
    }

    /// With the debug answers set, an unseen screen stands behind them: a question they leave unanswered is held there
    /// and fails the test, rather than coming up as an alert or panel that waits for a click. Clearing them puts the
    /// test run's default back.
    func testTheTestsHoldBackUnansweredQuestions() throws {
        setDebugAnswers()
        // Unwrapped rather than asserted: without the screen, the question below would come up as a real alert
        let held = try XCTUnwrap(Dialogs.prompter as? DebugPrompter)
        _ = try XCTUnwrap(held.base as? UnseenScreen)
        withoutEnvironment([.confirm]) { XCTAssertFalse(Dialogs.confirm("Delete?", "a.txt")) }
        XCTExpectFailure("the confirmation no variable answered is reported") { clearDebugAnswers() }
        let restored = try XCTUnwrap(Dialogs.prompter as? DebugPrompter)
        XCTAssertTrue(restored.base is UnansweredPrompter)
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
        let answer = NSRegularExpression(literal: #"DebugVariable\.(confirm|passwordRetry|overwrite|update|choose|rarTool)\b"#)
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
        withPrompter(screen) { XCTAssertFalse(RarTools.askForTool(into: "/nonexistent/rar")) }
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

    /// In a test run (MACRAR_DEBUG_UNSEEN) a question no debug variable answers never reaches a real alert or panel,
    /// whichever test class asks it: behind the debug answers stands UnansweredPrompter, which says what was asked and
    /// changes nothing. Behind them stood AppKitPrompter, whose alert waits for a click.
    func testATestRunNeverShowsAQuestion() throws {
        let front = try XCTUnwrap(Dialogs.defaultPrompter as? DebugPrompter)
        XCTAssertTrue(front.base is UnansweredPrompter, "\(type(of: front.base))")
        let unanswered = UnansweredPrompter()
        let question = Question(topic: .rarToolMissing, title: "Choose?", message: "", buttons: ["Choose", "Open", "Cancel"])
        var answer: Answer?, password: String? = "set", overwrite = Dialogs.OverwriteMode.overwrite, chosen = [URL(fileURLWithPath: "/")]
        let told = printed {
            answer = unanswered.ask(question)
            password = unanswered.askPassword(archiveName: "x.zip", wrong: false)
            overwrite = unanswered.askOverwrite(existing: ["a.txt"], dest: "/tmp")
            chosen = unanswered.choose(Panel(kind: .open, title: "Pick", message: "", prompt: "Open"))
        }
        XCTAssertEqual(answer, Answer(button: 2))
        XCTAssertNil(password)
        XCTAssertEqual(overwrite, .cancel)
        XCTAssertEqual(chosen, [])
        XCTAssertTrue(told.contains("unanswered Choose?") && told.contains("unanswered Pick"), told)
    }
}
