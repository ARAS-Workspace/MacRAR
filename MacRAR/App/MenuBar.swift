import AppKit

/// The menu bar: MenuSpec in the language chosen, rendered into NSApp's menus, and rendered again whenever the
/// language changes. The app's commands go to `appTarget`; the window's go up the responder chain to the window in
/// front.
final class MenuBar: NSObject {
    /// What one rendering made: the main menu, and the Window and Help menus NSApp is told about.
    struct Menus {
        let main: NSMenu
        let windows: NSMenu?
        let help: NSMenu?
    }

    private let loc: LocalizationManager
    private let app: NSApplication?
    private weak var appTarget: CommandResponder?
    private weak var recent: NSMenuDelegate?
    /// The menus last rendered.
    private(set) var menus: Menus?

    /// A menu bar for `app`; nil renders without showing, for the tests.
    init(loc: LocalizationManager, app: NSApplication?, appTarget: CommandResponder?, recent: NSMenuDelegate?) {
        self.loc = loc
        self.app = app
        self.appTarget = appTarget
        self.recent = recent
    }

    /// Shows the menu bar and keeps it in the language chosen.
    func install() {
        render()
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageDidChange), name: LocalizationManager.didChange, object: loc)
    }

    @objc private func languageDidChange() { render() }

    private func render() {
        let rendered = Self.render(MenuSpec(loc: loc), appTarget: appTarget, recent: recent)
        menus = rendered
        guard let app else { return }
        app.windowsMenu = rendered.windows
        app.helpMenu = rendered.help
        app.mainMenu = rendered.main
    }

    /// The NSMenus of `spec`, one item of the main menu per menu.
    static func render(_ spec: MenuSpec, appTarget: CommandResponder?, recent: NSMenuDelegate?) -> Menus {
        let main = NSMenu()
        var windows: NSMenu?, help: NSMenu?
        for menu in spec.menus {
            let rendered = MenuSpec.menu(menu.title, menu.items, appTarget: appTarget, recent: recent)
            let item = NSMenuItem()
            main.addItem(item)
            item.submenu = rendered
            switch menu.role {
            case .windows: windows = rendered
            case .help: help = rendered
            case nil: break
            }
        }
        return Menus(main: main, windows: windows, help: help)
    }
}
