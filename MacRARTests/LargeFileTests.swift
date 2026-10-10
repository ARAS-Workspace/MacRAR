import XCTest
@testable import MacRAR

/// The generated large files (LargeFiles) through the app's own flows, as people run them on big media: the progress
/// window names the file being worked on instead of staying on "Preparing…", every format gives each file back byte
/// for byte, a cancelled run stops at once and leaves nothing behind, and the Finder Quick Action packs them in a
/// second copy of the app. They take minutes on CI, the price of seeing what a long run looks like. The RAR parts use
/// RarTool through the RarPath setting in the argument domain (never saved), as RARTests does.
final class LargeFileTests: XCTestCase {
    private var files: [String] = []
    private var rar: RarTool?
    private var workspace: Workspace!
    private var savedArguments: [String: Any]?

    override func setUpWithError() throws {
        files = try LargeFiles.locate()
        workspace = try Workspace()
        rar = try? RarTool.locate()
        if let rar {
            let defaults = UserDefaults.standard
            let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
            savedArguments = arguments
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(arguments.merging(["RarPath": rar.url.path]) { $1 }, forName: UserDefaults.argumentDomain)
        }
        setenv("MACRAR_DEBUG_CONFIRM", "1", 1)
    }

    override func tearDown() {
        unsetenv("MACRAR_DEBUG_CONFIRM")
        if let savedArguments {
            UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            UserDefaults.standard.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain)
        }
        savedArguments = nil
        workspace = nil
    }

    // MARK: Helpers

    /// What the progress window showed while an operation ran.
    private struct Run {
        var ok = false
        /// Each file line it showed, in order, without repeats, "Preparing…" and "Cancelling…" left out
        var shown: [String] = []
        /// Seconds from the window appearing to it naming a file
        var named: TimeInterval?
        /// Each percentage it showed, in order, without repeats
        var percents: [Int] = []
        /// Seconds from Cancel being clicked to the operation completing
        var stopped: TimeInterval?
        /// Seconds the window was on screen
        var visible: TimeInterval = 0

        var shownNames: [String] { shown.map { ($0 as NSString).lastPathComponent } }
    }

    private var names: [String] { files.map { ($0 as NSString).lastPathComponent } }

    /// Runs an operation the way the app does and reads its progress window every 0.1 s until it completes; with
    /// `cancelWhen`, clicks the window's Cancel button once what it has shown satisfies it.
    private func watch(cancelWhen: ((Run) -> Bool)? = nil, _ operation: (@escaping (Bool) -> Void) -> Void) -> Run {
        let quiet = [loc.t("progress_preparing"), loc.t("progress_cancelling"), ""]
        var run = Run()
        var finished = false
        var appeared: Date?
        var clicked: Date?
        let started = Date()
        operation { ok in
            run.ok = ok
            finished = true
        }
        while !finished, Date().timeIntervalSince(started) < 900 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            guard !finished, let panel = NSApp.windows.lazy.compactMap({ $0.windowController as? ProgressPanel })
                .first(where: { $0.window?.isVisible == true }) else { continue }
            let appearedAt = appeared ?? Date()
            appeared = appearedAt
            run.visible = Date().timeIntervalSince(appearedAt)
            let (file, detail) = panel.readout
            if !quiet.contains(file), run.shown.last != file {
                run.shown.append(file)
                run.named = run.named ?? Date().timeIntervalSince(appearedAt)
            }
            if let percent = Int(detail.drop { !$0.isNumber }.prefix { $0.isNumber }), run.percents.last != percent {
                run.percents.append(percent)
            }
            if clicked == nil, let cancelWhen, cancelWhen(run), let cancel = cancelButton(in: panel.window?.contentView) {
                cancel.performClick(nil)
                clicked = Date()
            }
        }
        XCTAssertTrue(finished, "the operation did not finish")
        run.stopped = clicked.map { Date().timeIntervalSince($0) }
        return run
    }

    private func cancelButton(in view: NSView?) -> NSButton? {
        for sub in view?.subviews ?? [] {
            if let button = sub as? NSButton, button.keyEquivalent == "\u{1b}" { return button }
            if let button = cancelButton(in: sub) { return button }
        }
        return nil
    }

    private func compress(_ format: ArchiveFormat, to archive: String, cancelWhen: ((Run) -> Bool)? = nil) -> Run {
        var options = CompressOptions(archivePath: archive)
        options.format = format
        return watch(cancelWhen: cancelWhen) { done in
            Ops.compress(items: files, options: options, host: nil) { ok, _ in done(ok) }
        }
    }

    /// 7-Zip extracts the archive again and every file comes back byte for byte.
    private func assertGivesBackEachFile(_ archive: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let out = try workspace.makeDirectory("out-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: out) }
        let outcome = run(.extract(archive: archive, destination: out, items: nil, overwrite: .overwrite, password: nil))
        XCTAssertEqual(outcome.code, .ok, outcome.error, file: file, line: line)
        try assertSameFiles(in: out, file: file, line: line)
    }

    private func assertSameFiles(in folder: String, file: StaticString = #filePath, line: UInt = #line) throws {
        for original in files {
            let name = (original as NSString).lastPathComponent
            XCTAssertEqual(try LargeFiles.digest("\(folder)/\(name)"), try LargeFiles.digest(original), name, file: file, line: line)
        }
    }

    /// Whether a process writing this archive is still running, whoever started it: a rar the app left behind runs on
    /// with no parent once the app is gone.
    private func stillRunning(writing archive: String) -> Bool {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", NSRegularExpression.escapedPattern(for: archive)]
        pgrep.standardOutput = FileHandle.nullDevice
        guard (try? pgrep.run()) != nil else { return false }
        pgrep.waitUntilExit()
        return pgrep.terminationStatus == 0
    }

    // MARK: Compressing

    /// The case that stayed on "Preparing…": rar named the file and its first percentage in one go. The window names
    /// each file in turn as rar takes it, and the percentage only grows.
    func testRarNamesEachFileWhileItPacksThem() throws {
        guard rar != nil else { throw XCTSkip("RARLAB's rar is not fetched; run External/fetch-rar.sh") }
        let archive = workspace.path("large.rar")
        let run = compress(.rar5, to: archive)
        XCTAssertTrue(run.ok)
        XCTAssertEqual(run.shownNames, names)
        XCTAssertLessThan(try XCTUnwrap(run.named, "the window never named a file"), 2)
        XCTAssertEqual(run.percents, run.percents.sorted(), "the percentage went back")
        XCTAssertGreaterThan(run.percents.last ?? 0, 80)
        try assertGivesBackEachFile(archive)
    }

    /// On a busy machine the pipe hands over a file's name together with its first percentage, the case that left the
    /// window on "Preparing…" for the whole run. A stand-in rar writes them that way every time, as rar 7.23 words them,
    /// slowly enough for the window to be up, and the window names each file all the same.
    func testTheWindowNamesAFileThatComesWithItsFirstPercentage() throws {
        let standIn = workspace.url("rar")
        try #"""
        #!/bin/sh
        while [ "$1" != "--" ]; do shift; done
        shift; archive=$1; shift
        printf '\nCreating archive %s\n' "$archive"
        sleep 0.5
        percent=0
        for file in "$@"; do
            [ $percent -gt 0 ] && printf '\010\010\010\010\010  OK '
            printf '\nAdding    %s     \010\010\010\010%3d%%' "$file" $percent
            sleep 0.4
            percent=$((percent + 30))
            printf '\010\010\010\010%3d%%' $percent
            sleep 0.4
        done
        printf '\010\010\010\010\010  OK \nDone\n'
        """#.write(to: standIn, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: standIn.path)
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(arguments.merging(["RarPath": standIn.path]) { $1 }, forName: UserDefaults.argumentDomain)
        defer {
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }

        let run = compress(.rar5, to: workspace.path("announced.rar"))
        XCTAssertTrue(run.ok)
        XCTAssertEqual(run.shownNames, names)
        XCTAssertEqual(run.percents, [0, 30, 60, 90])
    }

    /// 7-Zip names a file as soon as it opens it: 7z packs them one by one, ZIP several at a time.
    func testSevenZipAndZipNameTheFilesAndGiveThemBack() throws {
        for format in [ArchiveFormat.sevenZip, .zip] {
            let archive = workspace.path("large.\(format.ext)")
            let run = compress(format, to: archive)
            XCTAssertTrue(run.ok, format.ext)
            XCTAssertLessThan(try XCTUnwrap(run.named, "the window never named a file: \(format.ext)"), 2, format.ext)
            XCTAssertFalse(Set(run.shownNames).isDisjoint(with: names), "\(format.ext): \(run.shown)")
            if format == .sevenZip { XCTAssertEqual(Set(run.shownNames), Set(names)) }
            try assertGivesBackEachFile(archive)
            try FileManager.default.removeItem(atPath: archive)
        }
    }

    /// A tar.gz is packed into a tar in the temporary folder first and that tar is then compressed. gzip keeps the
    /// name of what it packs in the archive, which gunzip -N and other tools restore, and the window shows it while
    /// it compresses: it is the archive's own tar, where it used to be Archiver-<UUID>.tar.
    func testTarGzNamesItsTarAfterTheArchive() throws {
        let archive = workspace.path("large.tar.gz")
        let run = compress(.tgz, to: archive)
        XCTAssertTrue(run.ok)
        XCTAssertLessThan(try XCTUnwrap(run.named, "the window never named a file"), 2)
        XCTAssertEqual(try gzipName(archive), "large.tar")
        XCTAssertEqual(run.shownNames.last, "large.tar", "\(run.shown)")
        try assertGivesBackEachFile(archive)
    }

    // MARK: Extracting

    /// Extraction names each file it writes, from a 7z the library made and from a RAR rar made, and the app's own flow
    /// gives each one back. Writing them takes a fraction of a second on a fast disk, under the time the window waits
    /// before it appears, so the names are read where the window gets them; a window that does come up names a file.
    func testExtractingNamesEachFileAndGivesItBack() throws {
        var archives = [workspace.path("stored.7z")]
        update(archives[0], files, SevenZipBridge.UpdateOptions(format: "7z", level: 0))
        if let rar {
            archives.append(workspace.path("stored.rar"))
            let made = try rar.run(RarRunner.addArguments + ["-m0", "-ma5", "--", archives[1]] + files, in: workspace.root.path)
            XCTAssertEqual(made.status, 0, made.output)
        }
        for archive in archives {
            let kind = (archive as NSString).pathExtension
            XCTAssertEqual(Set(try extractionNames(archive)), Set(names), kind)

            guard case .ok(let info) = ArchiveReader.list(archive, password: nil) else { return XCTFail("\(archive) did not list") }
            let destination = try workspace.makeDirectory("out-\(kind)")
            let run = watch { done in
                Ops.extract(info: info, names: nil, dest: destination, password: nil, host: nil) { ok, _ in done(ok) }
            }
            XCTAssertTrue(run.ok, kind)
            if run.visible > 1 { XCTAssertNotNil(run.named, "\(kind): the window was up without naming a file") }
            XCTAssertTrue(Set(run.shownNames).isSubset(of: names), "\(kind): \(run.shown)")
            try assertSameFiles(in: destination)
            try FileManager.default.removeItem(atPath: destination)
        }
    }

    /// The names 7-Zip reports while it extracts, as SevenZipBridge.Job hands them to the progress window.
    private func extractionNames(_ archive: String) throws -> [String] {
        let destination = try workspace.makeDirectory("named-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: destination) }
        let job = SevenZipBridge.Job()
        var named: [String] = []
        job.onItem = { named.append($0) }
        let done = expectation(description: "extracted")
        job.start(.extract(archive: archive, destination: destination, items: nil, overwrite: .overwrite, password: nil)) {
            XCTAssertEqual($0.code, .ok)
            done.fulfill()
        }
        wait(for: [done], timeout: 300)
        return named
    }

    // MARK: Cancelling

    /// Cancel stops a long run within moments, rar included, and leaves neither a partial archive nor the tar a tar.gz
    /// is packed through.
    func testCancellingStopsAtOnceAndLeavesNothingBehind() throws {
        let temporary = NSTemporaryDirectory()
        let fm = FileManager.default
        for format in (rar == nil ? [] : [ArchiveFormat.rar5]) + [.sevenZip, .tgz] {
            let before = Set(try fm.contentsOfDirectory(atPath: temporary))
            let archive = workspace.path("cancelled.\(format.ext)")
            // A tar.gz is cancelled while its tar is compressed, the step that has to clean up after the first
            let run = compress(format, to: archive) { run in
                format == .tgz ? run.shownNames.last?.hasSuffix(".tar") == true : (run.percents.last ?? 0) >= 5
            }
            XCTAssertFalse(run.ok, format.ext)
            XCTAssertLessThan(try XCTUnwrap(run.stopped, "Cancel was never clicked: \(format.ext)"), 3, format.ext)
            XCTAssertFalse(stillRunning(writing: archive), format.ext)
            XCTAssertEqual(try fm.contentsOfDirectory(atPath: workspace.root.path).filter { $0.hasPrefix("cancelled") }, [],
                           "\(format.ext): a partial archive was left")
            let left = Set(try fm.contentsOfDirectory(atPath: temporary)).subtracting(before).filter { $0.hasPrefix("Archiver-") }
            XCTAssertEqual(left, [], "\(format.ext): the tar packed on the way was left")
        }
    }

    // MARK: Finder

    /// The Quick Action from Finder, in a second copy of the app: the archive is written next to the files, named after
    /// their folder, and the copy ends with nothing left running.
    func testQuickActionPacksThem() throws {
        let copies = try LargeFiles.clone(into: workspace, folder: "media")
        var runs: [(ArchiveFormat, [String])] = [(.sevenZip, [])]
        if let rar { runs.insert((.rar5, ["-RarPath", rar.url.path]), at: 0) }
        for (format, tool) in runs {
            let settings = ["-DefaultFormat", "\(format.rawValue)", "-DefaultLevel", "3", "-DefaultSolid", "NO", "-DefaultRecovery", "NO"]
            let ran = try launchApp(tool + settings + ["--compress"] + copies, timeout: 600)
            XCTAssertEqual(ran.status, 0, ran.output)
            let archive = workspace.path("media/media.\(format.ext)")
            XCTAssertFalse(stillRunning(writing: archive), format.ext)
            try assertGivesBackEachFile(archive)
            try FileManager.default.removeItem(atPath: archive)
        }
    }
}
