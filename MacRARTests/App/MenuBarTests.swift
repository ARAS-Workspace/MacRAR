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

    func testTheWindowHelpAndServicesMenusAndOpenRecentAreWired() throws {
        for language in languages {
            loc.current = language
            let items = try XCTUnwrap(NSApp.mainMenu?.items)
            guard items.count == MenuBarTable.menus.count else { return XCTFail("\(language): \(items.count) menus") }
            XCTAssertTrue(NSApp.windowsMenu === items[4].submenu, "\(language): AppKit is not told the Window menu")
            XCTAssertTrue(NSApp.helpMenu === items[5].submenu, "\(language): AppKit is not told the Help menu")
            let services = items[0].submenu?.items.first { $0.title == loc.t("menu_services") }?.submenu
            XCTAssertTrue(NSApp.servicesMenu === services, "\(language): AppKit is not told the Services menu")
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

    /// Rendering sends the app's commands to their target and the window's up the responder chain, and AppKit's own
    /// actions to AppKit's responders; the modifiers, Open Recent's delegate and the Window and Help roles come along.
    func testRenderingSendsTheAppsCommandsToTheirTargetAndTheWindowsUpTheChain() throws {
        let delegate = try XCTUnwrap(AppDelegate.shared)
        let menus = MenuBar.render(MenuSpec(loc: loc), appTarget: delegate, recent: delegate)
        let items = menus.main.items.flatMap { $0.submenu?.items ?? [] }
        // An item with a submenu, Open Recent's, is AppKit's: it sends submenuAction: to its submenu
        for item in items where item.action != nil && !item.hasSubmenu {
            if let command = Command(sender: item), command.scope == .app {
                XCTAssertTrue(item.target === delegate, "\(command) is not sent to the app delegate")
            } else {
                XCTAssertNil(item.target, item.title)
            }
        }
        XCTAssertEqual(try XCTUnwrap(items.first { Command(sender: $0) == .quickLook }).keyEquivalentModifierMask, [])
        XCTAssertEqual(try XCTUnwrap(items.first { Command(sender: $0) == .extractTo }).keyEquivalentModifierMask, [.command, .shift])
        XCTAssertTrue(try XCTUnwrap(items.first { $0.title == loc.t("menu_open_recent") }?.submenu).delegate === delegate)
        XCTAssertTrue(menus.windows === menus.main.items[4].submenu)
        XCTAssertTrue(menus.help === menus.main.items[5].submenu)
        XCTAssertTrue(menus.services === menus.main.items[0].submenu?.items.first { $0.title == loc.t("menu_services") }?.submenu)
        XCTAssertNotNil(menus.services)
    }

    /// A menu bar on a language manager of its own renders again when that language changes, and leaves the app's
    /// menu bar as it was.
    func testTheMenuBarRendersAgainWhenItsLanguageChanges() throws {
        let suite = "MacRARTests-MenuBar"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = LocalizationManager(defaults: defaults, environment: ["MACRAR_LANG": "en"])
        let appMenuBar = NSApp.mainMenu
        let bar = MenuBar(loc: manager, app: nil, appTarget: nil, recent: nil)
        bar.install()
        XCTAssertEqual(bar.menus?.main.items[1].submenu?.title, try strings(.en)["menu_file"])
        manager.current = .tr
        XCTAssertEqual(bar.menus?.main.items[1].submenu?.title, try strings(.tr)["menu_file"])
        XCTAssertTrue(NSApp.mainMenu === appMenuBar)
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
