import AppKit

/// The archive window answers the window's commands, from the menu bar, its toolbar and its context menu alike.
extension ArchiveWindowController: CommandResponder {
    @objc func performCommand(_ sender: Any?) { performCommand(from: sender) }

    /// A menu item carries its command; a toolbar button is known by the identifier the toolbar saves.
    func command(for sender: Any?) -> Command? {
        Command(sender: sender) ?? (sender as? NSToolbarItem).flatMap { Self.toolbarButtons[$0.itemIdentifier]?.command }
    }

    func canPerform(_ command: Command) -> Bool {
        switch command {
        case .openArchive, .newArchive:
            return true
        case .extractHere, .extractToFolder, .extractTo, .testArchive, .showInfo:
            return info != nil
        case .addFiles:
            return info == nil || info?.supportsModification == true
        case .deleteSelected:
            return info?.supportsModification == true && !outline.selectedRowIndexes.isEmpty
        case .extractSelectedHere, .extractSelectedTo, .openSelected:
            return info != nil && !outline.selectedRowIndexes.isEmpty
        case .quickLook:
            return info != nil && selectedNodes().contains { !$0.isDir }
        case .expandAll, .collapseAll, .refresh, .revealArchive:
            return info != nil
        case .showAbout, .checkForUpdates, .showSettings, .showAssociations, .installQuickActions, .openHelp, .openReleaseNotes:
            // The app's, sent to the app delegate
            return false
        }
    }

    func perform(_ command: Command) {
        switch command {
        case .openArchive: openArchive(nil)
        case .newArchive: newArchive(nil)
        case .extractHere: extractHere(nil)
        case .extractToFolder: extractToFolder(nil)
        case .extractTo: extractTo(nil)
        case .extractSelectedHere: extractSelectedHere(nil)
        case .extractSelectedTo: extractSelectedTo(nil)
        case .testArchive: testArchive(nil)
        case .showInfo: showInfo(nil)
        case .addFiles: addFiles(nil)
        case .deleteSelected: deleteSelected(nil)
        case .openSelected: openSelected(nil)
        case .quickLook: quickLook(nil)
        case .expandAll: expandAll(nil)
        case .collapseAll: collapseAll(nil)
        case .refresh: refresh(nil)
        case .revealArchive: revealArchive(nil)
        case .showAbout, .checkForUpdates, .showSettings, .showAssociations, .installQuickActions, .openHelp, .openReleaseNotes:
            break
        }
    }
}
