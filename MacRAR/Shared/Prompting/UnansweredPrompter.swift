import Foundation

/// What stands behind the debug answers in a test run (MACRAR_DEBUG_UNSEEN) instead of AppKitPrompter: a question no
/// debug variable answers is printed as "unanswered <title>" and given the answer that changes nothing (Later for the
/// update alert, the last button elsewhere, no password, Cancel, no file), so a test run never waits at a real alert
/// or panel, whichever test asked.
struct UnansweredPrompter: Prompter {
    func ask(_ question: Question) -> Answer {
        print("unanswered \(question.title)")
        return Answer(button: question.topic == .update ? 1 : max(question.buttons.count - 1, 0))
    }

    func report(_ report: Report) { print("unanswered \(report.title): \(report.detail)") }

    func askPassword(archiveName: String, wrong: Bool) -> String? {
        print("unanswered password for \(archiveName)")
        return nil
    }

    func askOverwrite(existing: [String], dest: String) -> Dialogs.OverwriteMode {
        print("unanswered overwrite \(existing.sorted())")
        return .cancel
    }

    func choose(_ panel: Panel) -> [URL] {
        print("unanswered \(panel.title)")
        return []
    }

    func openInBrowser(_ page: URL) { print("unanswered open \(page.absoluteString)") }
}
