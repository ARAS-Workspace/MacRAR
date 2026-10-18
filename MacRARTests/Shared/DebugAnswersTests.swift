import XCTest
@testable import MacRAR

/// The debug variables answer every question the app asks before it comes up, so the tests and the copies of the app
/// they start never wait at an alert: MACRAR_DEBUG_CONFIRM prints a report, a page and a question instead, answering
/// a confirmation yes unprinted, a question with its first button and the file associations Not Now, and prints a
/// panel's title, answered with MACRAR_DEBUG_CHOOSE's path or cancelled, and the RAR tool's questions, cancelled unless
/// MACRAR_DEBUG_RARTOOL picks a way; MACRAR_DEBUG_PASSWORD,
/// MACRAR_DEBUG_PASSWORD_RETRY and MACRAR_DEBUG_OVERWRITE answer their questions with or without it. The update alert's
/// answers are in LaunchQuestionsTests and UpdateCheckerTests.
final class DebugAnswersTests: XCTestCase {
    override func setUp() {
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
    }

    func testAConfirmationIsAnsweredYesUnprinted() {
        let output = printed {
            XCTAssertTrue(Dialogs.confirm("Delete 2 items?", "a.txt, b.txt", okTitle: loc.t("delete"), destructive: true))
            XCTAssertTrue(Dialogs.confirm("Extract?", "to Desktop"))
        }
        XCTAssertEqual(output, "")
    }

    /// An error prints its title and detail as given, without the tool's output it carries for the alert to copy, and
    /// an empty detail stays empty.
    func testAReportPrintsItsTitleAndDetail() {
        XCTAssertEqual(printed { Dialogs.error("Extraction failed", "CRC failed in a.txt", details: "full\noutput") },
                       "Extraction failed: CRC failed in a.txt\n")
        XCTAssertEqual(printed { Dialogs.error("Extraction failed", "") }, "Extraction failed: \n")
        XCTAssertEqual(printed { Dialogs.info("Test passed", "x.zip is intact") }, "Test passed: x.zip is intact\n")
    }

    func testAPageIsPrintedInsteadOfOpened() throws {
        let page = try XCTUnwrap(URL(string: "https://www.rarlab.com/download.htm"))
        XCTAssertEqual(printed { Dialogs.openInBrowser(page) }, "open https://www.rarlab.com/download.htm\n")
    }

    /// The first question and the one after a wrong password each take their own variable, printing nothing; an empty
    /// answer is a password too.
    func testThePasswordQuestionsTakeTheirVariables() {
        withEnvironment([.password: "şifre 1", .passwordRetry: "şifre 2"]) {
            let output = printed {
                XCTAssertEqual(Dialogs.askPassword(archiveName: "x.7z"), "şifre 1")
                XCTAssertEqual(Dialogs.askPassword(archiveName: "x.7z", wrong: true), "şifre 2")
            }
            XCTAssertEqual(output, "")
        }
        withEnvironment([.password: "", .passwordRetry: "__cancel__"]) {
            XCTAssertEqual(Dialogs.askPassword(archiveName: "x.7z"), "")
            XCTAssertNil(Dialogs.askPassword(archiveName: "x.7z", wrong: true))
        }
    }

    func testTheOverwriteQuestionTakesItsVariable() {
        let answers: [String: Dialogs.OverwriteMode] = ["overwrite": .overwrite, "rename": .rename, "skip": .skip, "cancel": .cancel]
        for (value, mode) in answers {
            withEnvironment([.overwrite: value]) {
                XCTAssertEqual(Dialogs.askOverwrite(existing: ["a.txt"], dest: "/tmp/out"), mode, value)
            }
        }
    }

    /// The file associations question prints and is answered Not Now, leaving the user's associations as they are.
    func testTheAssociationsQuestionIsAnsweredNotNow() {
        let title = loc.t("assoc_title", AppInfo.name)
        let message = loc.t("assoc_message_first_launch") + "\n\n" + loc.t("assoc_confirm_note")
        XCTAssertEqual(printed { XCTAssertFalse(Associations.show(firstLaunch: true)) }, "\(title): \(message)\n")
    }

    /// A downloaded copy's placement warning prints, answered OK with "Don't show this again" left unticked.
    func testThePlacementWarningPrintsAndStaysOn() throws {
        let key = QuickActions.placementWarningOffKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        let title = loc.t("quick_actions_need_applications_title", AppInfo.name)
        let message = loc.t("quick_actions_need_applications_message", AppInfo.name, AppInfo.name)
        let delegate = try XCTUnwrap(AppDelegate.shared)
        withEnvironment([.placement: "downloaded"]) {
            XCTAssertEqual(printed { delegate.warnAboutPlacementWhenIdle() }, "\(title): \(message)\n")
        }
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
    }

    /// Without RARLAB's rar, its questions print and are cancelled unless MACRAR_DEBUG_RARTOOL picks a way: choose, the
    /// tool already downloaded, through the panel; or download, the page printed instead of opened, then the tool once
    /// downloaded, through the panel. With no path to choose nothing is installed, and the questions are told a folder
    /// that does not exist rather than the app's own. They used to come up.
    func testTheRarToolQuestionsTakeTheDebugAnswers() {
        let required = "\(loc.t("rar_tool_required_title")): \(loc.t("rar_tool_required_message"))\n"
        let waiting = "\(loc.t("rar_tool_wait_title")): \(loc.t("rar_tool_wait_message"))\n"
        let panel = "choose \(loc.t("rar_tool_panel_title"))\n"
        let page = "open \(RarTools.downloadPage.absoluteString)\n"
        let ways: [(way: String?, printed: String)] = [
            (nil, required), ("choose", required + panel), ("download", required + page + waiting + panel),
        ]
        for (way, expected) in ways {
            var reached: [UnseenScreen.Prompt] = []
            let output = printed {
                withEnvironment(way.map { [.rarTool: $0] } ?? [:]) {
                    reached = reachingTheScreen { XCTAssertFalse(RarTools.askForTool(into: "/nonexistent/rar")) }
                }
            }
            XCTAssertEqual(reached, [], way ?? "unanswered")
            XCTAssertEqual(output, expected, way ?? "unanswered")
        }
    }

    /// The open and save panels print their titles and are cancelled: Extract To's folder, Open's and Add Files' files,
    /// and Create Archive's Browse. They used to come up.
    func testThePanelsTakeTheDebugAnswers() {
        var reached: [UnseenScreen.Prompt] = []
        let output = printed {
            reached = reachingTheScreen {
                XCTAssertNil(Dialogs.chooseFolder(title: "Extract to", prompt: "Extract"))
                XCTAssertEqual(Dialogs.chooseFiles(title: "Open", prompt: "Open", archivesOnly: true), [])
                XCTAssertEqual(Dialogs.choose(Panel(kind: .save, title: "Save", name: "x.zip")), [])
            }
        }
        XCTAssertEqual(reached, [])
        XCTAssertEqual(output, "choose Extract to\nchoose Open\nchoose Save\n")
    }

    /// MACRAR_DEBUG_CHOOSE answers a panel with the path it gives, a folder or a file alike.
    func testAPanelTakesThePathItIsGiven() {
        withEnvironment([.choose: "/tmp/çıktı"]) {
            let output = printed {
                XCTAssertEqual(Dialogs.chooseFolder(title: "Extract to", prompt: "Extract"), "/tmp/çıktı")
                XCTAssertEqual(Dialogs.chooseFiles(title: "Add", prompt: "Add", archivesOnly: false), ["/tmp/çıktı"])
            }
            XCTAssertEqual(output, "choose Extract to\nchoose Add\n")
        }
    }
}
