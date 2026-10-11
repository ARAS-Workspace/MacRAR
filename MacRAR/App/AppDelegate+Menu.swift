import AppKit

/// The menu bar, its Open Recent submenu and the About panel; the menus are built again when the language changes.
extension AppDelegate {
    // MARK: Open Recent menu
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        for url in urls.prefix(15) {
            let item = menu.addItem(withTitle: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.representedObject = url.path
            item.image = NSWorkspace.shared.icon(forFile: url.path); item.image?.size = NSSize(width: 16, height: 16)
            item.toolTip = url.path
            item.target = self
        }
        if urls.isEmpty {
            let none = menu.addItem(withTitle: "—", action: nil, keyEquivalent: ""); none.isEnabled = false
        } else {
            menu.addItem(.separator())
            let clear = menu.addItem(withTitle: loc.t("menu_clear_recent"), action: #selector(clearRecent(_:)), keyEquivalent: "")
            clear.target = self
        }
    }
    @objc func openRecent(_ sender: NSMenuItem) { if let path = sender.representedObject as? String { openArchive(path, reuse: nil) } }
    @objc func clearRecent(_ sender: Any?) { NSDocumentController.shared.clearRecentDocuments(nil) }

    @objc func installQuickActionsAction(_ sender: Any?) { installQuickActions() }

    // MARK: About

    @objc func showAbout(_ sender: Any?) {
        let credits = NSMutableAttributedString()
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor, .paragraphStyle: para,
        ]
        credits.append(NSAttributedString(string: loc.t("about_developer"), attributes: base))
        var link = base
        link[.link] = URL(string: "https://github.com/mstcvk/MacRAR")!
        link[.foregroundColor] = NSColor.linkColor
        credits.append(NSAttributedString(string: "github.com/mstcvk/MacRAR", attributes: link))
        credits.append(
            NSAttributedString(
                string: loc.t("about_third_party"),
                attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para]))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationVersion: AppInfo.version,
            .applicationName: AppInfo.name,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 Mesut Çevik",
        ])
    }

    // MARK: Menu

    /// A language change: the menus are rebuilt and the Finder Quick Actions take their new names.
    @objc func languageDidChange() {
        buildMenu()
        if QuickActions.ownedByThisCopy { QuickActions.relocalize() }
    }

    /// The menu bar in the current language: the app, File, Edit, View, Window and Help menus.
    func buildMenu() {
        let main = NSMenu()
        let window = windowMenu(), help = helpMenu()
        for menu in [appMenu(), fileMenu(), editMenu(), viewMenu(), window, help] {
            let item = NSMenuItem()
            main.addItem(item)
            item.submenu = menu
        }
        NSApp.windowsMenu = window
        NSApp.helpMenu = help
        NSApp.mainMenu = main
    }

    /// About, updates, Settings, associations and Quick Actions, then hiding and quitting.
    private func appMenu() -> NSMenu {
        let app = NSMenu()
        app.addItem(withTitle: loc.t("menu_about", AppInfo.name), action: #selector(showAbout(_:)), keyEquivalent: "")
        app.addItem(withTitle: loc.t("menu_check_for_updates"), action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: loc.t("menu_settings"), action: #selector(showPreferences(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: loc.t("action_file_associations"), action: #selector(showAssociations(_:)), keyEquivalent: "")
        app.addItem(withTitle: loc.t("menu_install_quick_actions"), action: #selector(installQuickActionsAction(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: loc.t("menu_hide_app", AppInfo.name), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(
            withTitle: loc.t("menu_hide_others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: loc.t("menu_show_all"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: loc.t("menu_quit_app", AppInfo.name), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return app
    }

    /// Opening, creating, extracting, testing and changing archives.
    private func fileMenu() -> NSMenu {
        let file = NSMenu(title: loc.t("menu_file"))
        file.addItem(
            withTitle: loc.t("action_open_archive"), action: #selector(ArchiveWindowController.openArchive(_:)), keyEquivalent: "o")
        file.addItem(withTitle: loc.t("action_new_archive"), action: #selector(ArchiveWindowController.newArchive(_:)), keyEquivalent: "n")
        let recentItem = file.addItem(withTitle: loc.t("menu_open_recent"), action: nil, keyEquivalent: "")
        let recent = NSMenu(title: loc.t("menu_open_recent"))
        recent.delegate = self
        recentItem.submenu = recent
        file.addItem(.separator())
        file.addItem(
            withTitle: loc.t("action_extract_here"), action: #selector(ArchiveWindowController.extractHere(_:)), keyEquivalent: "e")
        let ef = file.addItem(
            withTitle: loc.t("action_extract_to_folder"), action: #selector(ArchiveWindowController.extractToFolder(_:)), keyEquivalent: "e"
        )
        ef.keyEquivalentModifierMask = [.command, .option]
        let et = file.addItem(
            withTitle: loc.t("action_extract_to"), action: #selector(ArchiveWindowController.extractTo(_:)), keyEquivalent: "e")
        et.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(
            withTitle: loc.t("action_extract_selected_here"), action: #selector(ArchiveWindowController.extractSelectedHere(_:)),
            keyEquivalent: "")
        file.addItem(
            withTitle: loc.t("action_extract_selected_to"), action: #selector(ArchiveWindowController.extractSelectedTo(_:)),
            keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(
            withTitle: loc.t("action_test_archive"), action: #selector(ArchiveWindowController.testArchive(_:)), keyEquivalent: "t")
        file.addItem(withTitle: loc.t("action_archive_info"), action: #selector(ArchiveWindowController.showInfo(_:)), keyEquivalent: "i")
        file.addItem(.separator())
        let add = file.addItem(
            withTitle: loc.t("action_add_files"), action: #selector(ArchiveWindowController.addFiles(_:)), keyEquivalent: "a")
        add.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(
            withTitle: loc.t("action_delete_selected"), action: #selector(ArchiveWindowController.deleteSelected(_:)),
            keyEquivalent: "\u{8}")
        file.addItem(.separator())
        file.addItem(withTitle: loc.t("menu_close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return file
    }

    /// The standard editing commands, for the search field and the dialogs' text fields.
    private func editMenu() -> NSMenu {
        let edit = NSMenu(title: loc.t("menu_edit"))
        edit.addItem(withTitle: loc.t("menu_undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: loc.t("menu_redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: loc.t("menu_cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: loc.t("menu_copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: loc.t("menu_paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: loc.t("menu_select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return edit
    }

    /// Quick Look, expanding and collapsing the tree, refreshing, and showing the archive in Finder.
    private func viewMenu() -> NSMenu {
        let view = NSMenu(title: loc.t("menu_view"))
        view.addItem(withTitle: loc.t("action_quick_look"), action: #selector(ArchiveWindowController.quickLook(_:)), keyEquivalent: " ")
            .keyEquivalentModifierMask = []
        view.addItem(.separator())
        let ea = view.addItem(
            withTitle: loc.t("action_expand_all"), action: #selector(ArchiveWindowController.expandAll(_:)),
            keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        ea.keyEquivalentModifierMask = [.command, .option]
        let ca = view.addItem(
            withTitle: loc.t("action_collapse_all"), action: #selector(ArchiveWindowController.collapseAll(_:)),
            keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        ca.keyEquivalentModifierMask = [.command, .option]
        view.addItem(.separator())
        view.addItem(withTitle: loc.t("action_refresh"), action: #selector(ArchiveWindowController.refresh(_:)), keyEquivalent: "r")
        let rv = view.addItem(
            withTitle: loc.t("action_show_in_finder"), action: #selector(ArchiveWindowController.revealArchive(_:)), keyEquivalent: "r")
        rv.keyEquivalentModifierMask = [.command, .shift]
        return view
    }

    /// The Window menu, which AppKit fills with the open windows.
    private func windowMenu() -> NSMenu {
        let win = NSMenu(title: loc.t("menu_window"))
        win.addItem(withTitle: loc.t("menu_minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: loc.t("menu_zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        win.addItem(.separator())
        win.addItem(withTitle: loc.t("menu_bring_all_to_front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return win
    }

    /// The README in the app's language and the changelog (Help.swift).
    private func helpMenu() -> NSMenu {
        let help = NSMenu(title: loc.t("menu_help"))
        help.addItem(withTitle: loc.t("menu_help_app", AppInfo.name), action: #selector(openHelp(_:)), keyEquivalent: "?")
        help.addItem(withTitle: loc.t("menu_release_notes"), action: #selector(openReleaseNotes(_:)), keyEquivalent: "")
        return help
    }
}
