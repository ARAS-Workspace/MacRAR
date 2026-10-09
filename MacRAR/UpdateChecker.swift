#if !APPSTORE
import AppKit

/// Checks GitHub Releases for a new version (anonymous API, no credentials).
enum UpdateChecker {
    static let repo = "mstcvk/MacRAR"
    static let releasesPage = URL(string: "https://github.com/mstcvk/MacRAR/releases/latest")!
    private static let lastCheckKey = "UpdateLastCheck"
    private static let skipKey = "UpdateSkippedVersion"
    private static let interval: TimeInterval = 24 * 3600

    static var currentVersion: String {
        if let v = ProcessInfo.processInfo.environment["MACRAR_DEBUG_VERSION"] { return v }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
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
                guard error == nil, let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    if manual { Dialogs.error(loc.t("update_check_failed_title"), loc.t("update_check_failed_message")) }
                    return
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let pageURL = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
                let notes = (json["body"] as? String) ?? ""
                if isNewer(latest, than: currentVersion) {
                    if !manual, UserDefaults.standard.string(forKey: skipKey) == latest { return }
                    present(latest: latest, page: pageURL, notes: notes)
                } else if manual {
                    Dialogs.info(loc.t("update_up_to_date_title"), loc.t("update_up_to_date_message", currentVersion))
                }
            }
        }.resume()
    }

    static func isNewer(_ version: String, than other: String) -> Bool {
        let pa = version.split(separator: ".").map { Int($0) ?? 0 }
        let pb = other.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let mine = i < pa.count ? pa[i] : 0
            let theirs = i < pb.count ? pb[i] : 0
            if mine != theirs { return mine > theirs }
        }
        return false
    }

    private static func present(latest: String, page: URL, notes: String) {
        Dialogs.activate()
        let alert = NSAlert()
        alert.messageText = loc.t("update_available_title", latest)
        var info = loc.t("update_available_message", currentVersion)
        // Simplify the Markdown markup, show the first lines
        let lines = notes.components(separatedBy: "\n").map { line -> String in
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            while trimmed.hasPrefix("#") { trimmed.removeFirst() }
            trimmed = trimmed.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            if trimmed.hasPrefix("- ") { trimmed = "• " + trimmed.dropFirst(2) }
            return trimmed.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        if !lines.isEmpty {
            let shown = lines.prefix(7)
            info += "\n\n" + shown.joined(separator: "\n") + (lines.count > shown.count ? "\n…" : "")
        }
        alert.informativeText = info
        alert.addButton(withTitle: loc.t("download"))
        alert.addButton(withTitle: loc.t("later"))
        alert.addButton(withTitle: loc.t("update_skip_version"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(page)
        case .alertThirdButtonReturn: UserDefaults.standard.set(latest, forKey: skipKey)
        default: break
        }
    }
}

#endif
