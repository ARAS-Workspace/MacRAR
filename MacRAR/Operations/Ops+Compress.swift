import AppKit

/// Creating archives from the Create Archive dialog's choices: 7-Zip in the app, or the user's rar.
extension Ops {
    // swiftlint:disable:next function_body_length
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
        // A split set under this name counts as there when the new archive is split as well: rar would write over its
        // first volumes and leave the rest behind, and 7-Zip cannot update a split set
        let existingSet = options.isSplit ? firstVolume(of: options.archivePath) : options.archivePath
        let setExists = existingSet != options.archivePath
        if FileManager.default.fileExists(atPath: options.archivePath) || setExists {
            let alert = NSAlert()
            alert.messageText = loc.t("compress_exists_title", name(existingSet))
            if options.format.supportsAppend, !setExists {
                // Is the existing archive encrypted? (try listing without a password)
                var existingEncrypted = false
                switch ArchiveReader.list(options.archivePath, password: nil) {
                case .ok(let ex): existingEncrypted = ex.hasEncryptedFiles
                case .wrongPassword: existingEncrypted = true
                case .error: break
                }
                if existingEncrypted {
                    alert.informativeText = loc.t("compress_exists_encrypted_message")
                    alert.addButton(withTitle: loc.t("compress_create_new"))
                    alert.addButton(withTitle: loc.t("compress_add_to_encrypted"))
                    alert.addButton(withTitle: loc.t("cancel"))
                    switch Dialogs.ask(alert) {
                    case .alertFirstButtonReturn:
                        options.archivePath = uniquePath(options.archivePath, taken: isTaken)
                    case .alertSecondButtonReturn:
                        var pw: String?
                        guard let existing = listInteractive(archive: options.archivePath, password: &pw) else {
                            completion(false, options.archivePath); return
                        }
                        add(info: existing, items: items, password: pw, host: host) { ok, _ in completion(ok, options.archivePath) }
                        return
                    default:
                        completion(false, options.archivePath); return
                    }
                } else {
                    alert.informativeText = loc.t("compress_exists_message")
                    alert.addButton(withTitle: loc.t("compress_create_new"))
                    alert.addButton(withTitle: loc.t("compress_add_to_existing"))
                    alert.addButton(withTitle: loc.t("cancel"))
                    switch Dialogs.ask(alert) {
                    case .alertFirstButtonReturn: options.archivePath = uniquePath(options.archivePath, taken: isTaken)
                    case .alertSecondButtonReturn: break
                    default: completion(false, options.archivePath); return
                    }
                }
            } else {
                alert.informativeText = loc.t(setExists ? "compress_exists_split_message" : "compress_exists_no_append_message")
                alert.addButton(withTitle: loc.t("compress_create_new"))
                alert.addButton(withTitle: loc.t("cancel"))
                if Dialogs.ask(alert) == .alertFirstButtonReturn {
                    options.archivePath = uniquePath(options.archivePath, taken: isTaken)
                } else {
                    completion(false, options.archivePath); return
                }
            }
        }
        let cwd = (options.archivePath as NSString).deletingLastPathComponent
        let steps = options.buildSteps(items: items)
        runSteps(steps, index: 0, archive: options.archivePath, cwd: cwd, host: host, completion: completion)
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

    // swiftlint:disable:next function_parameter_count
    private static func runSteps(_ steps: [CompressOptions.Step], index: Int, archive: String, cwd: String,
                                 host: NSWindow?, completion: @escaping (Bool, String) -> Void) {
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
            runSteps(steps, index: index + 1, archive: archive, cwd: cwd, host: host, completion: completion)
        }
        switch step.work {
        case .rar(let args, let password): runRar(title: title, args: args, password: password, cwd: cwd, host: host, completion: next)
        case .sevenZip(let operation): runJob(title: title, operation: operation, host: host, completion: next)
        }
    }
}
