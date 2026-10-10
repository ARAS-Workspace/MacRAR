import AppKit

/// User settings (UserDefaults)
enum Prefs {
    private static let defaults = UserDefaults.standard
    static var defaultFormat: ArchiveFormat {
        get {
            let fallback: ArchiveFormat = RarTools.available ? .rar5 : .zip
            guard defaults.object(forKey: "DefaultFormat") != nil,
                let f = ArchiveFormat(rawValue: defaults.integer(forKey: "DefaultFormat")),
                  ArchiveFormat.creatable.contains(f) else { return fallback }
            return f
        }
        set { defaults.set(newValue.rawValue, forKey: "DefaultFormat") }
    }
    static var defaultLevel: Int {
        get { defaults.object(forKey: "DefaultLevel") == nil ? 3 : max(0, min(5, defaults.integer(forKey: "DefaultLevel"))) }
        set { defaults.set(newValue, forKey: "DefaultLevel") }
    }
    static var solid: Bool { get { defaults.bool(forKey: "DefaultSolid") } set { defaults.set(newValue, forKey: "DefaultSolid") } }
    static var recoveryRecord: Bool {
        get { defaults.bool(forKey: "DefaultRecovery") }
        set { defaults.set(newValue, forKey: "DefaultRecovery") }
    }
    static var revealAfterExtract: Bool {
        get { defaults.object(forKey: "RevealAfterExtract") == nil ? true : defaults.bool(forKey: "RevealAfterExtract") }
        set { defaults.set(newValue, forKey: "RevealAfterExtract") }
    }
    static var revealAfterCompress: Bool {
        get { defaults.object(forKey: "RevealAfterCompress") == nil ? true : defaults.bool(forKey: "RevealAfterCompress") }
        set { defaults.set(newValue, forKey: "RevealAfterCompress") }
    }
    static var checkUpdates: Bool {
        get { defaults.object(forKey: "CheckUpdates") == nil ? true : defaults.bool(forKey: "CheckUpdates") }
        set { defaults.set(newValue, forKey: "CheckUpdates") }
    }
}

/// Settings window (⌘,)
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()
    private let formatPopup = NSPopUpButton()
    private let levelPopup = NSPopUpButton()
    private let solidBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let rrBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let revealExtractBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let revealCompressBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let updatesBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let languagePopup = NSPopUpButton()
    private let toolStatus = NSTextField(labelWithString: "")
    private lazy var toolButton = NSButton(title: "", target: self, action: #selector(toolAction))
    private lazy var associationsButton = NSButton(
        title: "", target: AppDelegate.shared, action: #selector(AppDelegate.showAssociations(_:)))
    private let quickCompressHeader = NSTextField(labelWithString: "")
    private let behaviourHeader = NSTextField(labelWithString: "")
    private let formatLabel = PreferencesWindowController.rowLabel()
    private let levelLabel = PreferencesWindowController.rowLabel()
    private let languageLabel = PreferencesWindowController.rowLabel()
    private let toolLabel = PreferencesWindowController.rowLabel()
    private let filesLabel = PreferencesWindowController.rowLabel()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        applyLanguage()
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageDidChange), name: LocalizationManager.didChange, object: loc)
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func rowLabel() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.alignment = .right
        return field
    }

    private func build() {
        guard let content = window?.contentView else { return }
        languagePopup.addItems(withTitles: LocalizationManager.Language.allCases.map { "\($0.flag) \($0.displayName)" })
        languagePopup.target = self
        languagePopup.action = #selector(languageChosen)
        for box in [solidBox, rrBox, revealExtractBox, revealCompressBox, updatesBox] { box.target = self; box.action = #selector(changed) }
        for popup in [formatPopup, levelPopup] { popup.target = self; popup.action = #selector(changed) }
        for header in [quickCompressHeader, behaviourHeader] { header.font = .boldSystemFont(ofSize: 12) }

        let grid = NSGridView(views: [
            [NSGridCell.emptyContentView, quickCompressHeader],
            [formatLabel, formatPopup],
            [levelLabel, levelPopup],
            [NSGridCell.emptyContentView, solidBox],
            [NSGridCell.emptyContentView, rrBox],
            [NSGridCell.emptyContentView, behaviourHeader],
            [NSGridCell.emptyContentView, revealExtractBox],
            [NSGridCell.emptyContentView, revealCompressBox],
            [NSGridCell.emptyContentView, updatesBox],
            [languageLabel, languagePopup],
            [toolLabel, toolStatus],
            [NSGridCell.emptyContentView, toolButton],
            [filesLabel, associationsButton],
        ])
        updatesBox.isHidden = AppInfo.isAppStore
        toolStatus.font = .systemFont(ofSize: 11)
        toolStatus.textColor = .secondaryLabelColor
        toolStatus.lineBreakMode = .byTruncatingMiddle
        toolStatus.widthAnchor.constraint(lessThanOrEqualToConstant: 340).isActive = true
        grid.rowSpacing = 8; grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    /// Every text in the window: set when it is built and again whenever the language changes.
    private func applyLanguage() {
        window?.title = loc.t("prefs_title")
        quickCompressHeader.stringValue = loc.t("prefs_section_quick_compress")
        behaviourHeader.stringValue = loc.t("prefs_section_behaviour")
        formatLabel.stringValue = loc.t("compress_label_format")
        levelLabel.stringValue = loc.t("compress_label_level")
        languageLabel.stringValue = loc.t("prefs_label_language")
        toolLabel.stringValue = AppInfo.isAppStore ? loc.t("prefs_label_folders") : loc.t("prefs_label_rar_tool")
        filesLabel.stringValue = loc.t("prefs_label_files")
        solidBox.title = loc.t("compress_solid")
        rrBox.title = loc.t("compress_recovery_record")
        revealExtractBox.title = loc.t("prefs_reveal_after_extract")
        revealCompressBox.title = loc.t("prefs_reveal_after_compress")
        updatesBox.title = loc.t("prefs_check_updates")
        associationsButton.title = loc.t("action_file_associations")
        levelPopup.removeAllItems()
        levelPopup.addItems(withTitles: [
            loc.t("level_store"), loc.t("level_fastest"), loc.t("level_fast"), loc.t("level_normal"), loc.t("level_good"),
            loc.t("level_best"),
        ])
        levelPopup.selectItem(at: Prefs.defaultLevel)
        reloadFormats()
        languagePopup.selectItem(at: LocalizationManager.Language.allCases.firstIndex(of: loc.current) ?? 0)
        refreshTool()
    }

    @objc private func languageDidChange() {
        applyLanguage()
        fitContent()
    }

    private func reloadFormats() {
        formatPopup.removeAllItems()
        formatPopup.addItems(withTitles: ArchiveFormat.creatable.map { $0.title })
        formatPopup.selectItem(at: ArchiveFormat.creatable.firstIndex(of: Prefs.defaultFormat) ?? 0)
    }

    private func refreshTool() {
        if AppInfo.isAppStore {
            let count = FolderAccess.grantedFolders.count
            toolStatus.stringValue = count == 0 ? loc.t("prefs_folders_none") : loc.t("prefs_folders_count", count)
            toolButton.title = loc.t("prefs_allow_home")
        } else if let v = RarTools.version {
            toolStatus.stringValue = loc.t("prefs_rar_installed", v)
            toolButton.title = loc.t("prefs_rar_remove")
        } else {
            toolStatus.stringValue = loc.t("prefs_rar_not_installed")
            toolButton.title = loc.t("prefs_rar_install")
        }
    }

    @objc private func toolAction() {
        if AppInfo.isAppStore {
            FolderAccess.grantHome()
        } else {
            #if !APPSTORE
            if RarTools.available { RarTools.uninstall() } else { RarTools.ensureAvailable() }
            #endif
        }
        refreshTool()
        reloadFormats()
    }

    private func load() {
        refreshTool()
        reloadFormats()
        levelPopup.selectItem(at: Prefs.defaultLevel)
        solidBox.state = Prefs.solid ? .on : .off
        rrBox.state = Prefs.recoveryRecord ? .on : .off
        revealExtractBox.state = Prefs.revealAfterExtract ? .on : .off
        revealCompressBox.state = Prefs.revealAfterCompress ? .on : .off
        updatesBox.state = Prefs.checkUpdates ? .on : .off
        languagePopup.selectItem(at: LocalizationManager.Language.allCases.firstIndex(of: loc.current) ?? 0)
    }

    @objc private func changed() {
        let list = ArchiveFormat.creatable
        let fi = formatPopup.indexOfSelectedItem
        Prefs.defaultFormat = fi >= 0 && fi < list.count ? list[fi] : .zip
        Prefs.defaultLevel = levelPopup.indexOfSelectedItem
        Prefs.solid = solidBox.state == .on
        Prefs.recoveryRecord = rrBox.state == .on
        Prefs.revealAfterExtract = revealExtractBox.state == .on
        Prefs.revealAfterCompress = revealCompressBox.state == .on
        Prefs.checkUpdates = updatesBox.state == .on
    }

    /// The language applies at once: the manager saves it and every window and menu follows.
    @objc private func languageChosen() {
        let languages = LocalizationManager.Language.allCases
        let index = languagePopup.indexOfSelectedItem
        guard languages.indices.contains(index) else { return }
        loc.current = languages[index]
    }

    /// Sizes the window to its content, keeping its top edge in place.
    private func fitContent() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = NSSize(width: max(content.fittingSize.width, 520), height: content.fittingSize.height)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    func show() {
        load()
        guard let window else { return }
        fitContent()
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
