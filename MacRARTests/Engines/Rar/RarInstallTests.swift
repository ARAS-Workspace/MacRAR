import XCTest
@testable import MacRAR

/// Installing the RAR tool the user chose, into a scratch folder and never the app's own: RARLAB's tar.gz, its rar
/// folder and its program are taken with the download quarantine removed; anything else is refused before its
/// quarantine comes off, and the tool already installed stays.
final class RarInstallTests: XCTestCase {
    private var rar: RarTool!
    private var workspace: Workspace!
    private var target: String { workspace.path("installed") }
    private var installed: URL { URL(fileURLWithPath: target).appendingPathComponent("rar") }

    override func setUpWithError() throws {
        rar = try RarTool.locate()
        workspace = try Workspace()
    }

    override func tearDown() {
        workspace = nil
    }

    private func quarantine(_ path: String) {
        let value = Data("0083;00000000;Safari;".utf8)
        _ = value.withUnsafeBytes { setxattr(path, "com.apple.quarantine", $0.baseAddress, value.count, 0, XATTR_NOFOLLOW) }
    }

    /// RARLAB's download as a browser leaves it: the rar folder in a quarantined tar.gz.
    private func download() throws -> URL {
        let folder = rar.url.deletingLastPathComponent()
        let tarball = workspace.url("rarmacos.tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", tarball.path, "-C", folder.deletingLastPathComponent().path, folder.lastPathComponent]
        try tar.run()
        tar.waitUntilExit()
        XCTAssertEqual(tar.terminationStatus, 0)
        quarantine(tarball.path)
        return tarball
    }

    /// Another program under the name rar, quarantined like a download.
    private func impostor(_ name: String, copying program: String) throws -> URL {
        let folder = try workspace.makeDirectory(name)
        let path = (folder as NSString).appendingPathComponent("rar")
        try FileManager.default.copyItem(atPath: program, toPath: path)
        quarantine(path)
        return URL(fileURLWithPath: path)
    }

    private func assertRefused(_ source: URL, _ key: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try RarTools.install(from: source, into: target), file: file, line: line) { error in
            XCTAssertEqual((error as? RarTools.InstallError)?.message, loc.t(key), file: file, line: line)
        }
    }

    func testRarlabsDownloadIsInstalledWithoutItsQuarantine() throws {
        try RarTools.install(from: try download(), into: target)
        XCTAssertEqual(RarTools.reportedVersion(of: installed), RarTools.reportedVersion(of: rar.url))
        XCTAssertNil(Quarantine.value(of: installed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(target)/default.sfx"))
    }

    /// The whole way through the app's questions: MACRAR_DEBUG_RARTOOL chooses the tool already downloaded, and
    /// MACRAR_DEBUG_CHOOSE gives the panel RARLAB's tar.gz; the tool is installed where the questions are told to.
    func testTheToolChosenThroughTheQuestionsIsInstalled() throws {
        let tarball = try download()
        setDebugAnswers()
        defer { clearDebugAnswers() }
        withEnvironment(["MACRAR_DEBUG_RARTOOL": "choose", "MACRAR_DEBUG_CHOOSE": tarball.path]) {
            _ = printed { XCTAssertTrue(RarTools.askForTool(into: target)) }
        }
        XCTAssertEqual(RarTools.reportedVersion(of: installed), RarTools.reportedVersion(of: rar.url))
    }

    func testTheRarFolderAndTheProgramAreTakenToo() throws {
        try RarTools.install(from: rar.url.deletingLastPathComponent(), into: target)
        XCTAssertNotNil(RarTools.reportedVersion(of: installed))
        try RarTools.install(from: rar.url, into: target)
        XCTAssertNotNil(RarTools.reportedVersion(of: installed))
    }

    /// The light check: a Mach-O program carrying RARLAB's copyright. The tool cannot be run to ask it before its
    /// quarantine comes off, so an impostor is refused unrun, a script never gets to write its marker.
    func testAnotherProgramNamedRarIsRefusedUnrun() throws {
        XCTAssertTrue(RarTools.looksLikeRarlabRar(at: rar.url.path))
        assertRefused(try impostor("echo", copying: "/bin/echo"), "rar_tool_err_not_rarlab")

        let marker = workspace.path("ran")
        let script = workspace.path("script.sh")
        try "#!/bin/sh\ntouch '\(marker)'\necho 7.23\n".write(toFile: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
        assertRefused(try impostor("script", copying: script), "rar_tool_err_not_rarlab")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker), "the impostor ran")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target))
    }

    /// A RARLAB build that does not run here (another architecture, a damaged download) passes the light check and
    /// fails when the staged copy is asked its version; the tool already installed is only replaced after that.
    func testAFailedInstallKeepsTheToolAlreadyThere() throws {
        try RarTools.install(from: rar.url.deletingLastPathComponent(), into: target)
        let broken = try impostor("broken", copying: rar.url.path)
        let handle = try FileHandle(forWritingTo: broken)
        try handle.seek(toOffset: 16)
        try handle.write(contentsOf: Data(count: 4096))
        try handle.close()
        XCTAssertTrue(RarTools.looksLikeRarlabRar(at: broken.path))
        assertRefused(broken, "rar_tool_err_wrong_arch")
        XCTAssertNotNil(RarTools.reportedVersion(of: installed), "the installed tool is gone")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: workspace.root.path).filter { $0.contains(".installing-") }
        XCTAssertEqual(leftovers, [])
    }

    func testAFolderWithoutRarIsRefused() throws {
        assertRefused(URL(fileURLWithPath: try workspace.makeDirectory("empty")), "rar_tool_err_not_found")
    }
}
