import AppKit

/// Passwords: what is tried once one is refused, the one that opens an archive found before anything is written, and
/// what keeps one from locking a new archive so that it opens as typed.
extension Ops {
    /// The password as earlier versions handed it to rar and 7zz, decomposed, the way Process passes arguments: an
    /// archive they locked with a password holding letters such as ü or ş opens only with those bytes. Nil when the
    /// password has no such letter or already is that form. (Swift compares strings by meaning, so the scalars decide.)
    static func decomposedForm(of password: String?) -> String? {
        guard let password else { return nil }
        let decomposed = password.decomposedStringWithCanonicalMapping
        return decomposed.unicodeScalars.elementsEqual(password.unicodeScalars) ? nil : decomposed
    }

    /// What to try once `password` is refused: its decomposed form first, then what the user enters. Nil on cancel.
    static func password(after password: String?, archive: String) -> String? {
        decomposedForm(of: password) ?? Dialogs.askPassword(archiveName: (archive as NSString).lastPathComponent, wrong: true)
    }

    /// 7-Zip writes ZIP only with a password of printable ASCII, space to DEL; any other letter, such as ü or ş, made it
    /// fail with "E_INVALIDARG", so that is explained before anything is written.
    static func zipTakes(password: String?) -> Bool {
        password?.unicodeScalars.allSatisfy { (0x20..<0x80).contains($0.value) } ?? true
    }

    /// Why `password` cannot lock a new archive of `format` so that it opens as typed, for the user; nil when it can.
    /// ZIP: printable ASCII only, and with AES, which the app always uses for a ZIP password, 99 characters at most;
    /// 7-Zip refused anything else with "E_INVALIDARG". RAR: rar uses the first 127 characters, counting Unicode
    /// scalars, while 7-Zip and WinRAR on Windows count UTF-16 units, an emoji taking two; when those 127 characters
    /// take more units, rar locked the archive with more of the password than they read, and the app could not open it.
    static func passwordProblem(_ password: String?, format: ArchiveFormat) -> String? {
        guard let password, !password.isEmpty else { return nil }
        switch format {
        case .zip:
            if !zipTakes(password: password) { return loc.t("zip_password_not_ascii") }
            if password.unicodeScalars.count > 99 { return loc.t("zip_password_too_long") }
        case .rar5:
            let used = String(String.UnicodeScalarView(password.unicodeScalars.prefix(127)))
            if used.utf16.count > 127 { return loc.t("rar_password_emoji_counted_twice") }
        case .sevenZip, .tar, .tgz, .txz, .tbz2:
            break
        }
        return nil
    }

    /// The form of `password` that opens the archive's encrypted files, found by extracting the smallest of them to a
    /// scratch folder: the password, its decomposed form, then what the user enters, until one does. Nil on cancel.
    static func findPassword(_ password: String, of info: ArchiveInfo, host: NSWindow?, completion: @escaping (String?) -> Void) {
        guard let sample = info.entries.filter({ $0.encrypted && !$0.isDirectory }).min(by: { $0.size < $1.size }) else {
            completion(password); return
        }
        let scratch = TempDirs.make("password")
        let operation = SevenZipBridge.Operation.extract(archive: info.path, destination: scratch, items: [sample.name],
                                                         overwrite: .overwrite, password: password)
        let title = loc.t("progress_checking_password", (info.path as NSString).lastPathComponent)
        runJob(title: title, operation: operation, host: host) { result in
            try? FileManager.default.removeItem(atPath: scratch)
            if result.cancelled { completion(nil); return }
            // Anything but a refused password, such as a damaged file, is the operation's to report
            guard result.wrongPassword else { completion(password); return }
            guard let next = Ops.password(after: password, archive: info.path) else { completion(nil); return }
            findPassword(next, of: info, host: host, completion: completion)
        }
    }
}
