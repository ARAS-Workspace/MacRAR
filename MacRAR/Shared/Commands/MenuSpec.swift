import AppKit

/// Menus as data: each item's title in the current language, what it runs and its key equivalent. Built from `loc`
/// alone, so both languages are tested without NSApp; `MenuSpec.menu(_:_:appTarget:recent:)` and MenuBar render it.
struct MenuSpec: Equatable {
    /// A key equivalent: the key, and the modifiers held with it.
    struct Shortcut: Equatable {
        let key: String
        let modifiers: NSEvent.ModifierFlags

        init(_ key: String, _ modifiers: NSEvent.ModifierFlags = .command) {
            self.key = key
            self.modifiers = modifiers
        }
    }

    /// What an item runs: one of the app's commands, or an action AppKit's own responders answer.
    enum Action: Equatable {
        case command(Command)
        case standard(Selector)
    }

    /// The submenus that fill themselves.
    enum Submenu: Equatable {
        /// File > Open Recent, filled from the recent documents each time it opens.
        case openRecent
    }

    enum Item: Equatable {
        case action(Action, title: String, shortcut: Shortcut?)
        case submenu(Submenu, title: String)
        case separator
    }

    /// The menus NSApp is told about: the Window menu lists the open windows, the Help menu gets the search field.
    enum Role: Equatable {
        case windows, help
    }

    struct Menu: Equatable {
        let title: String
        let role: Role?
        let items: [Item]
    }

    let menus: [Menu]

    static func command(_ command: Command, _ title: String, _ shortcut: Shortcut? = nil) -> Item {
        .action(.command(command), title: title, shortcut: shortcut)
    }

    static func standard(_ action: Selector, _ title: String, _ shortcut: Shortcut? = nil) -> Item {
        .action(.standard(action), title: title, shortcut: shortcut)
    }

    /// The menu for `items`: the app's commands go to `appTarget`, the window's up the responder chain, AppKit's
    /// actions to AppKit's responders.
    static func menu(_ title: String, _ items: [Item], appTarget: CommandResponder?, recent: NSMenuDelegate?) -> NSMenu {
        let menu = NSMenu(title: title)
        for item in items {
            switch item {
            case .action(let action, let title, let shortcut):
                let rendered: NSMenuItem
                switch action {
                case .command(let command):
                    rendered = NSMenuItem(command, title: title, keyEquivalent: shortcut?.key ?? "", appTarget: appTarget)
                case .standard(let selector):
                    rendered = NSMenuItem(title: title, action: selector, keyEquivalent: shortcut?.key ?? "")
                }
                if let shortcut { rendered.keyEquivalentModifierMask = shortcut.modifiers }
                menu.addItem(rendered)
            case .submenu(.openRecent, let title):
                let parent = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
                let recentMenu = NSMenu(title: title)
                recentMenu.delegate = recent
                parent.submenu = recentMenu
            case .separator:
                menu.addItem(.separator())
            }
        }
        return menu
    }
}
