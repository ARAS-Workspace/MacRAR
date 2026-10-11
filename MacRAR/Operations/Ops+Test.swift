import AppKit

/// Testing an archive's contents against their checksums.
extension Ops {
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
}
