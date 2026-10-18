import Foundation

/// RARLAB's "RAR for macOS" tool. Its licence does not allow shipping it with the app; the user downloads it.
enum RarTools {
    static let downloadPage = URL(string: "https://www.rarlab.com/download.htm")!
    static var installDir: String { (AppInfo.supportDir as NSString).appendingPathComponent("rar") }

    static var rarURL: URL? {
        var candidates: [String] = []
        if let custom = UserDefaults.standard.string(forKey: "RarPath"), !custom.isEmpty { candidates.append(custom) }
        candidates += [(installDir as NSString).appendingPathComponent("rar"), "/usr/local/bin/rar", "/opt/homebrew/bin/rar"]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
        return nil
    }

    static var available: Bool { rarURL != nil }

    /// The SFX module beside the rar in use: RARLAB ships default.sfx next to rar and install(from:) copies it, but rar
    /// on macOS only looks in the home directory, /usr/lib and /usr/local/lib. nil leaves rar to that search.
    static var sfxModule: URL? {
        guard let module = rarURL?.resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("default.sfx"),
              FileManager.default.fileExists(atPath: module.path) else { return nil }
        return module
    }

    /// e.g. "RAR 7.23"; nil if it does not run
    static var version: String? {
        guard let url = rarURL else { return nil }
        let process = Process()
        process.executableURL = url
        process.arguments = []
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe; process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let out = pipe.fileHandleForReading.readDataToEndOfFile().lossyUTF8
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
        return askForTool()
    }

    /// The questions that walk the user through downloading RARLAB's rar and choosing it; true once it is installed into
    /// `directory`, the app's own folder unless a test gives a scratch one.
    static func askForTool(into directory: String = installDir) -> Bool {
        var required = Question(topic: .rarToolMissing)
        required.title = loc.t("rar_tool_required_title")
        required.message = loc.t("rar_tool_required_message")
        required.buttons.append(loc.t("rar_tool_choose_downloaded"))
        required.buttons.append(loc.t("rar_tool_open_download_page"))
        required.buttons.append(loc.t("cancel"))
        switch Dialogs.ask(required).button {
        case 0:
            return chooseAndInstall(into: directory)
        case 1:
            Dialogs.openInBrowser(downloadPage)
            var wait = Question(topic: .rarToolDownloading)
            wait.title = loc.t("rar_tool_wait_title")
            wait.message = loc.t("rar_tool_wait_message")
            wait.buttons.append(loc.t("rar_tool_choose_file"))
            wait.buttons.append(loc.t("cancel"))
            return Dialogs.ask(wait).button == 0 ? chooseAndInstall(into: directory) : false
        default:
            return false
        }
    }

    private static func chooseAndInstall(into directory: String) -> Bool {
        var panel = Panel()
        panel.title = loc.t("rar_tool_panel_title")
        panel.message = loc.t("rar_tool_panel_message")
        panel.prompt = loc.t("install")
        panel.files = true
        panel.folders = true
        panel.multiple = false
        panel.directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let url = Dialogs.choose(panel).first else { return false }
        do {
            try install(from: url, into: directory)
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

    /// Installs the RAR tool the user chose (RARLAB's tar.gz, its rar folder or the rar program) into `directory`. The
    /// tool is checked before its download quarantine comes off and run once in a staging folder afterwards; one that
    /// fails either check is not installed, and the tool already there stays.
    static func install(from url: URL, into directory: String = installDir) throws {
        let fm = FileManager.default
        var sourceDir: String?
        let lower = url.lastPathComponent.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") {
            let tempDir = TempDirs.make("rar-install")
            defer { try? fm.removeItem(atPath: tempDir) }
            try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", url.path, "-C", tempDir]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw InstallError(message: loc.t("rar_tool_err_unreadable")) }
            guard let found = findRarDir(in: tempDir) else { throw InstallError(message: loc.t("rar_tool_err_not_found")) }
            try installChecked(from: found, into: directory)
            return
        } else if isDirectoryPath(url.path) {
            sourceDir = findRarDir(in: url.path)
        } else if url.lastPathComponent == "rar" {
            sourceDir = url.deletingLastPathComponent().path
        }
        guard let src = sourceDir else { throw InstallError(message: loc.t("rar_tool_err_not_found")) }
        try installChecked(from: src, into: directory)
    }

    private static func installChecked(from src: String, into directory: String) throws {
        let fm = FileManager.default
        guard looksLikeRarlabRar(at: (src as NSString).appendingPathComponent("rar")) else {
            throw InstallError(message: loc.t("rar_tool_err_not_rarlab"))
        }
        let staged = directory + ".installing-" + UUID().uuidString
        defer { try? fm.removeItem(atPath: staged) }
        try fm.createDirectory(atPath: staged, withIntermediateDirectories: true)
        for name in ["rar", "default.sfx", "rarfiles.lst", "license.txt", "rar.txt", "whatsnew.txt", "acknow.txt", "order.htm"] {
            let s = (src as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: s) { try fm.copyItem(atPath: s, toPath: (staged as NSString).appendingPathComponent(name)) }
        }
        let rar = (staged as NSString).appendingPathComponent("rar")
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rar)
        let sfx = (staged as NSString).appendingPathComponent("default.sfx")
        if fm.fileExists(atPath: sfx) { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sfx) }
        // A tool the user chose themselves, and RARLAB's by the check above: remove the download quarantine
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", staged]
        xattr.standardOutput = FileHandle.nullDevice; xattr.standardError = FileHandle.nullDevice
        try? xattr.run(); xattr.waitUntilExit()
        guard reportedVersion(of: URL(fileURLWithPath: rar)) != nil else {
            throw InstallError(message: loc.t("rar_tool_err_wrong_arch"))
        }
        try? fm.removeItem(atPath: directory)
        try fm.moveItem(atPath: staged, toPath: directory)
        if directory == installDir { UserDefaults.standard.removeObject(forKey: "RarPath") }
    }

    /// The light check made before the download quarantine comes off, when the tool cannot yet be run to ask it: a
    /// Mach-O program that carries RARLAB's copyright, which rar keeps as UTF-32 text.
    static func looksLikeRarlabRar(at path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path), data.count > 4,
              let copyright = "Alexander Roshal".data(using: .utf32LittleEndian) else { return false }
        let machO: [[UInt8]] = [[0xCF, 0xFA, 0xED, 0xFE], [0xCA, 0xFE, 0xBA, 0xBE], [0xCA, 0xFE, 0xBA, 0xBF]]
        return machO.contains(Array(data.prefix(4))) && data.range(of: copyright) != nil
    }

    /// The version the tool reports with -iver ("7.23"); nil when it does not run or answers something else.
    static func reportedVersion(of rar: URL) -> String? {
        let process = Process()
        process.executableURL = rar
        process.arguments = ["-iver"]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && version.range(of: #"^\d+\.\d+$"#, options: .regularExpression) != nil ? version : nil
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
}
