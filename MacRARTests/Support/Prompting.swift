import XCTest
@testable import MacRAR

/// The screen as the tests see it: a question, report, panel or page that gets this far is recorded and cancelled,
/// never shown.
final class UnseenScreen: Prompter {
    enum Prompt: Equatable {
        case ask(Question)
        case report(Report)
        case password(archiveName: String, wrong: Bool)
        case overwrite(existing: [String], dest: String)
        case choose(Panel)
        case open(URL)
    }

    private(set) var reached: [Prompt] = []

    /// The button that changes nothing: Later for the update alert, which would otherwise skip the version, and the
    /// last one elsewhere (Cancel, Not Now, or OK alone).
    func ask(_ question: Question) -> Answer {
        reached.append(.ask(question))
        return Answer(button: question.topic == .update ? 1 : max(question.buttons.count - 1, 0))
    }

    func report(_ report: Report) { reached.append(.report(report)) }

    func askPassword(archiveName: String, wrong: Bool) -> String? {
        reached.append(.password(archiveName: archiveName, wrong: wrong))
        return nil
    }

    func askOverwrite(existing: [String], dest: String) -> Dialogs.OverwriteMode {
        reached.append(.overwrite(existing: existing, dest: dest))
        return .cancel
    }

    func choose(_ panel: Panel) -> [URL] {
        reached.append(.choose(panel))
        return []
    }

    func openInBrowser(_ page: URL) { reached.append(.open(page)) }
}

extension XCTestCase {
    /// Runs `body` with `prompter` asking the app's questions, then puts back the one that did.
    func withPrompter(_ prompter: any Prompter, _ body: () throws -> Void) rethrows {
        let earlier = Dialogs.prompter
        Dialogs.prompter = prompter
        defer { Dialogs.prompter = earlier }
        try body()
    }

    /// What reaches the screen while `body` runs, past the debug answers: an unseen screen stands in for the alerts and
    /// panels, so that a question no variable answers fails the test instead of coming up.
    func reachingTheScreen(_ body: () throws -> Void) rethrows -> [UnseenScreen.Prompt] {
        let screen = UnseenScreen()
        try withPrompter(DebugPrompter(base: screen), body)
        return screen.reached
    }
}
