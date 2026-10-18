import AppKit

/// Creating archives from compress options, the Create Archive dialog's or a Quick Action's defaults: 7-Zip in the app, or
/// the user's rar.
extension Ops {
    static func compress(items: [String], options: CompressOptions, host: NSWindow?, completion: @escaping (Bool, String) -> Void) {
        var options = options
        // A self-extracting RAR is written as name.sfx: the checks below and the reported path are about that file
        options.archivePath = options.writtenPath
        if options.format.isRar, let part = rarPattern(in: items) {
            Dialogs.error(loc.t("compress_failed_title"), loc.t("rar_wildcard_compress", part))
            completion(false, options.archivePath); return
        }
        if options.format.isRar, !RarTools.ensureAvailable() { completion(false, options.archivePath); return }
        if let problem = passwordProblem(options.password, format: options.format) {
            Dialogs.error(loc.t("compress_failed_title"), problem)
            completion(false, options.archivePath); return
        }
        if !options.format.isRar, options.format.supportsVolumes, options.volumeBytes == nil {
            Dialogs.error(loc.t("compress_failed_title"), loc.t("compress_invalid_volume_size", options.volumeSize ?? ""))
            completion(false, options.archivePath); return
        }
        switch answerToExisting(options) {
        case .write(let path):
            options.archivePath = path
        case .add(let existing, let password):
            add(info: existing, items: items, password: password, host: host) { ok, _ in completion(ok, options.archivePath) }
            return
        case .cancel:
            completion(false, options.archivePath); return
        }
        let steps = options.buildSteps(items: items)
        runSteps(steps, index: 0, archive: options.archivePath, host: host) { ok, path, warnings in
            if ok, options.deleteAfter { moveSourcesToTrash(items, archive: path, password: options.password, warnings: warnings) }
            completion(ok, path)
        }
    }

    /// "Move source files to the Trash after archiving": once the archive is written without a warning and reads back,
    /// the chosen items go to the Trash, where they can be put back; a link among them goes itself, never what it points
    /// to. rar's -df and 7-Zip's -sdel deleted for good, followed links into folders nobody chose and deleted what was
    /// there, and for a compressed tar deleted the items before the archive was written. The sources stay, and the user
    /// is told why, when the engine left something out with a warning (a file it could not read) or the archive was
    /// saved inside one of them.
    private static func moveSourcesToTrash(_ items: [String], archive: String, password: String?, warnings: [String]) {
        let kept = loc.t("compress_sources_kept_title")
        if !warnings.isEmpty {
            Dialogs.error(kept, loc.t("compress_sources_kept_warnings", warnings.joined(separator: "\n")))
            return
        }
        if let holder = folder(holding: archive, among: items) {
            Dialogs.error(kept, loc.t("compress_sources_kept_inside", name(holder)))
            return
        }
        guard case .ok = ArchiveReader.list(archive, password: password.flatMap { $0.isEmpty ? nil : $0 }) else {
            Dialogs.error(kept, loc.t("compress_sources_kept"))
            return
        }
        let failed = items.filter { item in (try? moveToTrash(URL(fileURLWithPath: item))) == nil }
        if !failed.isEmpty {
            let names = failed.map { name($0) }.joined(separator: ", ")
            Dialogs.error(loc.t("compress_trash_failed_title"), loc.t("compress_trash_failed", names))
        }
    }

    /// A test run (MACRAR_DEBUG_UNSEEN) leaves the user's Trash alone: what it would trash goes to this folder.
    static let testTrash = (NSTemporaryDirectory() as NSString).appendingPathComponent("MacRARTests-Trash-\(getpid())")

    /// Moves `item` to the Trash, or to `testTrash` in a test run.
    static func moveToTrash(_ item: URL) throws {
        guard UnseenWindows.isOn else { try FileManager.default.trashItem(at: item, resultingItemURL: nil); return }
        try FileManager.default.createDirectory(atPath: testTrash, withIntermediateDirectories: true)
        let target = uniquePath((testTrash as NSString).appendingPathComponent(item.lastPathComponent))
        try FileManager.default.moveItem(at: item, to: URL(fileURLWithPath: target))
    }

    /// What to do about an archive already under the new archive's name.
    private enum Existing {
        /// Write the new archive at this path: the one asked for, or a free name beside it
        case write(String)
        /// Add the items to the existing archive instead, opened with this password
        case add(ArchiveInfo, String?)
        case cancel
    }

    /// Asks what to do when the new archive's name is taken. A split set under the name counts as there when the new
    /// archive is split as well: rar would write over its first volumes and leave the rest behind, and 7-Zip cannot
    /// update a split set.
    private static func answerToExisting(_ options: CompressOptions) -> Existing {
        let path = options.archivePath
        let existingSet = options.isSplit ? firstVolume(of: path) : path
        let setExists = existingSet != path
        guard FileManager.default.fileExists(atPath: path) || setExists else { return .write(path) }
        var question = Question(topic: .question, title: loc.t("compress_exists_title", name(existingSet)))
        guard options.format.supportsAppend, !setExists else {
            question.message = loc.t(setExists ? "compress_exists_split_message" : "compress_exists_no_append_message")
            question.buttons.append(loc.t("compress_create_new"))
            question.buttons.append(loc.t("cancel"))
            return Dialogs.ask(question).button == 0 ? .write(uniquePath(path, taken: isTaken)) : .cancel
        }
        let encrypted = isEncrypted(path)
        question.message = loc.t(encrypted ? "compress_exists_encrypted_message" : "compress_exists_message")
        question.buttons.append(loc.t("compress_create_new"))
        question.buttons.append(loc.t(encrypted ? "compress_add_to_encrypted" : "compress_add_to_existing"))
        question.buttons.append(loc.t("cancel"))
        switch Dialogs.ask(question).button {
        case 0:
            return .write(uniquePath(path, taken: isTaken))
        case 1:
            // An encrypted archive is opened first, which asks for its password; any other is written into as it is
            guard encrypted else { return .write(path) }
            var password: String?
            guard let existing = listInteractive(archive: path, password: &password) else { return .cancel }
            return .add(existing, password)
        default:
            return .cancel
        }
    }

    /// Whether the archive at `path` has encrypted files, as far as it lists without a password.
    private static func isEncrypted(_ path: String) -> Bool {
        switch ArchiveReader.list(path, password: nil) {
        case .ok(let listing): return listing.hasEncryptedFiles
        case .wrongPassword: return true
        case .error: return false
        }
    }

    /// The file a finished compression wrote under the archive's name, which the callers reveal in Finder and open. A
    /// split archive has none: rar writes name.part1.rar (part01, part001… as the count grows, and the first one is
    /// .sfx when self-extracting), 7-Zip name.7z.001 or name.zip.001. Their first volume stands in.
    static func firstVolume(of archive: String) -> String {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: archive) else { return archive }
        let ns = archive as NSString
        let rarVolumes = (0..<4).map { "\(ns.deletingPathExtension).part\(String(repeating: "0", count: $0))1.\(ns.pathExtension)" }
        return ([archive + ".001"] + rarVolumes).first { fm.fileExists(atPath: $0) } ?? archive
    }

    /// A name is taken by a file or by a split set under it.
    static func isTaken(_ path: String) -> Bool { firstVolume(of: path) != path || FileManager.default.fileExists(atPath: path) }

    /// Runs the steps one after another in the archive's folder, where rar writes its temporary archive. The completion
    /// gets the warnings of the steps that finished with one, each step adding its own.
    private static func runSteps(_ steps: [CompressOptions.Step], index: Int, archive: String, host: NSWindow?,
                                 completion: @escaping (Bool, String, [String]) -> Void) {
        let cwd = (archive as NSString).deletingLastPathComponent
        guard index < steps.count else { completion(true, firstVolume(of: archive), []); return }
        let step = steps[index]
        let suffix = steps.count > 1 ? " (\(index + 1)/\(steps.count))" : ""
        let title = "\(step.title): \(name(archive))\(suffix)"
        let next: (RarResult) -> Void = { result in
            step.cleanup?()
            if result.cancelled {
                steps[(index + 1)...].forEach { $0.cleanup?() }
                completion(false, archive, []); return
            }
            if !result.ok {
                steps[(index + 1)...].forEach { $0.cleanup?() }
                Dialogs.error(loc.t("compress_failed_title"), result.errorSummary, details: result.output)
                completion(false, archive, [])
                return
            }
            let warning = result.code == 0 ? nil : result.errorSummary
            runSteps(steps, index: index + 1, archive: archive, host: host) { ok, path, warnings in
                completion(ok, path, (warning.map { [$0] } ?? []) + warnings)
            }
        }
        switch step.work {
        case .rar(let args, let password): runRar(title: title, args: args, password: password, cwd: cwd, host: host, completion: next)
        case .sevenZip(let operation): runJob(title: title, operation: operation, host: host, completion: next)
        }
    }
}
