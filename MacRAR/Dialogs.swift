import AppKit
import QuartzCore
import UniformTypeIdentifiers

// swiftlint:disable file_length

// MARK: - Simple dialogs

enum Dialogs {
    static func activate() { NSApp.activate(ignoringOtherApps: true) }

    static func askPassword(archiveName: String, wrong: Bool = false) -> String? {
        if let dbg = ProcessInfo.processInfo.environment["MACRAR_DEBUG_PASSWORD"], !wrong { return dbg == "__cancel__" ? nil : dbg }
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

    static func confirm(_ title: String, _ detail: String, okTitle: String = loc.t("ok"), destructive: Bool = false) -> Bool {
        if ProcessInfo.processInfo.environment["MACRAR_DEBUG_CONFIRM"] != nil { return true }
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

    static func chooseFolder(title: String, prompt: String, initial: String? = nil) -> String? {
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

// MARK: - Progress bar (no animation, updates immediately)

final class PlainProgressBar: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 8) }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        let track = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.quaternaryLabelColor.setFill()
        track.fill()
        let filled = max(rect.height, rect.width * CGFloat(min(1, max(0, fraction))))
        if fraction > 0 {
            let fill = NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: filled, height: rect.height),
                                    xRadius: rect.height / 2, yRadius: rect.height / 2)
            NSColor.controlAccentColor.setFill()
            fill.fill()
        }
    }
}

// MARK: - Progress window

final class ProgressPanel: NSWindowController {
    private static let panelWidth: CGFloat = 500
    private let titleLabel = NSTextField(labelWithString: "")
    private let fileLabel = NSTextField(labelWithString: "")
    private let bar = PlainProgressBar()
    private let detailLabel = NSTextField(labelWithString: "")
    private let toggleButton = NSButton(title: loc.t("progress_show_details"), target: nil, action: nil)
    private let cancelButton = NSButton(title: loc.t("cancel"), target: nil, action: nil)
    private let logScroll = NSScrollView()
    private let logView = NSTextView()
    private let startTime = Date()
    private var lastLogged = ""
    /// Destination folder prefix in the unrar output (to shorten file names)
    var stripPrefix: String?
    var onCancel: (() -> Void)?
    private weak var host: NSWindow?

    // swiftlint:disable:next function_body_length
    init(title: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 150),
                         styleMask: [.titled], backing: .buffered, defer: false)
        window.title = AppInfo.name
        window.isReleasedWhenClosed = false
        super.init(window: window)

        titleLabel.stringValue = title
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        fileLabel.font = .systemFont(ofSize: 11)
        fileLabel.textColor = .secondaryLabelColor
        fileLabel.lineBreakMode = .byTruncatingHead        // the trailing file name always stays visible
        fileLabel.maximumNumberOfLines = 1
        fileLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fileLabel.stringValue = loc.t("progress_preparing")

        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 8).isActive = true

        detailLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        toggleButton.target = self
        toggleButton.action = #selector(toggleDetails)
        toggleButton.bezelStyle = .inline
        toggleButton.font = .systemFont(ofSize: 11)
        toggleButton.setContentHuggingPriority(.required, for: .horizontal)

        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)

        logView.isEditable = false
        logView.isRichText = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textColor = .secondaryLabelColor
        logView.backgroundColor = .textBackgroundColor
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = false
        logView.autoresizingMask = [.width]
        logView.textContainer?.widthTracksTextView = true
        logView.textContainer?.lineBreakMode = .byCharWrapping
        logView.textContainerInset = NSSize(width: 4, height: 4)
        logScroll.documentView = logView
        logScroll.hasVerticalScroller = true
        logScroll.borderType = .bezelBorder
        logScroll.isHidden = true
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        logScroll.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let bottomRow = NSStackView(views: [detailLabel, toggleButton, cancelButton])
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 10
        bottomRow.setHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [titleLabel, fileLabel, bar, bottomRow, logScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.detachesHiddenViews = true
        stack.setCustomSpacing(14, after: bar)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: Self.panelWidth),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            fileLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bottomRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            logScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func cancelPressed() {
        cancelButton.isEnabled = false
        fileLabel.stringValue = loc.t("progress_cancelling")
        onCancel?()
    }

    @objc private func toggleDetails() {
        let show = logScroll.isHidden
        logScroll.isHidden = !show
        toggleButton.title = show ? loc.t("progress_hide_details") : loc.t("progress_show_details")
        resizeToFit(animate: true)
        if show { scrollLogToEnd() }
    }

    /// Sizes the window to the height its content needs (grows and shrinks), keeping the top edge fixed
    private func resizeToFit(animate: Bool) {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let fit = content.fittingSize
        let contentRect = NSRect(x: 0, y: 0, width: Self.panelWidth, height: fit.height)
        if window.sheetParent != nil {
            window.setContentSize(contentRect.size)
            return
        }
        var frame = window.frameRect(forContentRect: contentRect)
        let old = window.frame
        frame.origin = NSPoint(x: old.origin.x, y: old.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animate)
    }

    /// The panel appears only once the operation has run for `showDelay`: a panel ordered in and out
    /// within a few milliseconds left the next NSAlert.runModal returning at once.
    static let showDelay: TimeInterval = 0.3
    private var pendingShow: DispatchWorkItem?

    func show(on host: NSWindow?) {
        self.host = host
        let present = DispatchWorkItem { [weak self] in self?.present() }
        pendingShow = present
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: present)
    }

    private func present() {
        pendingShow = nil
        guard let window else { return }
        resizeToFit(animate: false)
        if ProcessInfo.processInfo.environment["MACRAR_DEBUG_DETAILS"] != nil { toggleDetails() }
        if ProcessInfo.processInfo.environment["MACRAR_DEBUG_DETAILS"] == "toggle" { toggleDetails() }
        if let host, host.isVisible {
            host.beginSheet(window)
        } else {
            window.center()
            showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func dismiss() {
        if let pendingShow {
            pendingShow.cancel()
            self.pendingShow = nil
            close()
            return
        }
        guard let window else { return }
        if let host, host.isVisible, host.attachedSheet == window {
            host.endSheet(window)
        }
        window.orderOut(nil)
        close()
    }

    func setFile(_ raw: String) {
        var name = raw
        if let stripPrefix, !stripPrefix.isEmpty {
            let pre = stripPrefix.hasSuffix("/") ? stripPrefix : stripPrefix + "/"
            if name.hasPrefix(pre) {
                name = String(name.dropFirst(pre.count))
            } else if name == stripPrefix {
                name = (stripPrefix as NSString).lastPathComponent
            }
        }
        fileLabel.stringValue = name
        guard name != lastLogged else { return }
        lastLogged = name
        logView.textStorage?.append(NSAttributedString(string: name + "\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        if !logScroll.isHidden { scrollLogToEnd() }
    }

    private func scrollLogToEnd() {
        logView.scrollToEndOfDocument(nil)
    }

    func setFraction(_ f: Double?) {
        if let f {
            let v = min(1, max(0, f))
            bar.fraction = v
            var text = loc.t("progress_percent", Int(v * 100))
            let elapsed = Date().timeIntervalSince(startTime)
            if v >= 0.02, v < 1, elapsed > 2 {
                let remaining = elapsed * (1 - v) / v
                text += loc.t("progress_remaining_elapsed", Self.format(remaining), Self.format(elapsed))
            } else if elapsed > 2 {
                text += loc.t("progress_elapsed", Self.format(elapsed))
            }
            detailLabel.stringValue = text
        } else {
            bar.fraction = 0
            detailLabel.stringValue = ""
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let s = Int(interval.rounded())
        if s < 60 { return loc.t("duration_seconds", s) }
        if s < 3600 { return loc.t("duration_minutes_seconds", s / 60, s % 60) }
        return loc.t("duration_hours_minutes", s / 3600, (s % 3600) / 60)
    }
}

// MARK: - Compression options

enum ArchiveFormat: Int, CaseIterable {
    case rar5 = 0, sevenZip = 2, zip = 3, tar = 4, tgz = 5, txz = 6, tbz2 = 7

    /// Formats this edition can create (no RAR in the App Store edition)
    static var creatable: [ArchiveFormat] { AppInfo.isAppStore ? allCases.filter { $0 != .rar5 } : allCases }

    var title: String {
        switch self {
        case .rar5: return RarTools.available ? "RAR 5" : loc.t("format_rar5")
        case .sevenZip: return "7z"
        case .zip: return "ZIP"
        case .tar: return loc.t("format_tar")
        case .tgz: return "TAR.GZ"
        case .txz: return "TAR.XZ"
        case .tbz2: return "TAR.BZ2"
        }
    }
    var ext: String {
        switch self {
        case .rar5: return "rar"
        case .sevenZip: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        case .tgz: return "tar.gz"
        case .txz: return "tar.xz"
        case .tbz2: return "tar.bz2"
        }
    }
    var isRar: Bool { self == .rar5 }
    var isTarFamily: Bool { self == .tar || self == .tgz || self == .txz || self == .tbz2 }
    var supportsPassword: Bool { isRar || self == .sevenZip || self == .zip }
    var supportsEncryptNames: Bool { isRar || self == .sevenZip }
    var supportsSolid: Bool { isRar || self == .sevenZip }
    var supportsRecovery: Bool { isRar }
    var supportsSFX: Bool { isRar }
    var supportsVolumes: Bool { isRar || self == .sevenZip || self == .zip }
    var supportsLevel: Bool { self != .tar }
    var supportsAppend: Bool { !isTarFamily || self == .tar }

    static func detect(fromPath path: String) -> ArchiveFormat? {
        let lower = path.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") { return .tgz }
        if lower.hasSuffix(".tar.xz") || lower.hasSuffix(".txz") { return .txz }
        if lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tbz2") || lower.hasSuffix(".tbz") { return .tbz2 }
        switch (lower as NSString).pathExtension {
        case "rar": return .rar5
        case "7z": return .sevenZip
        case "zip": return .zip
        case "tar": return .tar
        default: return nil
        }
    }

    /// Changes the path's archive extension to match this format
    func replacingExtension(in path: String) -> String {
        var base = path
        let lower = base.lowercased()
        for suf in [".tar.gz", ".tar.xz", ".tar.bz2", ".tgz", ".txz", ".tbz2", ".tbz", ".rar", ".7z", ".zip", ".tar"]
        where lower.hasSuffix(suf) {
            base = String(base.dropLast(suf.count)); break
        }
        return base + "." + ext
    }
}

struct CompressOptions {
    var archivePath: String
    var format: ArchiveFormat = .rar5
    var level: Int = 3                 // 0-5
    var password: String?
    var encryptNames: Bool = false
    var solid: Bool = false
    var recoveryRecord: Bool = false
    var volumeSize: String?      // e.g. "100M"
    var sfx: Bool = false
    var deleteAfter: Bool = false

    enum StepWork {
        case rar([String])
        case sevenZip(SevenZipBridge.Operation)
    }

    struct Step {
        let title: String
        let work: StepWork
        var cleanup: (() -> Void)?
    }

    /// Maps the 0-5 level to the 7-Zip -mx value
    private var mx: Int32 { [0, 1, 3, 5, 7, 9][max(0, min(5, level))] }

    /// The split size in bytes, read the way 7-Zip reads -v: a number with an optional
    /// b, k, m or g suffix in powers of 1024. 0 for no split, nil when the text is not a size.
    var volumeBytes: UInt64? {
        guard let text = volumeSize?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return 0 }
        guard let match = text.range(of: #"^\d+\s*[bBkKmMgG]?$"#, options: .regularExpression), match == text.startIndex..<text.endIndex
        else { return nil }
        let digits = text.prefix { $0.isNumber }
        let suffix = text.last.map { $0.isNumber ? "b" : String($0).lowercased() } ?? "b"
        let shift: UInt64 = ["b": 0, "k": 10, "m": 20, "g": 30][suffix] ?? 0
        guard let value = UInt64(digits), value > 0, value <= (UInt64.max >> shift) else { return nil }
        return value << shift
    }

    func buildSteps(items: [String]) -> [Step] {
        let password = self.password.flatMap { $0.isEmpty ? nil : $0 }
        let split = format.supportsVolumes ? (volumeBytes ?? 0) : 0

        func update(_ archive: String, _ sources: [String], _ options: SevenZipBridge.UpdateOptions) -> StepWork {
            .sevenZip(.update(archive: archive, sources: sources, options: options))
        }

        switch format {
        case .rar5:
            var args = ["a", "-ep1", "-r", "-y", "-m\(level)", "-ma5"]
            if solid { args.append("-s") }
            if recoveryRecord { args.append("-rr3") }
            if let v = volumeSize, !v.isEmpty { args.append("-v\(v)") }
            if sfx { args.append("-sfx") }
            if deleteAfter { args.append("-df") }
            args += RarRunner.rarPasswordArgs(password, encryptHeaders: encryptNames)
            return [Step(title: loc.t("progress_compressing"), work: .rar(args + ["--", archivePath] + items))]

        case .sevenZip:
            var sevenZip = SevenZipBridge.UpdateOptions(format: "7z", level: mx, solid: solid ? 1 : 0, password: password)
            sevenZip.encryptHeaders = password != nil && encryptNames
            sevenZip.volumeSize = split
            sevenZip.deleteSources = deleteAfter
            return [Step(title: loc.t("progress_compressing"), work: update(archivePath, items, sevenZip))]

        case .zip:
            var zip = SevenZipBridge.UpdateOptions(format: "zip", level: mx, password: password)
            zip.zipAES256 = password != nil
            zip.volumeSize = split
            zip.deleteSources = deleteAfter
            return [Step(title: loc.t("progress_compressing"), work: update(archivePath, items, zip))]

        case .tar:
            var tar = SevenZipBridge.UpdateOptions(format: "tar")
            tar.deleteSources = deleteAfter
            return [Step(title: loc.t("progress_packing"), work: update(archivePath, items, tar))]

        case .tgz, .txz, .tbz2:
            let outer: String = format == .tgz ? "gzip" : (format == .txz ? "xz" : "bzip2")
            let tmpTar = NSTemporaryDirectory() + "Archiver-\(UUID().uuidString).tar"
            var tar = SevenZipBridge.UpdateOptions(format: "tar")
            tar.deleteSources = deleteAfter
            let stream = SevenZipBridge.UpdateOptions(format: outer, level: mx)
            return [
                Step(title: loc.t("progress_packing"), work: update(tmpTar, items, tar)),
                Step(
                    title: loc.t("progress_compressing"), work: update(archivePath, [tmpTar], stream),
                    cleanup: { try? FileManager.default.removeItem(atPath: tmpTar) }),
            ]
        }
    }

    /// Options object with the defaults from Settings
    static func withDefaults(for items: [String]) -> CompressOptions {
        var options = CompressOptions(archivePath: defaultArchivePath(for: items, format: Prefs.defaultFormat))
        options.format = Prefs.defaultFormat
        options.level = Prefs.defaultLevel
        options.solid = Prefs.solid && options.format.supportsSolid
        options.recoveryRecord = Prefs.recoveryRecord && options.format.supportsRecovery
        return options
    }

    static func defaultArchivePath(for items: [String], format: ArchiveFormat = .zip) -> String {
        guard let first = items.first else { return loc.t("compress_default_archive_name") + "." + format.ext }
        let parent = (first as NSString).deletingLastPathComponent
        var base: String
        if items.count == 1 {
            base = (first as NSString).lastPathComponent
            if !isDirectoryPath(first) { base = (base as NSString).deletingPathExtension }
        } else {
            base = (parent as NSString).lastPathComponent
        }
        if base.isEmpty || base == "/" { base = loc.t("compress_default_archive_name") }
        return (parent as NSString).appendingPathComponent(base + "." + format.ext)
    }
}

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

    // swiftlint:disable:next function_body_length
    private func build(itemCount: Int) {
        guard let content = window?.contentView else { return }
        pathField.stringValue = options.archivePath
        pathField.placeholderString = loc.t("compress_path_placeholder")
        pathField.usesSingleLineMode = true
        pathField.cell?.wraps = false
        pathField.cell?.isScrollable = true
        pathField.lineBreakMode = .byTruncatingMiddle
        let browse = NSButton(title: loc.t("compress_browse"), target: self, action: #selector(browse))
        let pathRow = NSStackView(views: [pathField, browse])
        pathRow.orientation = .horizontal
        pathField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        formatPopup.addItems(withTitles: ArchiveFormat.creatable.map { $0.title })
        formatPopup.selectItem(at: ArchiveFormat.creatable.firstIndex(of: options.format) ?? 0)
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
        deleteBox.state = options.deleteAfter ? .on : .off
        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.maximumNumberOfLines = 1
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hintLabel.widthAnchor.constraint(equalToConstant: 350).isActive = true

        func label(_ s: String) -> NSTextField {
            let field = NSTextField(labelWithString: s)
            field.alignment = .right
            return field
        }
        let header = NSTextField(labelWithString: loc.t("compress_item_count", itemCount))
        header.font = .boldSystemFont(ofSize: 13)

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

    private var selectedFormat: ArchiveFormat {
        let list = ArchiveFormat.creatable
        let i = formatPopup.indexOfSelectedItem
        return i >= 0 && i < list.count ? list[i] : (list.first ?? .zip)
    }

    @objc private func formatChanged() {
        let f = selectedFormat
        let path = pathField.stringValue.trimmingCharacters(in: .whitespaces)
        if !path.isEmpty { pathField.stringValue = f.replacingExtension(in: path) }
        applyFormatRules()
    }

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
        if ArchiveFormat.detect(fromPath: path) != f { path = f.replacingExtension(in: path) }
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
        chosen.sfx = f.supportsSFX && sfxBox.state == .on
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
