import AppKit
import UniformTypeIdentifiers

/// The command-line modes the Finder Quick Actions start a copy of the app in: each runs, reports and quits.
extension AppDelegate {
    // MARK: Command-line / Finder Quick Action mode

    func runCommand(_ cmd: Command) {
        switch cmd {
        case .setDefault:
            setDefaultHandler { _ in self.finishCommand() }
        case .installQuickActions:
            let count = QuickActions.installAll()
            print("\(count) Quick Actions installed: \(QuickActions.servicesDir)")
            self.finishCommand()
        case .extractHere(let paths):
            processArchives(Self.dedupeVolumes(paths), dest: { ($0 as NSString).deletingLastPathComponent })
        case .extractFolder(let paths):
            processArchives(Self.dedupeVolumes(paths), dest: { Ops.folderNamedAfterArchive($0) })
        case .extractTo(let paths):
            let list = Self.dedupeVolumes(paths)
            guard let first = list.first,
                  let dest = Dialogs.chooseFolder(title: loc.t("panel_extract_destination"), prompt: loc.t("extract"),
                                               initial: (first as NSString).deletingLastPathComponent) else {
                self.finishCommand(); return
            }
            processArchives(list, dest: { _ in dest })
        case .test(let paths):
            testArchives(Self.dedupeVolumes(paths))
        case .compress(let items):
            let existing = items.filter { FileManager.default.fileExists(atPath: $0) }
            guard !existing.isEmpty else { self.finishCommand(); return }
            var opts = CompressOptions.withDefaults(for: existing)
            // Debugging: MACRAR_DEBUG_FORMAT=zip|7z|tar.gz… and MACRAR_DEBUG_PASSWORD pick the format/password
            if let f = ProcessInfo.processInfo.environment["MACRAR_DEBUG_FORMAT"],
               let fmt = ArchiveFormat.allCases.first(where: { $0.ext == f }) {
                opts.format = fmt
                opts.archivePath = CompressOptions.defaultArchivePath(for: existing, format: fmt)
                opts.password = ProcessInfo.processInfo.environment["MACRAR_DEBUG_PASSWORD"]
                opts.encryptNames = ProcessInfo.processInfo.environment["MACRAR_DEBUG_ENCNAMES"] != nil
            }
            Ops.compress(items: existing, options: opts, host: nil) { ok, path in
                if ok, Prefs.revealAfterCompress { Ops.revealInFinder(path) }
                self.finishCommand()
            }
        case .compressDialog(let items):
            let existing = items.filter { FileManager.default.fileExists(atPath: $0) }
            guard !existing.isEmpty else { self.finishCommand(); return }
            compressWithDialog(items: existing, host: nil) { _ in self.finishCommand() }
        }
    }

    private func processArchives(_ archives: [String], dest: @escaping (String) -> String, index: Int = 0) {
        guard index < archives.count else { finishCommand(); return }
        let archive = archives[index]
        var pw: String?
        guard let info = Ops.listInteractive(archive: archive, password: &pw) else {
            processArchives(archives, dest: dest, index: index + 1)
            return
        }
        let target = dest(archive)
        Ops.extract(info: info, names: nil, dest: target, password: pw, host: nil) { [weak self] ok, _ in
            if ok, index == archives.count - 1 { Ops.revealExtracted(info: info, names: nil, dest: target) }
            self?.processArchives(archives, dest: dest, index: index + 1)
        }
    }

    private func testArchives(_ archives: [String], index: Int = 0) {
        guard index < archives.count else { finishCommand(); return }
        let archive = archives[index]
        var pw: String?
        guard let info = Ops.listInteractive(archive: archive, password: &pw) else {
            testArchives(archives, index: index + 1)
            return
        }
        Ops.test(info: info, password: pw, host: nil) { [weak self] _, _ in
            self?.testArchives(archives, index: index + 1)
        }
    }

    // MARK: Default app

    func setDefaultHandler(extensions: [String] = ["rar"], completion: @escaping (Error?) -> Void) {
        var types: [UTType] = []
        for ext in extensions {
            if ext == "rar", let utType = UTType("com.rarlab.rar-archive") { types.append(utType); continue }
            if let utType = UTType(filenameExtension: ext) { types.append(utType) }
        }
        func next(_ i: Int) {
            guard i < types.count else { completion(nil); return }
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: types[i]) { err in
                DispatchQueue.main.async {
                    if let err { completion(err) } else { next(i + 1) }
                }
            }
        }
        next(0)
    }
}
