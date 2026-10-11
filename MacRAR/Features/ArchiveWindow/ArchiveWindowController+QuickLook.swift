import AppKit
import Quartz

extension ArchiveWindowController {
    @objc func quickLook(_ sender: Any?) {
        if let panel = QLPreviewPanel.shared(), panel.isVisible { panel.orderOut(nil); return }
        prepareQuickLook { QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil) }
    }

    func prepareQuickLook(completion: @escaping () -> Void) {
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
}

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
