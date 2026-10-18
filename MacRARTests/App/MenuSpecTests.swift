import XCTest
@testable import MacRAR

/// The menus as data, built from a language manager of the tests' own and an app name of their own, without NSApp:
/// rendered, they are MenuBarTable item for item in both languages; no two items share a key; every command is
/// offered; and key equivalents are given in MenuSpec alone.
final class MenuSpecTests: XCTestCase {
    /// Not the app's name, so the menus are seen to take the name they are given.
    private let appName = "Test Archiver"

    /// A manager in `language` over a suite nothing is saved to.
    private func manager(_ language: LocalizationManager.Language) throws -> LocalizationManager {
        LocalizationManager(defaults: try XCTUnwrap(UserDefaults(suiteName: "MacRARTests-MenuSpec")),
                            environment: [DebugVariable.language.rawValue: language.rawValue])
    }

    private func strings(_ language: LocalizationManager.Language) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: language.rawValue, withExtension: "json", subdirectory: "translations"))
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    private func commands(_ items: [MenuSpec.Item]) -> [Command] {
        items.compactMap { item in
            guard case .action(.command(let command), _, _) = item else { return nil }
            return command
        }
    }

    func testTheMenuBarInEnglishAndTurkish() throws {
        for language in LocalizationManager.Language.allCases {
            let text = try strings(language)
            let spec = MenuSpec(loc: try manager(language), appName: appName)
            XCTAssertEqual(spec.menus.map(\.role), [nil, nil, nil, nil, .windows, .help], "\(language)")
            let menus = try MenuBar.render(spec, appTarget: nil, recent: nil).main.items.map { try XCTUnwrap($0.submenu) }
            XCTAssertEqual(menus.count, MenuBarTable.menus.count, "\(language)")
            for (expected, menu) in zip(MenuBarTable.menus, menus) {
                XCTAssertEqual(menu.title, expected.titleKey.map { text[$0] ?? $0 } ?? "", "\(language)")
                assertInOrder(expected.rows, in: menu, text: text, appName: appName, exactly: true, "\(language) \(menu.title)")
            }
        }
    }

    func testTheArchiveWindowsContextMenuInEnglishAndTurkish() throws {
        for language in LocalizationManager.Language.allCases {
            let menu = MenuSpec.menu("", MenuSpec.archiveContextMenu(loc: try manager(language)), appTarget: nil, recent: nil)
            assertInOrder(MenuBarTable.contextMenu, in: menu, text: try strings(language), appName: appName, exactly: true,
                          "\(language) context menu")
        }
    }

    func testNoTwoItemsShareAKeyEquivalent() throws {
        let shortcuts = MenuSpec(loc: try manager(.en), appName: appName).menus.flatMap(\.items).compactMap { item -> String? in
            guard case .action(_, _, let shortcut?) = item else { return nil }
            return "\(shortcut.modifiers.rawValue) \(shortcut.key)"
        }
        XCTAssertFalse(shortcuts.isEmpty)
        XCTAssertEqual(shortcuts.count, Set(shortcuts).count, "\(shortcuts.sorted())")
    }

    /// Every command is in the menu bar or the context menu, and none twice in the menu bar.
    func testEveryCommandIsOffered() throws {
        let loc = try manager(.en)
        let bar = commands(MenuSpec(loc: loc, appName: appName).menus.flatMap(\.items))
        let context = commands(MenuSpec.archiveContextMenu(loc: loc))
        XCTAssertEqual(Set(bar).union(context), Set(Command.allCases))
        XCTAssertEqual(bar.count, Set(bar).count, "a command is offered twice in the menu bar")
    }

    /// Key equivalents are given in MenuSpec alone, so that two can never be given for one key unseen: elsewhere only
    /// a dialog's Return and Esc, and in SwiftUI only the default and cancel actions.
    func testKeyEquivalentsAreGivenOnlyInMenuSpec() throws {
        let given = NSRegularExpression(
            literal: #"keyEquivalent\s*[:=]\s*"(?!"|\\r"|\\u\{1b\}")|\.keyboardShortcut\((?!\.defaultAction|\.cancelAction)"#)
        let shortcut = NSRegularExpression(literal: #"\bShortcut\("#)
        var givingKeys = Set<String>()
        let files = try XCTUnwrap(FileManager.default.enumerator(at: Repository.sources, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            let inMenuSpec = url.lastPathComponent.hasPrefix("MenuSpec")
            if given.firstMatch(in: text, range: range) != nil || (!inMenuSpec && shortcut.firstMatch(in: text, range: range) != nil) {
                givingKeys.insert(url.lastPathComponent)
            }
        }
        XCTAssertEqual(givingKeys, [])
    }
}
