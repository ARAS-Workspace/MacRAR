import AppKit

/// Checks GitHub Releases for a new version (anonymous API, no credentials).
enum UpdateChecker {
    static let repo = "ARAS-Workspace/MacRAR"
    static let releasesPage = URL(string: "https://github.com/ARAS-Workspace/MacRAR/releases/latest")!
    static let lastCheckKey = "UpdateLastCheck"
    static let skipKey = "UpdateSkippedVersion"
    private static let interval: TimeInterval = 24 * 3600

    static var currentVersion: String {
        if let v = ProcessInfo.processInfo.environment["MACRAR_DEBUG_VERSION"] { return v }
        return AppInfo.version
    }

    /// At app launch: at most once a day, silently.
    static func checkAutomatically() {
        if ProcessInfo.processInfo.environment["MACRAR_NO_UPDATE_CHECK"] != nil { return }
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        if Date().timeIntervalSince1970 - last < interval { return }
        check(manual: false)
    }

    /// From the menu: always reports the result.
    static func check(manual: Bool) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MacRAR/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
                let json = error == nil ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
                handle(release: json ?? [:], manual: manual)
            }
        }.resume()
    }

    /// What the latest release, as the GitHub API describes it, leads to: the update alert when it is newer than this
    /// copy, at once when asked for from the menu, otherwise once no other question is up (Dialogs.whenIdle) and only
    /// if the user has not skipped that version; from the menu, a word that this copy is up to date.
    static func handle(release json: [String: Any], manual: Bool) {
        guard let tag = json["tag_name"] as? String else {
            if manual { Dialogs.error(loc.t("update_check_failed_title"), loc.t("update_check_failed_message")) }
            return
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        let latest = version(fromTag: tag)
        if isNewer(latest, than: currentVersion) {
            if !manual, UserDefaults.standard.string(forKey: skipKey) == latest { return }
            let show = { present(latest: latest, page: page(of: json, tag: tag)) }
            if manual { show() } else { Dialogs.whenIdle(show) }
        } else if manual {
            Dialogs.info(loc.t("update_up_to_date_title"), loc.t("update_up_to_date_message", currentVersion))
        }
    }

    /// The version a release tag names: "mac-v1.4.2+ARAS.Patch.1" (what .github/scripts/release.sh pushes),
    /// "v1.4.2" or "1.4.2".
    static func version(fromTag tag: String) -> String {
        for prefix in ["mac-v", "v"] where tag.hasPrefix(prefix) {
            return String(tag.dropFirst(prefix.count))
        }
        return tag
    }

    /// Orders "1.4.2+ARAS.Patch.2" after "1.4.2+ARAS.Patch.1" and "1.4.3+ARAS.Patch.1" after both:
    /// the original release first, then the patch round, which semver's build metadata leaves unordered.
    static func isNewer(_ version: String, than other: String) -> Bool {
        let mine = orderKey(version), theirs = orderKey(other)
        for i in 0..<max(mine.count, theirs.count) {
            let lhs = i < mine.count ? mine[i] : 0
            let rhs = i < theirs.count ? theirs[i] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    /// Three release components, then the patch round (0 when the version has none).
    private static func orderKey(_ version: String) -> [Int] {
        let parts = version.split(separator: "+", maxSplits: 1)
        var release = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
        while release.count < 3 { release.append(0) }
        let round = parts.count > 1 ? parts[1].split(separator: ".").last.flatMap { Int($0) } ?? 0 : 0
        return Array(release.prefix(3)) + [round]
    }

    /// The new version's release page, where its DMGs are: the address GitHub gives, or else the page of its tag.
    static func page(of release: [String: Any], tag: String) -> URL {
        if let given = (release["html_url"] as? String).flatMap(URL.init(string:)) { return given }
        let path = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        return URL(string: "https://github.com/\(repo)/releases/tag/\(path)") ?? releasesPage
    }

    /// The update alert: the new version and the one in use, without the release notes, and a button that opens the
    /// new version's release page.
    static func alert(latest: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = loc.t("update_available_title", latest)
        alert.informativeText = loc.t("update_available_message", currentVersion)
        alert.addButton(withTitle: loc.t("update_open_download_page"))
        alert.addButton(withTitle: loc.t("later"))
        alert.addButton(withTitle: loc.t("update_skip_version"))
        return alert
    }

    private static func present(latest: String, page: URL) {
        Dialogs.activate()
        let alert = alert(latest: latest)
        switch debugAnswer(alert) ?? alert.runModal() {
        case .alertFirstButtonReturn: open(page)
        case .alertThirdButtonReturn: UserDefaults.standard.set(latest, forKey: skipKey)
        default: break
        }
    }

    /// MACRAR_DEBUG_CONFIRM: the alert goes to stdout and MACRAR_DEBUG_UPDATE answers it, download, skip or, by
    /// default, later.
    private static func debugAnswer(_ alert: NSAlert) -> NSApplication.ModalResponse? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MACRAR_DEBUG_CONFIRM"] != nil else { return nil }
        print("\(alert.messageText): \(alert.informativeText)")
        switch environment["MACRAR_DEBUG_UPDATE"] {
        case "download": return .alertFirstButtonReturn
        case "skip": return .alertThirdButtonReturn
        default: return .alertSecondButtonReturn
        }
    }

    /// Opens a page in the browser; with MACRAR_DEBUG_CONFIRM its address goes to stdout instead.
    private static func open(_ page: URL) {
        if ProcessInfo.processInfo.environment["MACRAR_DEBUG_CONFIRM"] != nil {
            print("open \(page.absoluteString)")
            return
        }
        NSWorkspace.shared.open(page)
    }
}
