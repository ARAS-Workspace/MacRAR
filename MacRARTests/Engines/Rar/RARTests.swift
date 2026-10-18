import XCTest
@testable import MacRAR

/// RAR, the format the app is named after, with RARLAB's own rar (RarTool): archives rar makes are listed, extracted
/// and tested through the 7-Zip library, and the archives the app has rar create, add to and delete from come out as
/// asked. The app reaches rar through the RarPath setting, which each test points at RarTool in the argument domain
/// (never saved); the app's questions get the tests' debug answers (setDebugAnswers), never a real alert.
final class RARTests: XCTestCase {
    private var rar: RarTool!
    private var workspace: Workspace!
    private var savedArguments: [String: Any]?

    override func setUpWithError() throws {
        rar = try RarTool.locate()
        workspace = try Workspace()
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        savedArguments = arguments
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(arguments.merging(["RarPath": rar.url.path]) { $1 }, forName: UserDefaults.argumentDomain)
        setDebugAnswers()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: Ops.testTrash)
        if let savedArguments {
            clearDebugAnswers()
            UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            UserDefaults.standard.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain)
        }
        savedArguments = nil
        workspace = nil
    }

    // MARK: Helpers

    /// An archive rar itself makes from the workspace sources, with the switches the app passes.
    @discardableResult
    private func makeRar(_ name: String, _ switches: [String] = [], file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let archive = workspace.path(name)
        let made = try rar.run(RarRunner.addArguments + ["-ma5"] + switches + ["--", archive] + workspace.sources, in: workspace.root.path)
        XCTAssertEqual(made.status, 0, made.output, file: file, line: line)
        return archive
    }

    private func info(_ archive: String, password: String? = nil, file: StaticString = #filePath, line: UInt = #line) -> ArchiveInfo? {
        guard case .ok(let info) = ArchiveReader.list(archive, password: password) else {
            XCTFail("\(archive) did not list", file: file, line: line)
            return nil
        }
        return info
    }

    private func extract(_ archive: String, password: String? = nil, into folder: String) throws -> SevenZipBridge.Outcome {
        let destination = try workspace.makeDirectory(folder)
        return run(.extract(archive: archive, destination: destination, items: nil, overwrite: .overwrite, password: password))
    }

    private func assertSourcesExtracted(into folder: String, file: StaticString = #filePath, line: UInt = #line) {
        for item in ["a.txt", "sub/b.bin", "sub/çalışma ğüş.txt"] {
            XCTAssertEqual(workspace.contents("\(folder)/\(item)"), workspace.contents("src/\(item)"), item, file: file, line: line)
        }
    }

    /// rar switches run the way the operations run them, through RarJob, with the password it asks for and what it
    /// reports along the way.
    private func runRarJob(_ args: [String], password: String? = nil, cwd: String? = nil,
                           onEvent: ((RarJob.Event) -> Void)? = nil) -> RarResult {
        let job = RarJob()
        job.onEvent = onEvent
        let done = expectation(description: "rar finished")
        var result: RarResult?
        job.start(args, cwd: cwd, password: password) { outcome in
            result = outcome
            done.fulfill()
        }
        withExtendedLifetime(job) { wait(for: [done], timeout: 120) }
        return result ?? RarResult(code: -1, output: "rar did not finish")
    }

    /// The SFX module RARLAB ships beside rar.
    private var sfxModule: String { rar.url.deletingLastPathComponent().appendingPathComponent("default.sfx").path }

    /// The rar call the Create Archive dialog's choices become: its switches and the password rar asks for.
    private func rarCall(_ options: CompressOptions) throws -> (args: [String], password: String?) {
        guard case .rar(let args, let password) = try XCTUnwrap(options.buildSteps(items: workspace.sources).first).work else {
            throw XCTSkip("expected rar switches")
        }
        return (args, password)
    }

    // MARK: Reading what rar makes

    func testRar5IsListedExtractedAndTested() throws {
        let archive = try makeRar("plain.rar")
        let info = try XCTUnwrap(info(archive))
        XCTAssertEqual(info.kind, .rar)
        XCTAssertEqual(info.details, "RAR 5")
        XCTAssertEqual(Set(info.entries.map(\.name)), ["a.txt", "sub", "sub/b.bin", "sub/çalışma ğüş.txt"])
        XCTAssertEqual(info.entries.first { $0.name == "sub/b.bin" }?.size, 1 << 20)
        XCTAssertFalse(info.hasEncryptedFiles)
        XCTAssertTrue(info.supportsModification)

        XCTAssertEqual(try extract(archive, into: "out").code, .ok)
        assertSourcesExtracted(into: "out")
        XCTAssertEqual(run(.test(archive: archive, password: nil)).code, .ok)
    }

    func testEncryptedFilesNeedThePassword() throws {
        let archive = try makeRar("data.rar", ["-ppw"])
        let info = try XCTUnwrap(info(archive))
        XCTAssertTrue(info.hasEncryptedFiles)
        XCTAssertFalse(info.headersEncrypted)

        XCTAssertTrue(RarResult(try extract(archive, into: "none")).wrongPassword)
        XCTAssertTrue(RarResult(try extract(archive, password: "wrong", into: "wrong")).wrongPassword)
        XCTAssertEqual(try extract(archive, password: "pw", into: "out").code, .ok)
        assertSourcesExtracted(into: "out")
    }

    func testEncryptedHeadersHideTheListing() throws {
        let archive = try makeRar("headers.rar", ["-hppw"])
        guard case .wrongPassword = ArchiveReader.list(archive, password: nil) else { return XCTFail("listed without the password") }
        guard case .wrongPassword = ArchiveReader.list(archive, password: "wrong") else { return XCTFail("listed with a wrong password") }
        let info = try XCTUnwrap(info(archive, password: "pw"))
        XCTAssertTrue(info.headersEncrypted)
        XCTAssertEqual(info.fileCount, 3)
    }

    func testVolumesAreReadFromTheFirstPart() throws {
        try makeRar("vol.rar", ["-v300k"])
        let parts = try FileManager.default.contentsOfDirectory(atPath: workspace.root.path).filter { $0.hasPrefix("vol.part") }.sorted()
        XCTAssertGreaterThan(parts.count, 1, "\(parts)")
        XCTAssertTrue(parts.allSatisfy(Formats.isMultiVolume), "\(parts)")

        let first = workspace.path("vol.part1.rar")
        let info = try XCTUnwrap(info(first))
        XCTAssertTrue(info.details.contains("volume"), info.details)
        XCTAssertEqual(try extract(first, into: "out").code, .ok)
        assertSourcesExtracted(into: "out")
    }

    /// A set named the old way, x.rar, x.r00, x.r01 …, in the order Finder lists it. rar 7 no longer names volumes
    /// so (-vn is gone): the set is a split archive's x.partN.rar volumes copied under those names, which 7-Zip reads
    /// the same.
    private func makeOldStyleSet(_ name: String) throws -> [String] {
        try makeRar("\(name)-split.rar", ["-v300k"])
        let parts = try FileManager.default.contentsOfDirectory(atPath: workspace.root.path)
            .filter { $0.hasPrefix("\(name)-split.part") }.sorted()
        XCTAssertGreaterThan(parts.count, 2, "\(parts)")
        var pieces: [String] = []
        for (index, part) in parts.enumerated() {
            let piece = workspace.path(index == 0 ? "\(name).rar" : String(format: "\(name).r%02d", index - 1))
            try FileManager.default.copyItem(atPath: workspace.path(part), toPath: piece)
            pieces.append(piece)
        }
        return pieces.sorted()
    }

    /// Upstream 1.4.3 (533ce7e): the pieces of an old-style set chosen together in Finder were each extracted as an
    /// archive. x.r00, first in Finder's order, fails with "Headers Error" and leaves the file it began empty, and
    /// x.rar then found that file in the way; the set is extracted once, from x.rar.
    func testOldStyleVolumesChosenTogetherAreExtractedOnce() throws {
        let pieces = try makeOldStyleSet("old")
        let exit = try launchApp(["--extract-folder"] + pieces)
        XCTAssertEqual(exit.status, 0, exit.output)
        XCTAssertFalse(exit.output.contains("ERROR"), exit.output)
        assertSourcesExtracted(into: "old")
    }

    /// Later volumes chosen without the first, which sits beside them: the set is read from its first volume. Read
    /// on their own they failed with "Headers Error".
    func testLaterVolumesChosenAloneAreReadFromTheFirst() throws {
        try makeRar("vol.rar", ["-v300k"])
        _ = try makeOldStyleSet("old")
        let tested = try launchApp(["--test", workspace.path("vol.part2.rar"), workspace.path("vol.part3.rar")])
        let extracted = try launchApp(["--extract-folder", workspace.path("old.r00"), workspace.path("old.r01")])
        XCTAssertTrue(tested.output.contains(try english("test_passed_title")), tested.output)
        XCTAssertFalse(extracted.output.contains("ERROR"), extracted.output)
        assertSourcesExtracted(into: "old")
    }

    func testSolidArchiveIsReportedSolid() throws {
        let info = try XCTUnwrap(info(try makeRar("solid.rar", ["-s"])))
        XCTAssertTrue(info.isSolid, info.details)
    }

    // MARK: The app driving rar

    func testCreateArchiveChoicesBecomeAWorkingRarCall() throws {
        var options = CompressOptions(archivePath: workspace.path("made.rar"))
        options.format = .rar5
        options.password = "pw"
        options.encryptNames = true
        options.solid = true
        options.recoveryRecord = true
        let call = try rarCall(options)
        let result = runRarJob(call.args, password: call.password)
        XCTAssertTrue(result.ok, result.output)

        guard case .wrongPassword = ArchiveReader.list(options.archivePath, password: nil) else {
            return XCTFail("the names are not encrypted")
        }
        let info = try XCTUnwrap(info(options.archivePath, password: "pw"))
        XCTAssertTrue(info.headersEncrypted)
        XCTAssertTrue(info.isSolid, info.details)
        XCTAssertEqual(try extract(options.archivePath, password: "pw", into: "out").code, .ok)
        assertSourcesExtracted(into: "out")
    }

    func testSplitSizeBecomesRarVolumes() throws {
        var options = CompressOptions(archivePath: workspace.path("split.rar"))
        options.format = .rar5
        options.volumeSize = "300k"
        let call = try rarCall(options)
        let result = runRarJob(call.args, password: call.password)
        XCTAssertTrue(result.ok, result.output)
        let info = try XCTUnwrap(info(workspace.path("split.part1.rar")))
        XCTAssertTrue(info.details.contains("volume"), info.details)
    }

    func testRarOutputTellsAWrongPassword() throws {
        let archive = try makeRar("data.rar", ["-ppw"])
        let wrong = runRarJob(["t", "-p", "--", archive], password: "wrong")
        XCTAssertFalse(wrong.ok)
        XCTAssertTrue(wrong.wrongPassword, wrong.output)
        let right = runRarJob(["t", "-p", "--", archive], password: "pw")
        XCTAssertTrue(right.ok, right.output)
        XCTAssertFalse(right.wrongPassword)
    }

    /// The Quick Action modes on RAR, in a second copy of the app given the same rar (CommandLineModeTests).
    func testQuickActionModesWorkOnRar() throws {
        let archive = try makeRar("quick.rar")
        let extracted = try launchApp(["--extract-folder", archive])
        XCTAssertEqual(extracted.status, 0, extracted.output)
        assertSourcesExtracted(into: "quick")

        let tested = try launchApp(["--test", archive])
        XCTAssertTrue(tested.output.contains(try english("test_passed_title")), tested.output)

        // The copy reads the user's own settings for whatever it is not given; solid and the recovery record would show
        // in the archive's details
        let rarDefault = ["-RarPath", rar.url.path, "-DefaultFormat", "\(ArchiveFormat.rar5.rawValue)",
                          "-DefaultSolid", "NO", "-DefaultRecovery", "NO"]
        let compressed = try launchApp(rarDefault + ["--compress", workspace.path("src/a.txt")])
        XCTAssertEqual(compressed.status, 0, compressed.output)
        let info = try XCTUnwrap(info(workspace.path("src/a.rar")))
        XCTAssertEqual(info.details, "RAR 5")
        XCTAssertEqual(info.entries.map(\.name), ["a.txt"])
    }

    /// rar writes its temporary archive in its working directory. The test host's is /, as is the app's when Finder
    /// opens it, so Ops.add and Ops.delete run rar in the archive's folder; inheriting / failed with
    /// "Cannot create __rar_….rartemp".
    func testAddingAndDeletingGoThroughRar() throws {
        let archive = try makeRar("edit.rar")
        try Data("added\n".utf8).write(to: workspace.url("added.txt"))
        let added = workspace.path("added.txt")

        let before = try XCTUnwrap(info(archive))
        XCTAssertTrue(finished { Ops.add(info: before, items: [added], password: nil, host: nil, completion: $0) })
        let afterAdding = try XCTUnwrap(info(archive))
        XCTAssertTrue(afterAdding.entries.contains { $0.name == "added.txt" })

        XCTAssertTrue(finished { Ops.delete(info: afterAdding, names: ["a.txt"], password: nil, host: nil, completion: $0) })
        let names = try XCTUnwrap(info(archive)).entries.map(\.name)
        XCTAssertFalse(names.contains("a.txt"), "\(names)")
        XCTAssertTrue(names.contains("added.txt"), "\(names)")
    }

    /// rar packs exactly the chosen items. With -r it read each chosen file name as a mask for the folders below: a file
    /// whose name holds Turkish letters composed on disk, as shell tools, git and archives made elsewhere write them, was
    /// left out without an error, since Process hands names over decomposed, and a same-named file in a folder nobody
    /// chose went into the archive and, with "delete files after archiving", off the disk. Chosen folders, nested or
    /// empty, are still added whole.
    func testCompressTakesExactlyTheChosenItems() throws {
        _ = try workspace.makeDirectory("src/other")
        let notChosen = Data("not chosen\n".utf8)
        try notChosen.write(to: workspace.url("src/other/a.txt"))
        try workspace.writeComposed(Data("Türkçe\n".utf8), to: "src/büyük dosya.txt")
        try workspace.writeComposed(Data("iç içe\n".utf8), to: "src/Klasör ğ/iç/d.txt")
        try workspace.makeComposedDirectory("src/boş")
        let files = ["a.txt", "büyük dosya.txt", "sub/b.bin", "sub/çalışma ğüş.txt", "Klasör ğ/iç/d.txt"]
        let originals = files.map { workspace.contents("src/\($0)") }

        var options = CompressOptions(archivePath: workspace.path("chosen.rar"))
        options.format = .rar5
        options.deleteAfter = true
        let made = compress(["a.txt", "büyük dosya.txt", "sub", "Klasör ğ", "boş"].map { workspace.path("src/\($0)") }, options)
        XCTAssertTrue(made.ok)
        let entries = try XCTUnwrap(info(made.path)).entries.map(\.name)
        let expected = files + ["sub", "Klasör ğ", "Klasör ğ/iç", "boş"]
        XCTAssertEqual(Set(entries), Set(expected))
        XCTAssertEqual(entries.count, expected.count, "\(entries)")
        XCTAssertEqual(workspace.contents("src/other/a.txt"), notChosen, "a file nobody chose was deleted")
        XCTAssertFalse(workspace.exists("src/büyük dosya.txt"), "the chosen file was not moved into the archive")

        XCTAssertEqual(try extract(made.path, into: "out").code, .ok)
        XCTAssertEqual(files.map { workspace.contents("out/\($0)") }, originals)
        XCTAssertTrue(isDirectoryPath(workspace.path("out/boş")))
    }

    /// Ops.add hands rar exactly the chosen items as well, a dropped folder with everything in it.
    func testAddingTakesExactlyTheChosenItems() throws {
        let archive = try makeRar("edit.rar")
        _ = try workspace.makeDirectory("more/other")
        try Data("chosen\n".utf8).write(to: workspace.url("more/added.txt"))
        try Data("not chosen\n".utf8).write(to: workspace.url("more/other/added.txt"))
        try workspace.writeComposed(Data("Türkçe\n".utf8), to: "more/eklenen ğüş.txt")
        try workspace.writeComposed(Data("iç içe\n".utf8), to: "more/Yeni klasör/iç/e.txt")

        let before = try XCTUnwrap(info(archive))
        let items = ["added.txt", "eklenen ğüş.txt", "Yeni klasör"].map { workspace.path("more/\($0)") }
        XCTAssertTrue(finished { Ops.add(info: before, items: items, password: nil, host: nil, completion: $0) })
        let after = try XCTUnwrap(info(archive)).entries.map(\.name)
        let expected = ["added.txt", "eklenen ğüş.txt", "Yeni klasör", "Yeni klasör/iç", "Yeni klasör/iç/e.txt"]
        XCTAssertEqual(Set(after).subtracting(before.entries.map(\.name)), Set(expected))
        XCTAssertEqual(after.count, before.entries.count + expected.count, "\(after)")
    }

    /// Adding to an archive with encrypted names keeps them encrypted (-hp), and so does deleting from it.
    func testEncryptedNamesStayEncrypted() throws {
        let archive = try makeRar("hidden.rar", ["-hppw"])
        try Data("added\n".utf8).write(to: workspace.url("added.txt"))
        let added = workspace.path("added.txt")

        let before = try XCTUnwrap(info(archive, password: "pw"))
        XCTAssertTrue(finished { Ops.add(info: before, items: [added], password: "pw", host: nil, completion: $0) })
        guard case .wrongPassword = ArchiveReader.list(archive, password: nil) else { return XCTFail("the names are no longer encrypted") }
        let afterAdding = try XCTUnwrap(info(archive, password: "pw"))
        XCTAssertTrue(afterAdding.entries.contains { $0.name == "added.txt" })

        XCTAssertTrue(finished { Ops.delete(info: afterAdding, names: ["a.txt"], password: "pw", host: nil, completion: $0) })
        guard case .wrongPassword = ArchiveReader.list(archive, password: nil) else { return XCTFail("deleting decrypted the names") }
        XCTAssertFalse(try XCTUnwrap(info(archive, password: "pw")).entries.contains { $0.name == "a.txt" })
    }

    /// rar on macOS looks for default.sfx in the home directory, /usr/lib or /usr/local/lib rather than next to itself,
    /// and names a self-extracting archive .sfx. The app passes the module beside rar and asks for that name; a bare
    /// -sfx stopped with "Cannot open /usr/local/etc/default.sfx".
    func testSelfExtractingArchiveIsWrittenAsSfx() throws {
        var options = CompressOptions(archivePath: workspace.path("sfx.rar"))
        options.format = .rar5
        options.sfx = true
        let args = try rarCall(options).args
        XCTAssertTrue(args.contains("-sfx" + sfxModule), "\(args)")
        let result = runRarJob(args)
        XCTAssertTrue(result.ok, result.output)

        let written = workspace.path("sfx.sfx")
        XCTAssertEqual(options.writtenPath, written)
        XCTAssertFalse(workspace.exists("sfx.rar"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: written))
        XCTAssertEqual(workspace.contents("sfx.sfx")?.prefix(4), Data([0xCF, 0xFA, 0xED, 0xFE]), "not a 64-bit Mach-O")
        XCTAssertEqual(try XCTUnwrap(info(written)).details, "RAR 5")
        XCTAssertEqual(try extract(written, into: "out").code, .ok)
        assertSourcesExtracted(into: "out")
    }

    /// A self-extracting archive is RAR by its content, so adding to and deleting from it go to rar, which keeps it
    /// self-extracting; by its .sfx name it went to 7-Zip, which cannot write RAR.
    func testSelfExtractingArchiveIsChangedThroughRar() throws {
        let archive = try makeRar("tool.sfx", ["-sfx" + sfxModule])
        try Data("added\n".utf8).write(to: workspace.url("added.txt"))
        let added = workspace.path("added.txt")

        let before = try XCTUnwrap(info(archive))
        XCTAssertEqual(before.kind, .rar)
        XCTAssertTrue(finished { Ops.add(info: before, items: [added], password: nil, host: nil, completion: $0) })
        let afterAdding = try XCTUnwrap(info(archive))
        XCTAssertTrue(finished { Ops.delete(info: afterAdding, names: ["a.txt"], password: nil, host: nil, completion: $0) })

        let names = try XCTUnwrap(info(archive)).entries.map(\.name)
        XCTAssertTrue(names.contains("added.txt"), "\(names)")
        XCTAssertFalse(names.contains("a.txt"), "\(names)")
        XCTAssertEqual(workspace.contents("tool.sfx")?.prefix(4), Data([0xCF, 0xFA, 0xED, 0xFE]), "no longer self-extracting")
    }

    /// Ops.compress reports the file it wrote, which the callers reveal in Finder and open.
    func testCompressReportsTheSfxItWrote() {
        var options = CompressOptions(archivePath: workspace.path("made.rar"))
        options.format = .rar5
        options.sfx = true
        let made = compress(workspace.sources, options)
        XCTAssertTrue(made.ok)
        XCTAssertEqual(made.path, workspace.path("made.sfx"))
        XCTAssertTrue(workspace.exists("made.sfx"))
    }

    /// An earlier split RAR under the same name keeps every volume: rar wrote a new set over its first volumes and
    /// left the rest behind. The question it raises now gives the new set a free name.
    func testSplittingOverAnEarlierRarSetMakesANewOne() throws {
        func options(_ split: String) -> CompressOptions {
            var options = CompressOptions(archivePath: workspace.path("set.rar"))
            options.format = .rar5
            options.volumeSize = split
            return options
        }
        XCTAssertTrue(compress(workspace.sources, options("200k")).ok)
        let earlier = try workspace.files(startingWith: "set.part")
        XCTAssertGreaterThan(earlier.count, 2)

        let again = compress(workspace.sources, options("700k"))
        XCTAssertTrue(again.ok)
        XCTAssertEqual(again.path, workspace.path("set 2.part1.rar"))
        XCTAssertEqual(try workspace.files(startingWith: "set.part"), earlier, "the earlier set changed")
        XCTAssertEqual(try extract(again.path, into: "out").code, .ok)
        assertSourcesExtracted(into: "out")
    }

    /// A split RAR has no file under its own name; Ops.compress reports its first volume, .sfx when self-extracting.
    func testCompressReportsTheFirstRarVolume() throws {
        let fm = FileManager.default
        for (sfx, first) in [(false, "split.part1.rar"), (true, "split.part1.sfx")] {
            var options = CompressOptions(archivePath: workspace.path("split.rar"))
            options.format = .rar5
            options.volumeSize = "300k"
            options.sfx = sfx
            let made = compress(workspace.sources, options)
            XCTAssertTrue(made.ok, first)
            XCTAssertEqual(made.path, workspace.path(first))
            XCTAssertNotNil(info(made.path), first)
            for volume in try fm.contentsOfDirectory(atPath: workspace.root.path) where volume.hasPrefix("split.") {
                try fm.removeItem(atPath: workspace.path(volume))
            }
        }
    }

}

// MARK: - Names, passwords and large files

extension RARTests {
    /// Deleting takes the names the archive window lists, byte for byte as the archive holds them. rar got them as
    /// arguments, which Process hands over decomposed, so a name stored with letters such as ü or ş composed matched
    /// nothing: nothing was deleted, and the deletion reported success. A folder goes with everything in it, and a name
    /// with spaces at either end is the name it is; 7z, which gets the names as they are, does the same.
    func testDeletingFindsItemsWithTurkishNames() throws {
        for relative in ["pack/Klasör ğ/iç/d.txt", "pack/Klasör ğ/üst.txt", "pack/ boşluk .txt", "pack/çalışma.txt", "pack/a.txt"] {
            try workspace.writeComposed(Data("\(relative)\n".utf8), to: relative)
        }
        let doomed = ["pack/Klasör ğ", "pack/ boşluk .txt", "pack/çalışma.txt"]
        for format in [ArchiveFormat.rar5, .sevenZip] {
            var options = CompressOptions(archivePath: workspace.path("names.\(format.ext)"))
            options.format = format
            XCTAssertTrue(compress([workspace.path("pack")], options).ok, format.ext)
            let before = try XCTUnwrap(info(options.archivePath))
            // The names the window lists, as the archive holds them: composed, read from the disk
            let names = doomed.compactMap { wanted in before.entries.first { $0.name == wanted }?.name }
            XCTAssertEqual(names.count, doomed.count, "\(format.ext): \(before.entries.map(\.name))")
            XCTAssertTrue(names.contains { $0.unicodeScalars.contains("\u{011F}") }, "\(format.ext): the names are not stored composed")

            XCTAssertTrue(finished { Ops.delete(info: before, names: names, password: nil, host: nil, completion: $0) }, format.ext)
            let left = Set(try XCTUnwrap(info(options.archivePath)).entries.map(\.name))
            XCTAssertEqual(left, ["pack", "pack/a.txt"], format.ext)
        }
        let temporary = try FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())
        XCTAssertEqual(temporary.filter { $0.hasPrefix("rar-names-") }, [], "the name list was left")
    }

    // MARK: Passwords

    /// A password with Turkish letters, composed, as typing gives it.
    private var typed: String { "Şifre İğüöçı" }

    private func scalars(_ text: String?) -> [Unicode.Scalar]? { text.map { Array($0.unicodeScalars) } }

    /// rar is handed the password on its standard input. On its command line it arrived decomposed, as Process passes
    /// arguments, so an archive locked with letters such as ü or ş opened neither in the app's 7-Zip nor in rar with the
    /// password as typed.
    func testATurkishPasswordLocksTheArchiveAsTyped() throws {
        for encryptNames in [false, true] {
            var options = CompressOptions(archivePath: workspace.path("locked-\(encryptNames).rar"))
            options.format = .rar5
            options.password = typed
            options.encryptNames = encryptNames
            let made = compress(workspace.sources, options)
            XCTAssertTrue(made.ok)
            XCTAssertEqual(try extract(made.path, password: typed, into: "out-\(encryptNames)").code, .ok, "names encrypted: \(encryptNames)")
            assertSourcesExtracted(into: "out-\(encryptNames)")
            let tested = runRarJob(["t", "-p", "--", made.path], password: typed)
            XCTAssertTrue(tested.ok, tested.output)
        }
    }

    /// Earlier versions, and the original app, handed rar the password on its command line, decomposed. Their archives
    /// open with the password as typed: the decomposed form is tried before asking again, and the form that opens the
    /// archive is the one the app goes on with.
    func testAnArchiveLockedTheEarlierWayOpensWithThePasswordAsTyped() throws {
        let decomposed = scalars(typed.decomposedStringWithCanonicalMapping)
        // RarTool passes switches through Process, as those versions did
        let data = try makeRar("data.rar", ["-p\(typed)"])
        let names = try makeRar("names.rar", ["-hp\(typed)"])

        let dataInfo = try XCTUnwrap(info(data))
        let out = try workspace.makeDirectory("out")
        var used: String?
        XCTAssertTrue(finished { done in
            Ops.extract(.init(info: dataInfo, names: nil, dest: out), password: self.typed, host: nil) { ok, pw in
                used = pw
                done(ok, pw)
            }
        })
        assertSourcesExtracted(into: "out")
        XCTAssertEqual(scalars(used), decomposed)
        XCTAssertTrue(finished { Ops.test(info: dataInfo, password: typed, host: nil, completion: $0) })

        var password: String?
        var listed: ArchiveInfo?
        withEnvironment(["MACRAR_DEBUG_PASSWORD": typed]) { listed = Ops.listInteractive(archive: names, password: &password) }
        XCTAssertEqual(scalars(password), decomposed)
        let namesInfo = try XCTUnwrap(listed)
        XCTAssertTrue(finished { Ops.delete(info: namesInfo, names: ["a.txt"], password: typed, host: nil, completion: $0) })
        let left = try XCTUnwrap(info(names, password: typed.decomposedStringWithCanonicalMapping))
        XCTAssertFalse(left.entries.contains { $0.name == "a.txt" })
    }

    /// Files added to an archive whose files are encrypted, under a password other than its own, were locked with that
    /// one: the archive ended up under two passwords, neither of which opened it whole. The password is checked first, a
    /// mistyped one is asked again, cancelling writes nothing, and an archive locked the earlier way is added to under
    /// its own form.
    func testAddingFindsTheArchivesOwnPasswordFirst() throws {
        try Data("added\n".utf8).write(to: workspace.url("added.txt"))
        try Data("not added\n".utf8).write(to: workspace.url("skipped.txt"))
        var options = CompressOptions(archivePath: workspace.path("locked.rar"))
        options.format = .rar5
        options.password = typed
        XCTAssertTrue(compress(workspace.sources, options).ok)
        let locked = try XCTUnwrap(info(options.archivePath))

        let added = [workspace.path("added.txt")], skipped = [workspace.path("skipped.txt")]
        withEnvironment(["MACRAR_DEBUG_PASSWORD_RETRY": typed]) {
            XCTAssertTrue(finished { Ops.add(info: locked, items: added, password: "Şifre", host: nil, completion: $0) })
        }
        withEnvironment(["MACRAR_DEBUG_PASSWORD_RETRY": "__cancel__"]) {
            XCTAssertFalse(finished { Ops.add(info: locked, items: skipped, password: "Şifre", host: nil, completion: $0) })
        }
        let names = try XCTUnwrap(info(options.archivePath)).entries.map(\.name)
        XCTAssertTrue(names.contains("added.txt"))
        XCTAssertFalse(names.contains("skipped.txt"))
        XCTAssertEqual(run(.test(archive: options.archivePath, password: typed)).code, .ok, "the archive is under two passwords")

        let earlier = try makeRar("earlier.rar", ["-p\(typed)"])
        let earlierInfo = try XCTUnwrap(info(earlier))
        XCTAssertTrue(finished { Ops.add(info: earlierInfo, items: added, password: typed, host: nil, completion: $0) })
        XCTAssertEqual(run(.test(archive: earlier, password: typed.decomposedStringWithCanonicalMapping)).code, .ok)
    }

    /// The large files packed the way the Create Archive dialog has rar pack them: the progress names each file as rar
    /// takes it and reaches 100%, and what 7-Zip extracts again is what went in.
    func testLargeFilesAreNamedWhileRarPacksThem() throws {
        let files = try LargeFiles.locate()
        var options = CompressOptions(archivePath: workspace.path("large.rar"))
        options.format = .rar5
        guard case .rar(let args, _) = try XCTUnwrap(options.buildSteps(items: files).first).work else {
            throw XCTSkip("expected rar switches")
        }
        var events: [RarJob.Event] = []
        let result = runRarJob(args, cwd: workspace.root.path) { events.append($0) }
        XCTAssertTrue(result.ok, result.output)
        XCTAssertEqual(events.compactMap { if case .file(let name) = $0 { return name } else { return nil } }, files)
        XCTAssertEqual(events.last, .progress(100))

        XCTAssertEqual(try extract(options.archivePath, into: "out").code, .ok)
        for file in files {
            let name = (file as NSString).lastPathComponent
            XCTAssertEqual(try LargeFiles.digest(workspace.path("out/\(name)")), try LargeFiles.digest(file), name)
        }
    }
}
