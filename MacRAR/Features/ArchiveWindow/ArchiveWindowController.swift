import AppKit
import Quartz

final class ArchiveWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private(set) var archivePath: String?
    private(set) var info: ArchiveInfo?
    var password: String?
    var root = Node(name: "", path: "", isDir: true)
    var filtered: [Node]?
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

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        window.title = AppInfo.name
        window.minSize = NSSize(width: 560, height: 300)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ArchiveWindow")
        super.init(window: window)
        window.delegate = self
        buildUI()
        buildToolbar()
        applyLanguage()
        window.center()
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageDidChange), name: LocalizationManager.didChange, object: loc)
    }
    required init?(coder: NSCoder) { fatalError() }

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
        outline.autosaveName = "ArchiveOutline"
        outline.autosaveTableColumns = true
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
        let m = NSMenu()
        m.addItem(withTitle: loc.t("open"), action: #selector(openSelected), keyEquivalent: "")
        m.addItem(withTitle: loc.t("action_quick_look"), action: #selector(quickLook(_:)), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: loc.t("action_extract_selected_here"), action: #selector(extractSelectedHere), keyEquivalent: "")
        m.addItem(withTitle: loc.t("action_extract_selected_to"), action: #selector(extractSelectedTo), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: loc.t("action_delete_from_archive"), action: #selector(deleteSelected), keyEquivalent: "")
        return m
    }

    // MARK: Toolbar

    enum ToolbarItemID {
        static let open = NSToolbarItem.Identifier("open")
        static let newArchive = NSToolbarItem.Identifier("new")
        static let extractTo = NSToolbarItem.Identifier("extractTo")
        static let extractHere = NSToolbarItem.Identifier("extractHere")
        static let extractFolder = NSToolbarItem.Identifier("extractFolder")
        static let test = NSToolbarItem.Identifier("test")
        static let add = NSToolbarItem.Identifier("add")
        static let delete = NSToolbarItem.Identifier("delete")
        static let info = NSToolbarItem.Identifier("info")
        static let search = NSToolbarItem.Identifier("search")
    }

    private func buildToolbar() {
        let tb = NSToolbar(identifier: "MainToolbar")
        tb.delegate = self
        tb.displayMode = .iconAndLabel
        tb.allowsUserCustomization = true
        tb.autosavesConfiguration = true
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
        if ProcessInfo.processInfo.environment["MACRAR_DEBUG_EXPAND"] != nil {
            outline.expandItem(nil, expandChildren: true)
        }
        if let sort = ProcessInfo.processInfo.environment["MACRAR_DEBUG_SORT"] {   // e.g. size:desc
            let parts = sort.split(separator: ":")
            outline.sortDescriptors = [NSSortDescriptor(key: String(parts[0]), ascending: parts.count < 2 || parts[1] != "desc")]
        }
        if let size = ProcessInfo.processInfo.environment["MACRAR_DEBUG_WINDOW"] {
            let parts = size.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { window?.setContentSize(NSSize(width: parts[0], height: parts[1])) }
        }
        updateStatus()
        NSDocumentController.shared.noteNewRecentDocumentURL(URL(fileURLWithPath: path))
        if let dest = ProcessInfo.processInfo.environment["MACRAR_DEBUG_DRAG"] { simulateDrag(to: dest) }
    }

    /// Debugging: writes the first top-level items to the destination as if dragged to Finder
    private func simulateDrag(to dest: String) {
        let nodes = Array(root.children.prefix(2))
        guard !nodes.isEmpty else { return }
        outlineView(outline, draggingSession: NSDraggingSession(), willBeginAt: .zero, forItems: nodes)
        for node in nodes {
            let provider = NSFilePromiseProvider(fileType: "public.data", delegate: self)
            provider.userInfo = node
            let url = URL(fileURLWithPath: (dest as NSString).appendingPathComponent(node.name))
            promiseQueue.addOperation { [self] in
                let done = DispatchSemaphore(value: 0)
                filePromiseProvider(provider, writePromiseTo: url) { err in
                    print("drag-sim:", node.name, err.map { "HATA \($0)" } ?? "OK")
                    done.signal()
                }
                done.wait()
            }
        }
    }

    func applyFilter() {
        if filterText.isEmpty {
            filtered = nil
        } else {
            var all: [Node] = []
            root.flatten(into: &all)
            filtered = all.filter { $0.path.localizedCaseInsensitiveContains(filterText) }
                .sorted { Node.compare($0, $1, key: sortKey, ascending: sortAscending) }
        }
        outline.reloadData()
        updateStatus()
    }

    func updateStatus() {
        emptyView.isHidden = info != nil
        guard let info else {
            statusLabel.stringValue = loc.t("status_no_archive")
            return
        }
        var parts: [String] = []
        let sel = selectedNodes()
        if !sel.isEmpty {
            let size = sel.reduce(0) { $0 + $1.totalSize }
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
            .replacingOccurrences(of: "recovery record", with: loc.t("status_flag_recovery_record"))
            .replacingOccurrences(of: "volume", with: loc.t("status_flag_volume"))
            .replacingOccurrences(of: "lock", with: loc.t("status_flag_locked"))
        if info.hasEncryptedFiles && !info.headersEncrypted { det += loc.t("status_flag_encrypted_files") }
        parts.append(det)
        statusLabel.stringValue = parts.joined(separator: "   •   ")
    }

    // MARK: Selection helpers

    func selectedNodes() -> [Node] {
        outline.selectedRowIndexes.compactMap { outline.item(atRow: $0) as? Node }
    }

    /// Archive paths of the selected nodes (folders that already cover their children are collapsed)
    func selectedPaths() -> [String] { Self.paths(for: selectedNodes()) }

    static func paths(for nodes: [Node]) -> [String] {
        let dirs = nodes.filter { $0.isDir }.map { $0.path + "/" }
        return nodes.filter { node in !dirs.contains { node.path.hasPrefix($0) } }.map { $0.path }
    }

    // MARK: Quick Look

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self; panel.delegate = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }

    @objc func searchChanged(_ sender: NSSearchField) {
        filterText = sender.stringValue.trimmingCharacters(in: .whitespaces)
        applyFilter()
    }

    @objc func selectAllItems(_ sender: Any?) {
        outline.selectAll(nil)
    }

    // MARK: Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        validate(item.action)
    }

    func validate(_ action: Selector?) -> Bool {
        guard let action else { return false }
        switch action {
        case #selector(openArchive), #selector(newArchive):
            return true
        case #selector(extractHere), #selector(extractToFolder), #selector(extractTo), #selector(testArchive), #selector(showInfo):
            return info != nil
        case #selector(addFiles):
            return info == nil || info?.supportsModification == true
        case #selector(deleteSelected):
            return info?.supportsModification == true && !outline.selectedRowIndexes.isEmpty
        case #selector(extractSelectedHere), #selector(extractSelectedTo), #selector(openSelected):
            return info != nil && !outline.selectedRowIndexes.isEmpty
        case #selector(quickLook(_:)):
            return info != nil && selectedNodes().contains { !$0.isDir }
        case #selector(expandAll(_:)), #selector(collapseAll(_:)), #selector(refresh(_:)), #selector(revealArchive(_:)):
            return info != nil
        default:
            return true
        }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        AppDelegate.shared.windowClosed(self)
    }
}
