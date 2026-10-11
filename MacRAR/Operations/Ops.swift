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

    static func name(_ path: String) -> String { (path as NSString).lastPathComponent }

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
