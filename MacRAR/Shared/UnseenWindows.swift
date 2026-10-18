import AppKit

/// MACRAR_DEBUG_UNSEEN, which the scheme's test action and launchApp set: every window the app builds is fully
/// transparent and lets clicks through, so a test run shows nothing, the archives it opens stay out of Open Recent,
/// and what it would move to the Trash goes to a temporary folder of its own (Ops.testTrash). Such a window still counts as up for the app: it is visible, takes sheets, keeps Dialogs.isBusy and is
/// drawn by MACRAR_SNAPSHOT.
enum UnseenWindows {
    static var isOn: Bool { ProcessInfo.processInfo.environment["MACRAR_DEBUG_UNSEEN"] != nil }

    /// Called where a window is built, before it can go on screen.
    @MainActor static func apply(to window: NSWindow?) {
        guard isOn, let window else { return }
        window.alphaValue = 0
        window.ignoresMouseEvents = true
    }
}
