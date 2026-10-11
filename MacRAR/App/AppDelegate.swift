import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    static var shared: AppDelegate!

    var windows: [ArchiveWindowController] = []
    var pendingCommand: Command?
    var pendingFiles: [String] = []
    private var launched = false
    var headless: Bool { pendingCommand != nil }

    static func isArchive(_ path: String) -> Bool { Formats.isArchive(path) }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageDidChange), name: LocalizationManager.didChange, object: loc)
        launched = true
        if runDebugLaunch() { return }
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
        settleWindowedLaunch()
    }

    /// What a windowed launch does once its windows are up: the Quick Actions of a new install, the daily update
    /// check, and the questions of a first launch.
    private func settleWindowedLaunch() {
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
        let unique = rawFiles.map { Self.resolved($0) }.filter { seen.insert($0).inserted }
        // A volume set opens once, from its first volume, whichever of its volumes came
        let files = VolumeSets.firstVolumes(unique)
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
}
