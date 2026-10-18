import AppKit
import XCTest

/// One item the user meets in a menu: a separator, or a title from translations/<language>.json, with `%@` standing
/// for the app's name, and its key and modifiers. An item without a key is matched whatever its mask: AppKit clears
/// the mask of an item it gives a ⌥ alternate, as it does in the Window menu with a second display.
struct MenuRow {
    let titleKey: String?
    let key: String
    let modifiers: NSEvent.ModifierFlags

    static let separator = MenuRow(titleKey: nil, key: "", modifiers: .command)

    static func item(_ titleKey: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> MenuRow {
        MenuRow(titleKey: titleKey, key: key, modifiers: modifiers)
    }
}

/// A menu of the menu bar: its title (none for the app menu) and its items in order.
struct ExpectedMenu {
    let titleKey: String?
    let rows: [MenuRow]
}

/// The menu bar and the archive window's context menu as the user meets them, written out here rather than taken
/// from the code that builds them.
enum MenuBarTable {
    static let menus = [app, file, edit, view, window, help]

    static let app = ExpectedMenu(titleKey: nil, rows: [
        .item("menu_about"), .item("menu_check_for_updates"), .separator,
        .item("menu_settings", ","), .separator,
        .item("action_file_associations"), .item("menu_install_quick_actions"), .separator,
        .item("menu_hide_app", "h"), .item("menu_hide_others", "h", [.command, .option]), .item("menu_show_all"), .separator,
        .item("menu_quit_app", "q"),
    ])

    static let file = ExpectedMenu(titleKey: "menu_file", rows: [
        .item("action_open_archive", "o"), .item("action_new_archive", "n"), .item("menu_open_recent"), .separator,
        .item("action_extract_here", "e"), .item("action_extract_to_folder", "e", [.command, .option]),
        .item("action_extract_to", "e", [.command, .shift]),
        .item("action_extract_selected_here"), .item("action_extract_selected_to"), .separator,
        .item("action_test_archive", "t"), .item("action_archive_info", "i"), .separator,
        // U+0008 is the Delete key
        .item("action_add_files", "a", [.command, .shift]), .item("action_delete_selected", "\u{8}"), .separator,
        .item("menu_close", "w"),
    ])

    static let edit = ExpectedMenu(titleKey: "menu_edit", rows: [
        .item("menu_undo", "z"), .item("menu_redo", "z", [.command, .shift]), .separator,
        .item("menu_cut", "x"), .item("menu_copy", "c"), .item("menu_paste", "v"), .item("menu_select_all", "a"),
    ])

    static let view = ExpectedMenu(titleKey: "menu_view", rows: [
        .item("action_quick_look", " ", []), .separator,
        // NSRightArrowFunctionKey and NSLeftArrowFunctionKey
        .item("action_expand_all", "\u{F703}", [.command, .option]),
        .item("action_collapse_all", "\u{F702}", [.command, .option]), .separator,
        .item("action_refresh", "r"), .item("action_show_in_finder", "r", [.command, .shift]),
    ])

    static let window = ExpectedMenu(titleKey: "menu_window", rows: [
        .item("menu_minimize", "m"), .item("menu_zoom"), .separator, .item("menu_bring_all_to_front"),
    ])

    static let help = ExpectedMenu(titleKey: "menu_help", rows: [.item("menu_help_app", "?"), .item("menu_release_notes")])

    static let contextMenu: [MenuRow] = [
        .item("open"), .item("action_quick_look"), .separator,
        .item("action_extract_selected_here"), .item("action_extract_selected_to"), .separator,
        .item("action_delete_from_archive"),
    ]
}

extension XCTestCase {
    /// The rows are in the menu in this order with their titles in `text`, their keys and modifiers. AppKit adds items
    /// of its own to some menus (Close All, Writing Tools, AutoFill, Start Dictation, Emoji & Symbols, the window
    /// list), so other items may sit between them unless `exactly` is set.
    func assertInOrder(_ rows: [MenuRow], in menu: NSMenu, text: [String: String], appName: String, exactly: Bool = false,
                       _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        if exactly {
            XCTAssertEqual(menu.items.count, rows.count, "\(label): \(menu.items.map(\.title))", file: file, line: line)
        }
        var remaining = menu.items[...]
        for row in rows {
            let title: String?
            if let key = row.titleKey {
                guard let translated = text[key] else { return XCTFail("\(label): \(key) is not translated", file: file, line: line) }
                title = translated.replacingOccurrences(of: "%@", with: appName)
            } else {
                title = nil
            }
            let match = remaining.firstIndex { item in
                guard let title else { return item.isSeparatorItem }
                return !item.isSeparatorItem && item.title == title && appKey(of: item) == row.key
                    && (row.key.isEmpty || item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == row.modifiers)
            }
            guard let match, !exactly || match == remaining.startIndex else {
                let wanted = title.map { "\(describe($0, row.key, row.modifiers))" } ?? "a separator"
                let namesake = menu.items.first { !$0.isSeparatorItem && $0.title == title }
                    .map { " (the menu has \(describe($0.title, appKey(of: $0), $0.keyEquivalentModifierMask)))" } ?? ""
                return XCTFail("\(label): \(wanted) is missing or out of order\(namesake) in \(menu.items.map(\.title))",
                               file: file, line: line)
            }
            remaining = menu.items[(match + 1)...]
        }
    }

    /// The key the app gave an item. AppKit moves some keys to where the user's keyboard layout has them, a moment
    /// after a menu is built (on Turkish Q, ⌘, reads as ⌘ö), unless the item does not allow it.
    private func appKey(of item: NSMenuItem) -> String {
        let allows = item.allowsAutomaticKeyEquivalentLocalization
        item.allowsAutomaticKeyEquivalentLocalization = false
        defer { item.allowsAutomaticKeyEquivalentLocalization = allows }
        return item.keyEquivalent
    }

    /// A title with its modifiers and key as a menu shows them; keys outside the printable range by number.
    private func describe(_ title: String, _ key: String, _ modifiers: NSEvent.ModifierFlags) -> String {
        let names: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let keys = key.unicodeScalars.map { $0.value < 0x20 || $0.value > 0xF000 ? String(format: "U+%04X", $0.value) : String($0) }
        return "\(title) [\(names.filter { modifiers.contains($0.0) }.map(\.1).joined())\(keys.joined())]"
    }
}
