import AppKit
import UniformTypeIdentifiers

enum Dialogs {
    static func activate() { NSApp.activate(ignoringOtherApps: true) }

    /// Whether something already waits for the user: a modal window (a password question, the Create Archive dialog,
    /// an alert), a sheet, or an operation, its progress window up or not yet, or an extraction carrying the archive's
    /// quarantine over once its window has gone.
    static var isBusy: Bool {
        NSApp.modalWindow != nil || ProgressPanel.running > 0 || Ops.carryingQuarantine > 0
            || NSApp.windows.contains { $0.isVisible && $0.attachedSheet != nil }
    }

    /// Blocks waiting in whenIdle.
    private(set) static var waiting = 0

    /// Runs `block` once nothing waits for the user (isBusy), looking again every 1.5 s. The questions the app asks on
    /// its own as it starts, the file associations and the update alert, wait here instead of coming up over another
    /// one. (Taken from MacRAR 1.4.3, which did not count an operation's progress.)
    static func whenIdle(_ block: @escaping () -> Void) {
        guard isBusy else { block(); return }
        waiting += 1
        func check() {
            guard !isBusy else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: check)
                return
            }
            waiting -= 1
            block()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: check)
    }

    /// Opens a page in the browser; with MACRAR_DEBUG_CONFIRM its address goes to stdout instead.
    static func openInBrowser(_ page: URL) {
        if ProcessInfo.processInfo.environment["MACRAR_DEBUG_CONFIRM"] != nil {
            print("open \(page.absoluteString)")
            return
        }
        NSWorkspace.shared.open(page)
    }

    static func askPassword(archiveName: String, wrong: Bool = false) -> String? {
        // Debugging: MACRAR_DEBUG_PASSWORD answers the first prompt, MACRAR_DEBUG_PASSWORD_RETRY the one after a wrong password
        if let answer = ProcessInfo.processInfo.environment[wrong ? "MACRAR_DEBUG_PASSWORD_RETRY" : "MACRAR_DEBUG_PASSWORD"] {
            print(wrong ? "password again" : "password")
            return answer == "__cancel__" ? nil : answer
        }
        activate()
        let alert = NSAlert()
        alert.messageText = wrong ? loc.t("password_wrong_title") : loc.t("password_required_title")
        alert.informativeText = loc.t("password_prompt_message", archiveName)
        alert.icon = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        alert.addButton(withTitle: loc.t("ok"))
        alert.addButton(withTitle: loc.t("cancel"))
        let secure = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        secure.placeholderString = loc.t("password_field")
        let plain = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        plain.placeholderString = loc.t("password_field")
        plain.isHidden = true
        let box = PasswordBox(secure: secure, plain: plain)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 52))
        secure.frame = NSRect(x: 0, y: 28, width: 300, height: 24)
        plain.frame = secure.frame
        box.toggle.frame = NSRect(x: 0, y: 2, width: 200, height: 20)
        container.addSubview(secure); container.addSubview(plain); container.addSubview(box.toggle)
        alert.accessoryView = container
        alert.window.initialFirstResponder = secure
        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return nil }
        return box.value
    }

    /// Password field + "Show password" toggle
    final class PasswordBox: NSObject {
        let secure: NSSecureTextField
        let plain: NSTextField
        let toggle: NSButton
        init(secure: NSSecureTextField, plain: NSTextField) {
            self.secure = secure; self.plain = plain
            toggle = NSButton(checkboxWithTitle: loc.t("password_show"), target: nil, action: nil)
            super.init()
            toggle.target = self; toggle.action = #selector(flip)
            toggle.font = .systemFont(ofSize: 11)
        }
        var value: String { plain.isHidden ? secure.stringValue : plain.stringValue }
        @objc private func flip() {
            if toggle.state == .on {
                plain.stringValue = secure.stringValue; plain.isHidden = false; secure.isHidden = true
                plain.window?.makeFirstResponder(plain)
            } else {
                secure.stringValue = plain.stringValue; secure.isHidden = false; plain.isHidden = true
                secure.window?.makeFirstResponder(secure)
            }
        }
    }

    enum OverwriteMode { case overwrite, rename, skip, cancel }

    static func askOverwrite(existing: [String], dest: String) -> OverwriteMode {
        // Debugging: MACRAR_DEBUG_OVERWRITE=overwrite|rename|skip|cancel answers the question, which goes to stdout
        let answers: [String: OverwriteMode] = ["overwrite": .overwrite, "rename": .rename, "skip": .skip, "cancel": .cancel]
        if let answer = ProcessInfo.processInfo.environment["MACRAR_DEBUG_OVERWRITE"].flatMap({ answers[$0] }) {
            print("overwrite \(existing.sorted())")
            return answer
        }
        activate()
        let alert = NSAlert()
        alert.messageText = loc.t("overwrite_title")
        let shown = existing.prefix(5).joined(separator: ", ") + (existing.count > 5 ? " …" : "")
        alert.informativeText = loc.t("overwrite_message", (dest as NSString).lastPathComponent, shown)
        alert.alertStyle = .warning
        alert.addButton(withTitle: loc.t("overwrite_replace"))
        alert.addButton(withTitle: loc.t("overwrite_rename"))
        alert.addButton(withTitle: loc.t("overwrite_skip"))
        alert.addButton(withTitle: loc.t("cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .overwrite
        case .alertSecondButtonReturn: return .rename
        case .alertThirdButtonReturn: return .skip
        default: return .cancel
        }
    }

    /// MACRAR_DEBUG_CONFIRM: an alert that only reports goes to stdout instead of waiting for the user
    private static func reportedForDebugging(_ title: String, _ detail: String) -> Bool {
        guard ProcessInfo.processInfo.environment["MACRAR_DEBUG_CONFIRM"] != nil else { return false }
        print("\(title): \(detail)")
        return true
    }

    static func error(_ title: String, _ detail: String, details: String? = nil) {
        if reportedForDebugging(title, detail) { return }
        activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail.isEmpty ? loc.t("unknown_error") : detail
        alert.alertStyle = .critical
        alert.addButton(withTitle: loc.t("ok"))
        let full = (details ?? "").replacingOccurrences(of: "\u{8}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty, full != detail {
            alert.addButton(withTitle: loc.t("error_copy_details"))
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 140))
            let tv = NSTextView(frame: scroll.bounds)
            tv.isEditable = false
            tv.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            tv.string = full
            tv.autoresizingMask = [.width]
            scroll.documentView = tv
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            alert.accessoryView = scroll
            if alert.runModal() == .alertSecondButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(full, forType: .string)
            }
            return
        }
        alert.runModal()
    }

    static func info(_ title: String, _ detail: String) {
        if reportedForDebugging(title, detail) { return }
        activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: loc.t("ok"))
        alert.runModal()
    }

    /// Shows a question and returns the button chosen; with MACRAR_DEBUG_CONFIRM the question goes to stdout and its
    /// first, default button answers.
    static func ask(_ alert: NSAlert) -> NSApplication.ModalResponse {
        if reportedForDebugging(alert.messageText, alert.informativeText) { return .alertFirstButtonReturn }
        activate()
        return alert.runModal()
    }

    static func confirm(_ title: String, _ detail: String, okTitle: String = loc.t("ok"), destructive: Bool = false) -> Bool {
        // MACRAR_DEBUG_CONFIRM: the question goes to stdout and is answered yes, or no when the variable says "no"
        if let answer = ProcessInfo.processInfo.environment["MACRAR_DEBUG_CONFIRM"] {
            print("confirm \(title)")
            return answer != "no"
        }
        activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = destructive ? .warning : .informational
        alert.addButton(withTitle: okTitle)
        alert.addButton(withTitle: loc.t("cancel"))
        if destructive, #available(macOS 11.0, *) { alert.buttons.first?.hasDestructiveAction = true }
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// MACRAR_DEBUG_CONFIRM: an open or save panel is not shown; its title goes to stdout as "choose <title>" and it is
    /// answered by MACRAR_DEBUG_CHOOSE, a path, or cancelled (an empty list). nil without the variable: show the panel.
    static func debugChoice(_ title: String) -> [String]? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MACRAR_DEBUG_CONFIRM"] != nil else { return nil }
        print("choose \(title)")
        return environment["MACRAR_DEBUG_CHOOSE"].map { [$0] } ?? []
    }

    static func chooseFolder(title: String, prompt: String, initial: String? = nil) -> String? {
        if let chosen = debugChoice(title) { return chosen.first }
        activate()
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.prompt = prompt
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let initial { panel.directoryURL = URL(fileURLWithPath: initial) }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func chooseFiles(title: String, prompt: String, archivesOnly: Bool) -> [String] {
        if let chosen = debugChoice(title) { return chosen }
        activate()
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.prompt = prompt
        panel.canChooseDirectories = !archivesOnly
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if archivesOnly {
            var types: [UTType] = [.archive]
            if let utType = UTType("com.rarlab.rar-archive") { types.append(utType) }
            if let utType = UTType("com.arasworkspace.MacRAR.archive") { types.append(utType) }
            for ext in Formats.openable { if let utType = UTType(filenameExtension: ext) { types.append(utType) } }
            panel.allowedContentTypes = types
            panel.allowsOtherFileTypes = true
        }
        return panel.runModal() == .OK ? panel.urls.map { $0.path } : []
    }
}
