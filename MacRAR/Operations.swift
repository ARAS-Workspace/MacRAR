import AppKit

/// All archive operations: used both from the window and from the Finder Quick Actions.
enum Ops {

    // MARK: Shared job runners (with progress window)

    /// An operation of the 7-Zip library.
    static func runJob(title: String, operation: SevenZipBridge.Operation, host: NSWindow?,
                       completion: @escaping (RarResult) -> Void) {
        let panel = ProgressPanel(title: title)
        let job = SevenZipBridge.Job()
        job.onItem = { panel.setFile($0) }
        job.onProgress = { panel.setFraction($0) }
        panel.onCancel = { job.cancel() }
        panel.show(on: host)
        job.start(operation) { outcome in
            panel.dismiss()
            completion(RarResult(outcome))
        }
    }

    /// The user's RAR tool.
    static func runRar(title: String, args: [String], password: String? = nil, cwd: String? = nil, host: NSWindow?,
                       completion: @escaping (RarResult) -> Void) {
        let panel = ProgressPanel(title: title)
        let job = RarJob()
        job.onEvent = { event in
            switch event {
            case .file(let name): panel.setFile(name)
            // rar's percentage is the overall progress of the archive
            case .progress(let pct): panel.setFraction(Double(pct) / 100.0)
            }
        }
        panel.onCancel = { job.cancel() }
        panel.show(on: host)
        job.start(args, cwd: cwd, password: password) { result in
            panel.dismiss()
            completion(result)
        }
    }

    private static func name(_ path: String) -> String { (path as NSString).lastPathComponent }

    // MARK: Passwords

    /// The password as earlier versions handed it to rar and 7zz, decomposed, the way Process passes arguments: an
    /// archive they locked with a password holding letters such as ü or ş opens only with those bytes. Nil when the
    /// password has no such letter or already is that form. (Swift compares strings by meaning, so the scalars decide.)
    static func decomposedForm(of password: String?) -> String? {
        guard let password else { return nil }
        let decomposed = password.decomposedStringWithCanonicalMapping
        return decomposed.unicodeScalars.elementsEqual(password.unicodeScalars) ? nil : decomposed
    }

    /// What to try once `password` is refused: its decomposed form first, then what the user enters. Nil on cancel.
    private static func password(after password: String?, archive: String) -> String? {
        decomposedForm(of: password) ?? Dialogs.askPassword(archiveName: name(archive), wrong: true)
    }

    /// 7-Zip writes ZIP only with a password of printable ASCII, space to DEL; any other letter, such as ü or ş, made it
    /// fail with "E_INVALIDARG", so that is explained before anything is written.
    static func zipTakes(password: String?) -> Bool {
        password?.unicodeScalars.allSatisfy { (0x20..<0x80).contains($0.value) } ?? true
    }

    // MARK: Listing (with password loop)

    /// Lists the archive; asks for a password if needed. Returns nil on cancel.
    static func listInteractive(archive: String, password: inout String?) -> ArchiveInfo? {
        var wrong = false
        while true {
            switch ArchiveReader.list(archive, password: password) {
            case .ok(let info):
                return info
            case .wrongPassword:
                if let decomposed = decomposedForm(of: password) {
                    password = decomposed
                    continue
                }
                guard let pw = Dialogs.askPassword(archiveName: name(archive), wrong: wrong) else { return nil }
                password = pw
                wrong = true
            case .error(let result):
                if result.notArchive {
                    Dialogs.error(loc.t("open_failed_title"), loc.t("open_failed_unsupported", name(archive)))
                } else {
                    Dialogs.error(loc.t("open_failed_title"), result.errorSummary, details: result.output)
                }
                return nil
            }
        }
    }

    // MARK: Extraction

    /// Are any of the items to extract encrypted? (names nil → whole archive)
    static func needsPassword(info: ArchiveInfo, names: [String]?) -> Bool {
        if info.headersEncrypted { return true }
        guard let names else { return info.hasEncryptedFiles }
        return info.entries.contains { entry in
            entry.encrypted && names.contains { selected in entry.name == selected || entry.name.hasPrefix(selected + "/") }
        }
    }

    // swiftlint:disable function_parameter_count
    /// names: nil means the whole archive. completion(success, password used)
    static func extract(info: ArchiveInfo, names: [String]?, dest: String, password: String?,
                        host: NSWindow?, quiet: Bool = false, completion: @escaping (Bool, String?) -> Void) {
        var pw = password
        if needsPassword(info: info, names: names), pw == nil {
            guard let entered = Dialogs.askPassword(archiveName: name(info.path)) else { completion(false, nil); return }
            pw = entered
        }
        // Overwrite check
        let tops = topLevelNames(info: info, names: names)
        let existing = tops.filter { FileManager.default.fileExists(atPath: (dest as NSString).appendingPathComponent($0)) }
        var mode: SevenZipBridge.Overwrite = .overwrite
        if !existing.isEmpty {
            switch Dialogs.askOverwrite(existing: existing, dest: dest) {
            case .overwrite: mode = .overwrite
            case .rename: mode = .rename
            case .skip: mode = .skip
            case .cancel: completion(false, pw); return
            }
        }
        runExtract(info: info, names: names, dest: dest, password: pw, mode: mode, host: host, quiet: quiet, completion: completion)
    }
    // swiftlint:enable function_parameter_count

    // swiftlint:disable:next function_parameter_count
    private static func runExtract(info: ArchiveInfo, names: [String]?, dest: String, password: String?,
                                   mode: SevenZipBridge.Overwrite,
                                   host: NSWindow?, quiet: Bool, completion: @escaping (Bool, String?) -> Void) {
        let operation = SevenZipBridge.Operation.extract(archive: info.path, destination: dest, items: names, overwrite: mode,
                                                         password: password)
        let quarantine = Quarantine.value(of: info.path)
        let started = Date()
        func finish(_ result: RarResult) {
            if result.cancelled { completion(false, password); return }
            if result.wrongPassword {
                guard let pw = Ops.password(after: password, archive: info.path) else { completion(false, password); return }
                runExtract(info: info, names: names, dest: dest, password: pw, mode: mode, host: host, quiet: quiet, completion: completion)
                return
            }
            if !result.ok {
                Dialogs.error(loc.t("extract_failed_title"), result.errorSummary, details: result.output)
                completion(false, password)
                return
            }
            if result.code == 1, !quiet {
                Dialogs.info(loc.t("extract_warnings_title"), result.errorSummary)
            }
            completion(true, password)
        }
        runJob(title: loc.t("progress_extracting", name(info.path)), operation: operation, host: host) { result in
            // Every item written, including by an interrupted extraction, gets the archive's quarantine (before the result is handled or anything is opened)
            guard let quarantine else { finish(result); return }
            let tops = topLevelNames(info: info, names: names)
            DispatchQueue.global(qos: .userInitiated).async {
                Quarantine.apply(quarantine, dest: dest, tops: tops, since: started)
                DispatchQueue.main.async { finish(result) }
            }
        }
    }

    // MARK: Test

    static func test(info: ArchiveInfo, password: String?, host: NSWindow?, completion: @escaping (Bool, String?) -> Void) {
        var pw = password
        if info.hasEncryptedFiles, pw == nil {
            guard let entered = Dialogs.askPassword(archiveName: name(info.path)) else { completion(false, nil); return }
            pw = entered
        }
        runTest(info: info, password: pw, host: host, completion: completion)
    }

    private static func runTest(info: ArchiveInfo, password: String?, host: NSWindow?, completion: @escaping (Bool, String?) -> Void) {
        let operation = SevenZipBridge.Operation.test(archive: info.path, password: password)
        runJob(title: loc.t("progress_testing", name(info.path)), operation: operation, host: host) { result in
            if result.cancelled { completion(false, password); return }
            if result.wrongPassword {
                guard let pw = Ops.password(after: password, archive: info.path) else { completion(false, password); return }
                runTest(info: info, password: pw, host: host, completion: completion)
                return
            }
            if result.ok {
                Dialogs.info(loc.t("test_passed_title"), loc.t("test_passed_message", name(info.path)))
            } else {
                Dialogs.error(loc.t("test_failed_title"), result.errorSummary, details: result.output)
            }
            completion(result.ok, password)
        }
    }

    // MARK: Compression

    // swiftlint:disable:next function_body_length
    static func compress(items: [String], options: CompressOptions, host: NSWindow?, completion: @escaping (Bool, String) -> Void) {
        var options = options
        // A self-extracting RAR is written as name.sfx: the checks below and the reported path are about that file
        options.archivePath = options.writtenPath
        if options.format.isRar, !RarTools.ensureAvailable() { completion(false, options.archivePath); return }
        if options.format == .zip, !zipTakes(password: options.password) {
            Dialogs.error(loc.t("compress_failed_title"), loc.t("zip_password_not_ascii"))
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

    // MARK: Adding files to / deleting from an existing archive

    static func add(info: ArchiveInfo, items: [String], password: String?, host: NSWindow?, completion: @escaping (Bool, String?) -> Void) {
        guard info.supportsModification else {
            Dialogs.error(loc.t("not_supported_title"), loc.t("add_tar_compressed_unsupported"))
            completion(false, password); return
        }
        if info.kind == .rar, !RarTools.ensureAvailable() { completion(false, password); return }
        var pw = password
        if info.hasEncryptedFiles, pw == nil {
            guard let entered = Dialogs.askPassword(archiveName: name(info.path)) else { completion(false, nil); return }
            pw = entered
        }
        if info.type.lowercased() == "zip", !zipTakes(password: pw) {
            Dialogs.error(loc.t("add_failed_title"), loc.t("zip_password_not_ascii"))
            completion(false, pw); return
        }
        // The archive's own password is found before anything is written: files added under another one left it with
        // files under two passwords, neither of which opened it whole. Encrypted names make the tools check it anyway.
        guard let typed = pw, info.hasEncryptedFiles, !info.headersEncrypted else {
            write(items, into: info, password: pw, host: host, completion: completion); return
        }
        findPassword(typed, of: info, host: host) { found in
            guard let found else { completion(false, pw); return }
            write(items, into: info, password: found, host: host, completion: completion)
        }
    }

    /// The form of `password` that opens the archive's encrypted files, found by extracting the smallest of them to a
    /// scratch folder: the password, its decomposed form, then what the user enters, until one does. Nil on cancel.
    private static func findPassword(_ password: String, of info: ArchiveInfo, host: NSWindow?, completion: @escaping (String?) -> Void) {
        guard let sample = info.entries.filter({ $0.encrypted && !$0.isDirectory }).min(by: { $0.size < $1.size }) else {
            completion(password); return
        }
        let scratch = TempDirs.make("password")
        let operation = SevenZipBridge.Operation.extract(archive: info.path, destination: scratch, items: [sample.name],
                                                         overwrite: .overwrite, password: password)
        runJob(title: loc.t("progress_checking_password", name(info.path)), operation: operation, host: host) { result in
            try? FileManager.default.removeItem(atPath: scratch)
            if result.cancelled { completion(nil); return }
            // Anything but a refused password, such as a damaged file, is the add's to report
            guard result.wrongPassword else { completion(password); return }
            guard let next = Ops.password(after: password, archive: info.path) else { completion(nil); return }
            findPassword(next, of: info, host: host, completion: completion)
        }
    }

    private static func write(_ items: [String], into info: ArchiveInfo, password: String?, host: NSWindow?,
                              completion: @escaping (Bool, String?) -> Void) {
        let title = loc.t("progress_adding", name(info.path))
        let finish: (RarResult) -> Void = { result in
            if result.cancelled { completion(false, password); return }
            if result.wrongPassword {
                guard let next = Ops.password(after: password, archive: info.path) else { completion(false, password); return }
                add(info: info, items: items, password: next, host: host, completion: completion)
                return
            }
            if !result.ok { Dialogs.error(loc.t("add_failed_title"), result.errorSummary, details: result.output) }
            completion(result.ok, password)
        }
        switch info.kind {
        case .rar:
            let args = RarRunner.addArguments + RarRunner.passwordSwitch(password, encryptHeaders: info.headersEncrypted)
                + ["--", info.path] + items
            // rar writes its temporary archive in its working directory, which is / when Finder opens the app
            let folder = (info.path as NSString).deletingLastPathComponent
            runRar(title: title, args: args, password: password, cwd: folder, host: host, completion: finish)
        case .other:
            var options = SevenZipBridge.UpdateOptions(format: info.type, password: password)
            options.encryptHeaders = password != nil && info.headersEncrypted
            runJob(title: title, operation: .update(archive: info.path, sources: items, options: options), host: host, completion: finish)
        }
    }

    static func delete(
        info: ArchiveInfo, names: [String], password: String?, host: NSWindow?, completion: @escaping (Bool, String?) -> Void
    ) {
        guard info.supportsModification else {
            Dialogs.error(loc.t("not_supported_title"), loc.t("delete_tar_compressed_unsupported"))
            completion(false, password); return
        }
        if info.kind == .rar, !RarTools.ensureAvailable() { completion(false, password); return }
        let folder = (info.path as NSString).deletingLastPathComponent
        var pw = password
        if info.headersEncrypted, pw == nil {
            guard let entered = Dialogs.askPassword(archiveName: name(info.path)) else { completion(false, nil); return }
            pw = entered
        }
        let title = loc.t("progress_deleting", name(info.path))
        let finish: (RarResult) -> Void = { result in
            if result.cancelled { completion(false, pw); return }
            if result.wrongPassword {
                guard let next = Ops.password(after: pw, archive: info.path) else { completion(false, pw); return }
                delete(info: info, names: names, password: next, host: host, completion: completion)
                return
            }
            if !result.ok { Dialogs.error(loc.t("delete_failed_title"), result.errorSummary, details: result.output) }
            completion(result.ok, pw)
        }
        switch info.kind {
        case .rar:
            let args = ["d", "-y"] + RarRunner.passwordSwitch(pw) + ["--", info.path] + names
            runRar(title: title, args: args, password: pw, cwd: folder, host: host, completion: finish)
        case .other:
            let operation = SevenZipBridge.Operation.delete(archive: info.path, items: names, password: pw,
                                                            encryptHeaders: info.headersEncrypted)
            runJob(title: title, operation: operation, host: host, completion: finish)
        }
    }

    // MARK: Destination folder helpers

    static func folderNamedAfterArchive(_ archive: String) -> String {
        let ns = archive as NSString
        var base = (ns.deletingPathExtension as NSString).lastPathComponent
        // multi-volume archives: "name.part1" → "name", "name.7z.001" → "name"
        if let range = base.range(of: #"\.part\d+$"#, options: [.regularExpression, .caseInsensitive]) { base.removeSubrange(range) }
        if ns.pathExtension.range(of: #"^\d{3}$"#, options: .regularExpression) != nil {
            base = (base as NSString).deletingPathExtension
        }
        // name.tar.gz → name
        if base.lowercased().hasSuffix(".tar") { base = String(base.dropLast(4)) }
        return (ns.deletingLastPathComponent as NSString).appendingPathComponent(base)
    }

    /// Top-level names to extract (names nil → whole archive)
    static func topLevelNames(info: ArchiveInfo, names: [String]?) -> [String] {
        guard let names else { return info.topLevelNames }
        var seen = Set<String>()
        return names.compactMap { entryName in
            let top = entryName.split(separator: "/", maxSplits: 1).first.map(String.init) ?? entryName
            return seen.insert(top).inserted ? top : nil
        }
    }

    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// After extraction: selects the extracted top-level items in Finder (or the destination folder if none)
    static func revealExtracted(info: ArchiveInfo, names: [String]?, dest: String) {
        guard Prefs.revealAfterExtract else { return }
        let urls = topLevelNames(info: info, names: names).map { URL(fileURLWithPath: (dest as NSString).appendingPathComponent($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty { revealInFinder(dest) } else { NSWorkspace.shared.activateFileViewerSelecting(Array(urls.prefix(50))) }
    }
}
