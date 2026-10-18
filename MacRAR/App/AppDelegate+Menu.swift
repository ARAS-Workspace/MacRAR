import AppKit

/// Open Recent, the About panel and the Quick Actions' names in a new language; MenuBar draws the menu bar (MenuSpec).
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

    // MARK: Language

    /// A language change: the Finder Quick Actions take their new names. MenuBar renders the menus again on its own.
    @objc func languageDidChange() {
        if QuickActions.ownedByThisCopy { QuickActions.relocalize() }
    }
}

/// The app delegate answers the app's commands, sent to it from the menu bar; a window's command reaches it only
/// when no archive window is in front, and it refuses it, so the item stays disabled.
extension AppDelegate: CommandResponder, NSMenuItemValidation {
    @objc func performCommand(_ sender: Any?) { performCommand(from: sender) }

    func validateMenuItem(_ item: NSMenuItem) -> Bool { canPerformCommand(of: item) }

    func canPerform(_ command: Command) -> Bool { command.scope == .app }

    func perform(_ command: Command) {
        switch command {
        case .showAbout: showAbout(nil)
        case .checkForUpdates: checkForUpdates(nil)
        case .showSettings: showSettings(nil)
        case .showAssociations: showAssociations(nil)
        case .installQuickActions: installQuickActions()
        case .openHelp: openHelp(nil)
        case .openReleaseNotes: openReleaseNotes(nil)
        case .openArchive, .newArchive, .extractHere, .extractToFolder, .extractTo, .extractSelectedHere, .extractSelectedTo,
             .testArchive, .showInfo, .addFiles, .deleteSelected, .openSelected, .quickLook, .expandAll, .collapseAll, .refresh,
             .revealArchive:
            break
        }
    }
}
