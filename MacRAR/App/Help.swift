import AppKit

/// The Help menu: the README in the app's language and the changelog, on this distribution's repository, the one
/// place it is published from.
extension AppDelegate {
    enum HelpPage {
        case readme
        case changelog
    }

    static let repository = URL(string: "https://github.com/\(UpdateChecker.repo)")!

    static func helpPage(_ page: HelpPage, language: LocalizationManager.Language) -> URL {
        switch page {
        case .readme:
            return repository.appendingPathComponent(language == .tr ? "blob/main/README_TR.md" : "blob/main/README.md")
        case .changelog:
            return repository.appendingPathComponent("blob/main/CHANGELOG")
        }
    }

    @objc func openHelp(_ sender: Any?) { Dialogs.openInBrowser(Self.helpPage(.readme, language: loc.current)) }

    @objc func openReleaseNotes(_ sender: Any?) { Dialogs.openInBrowser(Self.helpPage(.changelog, language: loc.current)) }
}
