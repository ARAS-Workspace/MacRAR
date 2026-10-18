import AppKit
import UniformTypeIdentifiers

/// The questions as the user sees them: alerts and panels, run modally over the app brought to the front.
struct AppKitPrompter: Prompter {
    func ask(_ question: Question) -> Answer {
        Dialogs.activate()
        let alert = NSAlert()
        alert.messageText = question.title
        alert.informativeText = question.message
        alert.alertStyle = question.style.alertStyle
        if question.appIcon { alert.icon = NSApp.applicationIconImage }
        for title in question.buttons { alert.addButton(withTitle: title) }
        if question.destructive { alert.buttons.first?.hasDestructiveAction = true }
        if let suppression = question.suppression {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = suppression
        }
        let boxes = question.choices.isEmpty ? [] : attach(question.choices, to: alert)
        let response = alert.runModal()
        return Answer(button: response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue,
                      suppressed: question.suppression != nil && alert.suppressionButton?.state == .on,
                      chosen: boxes.indices.filter { boxes[$0].state == .on })
    }

    func report(_ report: Report) {
        switch report.kind {
        case .error: error(report.title, report.detail, details: report.details)
        case .info: info(report.title, report.detail)
        }
    }

    private func error(_ title: String, _ detail: String, details: String?) {
        Dialogs.activate()
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

    private func info(_ title: String, _ detail: String) {
        Dialogs.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: loc.t("ok"))
        alert.runModal()
    }

    func askPassword(archiveName: String, wrong: Bool) -> String? {
        Dialogs.activate()
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

    func askOverwrite(existing: [String], dest: String) -> Dialogs.OverwriteMode {
        Dialogs.activate()
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

    func choose(_ request: Panel) -> [URL] {
        Dialogs.activate()
        let panel = request.kind == .open ? openPanel(request) : NSSavePanel()
        panel.title = request.title
        if let message = request.message { panel.message = message }
        if let prompt = request.prompt { panel.prompt = prompt }
        if let name = request.name { panel.nameFieldStringValue = name }
        if request.createFolders { panel.canCreateDirectories = true }
        if let directory = request.directory { panel.directoryURL = directory }
        guard panel.runModal() == .OK else { return [] }
        return (panel as? NSOpenPanel)?.urls ?? panel.url.map { [$0] } ?? []
    }

    /// An open panel with what it may choose: files, folders, more than one, and the archives the app opens.
    private func openPanel(_ request: Panel) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = request.folders
        panel.canChooseFiles = request.files
        panel.allowsMultipleSelection = request.multiple
        if request.archivesOnly {
            var types: [UTType] = [.archive]
            if let utType = UTType("com.rarlab.rar-archive") { types.append(utType) }
            if let utType = UTType("com.arasworkspace.MacRAR.archive") { types.append(utType) }
            for ext in Formats.openable { if let utType = UTType(filenameExtension: ext) { types.append(utType) } }
            panel.allowedContentTypes = types
            panel.allowsOtherFileTypes = true
        }
        return panel
    }

    func openInBrowser(_ page: URL) {
        NSWorkspace.shared.open(page)
    }

    /// The choices as a column of boxes under the message, each with its line beneath; the boxes, in their order.
    private func attach(_ choices: [Question.Choice], to alert: NSAlert) -> [NSButton] {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        var boxes: [NSButton] = []
        for choice in choices {
            let (row, box) = choiceRow(for: choice)
            stack.addArrangedSubview(row)
            boxes.append(box)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 10))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            container.widthAnchor.constraint(equalToConstant: 400),
        ])
        container.layoutSubtreeIfNeeded()
        container.setFrameSize(NSSize(width: 400, height: stack.fittingSize.height))
        alert.accessoryView = container
        return boxes
    }

    private func choiceRow(for choice: Question.Choice) -> (row: NSStackView, box: NSButton) {
        let box = NSButton(checkboxWithTitle: choice.title, target: nil, action: nil)
        box.state = choice.isOn ? .on : .off
        let detail = NSTextField(labelWithString: choice.detail)
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = choice.warns ? .systemOrange : .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        let row = NSStackView(views: [box, detail])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 1
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 20).isActive = true
        return (row, box)
    }
}

private extension Question.Style {
    var alertStyle: NSAlert.Style {
        switch self {
        case .informational: return .informational
        case .warning: return .warning
        }
    }
}
