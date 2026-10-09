import AppKit

/// App identity (GitHub edition "MacRAR", App Store edition "Easy Mac Archiver")
enum AppInfo {
    static let name: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MacRAR"
    /// "1.4.2+ARAS.Patch.1": the original developer's release and the ARAS patch round on top of it
    static let version: String = Bundle.main.object(forInfoDictionaryKey: "ARASDistributionVersion") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    static var isAppStore: Bool {
        #if APPSTORE
        return true
        #else
        return false
        #endif
    }
    /// The user's real home folder (inside the sandbox NSHomeDirectory() returns the app container)
    static let realHome: String = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }()
    static func abbreviate(_ path: String) -> String {
        path == realHome ? "~" : (path.hasPrefix(realHome + "/") ? "~" + path.dropFirst(realHome.count) : path)
    }
    static var supportDir: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.path
        return (base as NSString).appendingPathComponent(name)
    }
}

/// RARLAB's "RAR for macOS" tool. Its licence does not allow shipping it with the app; the user downloads it.
/// Never used in the App Store edition (Apple guideline 2.5.2).
enum RarTools {
    static let downloadPage = URL(string: "https://www.rarlab.com/download.htm")!
    static var installDir: String { (AppInfo.supportDir as NSString).appendingPathComponent("rar") }

    static var rarURL: URL? {
        #if APPSTORE
        return nil
        #else
        var candidates: [String] = []
        if let custom = UserDefaults.standard.string(forKey: "RarPath"), !custom.isEmpty { candidates.append(custom) }
        candidates += [(installDir as NSString).appendingPathComponent("rar"), "/usr/local/bin/rar", "/opt/homebrew/bin/rar"]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
        return nil
        #endif
    }

    static var available: Bool { rarURL != nil }

    /// e.g. "RAR 7.23"; nil if it does not run
    static var version: String? {
        guard let url = rarURL else { return nil }
        let process = Process()
        process.executableURL = url
        process.arguments = []
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe; process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // swiftlint:disable:next optional_data_string_conversion
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        for line in out.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("RAR ") { return trimmed.components(separatedBy: "  ").first }
        }
        return nil
    }

    /// Without RAR, walks the user through downloading and choosing it. true → now available.
    @discardableResult
    static func ensureAvailable() -> Bool {
        if available { return true }
        #if APPSTORE
        return false
        #else
        Dialogs.activate()
        let alert = NSAlert()
        alert.messageText = loc.t("rar_tool_required_title")
        alert.informativeText = loc.t("rar_tool_required_message")
        alert.addButton(withTitle: loc.t("rar_tool_choose_downloaded"))
        alert.addButton(withTitle: loc.t("rar_tool_open_download_page"))
        alert.addButton(withTitle: loc.t("cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return chooseAndInstall()
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(downloadPage)
            let wait = NSAlert()
            wait.messageText = loc.t("rar_tool_wait_title")
            wait.informativeText = loc.t("rar_tool_wait_message")
            wait.addButton(withTitle: loc.t("rar_tool_choose_file"))
            wait.addButton(withTitle: loc.t("cancel"))
            Dialogs.activate()
            return wait.runModal() == .alertFirstButtonReturn ? chooseAndInstall() : false
        default:
            return false
        }
        #endif
    }

    #if !APPSTORE
    private static func chooseAndInstall() -> Bool {
        let panel = NSOpenPanel()
        panel.title = loc.t("rar_tool_panel_title")
        panel.message = loc.t("rar_tool_panel_message")
        panel.prompt = loc.t("install")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        Dialogs.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try install(from: url)
            Dialogs.info(loc.t("rar_tool_installed_title"), loc.t("rar_tool_installed_message", version ?? "RAR"))
            return true
        } catch {
            Dialogs.error(loc.t("rar_tool_install_failed_title"), error.localizedDescription)
            return false
        }
    }

    struct InstallError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func install(from url: URL) throws {
        let fm = FileManager.default
        var sourceDir: String?
        var tmp: String?
        let lower = url.lastPathComponent.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") {
            let tempDir = TempDirs.make("rar-install")
            try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
            tmp = tempDir
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", url.path, "-C", tempDir]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw InstallError(message: loc.t("rar_tool_err_unreadable")) }
            sourceDir = findRarDir(in: tempDir)
        } else if isDirectoryPath(url.path) {
            sourceDir = findRarDir(in: url.path)
        } else if url.lastPathComponent == "rar" {
            sourceDir = url.deletingLastPathComponent().path
        }
        defer { if let tmp { try? fm.removeItem(atPath: tmp) } }
        guard let src = sourceDir else {
            throw InstallError(message: loc.t("rar_tool_err_not_found"))
        }
        try? fm.removeItem(atPath: installDir)
        try fm.createDirectory(atPath: installDir, withIntermediateDirectories: true)
        for name in ["rar", "default.sfx", "rarfiles.lst", "license.txt", "rar.txt", "whatsnew.txt", "acknow.txt", "order.htm"] {
            let s = (src as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: s) { try fm.copyItem(atPath: s, toPath: (installDir as NSString).appendingPathComponent(name)) }
        }
        let rar = (installDir as NSString).appendingPathComponent("rar")
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rar)
        let sfx = (installDir as NSString).appendingPathComponent("default.sfx")
        if fm.fileExists(atPath: sfx) { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sfx) }
        // A tool the user chose themselves: remove the download quarantine
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", installDir]
        xattr.standardOutput = FileHandle.nullDevice; xattr.standardError = FileHandle.nullDevice
        try? xattr.run(); xattr.waitUntilExit()
        UserDefaults.standard.removeObject(forKey: "RarPath")
        guard version != nil else {
            try? fm.removeItem(atPath: installDir)
            throw InstallError(message: loc.t("rar_tool_err_wrong_arch"))
        }
    }

    private static func findRarDir(in dir: String) -> String? {
        let fm = FileManager.default
        for candidate in [dir, (dir as NSString).appendingPathComponent("rar")] {
            if fm.isExecutableFile(atPath: (candidate as NSString).appendingPathComponent("rar")),
               !isDirectoryPath((candidate as NSString).appendingPathComponent("rar")) { return candidate }
        }
        if let enumerator = fm.enumerator(atPath: dir) {
            while let rel = enumerator.nextObject() as? String {
                if (rel as NSString).lastPathComponent == "rar" {
                    let full = (dir as NSString).appendingPathComponent(rel)
                    if !isDirectoryPath(full), fm.isExecutableFile(atPath: full) { return (full as NSString).deletingLastPathComponent }
                }
            }
        }
        return nil
    }

    static func uninstall() {
        try? FileManager.default.removeItem(atPath: installDir)
        UserDefaults.standard.removeObject(forKey: "RarPath")
    }
    #endif
}
