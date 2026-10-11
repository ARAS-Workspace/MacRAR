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

    /// What an extraction writes: the archive, the items in it (nil for all of them), where they go, and what is done
    /// about items already there, as the overwrite question decides.
    struct Extraction {
        let info: ArchiveInfo
        let names: [String]?
        let dest: String
        var overwrite: SevenZipBridge.Overwrite = .overwrite
    }

    /// completion(success, password used)
    static func extract(_ extraction: Extraction, password: String?, host: NSWindow?, quiet: Bool = false,
                        completion: @escaping (Bool, String?) -> Void) {
        let info = extraction.info
        var pw = password
        let encrypted = needsPassword(info: info, names: extraction.names)
        if encrypted, pw == nil {
            guard let entered = Dialogs.askPassword(archiveName: name(info.path)) else { completion(false, nil); return }
            pw = entered
        }
        let write = { (password: String?) in
            extract(extraction, checkedPassword: password, host: host, quiet: quiet, completion: completion)
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

    private static func extract(_ extraction: Extraction, checkedPassword pw: String?, host: NSWindow?, quiet: Bool,
                                completion: @escaping (Bool, String?) -> Void) {
        // Overwrite check
        var extraction = extraction
        let tops = topLevelNames(info: extraction.info, names: extraction.names)
        let existing = tops.filter { FileManager.default.fileExists(atPath: (extraction.dest as NSString).appendingPathComponent($0)) }
        if !existing.isEmpty {
            switch Dialogs.askOverwrite(existing: existing, dest: extraction.dest) {
            case .overwrite: extraction.overwrite = .overwrite
            case .rename: extraction.overwrite = .rename
            case .skip: extraction.overwrite = .skip
            case .cancel: completion(false, pw); return
            }
        }
        runExtract(extraction, password: pw, host: host, quiet: quiet, completion: completion)
    }

    private static func runExtract(_ extraction: Extraction, password: String?, host: NSWindow?, quiet: Bool,
                                   completion: @escaping (Bool, String?) -> Void) {
        let info = extraction.info
        let operation = SevenZipBridge.Operation.extract(archive: info.path, destination: extraction.dest, items: extraction.names,
                                                         overwrite: extraction.overwrite, password: password)
        let quarantine = Quarantine.value(of: info.path)
        let started = Date()
        func finish(_ result: RarResult) {
            if result.cancelled { completion(false, password); return }
            if result.wrongPassword {
                guard let pw = Ops.password(after: password, archive: info.path) else { completion(false, password); return }
                runExtract(extraction, password: pw, host: host, quiet: quiet, completion: completion)
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
            let tops = topLevelNames(info: info, names: extraction.names)
            DispatchQueue.global(qos: .userInitiated).async {
                Quarantine.apply(quarantine, dest: extraction.dest, tops: tops, since: started)
                DispatchQueue.main.async { finish(result) }
            }
        }
    }
}
