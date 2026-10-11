import AppKit

final class CompressDialog: NSWindowController, NSTextFieldDelegate {
    private let pathField = NSTextField()
    private let formatPopup = NSPopUpButton()
    private let levelPopup = NSPopUpButton()
    private let pwField = NSSecureTextField()
    private let pw2Field = NSSecureTextField()
    private let encryptNamesBox = NSButton(checkboxWithTitle: loc.t("compress_encrypt_names"), target: nil, action: nil)
    private let solidBox = NSButton(checkboxWithTitle: loc.t("compress_solid"), target: nil, action: nil)
    private let rrBox = NSButton(checkboxWithTitle: loc.t("compress_recovery_record"), target: nil, action: nil)
    private let sfxBox = NSButton(checkboxWithTitle: loc.t("compress_sfx"), target: nil, action: nil)
    private let deleteBox = NSButton(checkboxWithTitle: loc.t("compress_delete_sources"), target: nil, action: nil)
    private let volumeField = NSTextField()
    private let hintLabel = NSTextField(labelWithString: "")
    private var result: CompressOptions?
    private var options: CompressOptions

    init(options: CompressOptions, itemCount: Int) {
        self.options = options
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = loc.t("compress_title")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build(itemCount: itemCount)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build(itemCount: Int) {
        guard let content = window?.contentView else { return }
        let pathRow = makePathRow()
        setUpChoices()
        let header = NSTextField(labelWithString: loc.t("compress_item_count", itemCount))
        header.font = .boldSystemFont(ofSize: 13)

        let grid = makeGrid(pathRow: pathRow)

        let ok = NSButton(title: loc.t("create"), target: self, action: #selector(okPressed))
        ok.keyEquivalent = "\r"
        let cancel = NSButton(title: loc.t("cancel"), target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancel, ok])
        buttons.orientation = .horizontal

        let root = NSStackView(views: [header, grid, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            pathRow.widthAnchor.constraint(equalToConstant: 360),
        ])
        window?.initialFirstResponder = pathField
        applyFormatRules()
    }

    /// The archive's path, with Browse… beside it.
    private func makePathRow() -> NSStackView {
        pathField.stringValue = CompressOptions.archivePath(options.archivePath, format: options.format, sfx: options.sfx)
        pathField.placeholderString = loc.t("compress_path_placeholder")
        pathField.usesSingleLineMode = true
        pathField.cell?.wraps = false
        pathField.cell?.isScrollable = true
        pathField.lineBreakMode = .byTruncatingMiddle
        let browse = NSButton(title: loc.t("compress_browse"), target: self, action: #selector(browse))
        let pathRow = NSStackView(views: [pathField, browse])
        pathRow.orientation = .horizontal
        pathField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return pathRow
    }

    /// The format, level, password, split and option controls, set from the options the dialog opens with.
    private func setUpChoices() {
        formatPopup.addItems(withTitles: ArchiveFormat.allCases.map { $0.title })
        formatPopup.selectItem(at: ArchiveFormat.allCases.firstIndex(of: options.format) ?? 0)
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        levelPopup.addItems(withTitles: [
            loc.t("level_store"), loc.t("level_fastest"), loc.t("level_fast"), loc.t("level_normal"), loc.t("level_good"),
            loc.t("level_best"),
        ])
        levelPopup.selectItem(at: options.level)
        pwField.placeholderString = loc.t("compress_password_placeholder")
        pw2Field.placeholderString = loc.t("compress_password_repeat_placeholder")
        pwField.delegate = self
        volumeField.placeholderString = loc.t("compress_volume_placeholder")
        for f in [volumeField, pwField, pw2Field] as [NSTextField] {
            f.usesSingleLineMode = true
            f.cell?.wraps = false
            f.cell?.isScrollable = true
        }
        encryptNamesBox.state = options.encryptNames ? .on : .off
        solidBox.state = options.solid ? .on : .off
        rrBox.state = options.recoveryRecord ? .on : .off
        sfxBox.state = options.sfx ? .on : .off
        sfxBox.target = self
        sfxBox.action = #selector(sfxChanged)
        deleteBox.state = options.deleteAfter ? .on : .off
        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.maximumNumberOfLines = 1
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hintLabel.widthAnchor.constraint(equalToConstant: 350).isActive = true
    }

    /// The labels on the left and the controls on the right, one row each.
    private func makeGrid(pathRow: NSStackView) -> NSGridView {
        func label(_ s: String) -> NSTextField {
            let field = NSTextField(labelWithString: s)
            field.alignment = .right
            return field
        }
        let formatCell = NSStackView(views: [formatPopup, hintLabel])
        formatCell.orientation = .vertical
        formatCell.alignment = .leading
        formatCell.spacing = 4

        let grid = NSGridView(views: [
            [label(loc.t("compress_label_archive")), pathRow],
            [label(loc.t("compress_label_format")), formatCell],
            [label(loc.t("compress_label_level")), levelPopup],
            [label(loc.t("compress_label_password")), pwField],
            [label(loc.t("compress_label_password_repeat")), pw2Field],
            [NSGridCell.emptyContentView, encryptNamesBox],
            [label(loc.t("compress_label_volumes")), volumeField],
            [label(loc.t("compress_label_options")), solidBox],
            [NSGridCell.emptyContentView, rrBox],
            [NSGridCell.emptyContentView, sfxBox],
            [NSGridCell.emptyContentView, deleteBox],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 360
        return grid
    }

    private var selectedFormat: ArchiveFormat {
        let list = ArchiveFormat.allCases
        let i = formatPopup.indexOfSelectedItem
        return i >= 0 && i < list.count ? list[i] : (list.first ?? .zip)
    }

    @objc private func formatChanged() {
        refreshPath()
        applyFormatRules()
    }

    @objc private func sfxChanged() { refreshPath() }

    /// The path field shows the file that will be written, following the format and the SFX choice.
    private func refreshPath() {
        let path = pathField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }
        pathField.stringValue = CompressOptions.archivePath(path, format: selectedFormat, sfx: sfxChosen)
    }

    private var sfxChosen: Bool { selectedFormat.supportsSFX && sfxBox.state == .on }

    func controlTextDidChange(_ obj: Notification) { applyFormatRules() }

    private func applyFormatRules() {
        let f = selectedFormat
        levelPopup.isEnabled = f.supportsLevel
        pwField.isEnabled = f.supportsPassword
        pw2Field.isEnabled = f.supportsPassword
        encryptNamesBox.isEnabled = f.supportsEncryptNames && !pwField.stringValue.isEmpty
        solidBox.isEnabled = f.supportsSolid
        rrBox.isEnabled = f.supportsRecovery
        sfxBox.isEnabled = f.supportsSFX
        volumeField.isEnabled = f.supportsVolumes
        switch f {
        case .rar5: hintLabel.stringValue = RarTools.available ? loc.t("format_hint_rar5") : loc.t("format_hint_rar_tool_required")
        case .sevenZip: hintLabel.stringValue = loc.t("format_hint_7z")
        case .zip: hintLabel.stringValue = loc.t("format_hint_zip")
        case .tar: hintLabel.stringValue = loc.t("format_hint_tar")
        case .tgz, .txz, .tbz2: hintLabel.stringValue = loc.t("format_hint_tar_compressed")
        }
    }

    @objc private func browse() {
        let panel = NSSavePanel()
        panel.title = loc.t("compress_save_panel_title")
        panel.nameFieldStringValue = (pathField.stringValue as NSString).lastPathComponent
        panel.directoryURL = URL(fileURLWithPath: (pathField.stringValue as NSString).deletingLastPathComponent)
        if panel.runModal() == .OK, let url = panel.url { pathField.stringValue = url.path }
    }

    @objc private func okPressed() {
        var path = pathField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { NSSound.beep(); return }
        let f = selectedFormat
        path = CompressOptions.archivePath(path, format: f, sfx: sfxChosen)
        if f.isRar, !RarTools.ensureAvailable() { return }
        if f.supportsPassword, pwField.stringValue != pw2Field.stringValue {
            Dialogs.error(loc.t("compress_password_mismatch_title"), loc.t("compress_password_mismatch_message"))
            return
        }
        var chosen = options
        chosen.archivePath = path
        chosen.format = f
        chosen.level = levelPopup.indexOfSelectedItem
        chosen.password = (f.supportsPassword && !pwField.stringValue.isEmpty) ? pwField.stringValue : nil
        chosen.encryptNames = f.supportsEncryptNames && encryptNamesBox.state == .on
        chosen.solid = f.supportsSolid && solidBox.state == .on
        chosen.recoveryRecord = f.supportsRecovery && rrBox.state == .on
        chosen.sfx = sfxChosen
        chosen.deleteAfter = deleteBox.state == .on
        let v = volumeField.stringValue.trimmingCharacters(in: .whitespaces)
        chosen.volumeSize = (f.supportsVolumes && !v.isEmpty) ? v : nil
        // Remember the last used settings
        Prefs.defaultFormat = chosen.format
        Prefs.defaultLevel = chosen.level
        Prefs.solid = chosen.solid
        Prefs.recoveryRecord = chosen.recoveryRecord
        result = chosen
        NSApp.stopModal(withCode: .OK)
    }

    @objc private func cancelPressed() { NSApp.stopModal(withCode: .cancel) }

    /// Shows modally; returns nil on cancel.
    func run() -> CompressOptions? {
        guard let window else { return nil }
        Dialogs.activate()
        // Size the window to the height its content needs (so extra space is not spread between the rows)
        if let content = window.contentView {
            content.layoutSubtreeIfNeeded()
            let fit = content.fittingSize
            window.setContentSize(NSSize(width: max(fit.width, 520), height: fit.height))
        }
        window.center()
        let code = NSApp.runModal(for: window)
        window.orderOut(nil)
        return code == .OK ? result : nil
    }
}
