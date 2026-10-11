import AppKit
import Quartz
import UniformTypeIdentifiers

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
}
