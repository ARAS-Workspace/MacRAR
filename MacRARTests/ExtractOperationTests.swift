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
        setenv("MACRAR_DEBUG_CONFIRM", "1", 1)
    }

    override func tearDown() {
        unsetenv("MACRAR_DEBUG_CONFIRM")
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
        return finished { Ops.extract(info: info, names: nil, dest: destination, password: password, host: nil, completion: $0) }
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

        try withEnvironment(["MACRAR_DEBUG_OVERWRITE": "cancel"]) { XCTAssertFalse(try extract(info, into: "out")) }
        try withEnvironment(["MACRAR_DEBUG_OVERWRITE": "skip"]) { XCTAssertTrue(try extract(info, into: "out")) }
        XCTAssertEqual(workspace.contents("out/a.txt"), changed)

        try withEnvironment(["MACRAR_DEBUG_OVERWRITE": "rename"]) { XCTAssertTrue(try extract(info, into: "out")) }
        XCTAssertEqual(workspace.contents("out/a.txt"), changed)
        let names = try FileManager.default.contentsOfDirectory(atPath: workspace.path("out"))
        let renamed = names.filter { $0 != "a.txt" && $0.hasPrefix("a") }
        XCTAssertEqual(renamed.count, 1, "\(renamed)")
        XCTAssertEqual(renamed.first.flatMap { workspace.contents("out/\($0)") }, original)

        try withEnvironment(["MACRAR_DEBUG_OVERWRITE": "overwrite"]) { XCTAssertTrue(try extract(info, into: "out")) }
        XCTAssertEqual(workspace.contents("out/a.txt"), original)
    }

    func testAWrongPasswordIsAskedAgain() throws {
        let hidden = workspace.path("hidden.7z")
        _ = try makeArchive("hidden.7z", password: "pw", encryptHeaders: true)
        withEnvironment(["MACRAR_DEBUG_PASSWORD": "wrong", "MACRAR_DEBUG_PASSWORD_RETRY": "pw"]) {
            var password: String?
            XCTAssertNotNil(Ops.listInteractive(archive: hidden, password: &password))
            XCTAssertEqual(password, "pw")
        }
        withEnvironment(["MACRAR_DEBUG_PASSWORD": "wrong", "MACRAR_DEBUG_PASSWORD_RETRY": "__cancel__"]) {
            var password: String?
            XCTAssertNil(Ops.listInteractive(archive: hidden, password: &password))
        }

        let info = try makeArchive("data.7z", password: "pw")
        XCTAssertTrue(info.hasEncryptedFiles)
        try withEnvironment(["MACRAR_DEBUG_PASSWORD": "wrong", "MACRAR_DEBUG_PASSWORD_RETRY": "pw"]) {
            XCTAssertTrue(try extract(info, into: "out"))
        }
        XCTAssertEqual(workspace.contents("out/sub/b.bin"), workspace.contents("src/sub/b.bin"))
    }
}
