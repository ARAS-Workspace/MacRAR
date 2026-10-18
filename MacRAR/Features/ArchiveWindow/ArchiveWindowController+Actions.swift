import AppKit

/// What the window's menus, toolbar and context menu do to the archive it shows.
extension ArchiveWindowController {
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
        Ops.extract(.init(info: info, names: names, dest: dest), password: password, host: window) { [weak self] ok, pw in
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

    func addItems(_ items: [String]) {
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
        if let shared = Self.sharedName(among: selectedNodes(), in: root) {
            Dialogs.error(loc.t("delete_failed_title"), loc.t("delete_shared_name", shared))
            return
        }
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

    @objc func doubleClicked() {
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
        Ops.extract(.init(info: info, names: [node.path], dest: tmp), password: password, host: window, quiet: true) { [weak self] ok, pw in
            self?.password = pw ?? self?.password
            guard ok else { return }
            let target = Self.extracted(node, in: tmp)
            NSWorkspace.shared.open(URL(fileURLWithPath: target))
        }
    }

    // MARK: View actions

    @objc func expandAll(_ sender: Any?) { outline.expandItem(nil, expandChildren: true) }
    @objc func collapseAll(_ sender: Any?) { outline.collapseItem(nil, collapseChildren: true) }
    @objc func refresh(_ sender: Any?) { reload() }
    @objc func revealArchive(_ sender: Any?) { if let archivePath { Ops.revealInFinder(archivePath) } }

    /// The path of a selected file that is also a folder's path in `root`, the folder not selected with it: 7-Zip
    /// deletes by name, and the file's name takes the folder and everything in it too. nil when there is none.
    static func sharedName(among nodes: [Node], in root: Node) -> String? {
        var all: [Node] = []
        root.flatten(into: &all)
        let folders = Set(all.filter(\.isDir).map(\.path))
        let chosenFolders = Set(nodes.filter(\.isDir).map(\.path))
        return nodes.first { !$0.isDir && folders.contains($0.path) && !chosenFolders.contains($0.path) }?.path
    }

    /// Archive paths of the selected nodes (folders that already cover their children are collapsed)
    private func selectedPaths() -> [String] { Self.paths(for: selectedNodes()) }
}
