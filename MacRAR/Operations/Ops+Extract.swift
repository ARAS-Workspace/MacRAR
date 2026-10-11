import AppKit

/// Extraction, with the overwrite question and the archive's own password found before anything is written.
extension Ops {
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
        let encrypted = needsPassword(info: info, names: names)
        if encrypted, pw == nil {
            guard let entered = Dialogs.askPassword(archiveName: name(info.path)) else { completion(false, nil); return }
            pw = entered
        }
        let write = { (password: String?) in
            extract(info: info, names: names, dest: dest, checkedPassword: password, host: host, quiet: quiet, completion: completion)
        }
        // The archive's own password is found before anything is written: 7-Zip begins RAR and ZIP items before it finds
        // a password wrong, which emptied a file Overwrite was to replace and left the others behind, empty. Encrypted
        // names were already checked when the archive was listed.
        guard let typed = pw, encrypted, !info.headersEncrypted else { write(pw); return }
        findPassword(typed, of: info, host: host) { found in
            guard let found else { completion(false, pw); return }
            write(found)
        }
    }

    private static func extract(info: ArchiveInfo, names: [String]?, dest: String, checkedPassword pw: String?,
                                host: NSWindow?, quiet: Bool, completion: @escaping (Bool, String?) -> Void) {
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
}
