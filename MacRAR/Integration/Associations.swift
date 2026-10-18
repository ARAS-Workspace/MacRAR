import AppKit
import UniformTypeIdentifiers

/// "Which files should open with this app?" window: once on first launch, then from the menu.
enum Associations {
    struct Group {
        let title: String
        let exts: [String]
        let defaultOn: Bool
        let warning: String?
    }

    static var groups: [Group] {
        [
            // macOS asks for a separate confirmation per type: the preselected ones are limited to the 4 most common types
            Group(title: "RAR", exts: ["rar"], defaultOn: true, warning: nil),
            Group(title: "ZIP", exts: ["zip"], defaultOn: true, warning: nil),
            Group(title: "7z", exts: ["7z"], defaultOn: true, warning: nil),
            Group(title: "GZ, TAR.GZ", exts: ["gz"], defaultOn: true, warning: nil),
            Group(title: loc.t("assoc_group_other"),
                exts: ["tar", "tgz", "bz2", "tbz2", "xz", "txz", "zst", "lz4", "lzma", "zipx", "cab", "lzh", "lha", "arj", "cpio", "z"],
                defaultOn: false, warning: nil),
            Group(title: loc.t("assoc_group_disk_images"), exts: ["iso", "dmg", "vhd", "vmdk"], defaultOn: false,
                  warning: loc.t("assoc_disk_images_warning")),
            Group(title: loc.t("assoc_group_packages"), exts: ["pkg", "jar", "apk", "deb", "rpm", "msi"], defaultOn: false,
                  warning: loc.t("assoc_packages_warning")),
        ]
    }

    static func isMine(_ utType: UTType) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: utType) else { return false }
        return url.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static let shownKey = "AssociationPromptShown"
    static var alreadyShown: Bool { UserDefaults.standard.bool(forKey: shownKey) }

    static func types(for exts: [String]) -> [UTType] {
        var seen = Set<String>(); var out: [UTType] = []
        for ext in exts {
            let utType: UTType? =
                ext == "rar" ? (UTType("com.rarlab.rar-archive") ?? UTType(filenameExtension: ext)) : UTType(filenameExtension: ext)
            if let utType, !utType.identifier.hasPrefix("dyn."), seen.insert(utType.identifier).inserted { out.append(utType) }
        }
        return out
    }

    /// Name of the current default app for this type
    static func currentHandler(for exts: [String]) -> String {
        guard let utType = types(for: exts).first, let url = NSWorkspace.shared.urlForApplication(toOpen: utType) else {
            return loc.t("assoc_current_none")
        }
        if url.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL { return AppInfo.name }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Show on first launch (once)
    static func promptIfFirstLaunch() {
        if alreadyShown { return }
        UserDefaults.standard.set(true, forKey: shownKey)
        show(firstLaunch: true)
    }

    @discardableResult
    static func show(firstLaunch: Bool = false) -> Bool {
        var question = Question(topic: .associations)
        question.title = loc.t("assoc_title", AppInfo.name)
        question.message = (firstLaunch
            ? loc.t("assoc_message_first_launch")
            : loc.t("assoc_message")) + "\n\n" + loc.t("assoc_confirm_note")
        question.appIcon = true
        let groups = Self.groups
        question.choices = groups.map(choice(for:))
        question.buttons.append(loc.t("assoc_make_default"))
        question.buttons.append(loc.t("assoc_not_now"))
        let answer = Dialogs.ask(question)
        guard answer.button == 0 else { return false }
        // Do not ask again for types this app already owns
        let chosen = answer.chosen.map { groups[$0] }.flatMap { types(for: $0.exts) }.filter { !isMine($0) }
        if chosen.isEmpty { return true }
        apply(chosen)
        return true
    }

    /// A box for a group of types, ticked when it is on by default or already this app's, with the app that opens the
    /// group now beneath it.
    private static func choice(for group: Group) -> Question.Choice {
        let current = currentHandler(for: group.exts)
        let mine = current == AppInfo.name
        return Question.Choice(
            title: group.title, detail: loc.t("assoc_current", current) + (group.warning.map { "  •  " + $0 } ?? ""),
            warns: group.warning != nil, isOn: group.defaultOn || mine)
    }

    /// Make this app the default for the selected types; report the result
    static func apply(_ types: [UTType], quiet: Bool = false, completion: ((Int, [String]) -> Void)? = nil) {
        var ok = 0
        var failed: [String] = []
        func next(_ i: Int) {
            guard i < types.count else {
                completion?(ok, failed)
                if !quiet {
                    if failed.isEmpty {
                        Dialogs.info(loc.t("ok"), loc.t("assoc_done", AppInfo.name, ok))
                    } else {
                        Dialogs.error(loc.t("assoc_partial_failure"), failed.joined(separator: ", "))
                    }
                }
                return
            }
            let utType = types[i]
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: utType) { err in
                DispatchQueue.main.async {
                    if err == nil { ok += 1 } else { failed.append(utType.preferredFilenameExtension ?? utType.identifier) }
                    next(i + 1)
                }
            }
        }
        next(0)
    }
}
