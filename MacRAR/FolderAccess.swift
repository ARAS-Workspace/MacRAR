import AppKit

/// Folder permissions in the App Store (sandboxed) edition: the user picks a folder once and it is kept as a
/// security-scoped bookmark. In the GitHub edition everything is allowed and this type never asks.
enum FolderAccess {
    private static let key = "FolderBookmarks"
    private static var active: [URL] = []

    /// Activate the saved permissions at launch
    static func restore() {
        #if APPSTORE
        let datas = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        var keep: [Data] = []
        for d in datas {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: d, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            if url.startAccessingSecurityScopedResource() { active.append(url) }
            if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                keep.append(fresh)
            } else {
                keep.append(d)
            }
        }
        UserDefaults.standard.set(keep, forKey: key)
        #endif
    }

    static var grantedFolders: [String] { active.map { $0.path } }

    static func existingAncestor(of path: String) -> String {
        var p = path
        while !p.isEmpty, p != "/", !FileManager.default.fileExists(atPath: p) { p = (p as NSString).deletingLastPathComponent }
        return p.isEmpty ? "/" : p
    }

    static func canRead(_ dir: String) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: dir)) != nil
    }

    static func canWrite(_ dir: String) -> Bool {
        let probe = (dir as NSString).appendingPathComponent(".archiver-probe-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: probe, contents: Data()) else { return false }
        try? FileManager.default.removeItem(atPath: probe)
        return true
    }

    /// Asks for permission if needed. false → the user cancelled.
    @discardableResult
    static func ensure(_ dir: String, write: Bool) -> Bool {
        #if APPSTORE
        if write ? canWrite(dir) : canRead(dir) { return true }
        Dialogs.activate()
        let panel = NSOpenPanel()
        panel.title = loc.t("folder_access_title")
        panel.message = loc.t("folder_access_message", AppInfo.name, (dir as NSString).lastPathComponent)
        panel.prompt = loc.t("allow")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: dir)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        remember(url)
        return write ? canWrite(dir) : canRead(dir)
        #else
        return true
        #endif
    }

    /// From Settings: grant the home folder once
    static func grantHome() {
        #if APPSTORE
        let panel = NSOpenPanel()
        panel.title = loc.t("folder_access_title")
        panel.message = loc.t("folder_access_home_selected")
        panel.prompt = loc.t("allow")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: AppInfo.realHome)
        Dialogs.activate()
        if panel.runModal() == .OK, let url = panel.url { remember(url) }
        #endif
    }

    static func resetAll() {
        for u in active { u.stopAccessingSecurityScopedResource() }
        active = []
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func remember(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        var list = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        list.append(data)
        UserDefaults.standard.set(list, forKey: key)
        if url.startAccessingSecurityScopedResource() { active.append(url) }
    }
}
