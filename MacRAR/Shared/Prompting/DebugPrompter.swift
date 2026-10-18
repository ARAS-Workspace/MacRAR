import Foundation

/// The one place the debug variables answer the app's questions, in front of the prompter that shows them, so that
/// the tests and the copies of the app they start never wait at an alert. The environment is read at each question,
/// since the tests change it as they run.
/// - MACRAR_DEBUG_CONFIRM: a report goes to stdout instead of an alert, and so does a page the app would open in the
///   browser. A question goes there too and is answered with its first button, a confirmation without being printed,
///   the file associations Not Now, and the update alert as MACRAR_DEBUG_UPDATE says: download, skip or, by default,
///   later.
/// - MACRAR_DEBUG_PASSWORD answers the first password question, MACRAR_DEBUG_PASSWORD_RETRY the one after a wrong
///   password; "__cancel__" cancels.
/// - MACRAR_DEBUG_OVERWRITE=overwrite|rename|skip|cancel answers the overwrite question.
/// - MACRAR_DEBUG_CONFIRM: an open or save panel prints its title as "choose <title>", and MACRAR_DEBUG_CHOOSE answers
///   it with a path; without it, the panel is cancelled.
/// - MACRAR_DEBUG_CONFIRM: the RAR tool's questions print, and are cancelled unless MACRAR_DEBUG_RARTOOL says: choose,
///   the tool already downloaded, or download, its page (printed), then the tool once downloaded.
struct DebugPrompter: Prompter {
    let base: any Prompter
    var environment: () -> [String: String] = { ProcessInfo.processInfo.environment }

    func ask(_ question: Question) -> Answer {
        let variables = environment()
        guard variables["MACRAR_DEBUG_CONFIRM"] != nil else { return base.ask(question) }
        switch question.topic {
        case .confirmation:
            return Answer(button: 0)
        case .question:
            print("\(question.title): \(question.message)")
            return Answer(button: 0)
        case .associations:
            // Not Now, leaving the user's associations as they are
            print("\(question.title): \(question.message)")
            return Answer(button: 1)
        case .update:
            print("\(question.title): \(question.message)")
            switch variables["MACRAR_DEBUG_UPDATE"] {
            case "download": return Answer(button: 0)
            case "skip": return Answer(button: 2)
            default: return Answer(button: 1)
            }
        case .rarToolMissing:
            print("\(question.title): \(question.message)")
            switch variables["MACRAR_DEBUG_RARTOOL"] {
            case "choose": return Answer(button: 0)
            case "download": return Answer(button: 1)
            default: return Answer(button: 2)
            }
        case .rarToolDownloading:
            print("\(question.title): \(question.message)")
            return Answer(button: 0)
        }
    }

    func report(_ report: Report) {
        guard environment()["MACRAR_DEBUG_CONFIRM"] != nil else { return base.report(report) }
        print("\(report.title): \(report.detail)")
    }

    func askPassword(archiveName: String, wrong: Bool) -> String? {
        if let answer = environment()[wrong ? "MACRAR_DEBUG_PASSWORD_RETRY" : "MACRAR_DEBUG_PASSWORD"] {
            return answer == "__cancel__" ? nil : answer
        }
        return base.askPassword(archiveName: archiveName, wrong: wrong)
    }

    func askOverwrite(existing: [String], dest: String) -> Dialogs.OverwriteMode {
        switch environment()["MACRAR_DEBUG_OVERWRITE"] {
        case "overwrite": return .overwrite
        case "rename": return .rename
        case "skip": return .skip
        case "cancel": return .cancel
        default: return base.askOverwrite(existing: existing, dest: dest)
        }
    }

    func choose(_ panel: Panel) -> [URL] {
        let variables = environment()
        guard variables["MACRAR_DEBUG_CONFIRM"] != nil else { return base.choose(panel) }
        print("choose \(panel.title)")
        return variables["MACRAR_DEBUG_CHOOSE"].map { [URL(fileURLWithPath: $0)] } ?? []
    }

    func openInBrowser(_ page: URL) {
        guard environment()["MACRAR_DEBUG_CONFIRM"] != nil else { return base.openInBrowser(page) }
        print("open \(page.absoluteString)")
    }
}
