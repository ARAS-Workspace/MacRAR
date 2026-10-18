import XCTest
@testable import MacRAR

/// The menu bar and the archive window's context menu as MenuBarTable writes them out, in both languages: every item
/// in order, its title from the translations, its key and modifiers, and the menus AppKit is told about; and the
/// pages the Help menu opens. The tests switch the app's own language, so each one puts back the language and the
/// saved choice it found, and MACRAR_DEBUG_CONFIRM prints a page instead of opening the browser.
final class MenuBarTests: XCTestCase {
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

    /// The language the app is in first, then the other one, which the menus are built again for.
    private var languages: [LocalizationManager.Language] { [loc.current, loc.current == .tr ? .en : .tr] }

    private func strings(_ language: LocalizationManager.Language) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: language.rawValue, withExtension: "json", subdirectory: "translations"))
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    func testEveryMenuHasItsItemsInOrderWithTheirKeysInBothLanguages() throws {
        for language in languages {
            loc.current = language
            let text = try strings(language)
            let menus = try XCTUnwrap(NSApp.mainMenu).items.map(\.submenu)
            XCTAssertEqual(menus.count, MenuBarTable.menus.count, "\(language)")
            for (expected, menu) in zip(MenuBarTable.menus, menus) {
                let menu = try XCTUnwrap(menu, "\(language)")
                if let titleKey = expected.titleKey {
                    XCTAssertEqual(menu.title, text[titleKey], "\(language)")
                }
                assertInOrder(expected.rows, in: menu, text: text, appName: AppInfo.name, "\(language) \(menu.title)")
            }
        }
    }

    /// A row without a key matches its item whatever mask the item holds: AppKit clears a keyless item's mask when it
    /// gives the item a ⌥ alternate, as it does in the Window menu with a second display. A row with a key still needs
    /// its modifiers.
    func testAKeylessItemMatchesWhateverItsMask() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Zoom", action: nil, keyEquivalent: "").keyEquivalentModifierMask = []
        menu.addItem(withTitle: "Close", action: nil, keyEquivalent: "w").keyEquivalentModifierMask = [.command, .option]
        let text = ["menu_zoom": "Zoom", "menu_close": "Close"]
        assertInOrder([.item("menu_zoom")], in: menu, text: text, appName: "", "keyless")
        XCTExpectFailure("a key's modifiers count") {
            assertInOrder([.item("menu_close", "w")], in: menu, text: text, appName: "", "keyed")
        }
    }

    func testTheWindowAndHelpMenusAndOpenRecentAreWired() throws {
        for language in languages {
            loc.current = language
            let items = try XCTUnwrap(NSApp.mainMenu?.items)
            guard items.count == MenuBarTable.menus.count else { return XCTFail("\(language): \(items.count) menus") }
            XCTAssertTrue(NSApp.windowsMenu === items[4].submenu, "\(language): AppKit is not told the Window menu")
            XCTAssertTrue(NSApp.helpMenu === items[5].submenu, "\(language): AppKit is not told the Help menu")
            let recent = try XCTUnwrap(items[1].submenu?.items.first { $0.title == loc.t("menu_open_recent") }?.submenu)
            XCTAssertTrue(recent.delegate === AppDelegate.shared, "\(language): Open Recent is not filled")
        }
    }

    func testTheArchiveWindowsContextMenuInBothLanguages() throws {
        let controller = ArchiveWindowController()
        for language in languages {
            loc.current = language
            let menu = try XCTUnwrap(controller.outline.menu, "\(language)")
            assertInOrder(MenuBarTable.contextMenu, in: menu, text: try strings(language), appName: AppInfo.name,
                          exactly: true, "\(language) context menu")
        }
    }

    /// The Help menu opens the README in the app's language and the changelog, on this distribution's repository.
    /// Adapted from MacRAR 1.4.3, whose menu also opened its releases and a new issue. The items run as AppKit runs
    /// them.
    func testTheHelpMenuOpensTheReadmeInTheAppsLanguageAndTheChangelog() throws {
        let readmes: [LocalizationManager.Language: String] = [.tr: "README_TR.md", .en: "README.md"]
        for language in languages {
            loc.current = language
            let help = try XCTUnwrap(NSApp.helpMenu, "\(language)")
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
