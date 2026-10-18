import AppKit
import Quartz

final class ArchiveWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private(set) var archivePath: String?
    private(set) var info: ArchiveInfo?
    var password: String?
    private(set) var root = Node(name: "", path: "", isDir: true)
    private(set) var filtered: [Node]?
    private var filterText = ""

    let outline = ArchiveOutlineView()
    private let scroll = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var openButton = NSButton(title: "", target: self, action: #selector(openArchive(_:)))
    private lazy var newButton = NSButton(title: "", target: self, action: #selector(newArchive(_:)))
    private let emptyView = EmptyStateView()
    var sortKey = "name"
    var sortAscending = true
    var previewURLs: [URL] = []
    let promiseQueue: OperationQueue = {
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; return queue
    }()
    // Drag-to-Finder session (the question is asked once, the items are extracted in one go)
    var dragNodes: [Node] = []
    var dragDecision: Bool?
    /// What to do with the dragged items already at the destination, asked with the drag's first promise.
    var dragOverwrite: Dialogs.OverwriteMode?
    var dragTempDir: String?
    var dragExtracted = false
    var dragExtractOK = false
    var dragPending = 0

    static let nameCol = NSUserInterfaceItemIdentifier("name")
    static let sizeCol = NSUserInterfaceItemIdentifier("size")
    static let packedCol = NSUserInterfaceItemIdentifier("packed")
    static let ratioCol = NSUserInterfaceItemIdentifier("ratio")
    static let dateCol = NSUserInterfaceItemIdentifier("date")
    static let crcCol = NSUserInterfaceItemIdentifier("crc")
    static let lockCol = NSUserInterfaceItemIdentifier("lock")

    /// The name AppKit saves the archive windows' frame under, in the app's defaults.
    static let frameName = "ArchiveWindow"

    /// `savedFrame` is a frame as AppKit writes one, which a test gives in place of the one the user's windows saved.
    init(savedFrame: NSWindow.PersistableFrameDescriptor? = nil) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        window.title = AppInfo.name
        window.minSize = NSSize(width: 560, height: 300)
        window.isReleasedWhenClosed = false
        UnseenWindows.apply(to: window)
        super.init(window: window)
        window.delegate = self
        buildUI()
        buildToolbar()
        applyLanguage()
        place(savedFrame: savedFrame)
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageDidChange), name: LocalizationManager.didChange, object: loc)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// When the window last came to the front through the app: placed, or made main after (`windowDidBecomeMain`). A
    /// new window cascades from the archive window up with the latest, and not from the window server's order or
    /// main window, which differ between an app in front and one in the background: on CI, where the test host is the
    /// app in front, the first window stayed main and first in that order, and the third window came up on top of the
    /// second; on a Mac, where the test host is in the background, no window was main.
    private var cameToFront = 0
    private static var fronts = 0

    private func comeToFront() {
        Self.fronts += 1
        cameToFront = Self.fronts
    }

    /// Puts the window where the user's archive windows saved their frame, or in the middle when none is saved, and
    /// one step down and right of the archive window last in front when one is up. It takes the saved frame once it
    /// has its toolbar: given it before, the toolbar made the window taller every time it opened. A test run leaves the
    /// frame, columns, sort order and toolbar the user's windows saved as they were (MACRAR_DEBUG_UNSEEN).
    private func place(savedFrame: NSWindow.PersistableFrameDescriptor?) {
        guard let window else { return }
        let front = NSApp.windows.compactMap { $0.windowController as? ArchiveWindowController }
            .filter { $0 !== self && $0.window?.isVisible == true }
            .max { $0.cameToFront < $1.cameToFront }?.window
        let saved = savedFrame ?? (UnseenWindows.isOn ? nil : UserDefaults.standard.string(forKey: "NSWindow Frame \(Self.frameName)"))
        if let saved { window.setFrame(from: saved) } else { window.center() }
        // The first archive window up takes the name and saves its frame from then on
        if !UnseenWindows.isOn { window.setFrameAutosaveName(Self.frameName) }
        if let front { window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: front.frame.minX, y: front.frame.maxY))) }
        comeToFront()
    }

    // MARK: UI

    private func buildUI() {
        guard let window, let content = window.contentView else { return }
        setUpOutline()
        setUpEmptyState()
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusBar = NSVisualEffectView()
        statusBar.material = .titlebar
        statusBar.blendingMode = .withinWindow
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(statusLabel)

        content.addSubview(scroll)
        content.addSubview(statusBar)
        content.addSubview(emptyView)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -10),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            emptyView.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            emptyView.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 28),
            emptyView.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
        ])
        updateStatus()
    }

    /// The archive's tree: its columns, sorting, keys, double-click, and drags in and out, in a scroll view.
    private func setUpOutline() {
        func col(
            _ id: NSUserInterfaceItemIdentifier, _ title: String, width: CGFloat, min: CGFloat = 40, align: NSTextAlignment = .left
        ) -> NSTableColumn {
            let column = NSTableColumn(identifier: id)
            column.title = title
            column.width = width
            column.minWidth = min
            column.headerCell.alignment = align
            return column
        }
        outline.addTableColumn(col(Self.nameCol, "", width: 320, min: 160))
        outline.addTableColumn(col(Self.lockCol, "🔒", width: 28, min: 28, align: .center))
        outline.addTableColumn(col(Self.sizeCol, "", width: 90, align: .right))
        outline.addTableColumn(col(Self.packedCol, "", width: 90, align: .right))
        outline.addTableColumn(col(Self.ratioCol, "", width: 55, align: .right))
        outline.addTableColumn(col(Self.dateCol, "", width: 140))
        outline.addTableColumn(col(Self.crcCol, "CRC32", width: 80))
        for column in outline.tableColumns where column.identifier != Self.lockCol && column.identifier != Self.crcCol {
            column.sortDescriptorPrototype = NSSortDescriptor(key: column.identifier.rawValue, ascending: true)
        }
        outline.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        // A test run leaves the columns and sort order the user's windows saved as they were
        if !UnseenWindows.isOn {
            outline.autosaveName = "ArchiveOutline"
            outline.autosaveTableColumns = true
        }
        outline.onReturn = { [weak self] in self?.openSelected(nil) }
        outline.onSpace = { [weak self] in self?.quickLook(nil) }
        outline.outlineTableColumn = outline.tableColumns[0]
        outline.dataSource = self
        outline.delegate = self
        outline.allowsMultipleSelection = true
        outline.usesAlternatingRowBackgroundColors = true
        outline.rowSizeStyle = .default
        outline.autoresizesOutlineColumn = true
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.target = self
        outline.doubleAction = #selector(doubleClicked)
        outline.registerForDraggedTypes([.fileURL])
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)

        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
    }

    /// What an empty window shows over the tree: a hint, Open and New, and room to drop files.
    private func setUpEmptyState() {
        emptyLabel.alignment = .center
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 15)
        openButton.bezelStyle = .rounded; newButton.bezelStyle = .rounded
        let btnRow = NSStackView(views: [openButton, newButton]); btnRow.spacing = 12
        let emptyStack = NSStackView(views: [emptyLabel, btnRow])
        emptyStack.orientation = .vertical; emptyStack.alignment = .centerX; emptyStack.spacing = 18
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.addSubview(emptyStack)
        emptyView.onDrop = { [weak self] urls in self?.handleDrop(urls) }
        NSLayoutConstraint.activate([
            emptyStack.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])
    }

    /// Every text in the window: set when it is built and again whenever the language changes.
    private func applyLanguage() {
        let columnTitles: [NSUserInterfaceItemIdentifier: String] = [
            Self.nameCol: loc.t("column_name"), Self.sizeCol: loc.t("column_size"), Self.packedCol: loc.t("column_packed"),
            Self.ratioCol: loc.t("column_ratio"), Self.dateCol: loc.t("column_modified"),
        ]
        for (id, title) in columnTitles { outline.tableColumn(withIdentifier: id)?.title = title }
        outline.headerView?.needsDisplay = true
        outline.menu = buildContextMenu()
        emptyLabel.stringValue = loc.t("window_empty_hint")
        openButton.title = loc.t("action_open_archive")
        newButton.title = loc.t("window_empty_new_archive")
        window?.toolbar?.items.forEach(localize)
        updateStatus()
    }

    @objc private func languageDidChange() {
        applyLanguage()
    }

    private func buildContextMenu() -> NSMenu {
        MenuSpec.menu("", MenuSpec.archiveContextMenu(loc: loc), appTarget: nil, recent: nil)
    }

    // MARK: Toolbar

    private func buildToolbar() {
        let tb = NSToolbar(identifier: "MainToolbar")
        tb.delegate = self
        tb.displayMode = .iconAndLabel
        tb.allowsUserCustomization = true
        tb.autosavesConfiguration = !UnseenWindows.isOn
        window?.toolbar = tb
        window?.toolbarStyle = .expanded
    }

    // MARK: Archive loading

    func open(_ path: String) {
        archivePath = path
        password = nil
        reload()
    }

    func reload() {
        guard let path = archivePath else { return }
        guard let info = Ops.listInteractive(archive: path, password: &password) else {
            // could not be opened: leave the window empty
            if self.info == nil { archivePath = nil }
            updateStatus()
            return
        }
        self.info = info
        root = Node.buildTree(info.entries)
        root.sortRecursively(key: sortKey, ascending: sortAscending)
        applyFilter()
        window?.title = (path as NSString).lastPathComponent
        window?.subtitle = AppInfo.abbreviate((path as NSString).deletingLastPathComponent)
        window?.representedURL = URL(fileURLWithPath: path)
        outline.reloadData()
        if root.children.count == 1, let only = root.children.first, only.isDir {
            outline.expandItem(only)
        }
        updateStatus()
        // A test run leaves the user's Open Recent as it was
        if !UnseenWindows.isOn { NSDocumentController.shared.noteNewRecentDocumentURL(URL(fileURLWithPath: path)) }
    }

    func applyFilter() {
        if filterText.isEmpty {
            filtered = nil
        } else {
            var all: [Node] = []
            root.flatten(into: &all)
            filtered = all.filter { Self.matches($0.path, filterText) }
                .sorted { Node.compare($0, $1, key: sortKey, ascending: sortAscending) }
        }
        outline.reloadData()
        updateStatus()
    }

    /// Whether `path` holds `text` whatever the case, by the default rules or by Turkish ones, in any language and
    /// region: "istanbul" finds "İstanbul", and "I" finds "ılık" as well as "IRMAK".
    static func matches(_ path: String, _ text: String) -> Bool {
        path.range(of: text, options: .caseInsensitive) != nil
            || path.range(of: text, options: .caseInsensitive, locale: turkish) != nil
    }

    private static let turkish = Locale(identifier: "tr")

    func updateStatus() {
        emptyView.isHidden = info != nil
        guard let info else {
            statusLabel.stringValue = loc.t("status_no_archive")
            return
        }
        var parts: [String] = []
        let sel = selectedNodes()
        if !sel.isEmpty {
            let size = Self.outermost(sel).reduce(0) { $0 + $1.totalSize }
            parts.append(loc.t("status_selection", sel.count, Fmt.size(size)))
        } else if let f = filtered {
            parts.append(loc.t("status_matches", f.count))
        } else {
            parts.append(loc.t("status_summary", info.fileCount, Fmt.size(info.totalSize), Fmt.size(info.totalPacked)))
        }
        var det = info.details
        if info.headersEncrypted, !det.contains("encrypted headers") { det += ", encrypted headers" }
        det = det.replacingOccurrences(of: "encrypted headers", with: loc.t("status_flag_encrypted_headers"))
            .replacingOccurrences(of: "solid", with: loc.t("status_flag_solid"))
            .replacingOccurrences(of: "volume", with: loc.t("status_flag_volume"))
        if info.hasEncryptedFiles && !info.headersEncrypted { det += loc.t("status_flag_encrypted_files") }
        parts.append(det)
        statusLabel.stringValue = parts.joined(separator: "   •   ")
    }

    // MARK: Selection helpers

    func selectedNodes() -> [Node] {
        outline.selectedRowIndexes.compactMap { outline.item(atRow: $0) as? Node }
    }

    /// The nodes no other one of `nodes` holds: a file inside a selected folder is in the folder already.
    static func outermost(_ nodes: [Node]) -> [Node] {
        let dirs = nodes.filter { $0.isDir }.map { $0.path + "/" }
        return nodes.filter { node in !dirs.contains { node.path.hasPrefix($0) } }
    }

    static func paths(for nodes: [Node]) -> [String] { outermost(nodes).map { $0.path } }

    /// Where 7-Zip writes `node` when it extracts it into `folder`: its name without empty, "." and ".." parts, which
    /// 7-Zip takes out. Joined as it was, a name such as "dir/../../x.txt" pointed outside the folder, at a local file
    /// that opening, Quick Look and a drag then took for the archive's item.
    static func extracted(_ node: Node, in folder: String) -> String {
        let parts = node.path.split(separator: "/").map(String.init).filter { $0 != "." && $0 != ".." }
        return (folder as NSString).appendingPathComponent(parts.joined(separator: "/"))
    }

    // MARK: Quick Look

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self; panel.delegate = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }

    // MARK: Search

    @objc func searchChanged(_ sender: NSSearchField) {
        filterText = sender.stringValue.trimmingCharacters(in: .whitespaces)
        applyFilter()
    }

    // MARK: Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        canPerformCommand(of: item)
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeMain(_ notification: Notification) {
        comeToFront()
    }

    func windowWillClose(_ notification: Notification) {
        AppDelegate.shared.windowClosed(self)
    }
}
