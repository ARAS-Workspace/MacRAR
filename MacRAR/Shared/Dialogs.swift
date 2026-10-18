import AppKit

/// The app's questions and reports, asked through Dialogs.prompter, and when the questions it asks on its own come up.
enum Dialogs {
    /// What asks: the debug answers in front of the alerts and panels on screen.
    static var prompter: any Prompter = DebugPrompter(base: AppKitPrompter())

    static func activate() { NSApp.activate(ignoringOtherApps: true) }

    /// Whether something already waits for the user: a modal window (a password question, the Create Archive dialog,
    /// an alert), a sheet, or an operation, its progress window up or not yet, or an extraction carrying the archive's
    /// quarantine over once its window has gone.
    static var isBusy: Bool {
        NSApp.modalWindow != nil || ProgressPanel.running > 0 || Ops.carryingQuarantine > 0
            || NSApp.windows.contains { $0.isVisible && $0.attachedSheet != nil }
    }

    /// Blocks waiting in whenIdle.
    private(set) static var waiting = 0

    /// Runs `block` once nothing waits for the user (isBusy), looking again every 1.5 s. The questions the app asks on
    /// its own as it starts, the file associations and the update alert, wait here instead of coming up over another
    /// one. (Taken from MacRAR 1.4.3, which did not count an operation's progress.)
    static func whenIdle(_ block: @escaping () -> Void) {
        guard isBusy else { block(); return }
        waiting += 1
        func check() {
            guard !isBusy else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: check)
                return
            }
            waiting -= 1
            block()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: check)
    }

    /// Opens a page in the browser; with MACRAR_DEBUG_CONFIRM its address goes to stdout instead.
    static func openInBrowser(_ page: URL) {
        prompter.openInBrowser(page)
    }

    static func askPassword(archiveName: String, wrong: Bool = false) -> String? {
        prompter.askPassword(archiveName: archiveName, wrong: wrong)
    }

    enum OverwriteMode { case overwrite, rename, skip, cancel }

    static func askOverwrite(existing: [String], dest: String) -> OverwriteMode {
        prompter.askOverwrite(existing: existing, dest: dest)
    }

    static func error(_ title: String, _ detail: String, details: String? = nil) {
        prompter.report(Report(kind: .error, title: title, detail: detail, details: details))
    }

    static func info(_ title: String, _ detail: String) {
        prompter.report(Report(kind: .info, title: title, detail: detail))
    }

    /// Shows a question and returns the answer; with MACRAR_DEBUG_CONFIRM the question goes to stdout and DebugPrompter
    /// answers it by its topic.
    static func ask(_ question: Question) -> Answer {
        prompter.ask(question)
    }

    static func confirm(_ title: String, _ detail: String, okTitle: String = loc.t("ok"), destructive: Bool = false) -> Bool {
        var question = Question(topic: .confirmation)
        question.title = title
        question.message = detail
        question.style = destructive ? .warning : .informational
        question.buttons.append(okTitle)
        question.buttons.append(loc.t("cancel"))
        question.destructive = destructive
        return prompter.ask(question).button == 0
    }

    /// The files or folder chosen in an open or save panel; none when it is cancelled.
    static func choose(_ panel: Panel) -> [URL] {
        prompter.choose(panel)
    }

    static func chooseFolder(title: String, prompt: String, initial: String? = nil) -> String? {
        var panel = Panel()
        panel.title = title
        panel.message = title
        panel.prompt = prompt
        panel.folders = true
        panel.files = false
        panel.createFolders = true
        panel.multiple = false
        if let initial { panel.directory = URL(fileURLWithPath: initial) }
        return prompter.choose(panel).first?.path
    }

    static func chooseFiles(title: String, prompt: String, archivesOnly: Bool) -> [String] {
        var panel = Panel()
        panel.title = title
        panel.message = title
        panel.prompt = prompt
        panel.folders = !archivesOnly
        panel.files = true
        panel.multiple = true
        panel.archivesOnly = archivesOnly
        return prompter.choose(panel).map { $0.path }
    }
}
