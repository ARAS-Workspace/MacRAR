import AppKit
import UniformTypeIdentifiers

/// Drops onto the window, and drags out of it to Finder as file promises extracted when Finder asks.
extension ArchiveWindowController {
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
        // Onto an open archive, a drop with anything but archives in it goes in whole: the archives among the items
        // are added too, not left out without a word
        if info != nil, paths.contains(where: { !AppDelegate.isArchive($0) }) {
            DispatchQueue.main.async { [weak self] in self?.addItems(paths) }
            return
        }
        // Archives alone open in windows of their own, a volume set once, from its first volume; other items dropped
        // onto the empty window are compressed
        let picked = VolumeSets.firstVolumes(paths)
        for archive in picked where AppDelegate.isArchive(archive) {
            AppDelegate.shared.openArchive(archive, reuse: info == nil ? self : nil)
        }
        let others = picked.filter { !AppDelegate.isArchive($0) }
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
    /// Whether `folder` holds `item`, at any depth.
    static func holds(_ folder: Node, _ item: Node) -> Bool { folder.isDir && item.path.hasPrefix(folder.path + "/") }

    /// Puts `node`, extracted into `tmp`, at `url`. An item already there is replaced, kept with the new one beside it
    /// under a new name, or left alone, as `answer` says. A folder dragged with an item inside it, and that item, are
    /// copied: moved, either would leave the other short, whichever Finder asks for first. The rest is moved, and what
    /// is left goes with the temporary folder.
    static func putInPlace(_ node: Node, of nodes: [Node], from tmp: String, at url: URL, answer: Dialogs.OverwriteMode) throws {
        let src = URL(fileURLWithPath: extracted(node, in: tmp))
        var target = url
        if FileManager.default.fileExists(atPath: url.path) {
            switch answer {
            case .overwrite: try FileManager.default.removeItem(at: url)
            case .rename: target = URL(fileURLWithPath: uniquePath(url.path))
            case .skip, .cancel: return
            }
        }
        if nodes.contains(where: { holds($0, node) || holds(node, $0) }) {
            try FileManager.default.copyItem(at: src, to: target)
        } else {
            try FileManager.default.moveItem(at: src, to: target)
        }
    }

    /// The drag's questions, asked once for all its items with its first promise: whether to extract them to
    /// `destination`, and, when some are there already, what to do with those. Whether to go on.
    private func askAboutDrag(_ nodes: [Node], to destination: URL, from info: ArchiveInfo) -> Bool {
        if dragDecision == nil {
            let list = nodes.prefix(6).map { $0.name }.joined(separator: ", ") + (nodes.count > 6 ? " …" : "")
            let destName = destination.lastPathComponent
            let title = nodes.count == 1
                ? loc.t("drag_extract_confirm_single", nodes[0].name, destName)
                : loc.t("drag_extract_confirm_multiple", nodes.count, destName)
            dragDecision = Dialogs.confirm(
                title,
                loc.t("drag_extract_details", (info.path as NSString).lastPathComponent, AppInfo.abbreviate(destination.path), list),
                okTitle: loc.t("extract"))
            if dragDecision == true {
                var seen = Set<String>()
                let there = nodes.map(\.name).filter {
                    seen.insert($0).inserted && FileManager.default.fileExists(atPath: destination.appendingPathComponent($0).path)
                }
                dragOverwrite = there.isEmpty ? .overwrite : Dialogs.askOverwrite(existing: there, dest: destination.path)
            }
        }
        return dragDecision == true && dragOverwrite != .cancel
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        (filePromiseProvider.userInfo as? Node)?.name ?? "file"
    }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { promiseQueue }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void
    ) {
        guard let node = filePromiseProvider.userInfo as? Node else { completionHandler(nil); return }
        let sem = DispatchSemaphore(value: 0)
        var error: Error?

        // The window's state is read on the main thread alone: this runs on the promise queue
        DispatchQueue.main.async { [self] in
            guard let info else { sem.signal(); return }
            let nodes = dragNodes.isEmpty ? [node] : dragNodes
            let destFolder = url.deletingLastPathComponent()

            guard askAboutDrag(nodes, to: destFolder, from: info) else { error = CocoaError(.userCancelled); sem.signal(); return }

            func moveIntoPlace() {
                guard let tmp = dragTempDir else { error = CocoaError(.fileNoSuchFile); sem.signal(); return }
                do {
                    try Self.putInPlace(node, of: nodes, from: tmp, at: url, answer: dragOverwrite ?? .overwrite)
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
            let extraction = Ops.Extraction(info: info, names: Self.paths(for: nodes), dest: tmp)
            Ops.extract(extraction, password: password, host: window, quiet: true) { ok, pw in
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

extension ArchiveWindowController {
    /// Debugging, MACRAR_DEBUG_DRAG: writes the first top-level items to the destination as if dragged to Finder.
    func simulateDrag(to dest: String) {
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
                    print("drag-sim:", node.name, err.map { "error \($0)" } ?? "OK")
                    done.signal()
                }
                done.wait()
            }
        }
    }
}
