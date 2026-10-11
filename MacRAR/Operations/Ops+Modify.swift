import AppKit

/// Adding files to an archive that is open, and deleting from it.
extension Ops {
    static func add(info: ArchiveInfo, items: [String], password: String?, host: NSWindow?, completion: @escaping (Bool, String?) -> Void) {
        let items = itemsToAdd(items, into: info.path)
        guard !items.isEmpty else { completion(false, password); return }
        guard info.supportsModification else {
            Dialogs.error(loc.t("not_supported_title"), loc.t("add_tar_compressed_unsupported"))
            completion(false, password); return
        }
        if let problem = addProblem(items, into: info) {
            Dialogs.error(loc.t("add_failed_title"), problem)
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
            // A deletion that matched nothing used to report success while every item stayed
            guard let list = try? RarRunner.nameList(names) else {
                Dialogs.error(loc.t("delete_failed_title"), loc.t("unknown_error"))
                completion(false, pw); return
            }
            let args = ["d", "-y", "-scfl"] + RarRunner.passwordSwitch(pw) + ["--", info.path, list.argument]
            runRar(title: title, args: args, password: pw, cwd: folder, host: host) { result in
                try? FileManager.default.removeItem(atPath: list.folder)
                finish(result)
            }
        case .other:
            let operation = SevenZipBridge.Operation.delete(archive: info.path, items: names, password: pw,
                                                            encryptHeaders: info.headersEncrypted)
            runJob(title: title, operation: operation, host: host, completion: finish)
        }
    }
}
