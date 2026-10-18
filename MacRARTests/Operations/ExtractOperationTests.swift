import XCTest
@testable import MacRAR

/// Extracting the way the app does (Ops.extract and Ops.listInteractive): the archive's quarantine is carried over to
/// what it writes, existing items follow the answer to the overwrite question, and a wrong password is asked again.
/// MACRAR_DEBUG_OVERWRITE and MACRAR_DEBUG_PASSWORD(_RETRY) answer the questions; MACRAR_DEBUG_CONFIRM keeps an error
/// from waiting for a click.
final class ExtractOperationTests: XCTestCase {
    private var workspace: Workspace!

    override func setUpWithError() throws {
        workspace = try Workspace()
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        workspace = nil
    }

    private func makeArchive(_ name: String, password: String? = nil, encryptHeaders: Bool = false) throws -> ArchiveInfo {
        var options = SevenZipBridge.UpdateOptions(format: "7z", password: password)
        options.encryptHeaders = encryptHeaders
        update(workspace.path(name), workspace.sources, options)
        guard case .ok(let info) = ArchiveReader.list(workspace.path(name), password: password) else {
            throw XCTSkip("\(name) did not list")
        }
        return info
    }

    private func extract(_ info: ArchiveInfo, into folder: String, password: String? = nil) throws -> Bool {
        let destination = try workspace.makeDirectory(folder)
        return finished { Ops.extract(.init(info: info, names: nil, dest: destination), password: password, host: nil, completion: $0) }
    }

    /// The app stays busy (Dialogs.isBusy) until the extraction has carried the quarantine over, so the questions it
    /// asks on its own wait for it. The step runs once the job and its progress window have ended; for 4000 items it
    /// took about 80 ms, during which the app counted as idle.
    func testTheAppStaysBusyWhileTheQuarantineIsCarriedOver() throws {
        let many = try workspace.makeDirectory("many")
        for index in 0..<4000 { try Data("\(index)".utf8).write(to: URL(fileURLWithPath: "\(many)/\(index).txt")) }
        var options = SevenZipBridge.UpdateOptions(format: "7z")
        options.level = 0
        let archive = workspace.path("many.7z")
        update(archive, [many], options)
        let quarantine = Data("0083;66f1a2b3;Safari;".utf8)
        _ = quarantine.withUnsafeBytes { setxattr(archive, "com.apple.quarantine", $0.baseAddress, quarantine.count, 0, 0) }
        guard case .ok(let info) = ArchiveReader.list(archive, password: nil) else { return XCTFail("not listed") }
        let destination = try workspace.makeDirectory("out")

        var done = false, idle = 0
        let deadline = Date(timeIntervalSinceNow: 60)
        Ops.extract(.init(info: info, names: nil, dest: destination), password: nil, host: nil) { _, _ in done = true }
        while !done, Date() < deadline {
            if !Dialogs.isBusy { idle += 1 }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
        }
        XCTAssertTrue(done)
        XCTAssertEqual(idle, 0, "the app was idle while the extraction ran")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertFalse(Dialogs.isBusy, "the extraction still counts once it has ended")
    }

    /// Items an archive marks read-only get the archive's quarantine too, and keep their mode: 7-Zip writes them
    /// read-only, the quarantine could not be set on them, and a downloaded read-only script came out untagged.
    func testReadOnlyItemsCarryTheQuarantine() throws {
        let archive = workspace.path("readonly.zip")
        try HostileArchive.zip([
            HostileArchive.ZipEntry(name: "run.command", data: Data("echo hi\n".utf8), mode: 0o100555),
            HostileArchive.ZipEntry(name: "locked/", data: Data(), mode: 0o040555),
            HostileArchive.ZipEntry(name: "locked/inner.txt", data: Data("x".utf8), mode: 0o100444),
        ]).write(to: URL(fileURLWithPath: archive))
        let quarantine = Data("0083;66f1a2b3;Safari;".utf8)
        _ = quarantine.withUnsafeBytes { setxattr(archive, "com.apple.quarantine", $0.baseAddress, quarantine.count, 0, 0) }
        guard case .ok(let info) = ArchiveReader.list(archive, password: nil) else { return XCTFail("not listed") }
        let destination = try workspace.makeDirectory("readonly")
        XCTAssertTrue(finished { Ops.extract(.init(info: info, names: nil, dest: destination), password: nil, host: nil, completion: $0) })
        for (item, mode) in [("run.command", 0o555), ("locked/inner.txt", 0o444)] {
            let path = workspace.path("readonly/\(item)")
            XCTAssertEqual(Quarantine.value(of: path), quarantine, item)
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            XCTAssertEqual((attributes[.posixPermissions] as? Int).map { $0 & 0o777 }, mode, "\(item) kept its mode")
        }
        XCTAssertEqual(Quarantine.value(of: workspace.path("readonly/locked")), quarantine, "the folder")
        // The workspace goes in tearDown, which a read-only folder would stop
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: workspace.path("readonly/locked"))
    }

    private let extracted = ["a.txt", "sub", "sub/b.bin", "sub/çalışma ğüş.txt"]

    /// An archive downloaded from the internet hands its quarantine to every item it writes, so what comes out of it
    /// still meets Gatekeeper; an archive that has none passes none on.
    func testExtractedItemsCarryTheArchivesQuarantine() throws {
        let info = try makeArchive("download.7z")
        let quarantine = Data("0083;66f1a2b3;Safari;".utf8)
        _ = quarantine.withUnsafeBytes { setxattr(info.path, "com.apple.quarantine", $0.baseAddress, quarantine.count, 0, 0) }
        XCTAssertTrue(try extract(info, into: "out"))
        for item in extracted {
            XCTAssertEqual(Quarantine.value(of: workspace.path("out/\(item)")), quarantine, item)
        }

        let local = try makeArchive("local.7z")
        XCTAssertTrue(try extract(local, into: "plain"))
        for item in extracted {
            XCTAssertNil(Quarantine.value(of: workspace.path("plain/\(item)")), item)
        }
    }

    func testExtractingOverExistingItemsFollowsTheAnswer() throws {
        let info = try makeArchive("plain.7z")
        XCTAssertTrue(try extract(info, into: "out"))
        let original = workspace.contents("src/a.txt")
        let changed = Data("changed".utf8)
        try changed.write(to: workspace.url("out/a.txt"))

        try withEnvironment([.overwrite: "cancel"]) { XCTAssertFalse(try extract(info, into: "out")) }
        try withEnvironment([.overwrite: "skip"]) { XCTAssertTrue(try extract(info, into: "out")) }
        XCTAssertEqual(workspace.contents("out/a.txt"), changed)

        try withEnvironment([.overwrite: "rename"]) { XCTAssertTrue(try extract(info, into: "out")) }
        XCTAssertEqual(workspace.contents("out/a.txt"), changed)
        let names = try FileManager.default.contentsOfDirectory(atPath: workspace.path("out"))
        let renamed = names.filter { $0 != "a.txt" && $0.hasPrefix("a") }
        XCTAssertEqual(renamed.count, 1, "\(renamed)")
        XCTAssertEqual(renamed.first.flatMap { workspace.contents("out/\($0)") }, original)

        try withEnvironment([.overwrite: "overwrite"]) { XCTAssertTrue(try extract(info, into: "out")) }
        XCTAssertEqual(workspace.contents("out/a.txt"), original)
    }

    func testAWrongPasswordIsAskedAgain() throws {
        let hidden = workspace.path("hidden.7z")
        _ = try makeArchive("hidden.7z", password: "pw", encryptHeaders: true)
        withEnvironment([.password: "wrong", .passwordRetry: "pw"]) {
            var password: String?
            XCTAssertNotNil(Ops.listInteractive(archive: hidden, password: &password))
            XCTAssertEqual(password, "pw")
        }
        withEnvironment([.password: "wrong", .passwordRetry: "__cancel__"]) {
            var password: String?
            XCTAssertNil(Ops.listInteractive(archive: hidden, password: &password))
        }

        let info = try makeArchive("data.7z", password: "pw")
        XCTAssertTrue(info.hasEncryptedFiles)
        try withEnvironment([.password: "wrong", .passwordRetry: "pw"]) {
            XCTAssertTrue(try extract(info, into: "out"))
        }
        XCTAssertEqual(workspace.contents("out/sub/b.bin"), workspace.contents("src/sub/b.bin"))
    }
}
