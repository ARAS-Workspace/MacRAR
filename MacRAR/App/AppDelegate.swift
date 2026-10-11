import AppKit
import UniformTypeIdentifiers

enum Command: Equatable {
    case extractHere([String])
    case extractFolder([String])
    case extractTo([String])
    case test([String])
    case compress([String])
    case compressDialog([String])
    case setDefault
    case installQuickActions
}

// swiftlint:disable:next type_body_length
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

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
    static var shared: AppDelegate!

    var windows: [ArchiveWindowController] = []
    var pendingCommand: Command?
    var pendingFiles: [String] = []
    private var launched = false
    var headless: Bool { pendingCommand != nil }

    static func isArchive(_ path: String) -> Bool { Formats.isArchive(path) }

    // MARK: Lifecycle

    // swiftlint:disable:next cyclomatic_complexity
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageDidChange), name: LocalizationManager.didChange, object: loc)
        launched = true
        scheduleDebugSnapshot()
        if ProcessInfo.processInfo.environment["MACRAR_DEBUG_ABOUT"] != nil { showAbout(nil) }
        if ProcessInfo.processInfo.environment["MACRAR_DEBUG_PREFS"] != nil { showPreferences(nil) }
        if let ext = ProcessInfo.processInfo.environment["MACRAR_DEBUG_ASSOC_APPLY"] {
            Associations.apply(Associations.types(for: [ext]), quiet: true) { ok, failed in
                print("assoc \(ext): ok=\(ok) failed=\(failed) handler=\(Associations.currentHandler(for: [ext]))"); exit(0)
            }
            return
        }
        if let path = ProcessInfo.processInfo.environment["MACRAR_DEBUG_RARINSTALL"] {
            do {
                try RarTools.install(from: URL(fileURLWithPath: path))
                print("RAR installed:", RarTools.version ?? "?", RarTools.installDir)
            } catch {
                print("RAR install failed:", error.localizedDescription)
            }
            exit(0)
        }
        if let cmd = pendingCommand {
            NSApp.activate(ignoringOtherApps: true)
            runCommand(cmd)
            return
        }
        let files = pendingFiles
        pendingFiles = []
        if files.isEmpty {
            if windows.isEmpty { showEmptyWindow() }
        } else {
            handleOpen(files)
        }
        NSApp.activate(ignoringOtherApps: true)
        // Finder context-menu commands: install silently if not yet installed for this install (path + version)
        let stamp = Bundle.main.bundlePath + "|" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
        if UserDefaults.standard.string(forKey: "QuickActionsInstalledFor") != stamp, QuickActions.ownedByThisCopy {
            QuickActions.installAll()
            UserDefaults.standard.set(stamp, forKey: "QuickActionsInstalledFor")
        }
        // Windowed use only, once a day
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if Prefs.checkUpdates { UpdateChecker.checkAutomatically() } }
        // Offer file associations on first launch (only when running from the Applications folder)
        if QuickActions.ownedByThisCopy || ProcessInfo.processInfo.environment["MACRAR_DEBUG_ASSOC"] != nil {
            askAssociationsWhenIdle()
        }
        warnAboutPlacementWhenIdle()
    }

    /// The file associations question of the first launch, once no other question, sheet or progress window is up:
    /// opened with an archive, the app may be asking for its password.
    func askAssociationsWhenIdle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            Dialogs.whenIdle {
                if ProcessInfo.processInfo.environment["MACRAR_DEBUG_ASSOC"] != nil {
                    Associations.show(firstLaunch: true)
                } else {
                    Associations.promptIfFirstLaunch()
                }
            }
        }
    }

    @objc func showAssociations(_ sender: Any?) { Associations.show() }

    /// Command finished: the copy a Finder Quick Action started quits
    private func finishCommand() {
        NSApp.terminate(nil)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        UpdateChecker.check(manual: true)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let log = ProcessInfo.processInfo.environment["MACRAR_DEBUG_LOG"] {
            let line = "\(Date().timeIntervalSince1970) openFiles(\(filenames.count)): \(filenames.map { ($0 as NSString).lastPathComponent }) launched=\(launched) modal=\(NSApp.modalWindow != nil)\n"
            if let h = FileHandle(forWritingAtPath: log) {
                h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
            } else {
                try? line.write(toFile: log, atomically: true, encoding: .utf8)
            }
        }
        // Answer Finder right away; handle the files outside the Apple event handler, while no modal window is up
        sender.reply(toOpenOrPrint: .success)
        if launched {
            scheduleOpen(filenames)
        } else {
            pendingFiles += filenames
        }
    }

    private var queuedFiles: [String] = []
    private func scheduleOpen(_ files: [String]) {
        queuedFiles += files
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.flushQueuedFiles() }
    }
    private func flushQueuedFiles() {
        guard !queuedFiles.isEmpty else { return }
        if NSApp.modalWindow != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.flushQueuedFiles() }
            return
        }
        let files = queuedFiles
        queuedFiles = []
        handleOpen(files)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !headless }

    func applicationWillTerminate(_ notification: Notification) { TempDirs.cleanupAll() }

    @objc func showPreferences(_ sender: Any?) { PreferencesWindowController.shared.show() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, !headless { showEmptyWindow() }
        return true
    }

    // MARK: Windows

    @discardableResult
    func showEmptyWindow() -> ArchiveWindowController {
        let wc = ArchiveWindowController()
        windows.append(wc)
        wc.showWindow(nil)
        return wc
    }

    func windowClosed(_ wc: ArchiveWindowController) {
        windows.removeAll { $0 === wc }
    }

    static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    func handleOpen(_ rawFiles: [String]) {
        // The same file can arrive both as an argument and through LaunchServices → deduplicate
        var seen = Set<String>()
        let files = rawFiles.map { Self.resolved($0) }.filter { seen.insert($0).inserted }
        let archives = files.filter { Self.isArchive($0) }
        let others = files.filter { !Self.isArchive($0) }
        for archive in archives { openArchive(archive, reuse: nil) }
        if !others.isEmpty {
            compressWithDialog(items: others, host: nil) { [weak self] path in
                if let path {
                    self?.openArchive(path, reuse: nil)
                } else if self?.windows.isEmpty == true {
                    self?.showEmptyWindow()
                }
            }
        }
    }

    func openArchive(_ path: String, reuse: ArchiveWindowController?) {
        let path = Self.resolved(path)
        if let existing = windows.first(where: { $0.archivePath.map(Self.resolved) == path }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let wc: ArchiveWindowController
        var created = false
        if let reuse, reuse.info == nil {
            wc = reuse
        } else if let empty = windows.first(where: { $0.info == nil && $0.archivePath == nil }) {
            wc = empty
        } else {
            wc = ArchiveWindowController()
            windows.append(wc)
            created = true
        }
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        wc.open(path)
        // A file that does not open closes only the window made for it; the empty window the user had stays
        if wc.info == nil, created, windows.count > 1 { wc.close() }
    }

    /// Shows the options window and compresses. completion(path of the created archive / nil)
    func compressWithDialog(items: [String], host: NSWindow?, completion: @escaping (String?) -> Void) {
        let opts = CompressOptions.withDefaults(for: items)
        guard let chosen = CompressDialog(options: opts, itemCount: items.count).run() else { completion(nil); return }
        Ops.compress(items: items, options: chosen, host: host) { ok, path in
            if ok, Prefs.revealAfterCompress { Ops.revealInFinder(path) }
            completion(ok ? path : nil)
        }
    }

    // MARK: Command-line / Finder Quick Action mode

    private func runCommand(_ cmd: Command) {
        switch cmd {
        case .setDefault:
            setDefaultHandler { _ in self.finishCommand() }
        case .installQuickActions:
            let count = QuickActions.installAll()
            print("\(count) Quick Actions installed: \(QuickActions.servicesDir)")
            self.finishCommand()
        case .extractHere(let paths):
            processArchives(Self.dedupeVolumes(paths), dest: { ($0 as NSString).deletingLastPathComponent })
        case .extractFolder(let paths):
            processArchives(Self.dedupeVolumes(paths), dest: { Ops.folderNamedAfterArchive($0) })
        case .extractTo(let paths):
            let list = Self.dedupeVolumes(paths)
            guard let first = list.first,
                  let dest = Dialogs.chooseFolder(title: loc.t("panel_extract_destination"), prompt: loc.t("extract"),
                                               initial: (first as NSString).deletingLastPathComponent) else {
                self.finishCommand(); return
            }
            processArchives(list, dest: { _ in dest })
        case .test(let paths):
            testArchives(Self.dedupeVolumes(paths))
        case .compress(let items):
            let existing = items.filter { FileManager.default.fileExists(atPath: $0) }
            guard !existing.isEmpty else { self.finishCommand(); return }
            var opts = CompressOptions.withDefaults(for: existing)
            // Debugging: MACRAR_DEBUG_FORMAT=zip|7z|tar.gz… and MACRAR_DEBUG_PASSWORD pick the format/password
            if let f = ProcessInfo.processInfo.environment["MACRAR_DEBUG_FORMAT"],
               let fmt = ArchiveFormat.allCases.first(where: { $0.ext == f }) {
                opts.format = fmt
                opts.archivePath = CompressOptions.defaultArchivePath(for: existing, format: fmt)
                opts.password = ProcessInfo.processInfo.environment["MACRAR_DEBUG_PASSWORD"]
                opts.encryptNames = ProcessInfo.processInfo.environment["MACRAR_DEBUG_ENCNAMES"] != nil
            }
            Ops.compress(items: existing, options: opts, host: nil) { ok, path in
                if ok, Prefs.revealAfterCompress { Ops.revealInFinder(path) }
                self.finishCommand()
            }
        case .compressDialog(let items):
            let existing = items.filter { FileManager.default.fileExists(atPath: $0) }
            guard !existing.isEmpty else { self.finishCommand(); return }
            compressWithDialog(items: existing, host: nil) { _ in self.finishCommand() }
        }
    }

    private func processArchives(_ archives: [String], dest: @escaping (String) -> String, index: Int = 0) {
        guard index < archives.count else { finishCommand(); return }
        let archive = archives[index]
        var pw: String?
        guard let info = Ops.listInteractive(archive: archive, password: &pw) else {
            processArchives(archives, dest: dest, index: index + 1)
            return
        }
        let target = dest(archive)
        Ops.extract(info: info, names: nil, dest: target, password: pw, host: nil) { [weak self] ok, _ in
            if ok, index == archives.count - 1 { Ops.revealExtracted(info: info, names: nil, dest: target) }
            self?.processArchives(archives, dest: dest, index: index + 1)
        }
    }

    private func testArchives(_ archives: [String], index: Int = 0) {
        guard index < archives.count else { finishCommand(); return }
        let archive = archives[index]
        var pw: String?
        guard let info = Ops.listInteractive(archive: archive, password: &pw) else {
            testArchives(archives, index: index + 1)
            return
        }
        Ops.test(info: info, password: pw, host: nil) { [weak self] _, _ in
            self?.testArchives(archives, index: index + 1)
        }
    }

    // MARK: Debugging: MACRAR_SNAPSHOT=/path/prefix → save open windows as PNG and quit

    private func scheduleDebugSnapshot() {
        guard let prefix = ProcessInfo.processInfo.environment["MACRAR_SNAPSHOT"] else { return }
        let delay = Double(ProcessInfo.processInfo.environment["MACRAR_SNAPSHOT_DELAY"] ?? "") ?? 2.0
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            var i = 0
            for window in NSApp.windows where window.isVisible {
                guard let frame = window.contentView?.superview else { continue }
                func dump(_ v: NSView) {
                    if let indicator = v as? NSProgressIndicator {
                        print("progress bar value:", indicator.doubleValue, "indeterminate:", indicator.isIndeterminate)
                    }
                    v.subviews.forEach(dump)
                }
                dump(frame)
                guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { continue }
                frame.cacheDisplay(in: frame.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(prefix)-\(i).png"))
                    i += 1
                }
            }
            exit(0)
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: Default app

    func setDefaultHandler(extensions: [String] = ["rar"], completion: @escaping (Error?) -> Void) {
        var types: [UTType] = []
        for ext in extensions {
            if ext == "rar", let utType = UTType("com.rarlab.rar-archive") { types.append(utType); continue }
            if let utType = UTType(filenameExtension: ext) { types.append(utType) }
        }
        func next(_ i: Int) {
            guard i < types.count else { completion(nil); return }
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: types[i]) { err in
                DispatchQueue.main.async {
                    if let err { completion(err) } else { next(i + 1) }
                }
            }
        }
        next(0)
    }

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
    @objc private func languageDidChange() {
        buildMenu()
        if QuickActions.ownedByThisCopy { QuickActions.relocalize() }
    }

    // swiftlint:disable:next function_body_length
    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
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
        appItem.submenu = app

        let fileItem = NSMenuItem(); main.addItem(fileItem)
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
        fileItem.submenu = file

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: loc.t("menu_edit"))
        edit.addItem(withTitle: loc.t("menu_undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: loc.t("menu_redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: loc.t("menu_cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: loc.t("menu_copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: loc.t("menu_paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: loc.t("menu_select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let viewItem = NSMenuItem(); main.addItem(viewItem)
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
        viewItem.submenu = view

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: loc.t("menu_window"))
        win.addItem(withTitle: loc.t("menu_minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: loc.t("menu_zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        win.addItem(.separator())
        win.addItem(withTitle: loc.t("menu_bring_all_to_front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        winItem.submenu = win
        NSApp.windowsMenu = win

        let helpItem = NSMenuItem(); main.addItem(helpItem)
        let help = NSMenu(title: loc.t("menu_help"))
        help.addItem(withTitle: loc.t("menu_help_app", AppInfo.name), action: #selector(openHelp(_:)), keyEquivalent: "?")
        help.addItem(withTitle: loc.t("menu_release_notes"), action: #selector(openReleaseNotes(_:)), keyEquivalent: "")
        helpItem.submenu = help
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }
}
