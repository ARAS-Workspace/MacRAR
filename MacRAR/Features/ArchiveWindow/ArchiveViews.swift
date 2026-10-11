import AppKit

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
