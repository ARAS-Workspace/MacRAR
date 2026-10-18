import AppKit

/// What the user asks of the app from the menu bar, the archive window's toolbar and its context menu: one case per
/// command, whichever of them shows it. Menu items carry the command as their represented object and all send
/// `performCommand(_:)`; whoever answers says whether it can run now (`canPerform`) and runs it (`perform`).
enum Command: String, CaseIterable {
    // The app's: the app delegate answers them, whichever window is in front.
    case showAbout, checkForUpdates, showSettings, showAssociations, installQuickActions, openHelp, openReleaseNotes
    // The window's: the archive window in front answers them; with none in front they are disabled.
    case openArchive, newArchive
    case extractHere, extractToFolder, extractTo, extractSelectedHere, extractSelectedTo
    case testArchive, showInfo, addFiles, deleteSelected
    case openSelected, quickLook, expandAll, collapseAll, refresh, revealArchive

    /// Who answers a command.
    enum Scope {
        /// The app delegate, sent to it directly.
        case app
        /// The window in front, found up the responder chain.
        case window
    }

    var scope: Scope {
        switch self {
        case .showAbout, .checkForUpdates, .showSettings, .showAssociations, .installQuickActions, .openHelp, .openReleaseNotes:
            return .app
        case .openArchive, .newArchive, .extractHere, .extractToFolder, .extractTo, .extractSelectedHere, .extractSelectedTo,
             .testArchive, .showInfo, .addFiles, .deleteSelected, .openSelected, .quickLook, .expandAll, .collapseAll, .refresh,
             .revealArchive:
            return .window
        }
    }

    /// The command a menu item carries; nil for an item that is not one (Open Recent's files, AppKit's own items).
    init?(sender: Any?) {
        guard let command = (sender as? NSMenuItem)?.representedObject as? Command else { return nil }
        self = command
    }
}

/// The action AppKit sends for every command, by the one selector `Selector.performCommand`.
@objc protocol CommandAction {
    func performCommand(_ sender: Any?)
}

/// What answers commands: the app delegate the app's, the archive window's controller the window's.
protocol CommandResponder: CommandAction {
    /// Whether `command` can run now; its menu item and toolbar button are disabled otherwise.
    func canPerform(_ command: Command) -> Bool
    func perform(_ command: Command)
    /// The command `sender` carries: a menu item's represented object, unless the responder knows other senders.
    func command(for sender: Any?) -> Command?
}

extension CommandResponder {
    func command(for sender: Any?) -> Command? { Command(sender: sender) }

    /// What `performCommand(_:)` does: runs the command the sender carries, when it can run now. AppKit asks first and
    /// does not send a disabled item's action, so this only keeps a command sent some other way from running.
    func performCommand(from sender: Any?) {
        guard let command = command(for: sender), canPerform(command) else { return }
        perform(command)
    }

    /// What `validateMenuItem(_:)` and `validateToolbarItem(_:)` answer: whether the sender's command can run now. An
    /// item that carries no command keeps the answer it had before commands: enabled when it has an action.
    func canPerformCommand(of sender: NSValidatedUserInterfaceItem) -> Bool {
        guard let command = command(for: sender) else { return sender.action != nil }
        return canPerform(command)
    }
}

extension Selector {
    /// The one action of every command. Not `perform(_:)`: `#selector` reads that name as NSObject's `performSelector:`,
    /// and an item sending it crashes the app.
    static let performCommand = #selector(CommandAction.performCommand(_:))
}

extension NSMenuItem {
    /// An item that runs `command`: the app's are sent to `appTarget`, the window's up the responder chain.
    convenience init(_ command: Command, title: String, keyEquivalent: String = "", appTarget: AnyObject?) {
        self.init(title: title, action: .performCommand, keyEquivalent: keyEquivalent)
        representedObject = command
        target = command.scope == .app ? appTarget : nil
    }
}
