import AppKit

/// All archive operations: used both from the window and from the Finder Quick Actions.
enum Ops {

    // MARK: Shared job runner (with progress window)

    static func runJob(title: String, stages: [Stage], cwd: String? = nil,
                       host: NSWindow?, totalFiles: Int?, stripPrefix: String? = nil,
                       completion: @escaping (RarResult) -> Void) {
        let panel = ProgressPanel(title: title)
        panel.stripPrefix = stripPrefix
        let job = RarJob()
        var sawPercent = false
        var fileIndex = 0
        var lastName = ""
        job.onEvent = { ev in
            switch ev {
            case .file(let name):
                panel.setFile(name)
                if name != lastName {
                    lastName = name
                    fileIndex += 1
                    // For pipeline jobs that report no percentage, advance by file count
                    if !sawPercent, let total = totalFiles, total > 0 {
                        panel.setFraction(Double(min(fileIndex, total)) / Double(total))
                    }
                }
            case .progress(let pct):
                // The rar/unrar/7zz percentage is the overall progress of the archive
                sawPercent = true
                panel.setFraction(Double(pct) / 100.0)
            }
        }
        panel.onCancel = { job.cancel() }
        panel.show(on: host)
        job.start(stages: stages, cwd: cwd) { result in
            panel.dismiss()
            completion(result)
        }
    }

    static func runJob(title: String, tool: RarTool, args: [String], cwd: String? = nil,
                       host: NSWindow?, totalFiles: Int?, stripPrefix: String? = nil,
                       completion: @escaping (RarResult) -> Void) {
        runJob(title: title, stages: [(tool, args)], cwd: cwd, host: host, totalFiles: totalFiles, stripPrefix: stripPrefix, completion: completion)
    }

    private static func name(_ path: String) -> String { (path as NSString).lastPathComponent }

    // MARK: Listing (with password loop)

    /// Lists the archive; asks for a password if needed. Returns nil on cancel.
    static func listInteractive(archive: String, password: inout String?) -> ArchiveInfo? {
        let folder = (archive as NSString).deletingLastPathComponent
        if Formats.isMultiVolume(archive) || !FileManager.default.isReadableFile(atPath: archive) {
            guard FolderAccess.ensure(folder, write: false) else { return nil }
        }
        var wrong = false
        while true {
            switch RarRunner.list(archive, password: password) {
            case .ok(var info):
                if wrong { info.headersEncrypted = true }   // could not be listed without a password
                return info
            case .wrongPassword:
                guard let pw = Dialogs.askPassword(archiveName: name(archive), wrong: wrong) else { return nil }
                password = pw
                wrong = true
            case .error(let r):
                if r.notArchive {
                    Dialogs.error(loc.t("open_failed_title"), loc.t("open_failed_unsupported", name(archive)))
                } else {
                    Dialogs.error(loc.t("open_failed_title"), r.errorSummary, details: r.output)
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
        return info.entries.contains { e in
            e.encrypted && names.contains { n in e.name == n || e.name.hasPrefix(n + "/") }
        }
    }

    enum OverwriteArg { case overwrite, rename, skip }

    static func extractStages(info: ArchiveInfo, names: [String]?, dest: String, password: String?, mode: OverwriteArg) -> [Stage] {
        let ow = mode == .overwrite ? "-aoa" : (mode == .rename ? "-aou" : "-aos")
        if info.tarCompressed {
            var inner = ["x", "-si", "-ttar", "-y", "-bb1", ow, "-o" + dest]
            if let names { inner += ["--"] + names }
            return [(.sevenZip, ["x", "-so", RarRunner.passwordArg7z(password), "--", info.path]),
                    (.sevenZip, inner)]
        }
        var args = ["x", "-y", "-bsp1", "-bb1", ow, RarRunner.passwordArg7z(password), "-o" + dest, "--", info.path]
        if let names { args += names }
        return [(.sevenZip, args)]
    }

    /// names: nil means the whole archive. completion(success, password used)
    static func extract(info: ArchiveInfo, names: [String]?, dest: String, password: String?,
                        host: NSWindow?, quiet: Bool = false, completion: @escaping (Bool, String?) -> Void) {
        guard FolderAccess.ensure(FolderAccess.existingAncestor(of: dest), write: true) else { completion(false, password); return }
        var pw = password
        if needsPassword(info: info, names: names), pw == nil {
            guard let p = Dialogs.askPassword(archiveName: name(info.path)) else { completion(false, nil); return }
            pw = p
        }
        // Overwrite check
        let tops = topLevelNames(info: info, names: names)
        let existing = tops.filter { FileManager.default.fileExists(atPath: (dest as NSString).appendingPathComponent($0)) }
        var mode: OverwriteArg = .overwrite
        if !existing.isEmpty {
            switch Dialogs.askOverwrite(existing: existing, dest: dest) {
            case .overwrite: mode = .overwrite
            case .rename: mode = .rename
            case .skip: mode = .skip
            case .cancel: completion(false, pw); return
            }
        }
        let count = names == nil ? info.entries.count : nil
        runExtract(info: info, names: names, dest: dest, password: pw, mode: mode, host: host, count: count, quiet: quiet, completion: completion)
    }

    private static func runExtract(info: ArchiveInfo, names: [String]?, dest: String, password: String?, mode: OverwriteArg,
                                   host: NSWindow?, count: Int?, quiet: Bool, completion: @escaping (Bool, String?) -> Void) {
        let stages = extractStages(info: info, names: names, dest: dest, password: password, mode: mode)
        let quarantine = Quarantine.value(of: info.path)
        let started = Date()
        func finish(_ r: RarResult) {
            if r.cancelled { completion(false, password); return }
            if r.wrongPassword {
                guard let pw = Dialogs.askPassword(archiveName: name(info.path), wrong: true) else { completion(false, password); return }
                runExtract(info: info, names: names, dest: dest, password: pw, mode: mode, host: host, count: count, quiet: quiet, completion: completion)
                return
            }
            if !r.ok {
                Dialogs.error(loc.t("extract_failed_title"), r.errorSummary, details: r.output)
                completion(false, password)
                return
            }
            if r.code == 1, !quiet {
                Dialogs.info(loc.t("extract_warnings_title"), r.errorSummary)
            }
            completion(true, password)
        }
        runJob(title: loc.t("progress_extracting", name(info.path)), stages: stages, host: host, totalFiles: count, stripPrefix: dest) { r in
            // Every item written, including by an interrupted extraction, gets the archive's quarantine (before the result is handled or anything is opened)
            guard let quarantine else { finish(r); return }
            let tops = topLevelNames(info: info, names: names)
            DispatchQueue.global(qos: .userInitiated).async {
                Quarantine.apply(quarantine, dest: dest, tops: tops, since: started)
                DispatchQueue.main.async { finish(r) }
            }
        }
    }

    // MARK: Test

    static func test(info: ArchiveInfo, password: String?, host: NSWindow?, completion: @escaping (Bool, String?) -> Void) {
        var pw = password
        if info.hasEncryptedFiles, pw == nil {
            guard let p = Dialogs.askPassword(archiveName: name(info.path)) else { completion(false, nil); return }
            pw = p
        }
        runTest(info: info, password: pw, host: host, completion: completion)
    }

    private static func runTest(info: ArchiveInfo, password: String?, host: NSWindow?, completion: @escaping (Bool, String?) -> Void) {
        let stages: [Stage]
        if info.tarCompressed {
            stages = [(.sevenZip, ["x", "-so", RarRunner.passwordArg7z(password), "--", info.path]),
                      (.sevenZip, ["t", "-si", "-ttar", "-bb1"])]
        } else {
            stages = [(.sevenZip, ["t", "-bsp1", "-bb1", RarRunner.passwordArg7z(password), "--", info.path])]
        }
        runJob(title: loc.t("progress_testing", name(info.path)), stages: stages, host: host, totalFiles: info.entries.count) { r in
            if r.cancelled { completion(false, password); return }
            if r.wrongPassword {
                guard let pw = Dialogs.askPassword(archiveName: name(info.path), wrong: true) else { completion(false, password); return }
                runTest(info: info, password: pw, host: host, completion: completion)
                return
            }
            if r.ok {
                Dialogs.info(loc.t("test_passed_title"), loc.t("test_passed_message", name(info.path)))
            } else {
                Dialogs.error(loc.t("test_failed_title"), r.errorSummary, details: r.output)
            }
            completion(r.ok, password)
        }
    }

    // MARK: Compression

    static func compress(items: [String], options: CompressOptions, host: NSWindow?, completion: @escaping (Bool, String) -> Void) {
        var o = options
        if o.format.isRar, !RarTools.ensureAvailable() { completion(false, o.archivePath); return }
        guard FolderAccess.ensure((o.archivePath as NSString).deletingLastPathComponent, write: true) else { completion(false, o.archivePath); return }
        if FileManager.default.fileExists(atPath: o.archivePath) {
            let alert = NSAlert()
            alert.messageText = loc.t("compress_exists_title", name(o.archivePath))
            if o.format.supportsAppend {
                // Is the existing archive encrypted? (try listing without a password)
                var existingEncrypted = false
                switch RarRunner.list(o.archivePath, password: nil) {
                case .ok(let ex): existingEncrypted = ex.hasEncryptedFiles
                case .wrongPassword: existingEncrypted = true
                case .error: break
                }
                if existingEncrypted {
                    alert.informativeText = loc.t("compress_exists_encrypted_message")
                    alert.addButton(withTitle: loc.t("compress_create_new"))
                    alert.addButton(withTitle: loc.t("compress_add_to_encrypted"))
                    alert.addButton(withTitle: loc.t("cancel"))
                    Dialogs.activate()
                    switch alert.runModal() {
                    case .alertFirstButtonReturn:
                        o.archivePath = uniquePath(o.archivePath)
                    case .alertSecondButtonReturn:
                        var pw: String? = nil
                        guard let existing = listInteractive(archive: o.archivePath, password: &pw) else { completion(false, o.archivePath); return }
                        add(info: existing, items: items, password: pw, host: host) { ok, _ in completion(ok, o.archivePath) }
                        return
                    default:
                        completion(false, o.archivePath); return
                    }
                } else {
                    alert.informativeText = loc.t("compress_exists_message")
                    alert.addButton(withTitle: loc.t("compress_create_new"))
                    alert.addButton(withTitle: loc.t("compress_add_to_existing"))
                    alert.addButton(withTitle: loc.t("cancel"))
                    Dialogs.activate()
                    switch alert.runModal() {
                    case .alertFirstButtonReturn: o.archivePath = uniquePath(o.archivePath)
                    case .alertSecondButtonReturn: break
                    default: completion(false, o.archivePath); return
                    }
                }
            } else {
                alert.informativeText = loc.t("compress_exists_no_append_message")
                alert.addButton(withTitle: loc.t("compress_create_new"))
                alert.addButton(withTitle: loc.t("cancel"))
                Dialogs.activate()
                if alert.runModal() == .alertFirstButtonReturn { o.archivePath = uniquePath(o.archivePath) } else { completion(false, o.archivePath); return }
            }
        }
        let cwd = (o.archivePath as NSString).deletingLastPathComponent
        let steps = o.buildSteps(items: items)
        runSteps(steps, index: 0, archive: o.archivePath, cwd: cwd, host: host, completion: completion)
    }

    private static func runSteps(_ steps: [CompressOptions.Step], index: Int, archive: String, cwd: String,
                                 host: NSWindow?, completion: @escaping (Bool, String) -> Void) {
        guard index < steps.count else { completion(true, archive); return }
        let step = steps[index]
        let suffix = steps.count > 1 ? " (\(index + 1)/\(steps.count))" : ""
        runJob(title: "\(step.title): \(name(archive))\(suffix)", tool: step.tool, args: step.args, cwd: cwd, host: host, totalFiles: nil) { r in
            step.cleanup?()
            if r.cancelled {
                steps[(index + 1)...].forEach { $0.cleanup?() }
                completion(false, archive); return
            }
            if !r.ok {
                steps[(index + 1)...].forEach { $0.cleanup?() }
                Dialogs.error(loc.t("compress_failed_title"), r.errorSummary, details: r.output)
                completion(false, archive)
                return
            }
            runSteps(steps, index: index + 1, archive: archive, cwd: cwd, host: host, completion: completion)
        }
    }

    // MARK: Adding files to / deleting from an existing archive

    static func add(info: ArchiveInfo, items: [String], password: String?, host: NSWindow?, completion: @escaping (Bool, String?) -> Void) {
        guard info.supportsModification else {
            Dialogs.error(loc.t("not_supported_title"), loc.t("add_tar_compressed_unsupported"))
            completion(false, password); return
        }
        if info.kind == .rar, !RarTools.ensureAvailable() { completion(false, password); return }
        guard FolderAccess.ensure((info.path as NSString).deletingLastPathComponent, write: true) else { completion(false, password); return }
        var pw = password
        if info.hasEncryptedFiles, pw == nil {
            guard let p = Dialogs.askPassword(archiveName: name(info.path)) else { completion(false, nil); return }
            pw = p
        }
        let stages: [Stage]
        switch info.kind {
        case .rar:
            stages = [(.rar, ["a", "-ep1", "-r", "-y"] + RarRunner.rarPasswordArgs(pw, encryptHeaders: info.headersEncrypted) + ["--", info.path] + items)]
        case .other:
            var args = ["a", "-y", "-bsp1", "-bb1", RarRunner.passwordArg7z(pw)]
            if info.headersEncrypted { args.append("-mhe=on") }
            stages = [(.sevenZip, args + ["--", info.path] + items)]
        }
        runJob(title: loc.t("progress_adding", name(info.path)), stages: stages, host: host, totalFiles: nil) { r in
            if r.cancelled { completion(false, pw); return }
            if r.wrongPassword {
                guard let p = Dialogs.askPassword(archiveName: name(info.path), wrong: true) else { completion(false, pw); return }
                add(info: info, items: items, password: p, host: host, completion: completion)
                return
            }
            if !r.ok { Dialogs.error(loc.t("add_failed_title"), r.errorSummary, details: r.output) }
            completion(r.ok, pw)
        }
    }

    static func delete(info: ArchiveInfo, names: [String], password: String?, host: NSWindow?, completion: @escaping (Bool, String?) -> Void) {
        guard info.supportsModification else {
            Dialogs.error(loc.t("not_supported_title"), loc.t("delete_tar_compressed_unsupported"))
            completion(false, password); return
        }
        if info.kind == .rar, !RarTools.ensureAvailable() { completion(false, password); return }
        guard FolderAccess.ensure((info.path as NSString).deletingLastPathComponent, write: true) else { completion(false, password); return }
        var pw = password
        if info.headersEncrypted, pw == nil {
            guard let p = Dialogs.askPassword(archiveName: name(info.path)) else { completion(false, nil); return }
            pw = p
        }
        let stages: [Stage]
        switch info.kind {
        case .rar:
            stages = [(.rar, ["d", "-y"] + RarRunner.rarPasswordArgs(pw) + ["--", info.path] + names)]
        case .other:
            stages = [(.sevenZip, ["d", "-y", "-bsp1", "-bb1", RarRunner.passwordArg7z(pw), "--", info.path] + names)]
        }
        runJob(title: loc.t("progress_deleting", name(info.path)), stages: stages, host: host, totalFiles: nil) { r in
            if r.cancelled { completion(false, pw); return }
            if r.wrongPassword {
                guard let p = Dialogs.askPassword(archiveName: name(info.path), wrong: true) else { completion(false, pw); return }
                delete(info: info, names: names, password: p, host: host, completion: completion)
                return
            }
            if !r.ok { Dialogs.error(loc.t("delete_failed_title"), r.errorSummary, details: r.output) }
            completion(r.ok, pw)
        }
    }

    // MARK: Destination folder helpers

    static func folderNamedAfterArchive(_ archive: String) -> String {
        let ns = archive as NSString
        var base = (ns.deletingPathExtension as NSString).lastPathComponent
        // multi-volume archives: "name.part1" → "name", "name.7z.001" → "name"
        if let r = base.range(of: #"\.part\d+$"#, options: [.regularExpression, .caseInsensitive]) { base.removeSubrange(r) }
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
        return names.compactMap { n in
            let t = n.split(separator: "/", maxSplits: 1).first.map(String.init) ?? n
            return seen.insert(t).inserted ? t : nil
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
