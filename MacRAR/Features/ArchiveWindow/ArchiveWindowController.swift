import AppKit
import Quartz
import UniformTypeIdentifiers

// swiftlint:disable file_length

// MARK: - Keyboard-aware outline view

final class ArchiveOutlineView: NSOutlineView {
    var onReturn: (() -> Void)?
    var onSpace: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.numericPad)
        if mods.isEmpty, let ch = event.charactersIgnoringModifiers?.unicodeScalars.first {
            if ch == "\r" || ch == "\u{3}" { onReturn?(); return }
            if ch == " " { onSpace?(); return }
        }
        super.keyDown(with: event)
    }
}

/// Empty window: label + buttons; files can be dropped onto it
final class EmptyStateView: NSView {
    var onDrop: (([URL]) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

// MARK: - Tree node

final class Node: NSObject {
    let name: String
    let path: String
    let isDir: Bool
    var entry: ArchiveEntry?
    var children: [Node] = []
    weak var parent: Node?

    init(name: String, path: String, isDir: Bool) {
        self.name = name; self.path = path; self.isDir = isDir
    }

    var totalSize: Int64 {
        if !isDir { return entry?.size ?? 0 }
        return children.reduce(0) { $0 + $1.totalSize }
    }
    var totalPacked: Int64 {
        if !isDir { return entry?.packedSize ?? 0 }
        return children.reduce(0) { $0 + $1.totalPacked }
    }
    var containsEncrypted: Bool {
        if !isDir { return entry?.encrypted ?? false }
        return children.contains { $0.containsEncrypted }
    }

    func sortRecursively(key: String = "name", ascending: Bool = true) {
        children.sort { Node.compare($0, $1, key: key, ascending: ascending) }
        children.forEach { $0.sortRecursively(key: key, ascending: ascending) }
    }

    /// Folders always first; then by the selected column
    static func compare(_ lhs: Node, _ rhs: Node, key: String, ascending: Bool) -> Bool {
        if lhs.isDir != rhs.isDir { return lhs.isDir }
        var result: ComparisonResult
        func cmp<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
            left < right ? .orderedAscending : (left == right ? .orderedSame : .orderedDescending)
        }
        switch key {
        case "size": result = cmp(lhs.totalSize, rhs.totalSize)
        case "packed": result = cmp(lhs.totalPacked, rhs.totalPacked)
        case "date": result = (lhs.entry?.mtime ?? "").compare(rhs.entry?.mtime ?? "")
        case "ratio":
            let ra = lhs.totalSize > 0 ? Double(lhs.totalPacked) / Double(lhs.totalSize) : 0
            let rb = rhs.totalSize > 0 ? Double(rhs.totalPacked) / Double(rhs.totalSize) : 0
            result = cmp(ra, rb)
        default: result = lhs.name.localizedStandardCompare(rhs.name)
        }
        if result == .orderedSame { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }

    static func buildTree(_ entries: [ArchiveEntry]) -> Node {
        let root = Node(name: "", path: "", isDir: true)
        var map: [String: Node] = ["": root]
        func ensure(_ path: String) -> Node {
            if let existing = map[path] { return existing }
            let parentPath = (path as NSString).deletingLastPathComponent
            let parent = ensure(parentPath)
            let node = Node(name: (path as NSString).lastPathComponent, path: path, isDir: true)
            node.parent = parent
            parent.children.append(node)
            map[path] = node
            return node
        }
        for entry in entries {
            let clean = entry.name.hasSuffix("/") ? String(entry.name.dropLast()) : entry.name
            if entry.isDirectory {
                ensure(clean).entry = entry
            } else {
                let parent = ensure((clean as NSString).deletingLastPathComponent)
                let node = Node(name: (clean as NSString).lastPathComponent, path: clean, isDir: false)
                node.entry = entry
                node.parent = parent
                parent.children.append(node)
                map[clean] = node
            }
        }
        root.sortRecursively()
        return root
    }

    func flatten(into out: inout [Node]) {
        for child in children {
            out.append(child)
            child.flatten(into: &out)
        }
    }
}

// MARK: - Window

// swiftlint:disable:next type_body_length
final class ArchiveWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private(set) var archivePath: String?
    private(set) var info: ArchiveInfo?
    private var password: String?
    private var root = Node(name: "", path: "", isDir: true)
    private var filtered: [Node]?
    private var filterText = ""

    private let outline = ArchiveOutlineView()
    private let scroll = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var openButton = NSButton(title: "", target: self, action: #selector(openArchive(_:)))
    private lazy var newButton = NSButton(title: "", target: self, action: #selector(newArchive(_:)))
    private let emptyView = EmptyStateView()
    private var sortKey = "name"
    private var sortAscending = true
    private var previewURLs: [URL] = []
    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; return queue
    }()
    // Drag-to-Finder session (the question is asked once, the items are extracted in one go)
    private var dragNodes: [Node] = []
    private var dragDecision: Bool?
    private var dragTempDir: String?
    private var dragExtracted = false
    private var dragExtractOK = false
    private var dragPending = 0

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

    // swiftlint:disable:next function_body_length
    private func buildUI() {
        guard let window, let content = window.contentView else { return }

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

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

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

    private enum ToolbarItemID {
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

    private func reload() {
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

    private func applyFilter() {
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

    private func updateStatus() {
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

    private func selectedNodes() -> [Node] {
        outline.selectedRowIndexes.compactMap { outline.item(atRow: $0) as? Node }
    }

    /// Archive paths of the selected nodes (folders that already cover their children are collapsed)
    private func selectedPaths() -> [String] { Self.paths(for: selectedNodes()) }

    private static func paths(for nodes: [Node]) -> [String] {
        let dirs = nodes.filter { $0.isDir }.map { $0.path + "/" }
        return nodes.filter { node in !dirs.contains { node.path.hasPrefix($0) } }.map { $0.path }
    }

    // MARK: Actions

    @objc func openArchive(_ sender: Any?) {
        let files = Dialogs.chooseFiles(title: loc.t("panel_open_archive_title"), prompt: loc.t("open"), archivesOnly: true)
        for f in files { AppDelegate.shared.openArchive(f, reuse: self.info == nil ? self : nil) }
    }

    @objc func newArchive(_ sender: Any?) {
        let items = Dialogs.chooseFiles(title: loc.t("panel_compress_message"), prompt: loc.t("choose"), archivesOnly: false)
        guard !items.isEmpty else { return }
        AppDelegate.shared.compressWithDialog(items: items, host: window) { [weak self] path in
            guard let self, let path else { return }
            AppDelegate.shared.openArchive(path, reuse: self.info == nil ? self : nil)
        }
    }

    @objc func extractHere(_ sender: Any?) {
        guard let info else { return }
        let dest = (info.path as NSString).deletingLastPathComponent
        doExtract(names: nil, dest: dest)
    }

    @objc func extractToFolder(_ sender: Any?) {
        guard let info else { return }
        doExtract(names: nil, dest: Ops.folderNamedAfterArchive(info.path))
    }

    @objc func extractTo(_ sender: Any?) {
        guard let info else { return }
        guard let dest = Dialogs.chooseFolder(title: loc.t("panel_extract_destination"), prompt: loc.t("extract"),
                                              initial: (info.path as NSString).deletingLastPathComponent) else { return }
        doExtract(names: nil, dest: dest)
    }

    @objc func extractSelectedHere(_ sender: Any?) {
        guard let info else { return }
        let names = selectedPaths()
        guard !names.isEmpty else { return }
        doExtract(names: names, dest: (info.path as NSString).deletingLastPathComponent)
    }

    @objc func extractSelectedTo(_ sender: Any?) {
        guard let info else { return }
        let names = selectedPaths()
        guard !names.isEmpty else { return }
        guard let dest = Dialogs.chooseFolder(title: loc.t("panel_extract_selected_destination"), prompt: loc.t("extract"),
                                              initial: (info.path as NSString).deletingLastPathComponent) else { return }
        doExtract(names: names, dest: dest)
    }

    private func doExtract(names: [String]?, dest: String) {
        guard let info else { return }
        Ops.extract(info: info, names: names, dest: dest, password: password, host: window) { [weak self] ok, pw in
            self?.password = pw ?? self?.password
            if ok { Ops.revealExtracted(info: info, names: names, dest: dest) }
        }
    }

    @objc func testArchive(_ sender: Any?) {
        guard let info else { return }
        Ops.test(info: info, password: password, host: window) { [weak self] _, pw in
            self?.password = pw ?? self?.password
        }
    }

    @objc func addFiles(_ sender: Any?) {
        guard info != nil else { newArchive(sender); return }
        let items = Dialogs.chooseFiles(title: loc.t("panel_add_files_message"), prompt: loc.t("add"), archivesOnly: false)
        guard !items.isEmpty else { return }
        addItems(items)
    }

    private func addItems(_ items: [String]) {
        guard let info else { return }
        Ops.add(info: info, items: items, password: password, host: window) { [weak self] ok, pw in
            guard let self else { return }
            self.password = pw ?? self.password
            if ok { self.reload() }
        }
    }

    @objc func deleteSelected(_ sender: Any?) {
        guard let info else { return }
        let names = selectedPaths()
        guard !names.isEmpty else { return }
        let list = names.prefix(5).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ") + (names.count > 5 ? " …" : "")
        guard
            Dialogs.confirm(
                loc.t("delete_confirm_title", names.count), list + loc.t("delete_confirm_irreversible"), okTitle: loc.t("delete"),
                destructive: true)
        else { return }
        Ops.delete(info: info, names: names, password: password, host: window) { [weak self] ok, pw in
            guard let self else { return }
            self.password = pw ?? self.password
            if ok { self.reload() }
        }
    }

    @objc func showInfo(_ sender: Any?) {
        guard let info else { return }
        let attrs = (try? FileManager.default.attributesOfItem(atPath: info.path)) ?? [:]
        let fileSize = (attrs[.size] as? Int64) ?? 0
        let text = loc.t("archive_info_details",
                      info.path, Fmt.size(fileSize), info.details, info.fileCount, info.entries.count - info.fileCount,
                      Fmt.size(info.totalSize), Fmt.size(info.totalPacked), info.hasEncryptedFiles ? loc.t("yes") : loc.t("no"))
        Dialogs.info((info.path as NSString).lastPathComponent, text)
    }

    @objc func openSelected(_ sender: Any?) {
        for node in selectedNodes() { openNode(node) }
    }

    @objc private func doubleClicked() {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? Node else { return }
        if node.isDir {
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
        } else {
            openNode(node)
        }
    }

    private func openNode(_ node: Node) {
        guard let info else { return }
        let tmp = TempDirs.make("open")
        Ops.extract(info: info, names: [node.path], dest: tmp, password: password, host: window, quiet: true) { [weak self] ok, pw in
            self?.password = pw ?? self?.password
            guard ok else { return }
            let target = (tmp as NSString).appendingPathComponent(node.path)
            NSWorkspace.shared.open(URL(fileURLWithPath: target))
        }
    }

    // MARK: View actions

    @objc func expandAll(_ sender: Any?) { outline.expandItem(nil, expandChildren: true) }
    @objc func collapseAll(_ sender: Any?) { outline.collapseItem(nil, collapseChildren: true) }
    @objc func refresh(_ sender: Any?) { reload() }
    @objc func revealArchive(_ sender: Any?) { if let archivePath { Ops.revealInFinder(archivePath) } }

    // MARK: Quick Look

    @objc func quickLook(_ sender: Any?) {
        if let panel = QLPreviewPanel.shared(), panel.isVisible { panel.orderOut(nil); return }
        prepareQuickLook { QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil) }
    }

    private func prepareQuickLook(completion: @escaping () -> Void) {
        guard let info else { return }
        let files = selectedNodes().filter { !$0.isDir }
        guard !files.isEmpty else { return }
        let tmp = TempDirs.make("ql")
        Ops.extract(
            info: info, names: files.map { $0.path }, dest: tmp, password: password, host: window, quiet: true
        ) { [weak self] ok, pw in
            guard let self else { return }
            self.password = pw ?? self.password
            guard ok else { return }
            self.previewURLs = files.map { URL(fileURLWithPath: (tmp as NSString).appendingPathComponent($0.path)) }
            completion()
        }
    }

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

    private func validate(_ action: Selector?) -> Bool {
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

// MARK: - Toolbar delegate

extension ArchiveWindowController: NSToolbarDelegate, NSToolbarItemValidation {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemID.open, ToolbarItemID.newArchive, .space, ToolbarItemID.extractTo, ToolbarItemID.extractHere,
            ToolbarItemID.extractFolder, .space, ToolbarItemID.test, ToolbarItemID.add, ToolbarItemID.delete, ToolbarItemID.info,
            .flexibleSpace, ToolbarItemID.search,
        ]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.flexibleSpace, .space]
    }
    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if id == ToolbarItemID.search {
            let s = NSSearchToolbarItem(itemIdentifier: id)
            localize(s)
            s.searchField.target = self
            s.searchField.action = #selector(searchChanged(_:))
            s.searchField.sendsSearchStringImmediately = true
            s.searchField.sendsWholeSearchString = false
            return s
        }
        let buttons: [NSToolbarItem.Identifier: (symbol: String, action: Selector)] = [
            ToolbarItemID.open: ("folder", #selector(openArchive)),
            ToolbarItemID.newArchive: ("doc.zipper", #selector(newArchive)),
            ToolbarItemID.extractTo: ("square.and.arrow.down", #selector(extractTo)),
            ToolbarItemID.extractHere: ("arrow.down.doc", #selector(extractHere)),
            ToolbarItemID.extractFolder: ("folder.badge.plus", #selector(extractToFolder)),
            ToolbarItemID.test: ("checkmark.shield", #selector(testArchive)),
            ToolbarItemID.add: ("plus.rectangle.on.folder", #selector(addFiles)),
            ToolbarItemID.delete: ("trash", #selector(deleteSelected)),
            ToolbarItemID.info: ("info.circle", #selector(showInfo)),
        ]
        guard let button = buttons[id] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.image = NSImage(systemSymbolName: button.symbol, accessibilityDescription: nil)
        item.target = self
        item.action = button.action
        item.isBordered = true
        localize(item)
        return item
    }

    /// The label, tooltip and placeholder of a toolbar item in the current language.
    private func localize(_ item: NSToolbarItem) {
        if let search = item as? NSSearchToolbarItem {
            search.label = loc.t("search_label")
            search.searchField.placeholderString = loc.t("search_placeholder")
            return
        }
        let texts: [NSToolbarItem.Identifier: (label: String, tip: String)] = [
            ToolbarItemID.open: (loc.t("open"), loc.t("toolbar_open_tooltip")),
            ToolbarItemID.newArchive: (loc.t("toolbar_compress"), loc.t("toolbar_compress_tooltip")),
            ToolbarItemID.extractTo: (loc.t("toolbar_extract"), loc.t("toolbar_extract_tooltip")),
            ToolbarItemID.extractHere: (loc.t("toolbar_extract_here"), loc.t("toolbar_extract_here_tooltip")),
            ToolbarItemID.extractFolder: (loc.t("toolbar_extract_folder"), loc.t("toolbar_extract_folder_tooltip")),
            ToolbarItemID.test: (loc.t("toolbar_test"), loc.t("toolbar_test_tooltip")),
            ToolbarItemID.add: (loc.t("add"), loc.t("toolbar_add_tooltip")),
            ToolbarItemID.delete: (loc.t("delete"), loc.t("toolbar_delete_tooltip")),
            ToolbarItemID.info: (loc.t("toolbar_info"), loc.t("toolbar_info_tooltip")),
        ]
        guard let text = texts[item.itemIdentifier] else { return }
        item.label = text.label
        item.paletteLabel = text.label
        item.toolTip = text.tip
        item.image?.accessibilityDescription = text.label
    }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { validate(item.action) }
}

// MARK: - Outline data source / delegate

extension ArchiveWindowController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let f = filtered { return item == nil ? f.count : 0 }
        return ((item as? Node) ?? root).children.count
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let f = filtered { return f[index] }
        return ((item as? Node) ?? root).children[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if filtered != nil { return false }
        return (item as? Node)?.isDir ?? false
    }

    // swiftlint:disable:next function_body_length
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let col = tableColumn, let node = item as? Node else { return nil }
        let id = col.identifier
        var cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView
        if cell == nil {
            let newCell = NSTableCellView()
            newCell.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingMiddle
            tf.font = .systemFont(ofSize: 12)
            newCell.addSubview(tf)
            newCell.textField = tf
            if id == Self.nameCol {
                let iv = NSImageView()
                iv.translatesAutoresizingMaskIntoConstraints = false
                newCell.addSubview(iv)
                newCell.imageView = iv
                NSLayoutConstraint.activate([
                    iv.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 2),
                    iv.centerYAnchor.constraint(equalTo: newCell.centerYAnchor),
                    iv.widthAnchor.constraint(equalToConstant: 16),
                    iv.heightAnchor.constraint(equalToConstant: 16),
                    tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 4),
                ])
            } else {
                tf.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 4).isActive = true
                if id == Self.sizeCol || id == Self.packedCol || id == Self.ratioCol { tf.alignment = .right }
                if id == Self.lockCol { tf.alignment = .center }
                if id == Self.crcCol || id == Self.dateCol { tf.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular) }
            }
            NSLayoutConstraint.activate([
                tf.trailingAnchor.constraint(equalTo: newCell.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: newCell.centerYAnchor),
            ])
            cell = newCell
        }
        let entry = node.entry
        switch id {
        case Self.nameCol:
            cell?.textField?.stringValue = filtered != nil ? node.path : node.name
            cell?.imageView?.image = icon(for: node)
        case Self.sizeCol:
            cell?.textField?.stringValue = Fmt.size(node.totalSize)
        case Self.packedCol:
            cell?.textField?.stringValue = Fmt.size(node.totalPacked)
        case Self.ratioCol:
            cell?.textField?.stringValue = entry?.ratio ?? ""
        case Self.dateCol:
            cell?.textField?.stringValue = entry?.mtime ?? ""
        case Self.crcCol:
            cell?.textField?.stringValue = node.isDir ? "" : (entry?.crc ?? "")
        case Self.lockCol:
            cell?.textField?.stringValue = node.containsEncrypted ? "🔒" : ""
        default: break
        }
        return cell
    }

    private static var iconCache: [String: NSImage] = [:]
    private func icon(for node: Node) -> NSImage {
        if node.isDir { return NSWorkspace.shared.icon(for: .folder) }
        let ext = (node.name as NSString).pathExtension.lowercased()
        if let cached = Self.iconCache[ext] { return cached }
        let img: NSImage
        if let utType = UTType(filenameExtension: ext) {
            img = NSWorkspace.shared.icon(for: utType)
        } else {
            img = NSWorkspace.shared.icon(for: .data)
        }
        Self.iconCache[ext] = img
        return img
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        updateStatus()
        if let panel = QLPreviewPanel.shared(), panel.isVisible, panel.dataSource === self {
            prepareQuickLook { panel.reloadData() }
        }
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = outlineView.sortDescriptors.first, let key = descriptor.key else { return }
        sortKey = key
        sortAscending = descriptor.ascending
        root.sortRecursively(key: sortKey, ascending: sortAscending)
        applyFilter()
    }

    // Drag and drop: open a dropped archive file, add other files to the archive
    func outlineView(
        _ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard info.draggingSource as? NSOutlineView !== outlineView else { return [] }
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return [] }
        outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return .copy
    }
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return false }
        handleDrop(urls)
        return true
    }

    func handleDrop(_ urls: [URL]) {
        let paths = urls.map { $0.path }
        let archives = paths.filter { AppDelegate.isArchive($0) }
        let others = paths.filter { !AppDelegate.isArchive($0) }
        // Onto an open archive, a drop with anything but archives in it goes in whole: the archives among the items
        // are added too, not left out without a word
        if info != nil, !others.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.addItems(paths) }
            return
        }
        // Archives alone open in windows of their own; other items dropped onto the empty window are compressed
        for archive in archives { AppDelegate.shared.openArchive(archive, reuse: info == nil ? self : nil) }
        if !others.isEmpty {
            AppDelegate.shared.compressWithDialog(items: others, host: window) { [weak self] path in
                if let self, let path { AppDelegate.shared.openArchive(path, reuse: self) }
            }
        }
    }

    // Dragging from the archive to Finder (file promises)
    func outlineView(
        _ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
        forItems draggedItems: [Any]
    ) {
        dragNodes = draggedItems.compactMap { $0 as? Node }
        dragDecision = nil
        dragTempDir = nil
        dragExtracted = false
        dragExtractOK = false
        dragPending = dragNodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? Node else { return nil }
        let type: String
        if node.isDir {
            type = UTType.folder.identifier
        } else {
            type = UTType(filenameExtension: (node.name as NSString).pathExtension)?.identifier ?? UTType.data.identifier
        }
        let provider = NSFilePromiseProvider(fileType: type, delegate: self)
        provider.userInfo = node
        return provider
    }
}

extension ArchiveWindowController: NSFilePromiseProviderDelegate {
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        (filePromiseProvider.userInfo as? Node)?.name ?? "dosya"
    }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { promiseQueue }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void
    ) {
        guard let node = filePromiseProvider.userInfo as? Node, let info else { completionHandler(nil); return }
        let sem = DispatchSemaphore(value: 0)
        var error: Error?

        DispatchQueue.main.async { [self] in
            let nodes = dragNodes.isEmpty ? [node] : dragNodes
            let destFolder = url.deletingLastPathComponent()

            // Ask once per session
            if dragDecision == nil {
                let list = nodes.prefix(6).map { $0.name }.joined(separator: ", ") + (nodes.count > 6 ? " …" : "")
                let destName = destFolder.lastPathComponent
                let title = nodes.count == 1
                    ? loc.t("drag_extract_confirm_single", nodes[0].name, destName)
                    : loc.t("drag_extract_confirm_multiple", nodes.count, destName)
                dragDecision = Dialogs.confirm(
                    title,
                    loc.t("drag_extract_details", (info.path as NSString).lastPathComponent, AppInfo.abbreviate(destFolder.path), list),
                    okTitle: loc.t("extract"))
            }
            guard dragDecision == true else { error = CocoaError(.userCancelled); sem.signal(); return }

            func moveIntoPlace() {
                guard let tmp = dragTempDir else { error = CocoaError(.fileNoSuchFile); sem.signal(); return }
                do {
                    let src = URL(fileURLWithPath: (tmp as NSString).appendingPathComponent(node.path))
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                    try FileManager.default.moveItem(at: src, to: url)
                } catch let failure { error = failure }
                sem.signal()
            }

            if dragExtracted {
                if dragExtractOK { moveIntoPlace() } else { error = CocoaError(.userCancelled); sem.signal() }
                return
            }

            // First item: extract all dragged items to a temporary folder in one go
            let tmp = TempDirs.make("drag")
            dragTempDir = tmp
            dragExtracted = true
            Ops.extract(info: info, names: Self.paths(for: nodes), dest: tmp, password: password, host: window, quiet: true) { ok, pw in
                self.password = pw ?? self.password
                self.dragExtractOK = ok
                if ok { moveIntoPlace() } else { error = CocoaError(.userCancelled); sem.signal() }
            }
        }

        sem.wait()
        // Clean up the temporary folder once the last promise is fulfilled
        dragPending -= 1
        if dragPending <= 0, let tmp = dragTempDir {
            try? FileManager.default.removeItem(atPath: tmp)
            DispatchQueue.main.async { self.dragTempDir = nil }
        }
        completionHandler(error)
    }
}

// MARK: - Quick Look data source

extension ArchiveWindowController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { previewURLs[index] as NSURL }
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // Forward arrow keys to the list (Finder behaviour)
        if event.type == .keyDown, let ch = event.charactersIgnoringModifiers?.unicodeScalars.first,
           ch == UnicodeScalar(NSUpArrowFunctionKey) || ch == UnicodeScalar(NSDownArrowFunctionKey) {
            outline.keyDown(with: event)
            return true
        }
        return false
    }
}
