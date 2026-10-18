import AppKit

/// The menu bar: MenuSpec in the language chosen, rendered into NSApp's menus, and rendered again whenever the
/// language changes. The app's commands go to `appTarget`; the window's go up the responder chain to the window in
/// front.
final class MenuBar: NSObject {
    /// What one rendering made: the main menu, and the Window, Help and Services menus NSApp is told about.
    struct Menus {
        let main: NSMenu
        let windows: NSMenu?
        let help: NSMenu?
        let services: NSMenu?
    }

    private let loc: LocalizationManager
    private let app: NSApplication?
    private weak var appTarget: CommandResponder?
    private weak var recent: NSMenuDelegate?
    /// The menus last rendered.
    private(set) var menus: Menus?
    /// The Services menu AppKit was told about and fills. NSApp takes the first servicesMenu it is given and keeps it,
    /// so every later rendering puts this one under its Services item.
    private var services: NSMenu?

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
        // A menu is the submenu of one item at a time: off the item of the last rendering first
        services?.supermenu?.items.first { $0.submenu === services }?.submenu = nil
        let rendered = Self.render(MenuSpec(loc: loc), appTarget: appTarget, recent: recent, services: services)
        services = rendered.services
        menus = rendered
        guard let app else { return }
        app.windowsMenu = rendered.windows
        app.helpMenu = rendered.help
        app.servicesMenu = rendered.services
        app.mainMenu = rendered.main
    }

    /// The NSMenus of `spec`, one item of the main menu per menu; the Services submenu is `kept` when it is given.
    static func render(_ spec: MenuSpec, appTarget: CommandResponder?, recent: NSMenuDelegate?, services kept: NSMenu? = nil) -> Menus {
        let main = NSMenu()
        var windows: NSMenu?, help: NSMenu?, services: NSMenu?
        for menu in spec.menus {
            let rendered = MenuSpec.menu(menu.title, menu.items, appTarget: appTarget, recent: recent, services: kept)
            // Each item of the spec is one item of the menu
            for (item, renderedItem) in zip(menu.items, rendered.items) {
                if case .submenu(.services, _) = item { services = renderedItem.submenu }
            }
            let item = NSMenuItem()
            main.addItem(item)
            item.submenu = rendered
            switch menu.role {
            case .windows: windows = rendered
            case .help: help = rendered
            case nil: break
            }
        }
        return Menus(main: main, windows: windows, help: help, services: services)
    }
}
