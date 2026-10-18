import AppKit

/// A progress bar without animation: it shows a new fraction at once.
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
    var onCancel: (() -> Void)?
    private weak var host: NSWindow?

    init(title: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 150),
                         styleMask: [.titled], backing: .buffered, defer: false)
        window.title = AppInfo.name
        window.isReleasedWhenClosed = false
        UnseenWindows.apply(to: window)
        super.init(window: window)
        setUpReadout(title: title)
        setUpButtons()
        setUpLog()
        lay(out: window.contentView!)
    }

    /// The title, the file being worked on, the bar and the details beneath it.
    private func setUpReadout(title: String) {
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
    }

    private func setUpButtons() {
        toggleButton.target = self
        toggleButton.action = #selector(toggleDetails)
        toggleButton.bezelStyle = .inline
        toggleButton.font = .systemFont(ofSize: 11)
        toggleButton.setContentHuggingPriority(.required, for: .horizontal)

        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)
    }

    /// The output the operation writes, hidden until the user asks for the details.
    private func setUpLog() {
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
    }

    /// The title, the file, the bar, then the details, the toggle and Cancel in a row, and the log below them.
    private func lay(out content: NSView) {
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

    /// Operations started and not finished, their progress windows up or still waiting out showDelay: the questions the
    /// app asks on its own wait for them (Dialogs.isBusy).
    private(set) static var running = 0
    private var counted = false

    deinit { uncount() }

    private func uncount() {
        guard counted else { return }
        counted = false
        Self.running -= 1
    }

    func show(on host: NSWindow?) {
        if !counted {
            counted = true
            Self.running += 1
        }
        self.host = host
        let present = DispatchWorkItem { [weak self] in self?.present() }
        pendingShow = present
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: present)
    }

    private func present() {
        pendingShow = nil
        guard let window else { return }
        resizeToFit(animate: false)
        if let host, host.isVisible {
            host.beginSheet(window)
        } else {
            window.center()
            showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Takes the window off the screen, or keeps it from coming up, and lets go of what Cancel would stop: the job
    /// holds the window while it runs, so holding the job back kept both once the operation had ended.
    func dismiss() {
        onCancel = nil
        uncount()
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

    /// The file line and the percentage line as they read now
    var readout: (file: String, detail: String) { (fileLabel.stringValue, detailLabel.stringValue) }

    func setFile(_ name: String) {
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

    /// A fraction as a whole percentage, rounded down, with a margin of 1e-9 that keeps what floating point leaves just
    /// under a whole one at it: rar's 29% came as 0.29, and 0.29 × 100 is 28.999…, which read 28%.
    static func percent(_ fraction: Double) -> Int {
        Int((min(1, max(0, fraction)) * 100 + 1e-9).rounded(.down))
    }

    func setFraction(_ f: Double) {
        let v = min(1, max(0, f))
        bar.fraction = v
        var text = loc.t("progress_percent", Self.percent(v))
        let elapsed = Date().timeIntervalSince(startTime)
        if v >= 0.02, v < 1, elapsed > 2 {
            let remaining = elapsed * (1 - v) / v
            text += loc.t("progress_remaining_elapsed", Self.format(remaining), Self.format(elapsed))
        } else if elapsed > 2 {
            text += loc.t("progress_elapsed", Self.format(elapsed))
        }
        detailLabel.stringValue = text
    }

    private static func format(_ interval: TimeInterval) -> String {
        let s = Int(interval.rounded())
        if s < 60 { return loc.t("duration_seconds", s) }
        if s < 3600 { return loc.t("duration_minutes_seconds", s / 60, s % 60) }
        return loc.t("duration_hours_minutes", s / 3600, (s % 3600) / 60)
    }
}
