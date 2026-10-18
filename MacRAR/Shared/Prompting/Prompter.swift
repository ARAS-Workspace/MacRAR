import Foundation

/// What asks the user, and tells them: the questions, reports, panels and pages the app shows. Dialogs.prompter is
/// DebugPrompter in front of AppKitPrompter, so the debug variables answer before anything comes up on screen.
protocol Prompter {
    func ask(_ question: Question) -> Answer
    func report(_ report: Report)
    func askPassword(archiveName: String, wrong: Bool) -> String?
    func askOverwrite(existing: [String], dest: String) -> Dialogs.OverwriteMode
    /// The files or folder chosen; none when the panel is cancelled.
    func choose(_ panel: Panel) -> [URL]
    func openInBrowser(_ page: URL)
}
