import XCTest
@testable import MacRAR

/// RAR, the format the app is named after, with RARLAB's own rar (RarTool): archives rar makes are listed, extracted
/// and tested through the 7-Zip library, and the archives the app has rar create, add to and delete from come out as
/// asked. The app reaches rar through the RarPath setting, which each test points at RarTool in the argument domain
/// (never saved); alerts that report an error print instead of waiting (MACRAR_DEBUG_CONFIRM).
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
        setenv("MACRAR_DEBUG_CONFIRM", "1", 1)
    }

    override func tearDown() {
        if let savedArguments {
            unsetenv("MACRAR_DEBUG_CONFIRM")
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
        let made = try rar.run(["a", "-ma5", "-ep1", "-r", "-y"] + switches + ["--", archive] + workspace.sources, in: workspace.root.path)
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

    /// rar switches run the way the operations run them, through RarJob.
    private func runRarJob(_ args: [String]) -> RarResult {
        let job = RarJob()
        let done = expectation(description: "rar finished")
        var result: RarResult?
        job.start(args) { outcome in
            result = outcome
            done.fulfill()
        }
        withExtendedLifetime(job) { wait(for: [done], timeout: 120) }
        return result ?? RarResult(code: -1, output: "rar did not finish")
    }

    /// The switches the Create Archive dialog's choices become.
    private func rarSwitches(_ options: CompressOptions) throws -> [String] {
        guard case .rar(let args) = try XCTUnwrap(options.buildSteps(items: workspace.sources).first).work else {
            throw XCTSkip("expected rar switches")
        }
        return args
    }

    /// An operation such as Ops.add run to its completion.
    private func finished(_ operation: (@escaping (Bool, String?) -> Void) -> Void) -> Bool {
        let done = expectation(description: "operation finished")
        var succeeded = false
        operation { ok, _ in
            succeeded = ok
            done.fulfill()
        }
        wait(for: [done], timeout: 120)
        return succeeded
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
        let result = runRarJob(try rarSwitches(options))
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
        let result = runRarJob(try rarSwitches(options))
        XCTAssertTrue(result.ok, result.output)
        let info = try XCTUnwrap(info(workspace.path("split.part1.rar")))
        XCTAssertTrue(info.details.contains("volume"), info.details)
    }

    func testRarOutputTellsAWrongPassword() throws {
        let archive = try makeRar("data.rar", ["-ppw"])
        let wrong = runRarJob(["t", "-pwrong", "--", archive])
        XCTAssertFalse(wrong.ok)
        XCTAssertTrue(wrong.wrongPassword, wrong.output)
        let right = runRarJob(["t", "-ppw", "--", archive])
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

        let rarDefault = ["-RarPath", rar.url.path, "-DefaultFormat", "\(ArchiveFormat.rar5.rawValue)"]
        let compressed = try launchApp(rarDefault + ["--compress", workspace.path("src/a.txt")])
        XCTAssertEqual(compressed.status, 0, compressed.output)
        let info = try XCTUnwrap(info(workspace.path("src/a.rar")))
        XCTAssertEqual(info.details, "RAR 5")
        XCTAssertEqual(info.entries.map(\.name), ["a.txt"])
    }

    // MARK: Known issues
    // Each one fails today and is marked with XCTExpectFailure; once the app is fixed, XCTest reports the expected
    // failure as missing and the mark comes off, leaving the test to guard the fix.

    private static let workingDirectoryIssue = "rar runs in the app's working directory, /, and cannot create its temporary archive there"

    /// Ops.add and Ops.delete run rar without a working directory, so it inherits the app's: / when Finder opens the
    /// app, and in the test host. rar 7 writes its temporary archive there ("Cannot create __rar_….rartemp") and stops.
    /// Creating archives passes the archive's folder and works.
    func testAddingAndDeletingIsAKnownIssue() throws {
        let archive = try makeRar("edit.rar")
        try Data("added\n".utf8).write(to: workspace.url("added.txt"))
        let added = workspace.path("added.txt")

        let before = try XCTUnwrap(info(archive))
        XCTExpectFailure(Self.workingDirectoryIssue)
        XCTAssertTrue(finished { Ops.add(info: before, items: [added], password: nil, host: nil, completion: $0) })
        let afterAdding = try XCTUnwrap(info(archive))
        XCTAssertTrue(afterAdding.entries.contains { $0.name == "added.txt" })

        XCTAssertTrue(finished { Ops.delete(info: afterAdding, names: ["a.txt"], password: nil, host: nil, completion: $0) })
        let names = try XCTUnwrap(info(archive)).entries.map(\.name)
        XCTAssertFalse(names.contains("a.txt"), "\(names)")
        XCTAssertTrue(names.contains("added.txt"), "\(names)")
    }

    /// Adding to an archive with encrypted names keeps them encrypted (-hp); blocked by the same issue.
    func testAddingWithEncryptedNamesIsAKnownIssue() throws {
        let archive = try makeRar("hidden.rar", ["-hppw"])
        try Data("added\n".utf8).write(to: workspace.url("added.txt"))
        let added = workspace.path("added.txt")

        let before = try XCTUnwrap(info(archive, password: "pw"))
        XCTExpectFailure(Self.workingDirectoryIssue)
        XCTAssertTrue(finished { Ops.add(info: before, items: [added], password: "pw", host: nil, completion: $0) })
        guard case .wrongPassword = ArchiveReader.list(archive, password: nil) else { return XCTFail("the names are no longer encrypted") }
        XCTAssertTrue(try XCTUnwrap(info(archive, password: "pw")).entries.contains { $0.name == "added.txt" })
    }

    /// rar on macOS looks for default.sfx in the home directory, /usr/lib or /usr/local/lib rather than next to itself,
    /// and names the archive .sfx; the app passes a bare -sfx and expects the .rar it asked for.
    func testSelfExtractingArchiveIsAKnownIssue() throws {
        var options = CompressOptions(archivePath: workspace.path("sfx.rar"))
        options.format = .rar5
        options.sfx = true
        let result = runRarJob(try rarSwitches(options))
        XCTExpectFailure("rar -sfx finds no default.sfx, and would write sfx.sfx rather than sfx.rar")
        XCTAssertTrue(result.ok, result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: options.archivePath))
    }
}
