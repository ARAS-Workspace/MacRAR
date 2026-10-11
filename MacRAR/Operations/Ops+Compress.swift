import AppKit

/// Creating archives from compress options, the Create Archive dialog's or a Quick Action's defaults: 7-Zip in the app, or
/// the user's rar.
extension Ops {
    static func compress(items: [String], options: CompressOptions, host: NSWindow?, completion: @escaping (Bool, String) -> Void) {
        var options = options
        // A self-extracting RAR is written as name.sfx: the checks below and the reported path are about that file
        options.archivePath = options.writtenPath
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
        runSteps(steps, index: 0, archive: options.archivePath, host: host, completion: completion)
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
        let alert = NSAlert()
        alert.messageText = loc.t("compress_exists_title", name(existingSet))
        guard options.format.supportsAppend, !setExists else {
            alert.informativeText = loc.t(setExists ? "compress_exists_split_message" : "compress_exists_no_append_message")
            alert.addButton(withTitle: loc.t("compress_create_new"))
            alert.addButton(withTitle: loc.t("cancel"))
            return Dialogs.ask(alert) == .alertFirstButtonReturn ? .write(uniquePath(path, taken: isTaken)) : .cancel
        }
        let encrypted = isEncrypted(path)
        alert.informativeText = loc.t(encrypted ? "compress_exists_encrypted_message" : "compress_exists_message")
        alert.addButton(withTitle: loc.t("compress_create_new"))
        alert.addButton(withTitle: loc.t(encrypted ? "compress_add_to_encrypted" : "compress_add_to_existing"))
        alert.addButton(withTitle: loc.t("cancel"))
        switch Dialogs.ask(alert) {
        case .alertFirstButtonReturn:
            return .write(uniquePath(path, taken: isTaken))
        case .alertSecondButtonReturn:
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

    /// Runs the steps one after another in the archive's folder, where rar writes its temporary archive.
    private static func runSteps(_ steps: [CompressOptions.Step], index: Int, archive: String, host: NSWindow?,
                                 completion: @escaping (Bool, String) -> Void) {
        let cwd = (archive as NSString).deletingLastPathComponent
        guard index < steps.count else { completion(true, firstVolume(of: archive)); return }
        let step = steps[index]
        let suffix = steps.count > 1 ? " (\(index + 1)/\(steps.count))" : ""
        let title = "\(step.title): \(name(archive))\(suffix)"
        let next: (RarResult) -> Void = { result in
            step.cleanup?()
            if result.cancelled {
                steps[(index + 1)...].forEach { $0.cleanup?() }
                completion(false, archive); return
            }
            if !result.ok {
                steps[(index + 1)...].forEach { $0.cleanup?() }
                Dialogs.error(loc.t("compress_failed_title"), result.errorSummary, details: result.output)
                completion(false, archive)
                return
            }
            runSteps(steps, index: index + 1, archive: archive, host: host, completion: completion)
        }
        switch step.work {
        case .rar(let args, let password): runRar(title: title, args: args, password: password, cwd: cwd, host: host, completion: next)
        case .sevenZip(let operation): runJob(title: title, operation: operation, host: host, completion: next)
        }
    }
}
