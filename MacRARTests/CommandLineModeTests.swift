import XCTest
@testable import MacRAR

/// Runs a second copy of the app with a command-line mode, as a Finder Quick Action does, and checks what
/// it leaves behind. MACRAR_DEBUG_CONFIRM prints the alerts that report a result, and the argument domain
/// keeps the result from being revealed in Finder. --set-default and --install-quick-actions change the
/// user's LaunchServices and Finder settings, so only their parsing and the workflows are tested
/// (LaunchArgumentsTests, QuickActionsTests).
final class CommandLineModeTests: XCTestCase {
    private struct Exit {
        let status: Int32
        let output: String
        let seconds: TimeInterval
    }

    private var workspace: Workspace!

    override func setUpWithError() throws {
        workspace = try Workspace()
    }

    override func tearDown() {
        workspace = nil
    }

    private func launchApp(_ arguments: [String], environment: [String: String] = [:],
                           file: StaticString = #filePath, line: UInt = #line) throws -> Exit {
        let process = Process()
        process.executableURL = try XCTUnwrap(Bundle.main.executableURL)
        process.arguments = ["-RevealAfterExtract", "NO", "-RevealAfterCompress", "NO"] + arguments
        // A fresh environment: the test host's XCTest variables would load the tests into the copy as well
        process.environment = [
            "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory(), "PATH": "/usr/bin:/bin",
            "MACRAR_LANG": "en", "MACRAR_NO_UPDATE_CHECK": "1", "MACRAR_DEBUG_CONFIRM": "1",
        ].merging(environment) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        let started = Date()
        try process.run()
        if finished.wait(timeout: .now() + 60) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            XCTFail("MacRAR \(arguments.joined(separator: " ")) did not finish", file: file, line: line)
        }
        let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Exit(status: process.terminationStatus, output: output, seconds: Date().timeIntervalSince(started))
    }

    private func makeZip(level: Int32 = -1) -> String {
        let archive = workspace.path("sample.zip")
        update(archive, workspace.sources, SevenZipBridge.UpdateOptions(format: "zip", level: level))
        return archive
    }

    private func english(_ key: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "en", withExtension: "json", subdirectory: "translations"))
        let table = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        return try XCTUnwrap(table[key], key)
    }

    func testExtractHere() throws {
        let exit = try launchApp(["--extract-here", makeZip()])
        XCTAssertEqual(exit.status, 0, exit.output)
        XCTAssertEqual(workspace.contents("a.txt"), workspace.contents("src/a.txt"))
        XCTAssertEqual(workspace.contents("sub/b.bin"), workspace.contents("src/sub/b.bin"))
    }

    func testExtractFolder() throws {
        let exit = try launchApp(["--extract-folder", makeZip()])
        XCTAssertEqual(exit.status, 0, exit.output)
        XCTAssertEqual(workspace.contents("sample/a.txt"), workspace.contents("src/a.txt"))
        XCTAssertEqual(workspace.contents("sample/sub/b.bin"), workspace.contents("src/sub/b.bin"))
    }

    func testTestReportsTheResult() throws {
        let archive = makeZip(level: 0)
        let passed = try launchApp(["--test", archive])
        XCTAssertTrue(passed.output.contains(try english("test_passed_title")), passed.output)

        // Stored, so the text sits in the archive as it is: changing it breaks the CRC
        let url = URL(fileURLWithPath: archive)
        var data = try Data(contentsOf: url)
        let text = try XCTUnwrap(data.range(of: Data("hello archive".utf8)))
        data.replaceSubrange(text, with: Data("HELLO ARCHIVE".utf8))
        try data.write(to: url)
        let failed = try launchApp(["--test", archive])
        XCTAssertTrue(failed.output.contains(try english("test_failed_title")), failed.output)
    }

    func testCompressUsesTheDefaultFormat() throws {
        for format in [ArchiveFormat.sevenZip, .zip] {
            let exit = try launchApp(["-DefaultFormat", "\(format.rawValue)", "--compress", workspace.path("src/a.txt")])
            XCTAssertEqual(exit.status, 0, exit.output)
            let listing = try SevenZipBridge.list(workspace.path("src/a.\(format.ext)"), password: nil).get()
            XCTAssertEqual(listing.items.map(\.path), ["a.txt"], format.ext)
        }
    }

    /// The two modes that ask first are still waiting on their window when the snapshot hook saves the
    /// open windows and quits, and they have written nothing.
    func testExtractToAndCompressDialogWaitForTheUser() throws {
        let archive = makeZip()
        let before = try FileManager.default.contentsOfDirectory(atPath: workspace.path("src")).sorted()
        for (index, arguments) in [["--extract-to", archive], ["--compress-dialog", workspace.path("src/a.txt")]].enumerated() {
            let exit = try launchApp(arguments, environment: ["MACRAR_SNAPSHOT": workspace.path("shot\(index)"), "MACRAR_SNAPSHOT_DELAY": "3"])
            XCTAssertEqual(exit.status, 0, exit.output)
            XCTAssertGreaterThanOrEqual(exit.seconds, 3, arguments[0])
            XCTAssertTrue(workspace.exists("shot\(index)-0.png"), "\(arguments[0]) showed no window")
        }
        XCTAssertFalse(workspace.exists("a.txt"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: workspace.path("src")).sorted(), before)
    }
}
