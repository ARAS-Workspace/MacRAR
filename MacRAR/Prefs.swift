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
    /// "" = system language, "tr", "en"
    static var language: String { get { defaults.string(forKey: "Language") ?? "" } set { defaults.set(newValue, forKey: "Language") } }
}

/// Settings window (⌘,)
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()
    private let formatPopup = NSPopUpButton()
    private let levelPopup = NSPopUpButton()
    private let solidBox = NSButton(checkboxWithTitle: loc.t("compress_solid"), target: nil, action: nil)
    private let rrBox = NSButton(checkboxWithTitle: loc.t("compress_recovery_record"), target: nil, action: nil)
    private let revealExtractBox = NSButton(checkboxWithTitle: loc.t("prefs_reveal_after_extract"), target: nil, action: nil)
    private let revealCompressBox = NSButton(checkboxWithTitle: loc.t("prefs_reveal_after_compress"), target: nil, action: nil)
    private let updatesBox = NSButton(checkboxWithTitle: loc.t("prefs_check_updates"), target: nil, action: nil)
    private let languagePopup = NSPopUpButton()
    private let languageNote = NSTextField(labelWithString: loc.t("prefs_language_note"))
    private let toolStatus = NSTextField(labelWithString: "")
    private lazy var toolButton = NSButton(title: "", target: self, action: #selector(toolAction))

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = loc.t("prefs_title")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        func label(_ s: String) -> NSTextField { let field = NSTextField(labelWithString: s); field.alignment = .right; return field }
        formatPopup.addItems(withTitles: ArchiveFormat.creatable.map { $0.title })
        levelPopup.addItems(withTitles: [
            loc.t("level_store"), loc.t("level_fastest"), loc.t("level_fast"), loc.t("level_normal"), loc.t("level_good"),
            loc.t("level_best"),
        ])
        languagePopup.addItems(withTitles: [loc.t("prefs_system_language")] + LocalizationManager.Language.allCases.map(\.displayName))
        languageNote.font = .systemFont(ofSize: 10)
        languageNote.textColor = .secondaryLabelColor
        for box in [solidBox, rrBox, revealExtractBox, revealCompressBox, updatesBox] { box.target = self; box.action = #selector(changed) }
        for popup in [formatPopup, levelPopup, languagePopup] { popup.target = self; popup.action = #selector(changed) }

        let header1 = NSTextField(labelWithString: loc.t("prefs_section_quick_compress")); header1.font = .boldSystemFont(ofSize: 12)
        let header2 = NSTextField(labelWithString: loc.t("prefs_section_behaviour")); header2.font = .boldSystemFont(ofSize: 12)
        let grid = NSGridView(views: [
            [NSGridCell.emptyContentView, header1],
            [label(loc.t("compress_label_format")), formatPopup],
            [label(loc.t("compress_label_level")), levelPopup],
            [NSGridCell.emptyContentView, solidBox],
            [NSGridCell.emptyContentView, rrBox],
            [NSGridCell.emptyContentView, header2],
            [NSGridCell.emptyContentView, revealExtractBox],
            [NSGridCell.emptyContentView, revealCompressBox],
            [NSGridCell.emptyContentView, updatesBox],
            [label(loc.t("prefs_label_language")), languagePopup],
            [NSGridCell.emptyContentView, languageNote],
            [label(AppInfo.isAppStore ? loc.t("prefs_label_folders") : loc.t("prefs_label_rar_tool")), toolStatus],
            [NSGridCell.emptyContentView, toolButton],
            [
                label(loc.t("prefs_label_files")),
                NSButton(
                    title: loc.t("action_file_associations"), target: AppDelegate.shared,
                    action: #selector(AppDelegate.showAssociations(_:))),
            ],
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
        formatPopup.removeAllItems()
        formatPopup.addItems(withTitles: ArchiveFormat.creatable.map { $0.title })
        formatPopup.selectItem(at: ArchiveFormat.creatable.firstIndex(of: Prefs.defaultFormat) ?? 0)
    }

    private func load() {
        refreshTool()
        formatPopup.selectItem(at: ArchiveFormat.creatable.firstIndex(of: Prefs.defaultFormat) ?? 0)
        levelPopup.selectItem(at: Prefs.defaultLevel)
        solidBox.state = Prefs.solid ? .on : .off
        rrBox.state = Prefs.recoveryRecord ? .on : .off
        revealExtractBox.state = Prefs.revealAfterExtract ? .on : .off
        revealCompressBox.state = Prefs.revealAfterCompress ? .on : .off
        updatesBox.state = Prefs.checkUpdates ? .on : .off
        languagePopup.selectItem(at: LocalizationManager.Language.allCases.firstIndex { $0.rawValue == Prefs.language }.map { $0 + 1 } ?? 0)
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
        Prefs.language = ([""] + LocalizationManager.Language.allCases.map(\.rawValue))[languagePopup.indexOfSelectedItem]
    }

    func show() {
        load()
        guard let window else { return }
        if let content = window.contentView {
            content.layoutSubtreeIfNeeded()
            window.setContentSize(NSSize(width: max(content.fittingSize.width, 520), height: content.fittingSize.height))
        }
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
