import XCTest
@testable import MacRAR

/// The Help menu, last in the menu bar, opens the README in the app's language and the changelog, on this
/// distribution's repository. Adapted from MacRAR 1.4.3, whose menu also opened its releases and a new issue. The items
/// run as AppKit runs them, with MACRAR_DEBUG_CONFIRM printing the page instead of opening the browser; each test puts
/// back the language and the saved choice it found.
final class HelpMenuTests: XCTestCase {
    private var original: LocalizationManager.Language!
    private var saved: Any?

    override func setUp() {
        original = loc.current
        saved = UserDefaults.standard.object(forKey: LocalizationManager.defaultsKey)
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        loc.current = original
        UserDefaults.standard.set(saved, forKey: LocalizationManager.defaultsKey)
    }

    private func strings(_ language: LocalizationManager.Language) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: language.rawValue, withExtension: "json", subdirectory: "translations"))
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    func testTheHelpMenuOpensTheReadmeInTheAppsLanguageAndTheChangelog() throws {
        let readmes: [LocalizationManager.Language: String] = [.tr: "README_TR.md", .en: "README.md"]
        for language in LocalizationManager.Language.allCases {
            loc.current = language
            let text = try strings(language)
            let help = try XCTUnwrap(NSApp.helpMenu, "\(language)")
            XCTAssertTrue(NSApp.mainMenu?.items.last?.submenu === help, "\(language): Help is not the last menu")
            XCTAssertEqual(help.title, text["menu_help"])
            let titles = [try XCTUnwrap(text["menu_help_app"]).replacingOccurrences(of: "%@", with: "MacRAR"), text["menu_release_notes"]]
            XCTAssertEqual(help.items.map(\.title), titles, "\(language)")
            XCTAssertEqual(help.items.first?.keyEquivalent, "?")

            let opened = try help.items.map { item in
                try printed { XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item), item.title) }
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            XCTAssertEqual(opened, [
                "open https://github.com/ARAS-Workspace/MacRAR/blob/main/\(readmes[language] ?? "")",
                "open https://github.com/ARAS-Workspace/MacRAR/blob/main/CHANGELOG",
            ], "\(language)")
        }
    }
}
