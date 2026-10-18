import XCTest
@testable import MacRAR

/// The debug variables answer every question the app asks before it comes up, so the tests and the copies of the app
/// they start never wait at an alert or a panel: MACRAR_DEBUG_CONFIRM prints a report, a page, a confirmation and a
/// question instead, answering the confirmation yes ("no" says no), the question with its first button and the file
/// associations Not Now, and prints an open or save panel's title as "choose <title>", which MACRAR_DEBUG_CHOOSE answers
/// with a path or it is cancelled; MACRAR_DEBUG_PASSWORD, MACRAR_DEBUG_PASSWORD_RETRY and MACRAR_DEBUG_OVERWRITE answer
/// their questions, which then print, with or without it. The update alert's answers are in LaunchQuestionsTests and
/// UpdateCheckerTests.
final class DebugAnswersTests: XCTestCase {
    override func setUp() {
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
    }

    func testAConfirmationPrintsAndIsAnsweredYesOrNo() {
        let output = printed {
            XCTAssertTrue(Dialogs.confirm("Delete 2 items?", "a.txt, b.txt", okTitle: loc.t("delete"), destructive: true))
            XCTAssertTrue(Dialogs.confirm("Extract?", "to Desktop"))
        }
        XCTAssertEqual(output, "confirm Delete 2 items?\nconfirm Extract?\n")
        withEnvironment(["MACRAR_DEBUG_CONFIRM": "no"]) { XCTAssertFalse(Dialogs.confirm("Extract?", "to Desktop")) }
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

    /// The first question and the one after a wrong password each take their own variable, printing which was asked; an
    /// empty answer is a password too.
    func testThePasswordQuestionsTakeTheirVariables() {
        withEnvironment(["MACRAR_DEBUG_PASSWORD": "şifre 1", "MACRAR_DEBUG_PASSWORD_RETRY": "şifre 2"]) {
            let output = printed {
                XCTAssertEqual(Dialogs.askPassword(archiveName: "x.7z"), "şifre 1")
                XCTAssertEqual(Dialogs.askPassword(archiveName: "x.7z", wrong: true), "şifre 2")
            }
            XCTAssertEqual(output, "password\npassword again\n")
        }
        withEnvironment(["MACRAR_DEBUG_PASSWORD": "", "MACRAR_DEBUG_PASSWORD_RETRY": "__cancel__"]) {
            XCTAssertEqual(Dialogs.askPassword(archiveName: "x.7z"), "")
            XCTAssertNil(Dialogs.askPassword(archiveName: "x.7z", wrong: true))
        }
    }

    func testTheOverwriteQuestionTakesItsVariable() {
        let answers: [String: Dialogs.OverwriteMode] = ["overwrite": .overwrite, "rename": .rename, "skip": .skip, "cancel": .cancel]
        for (value, mode) in answers {
            withEnvironment(["MACRAR_DEBUG_OVERWRITE": value]) {
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
        withEnvironment(["MACRAR_DEBUG_PLACEMENT": "downloaded"]) {
            XCTAssertEqual(printed { delegate.warnAboutPlacementWhenIdle() }, "\(title): \(message)\n")
        }
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
    }

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
