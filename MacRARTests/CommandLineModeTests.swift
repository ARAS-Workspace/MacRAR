import XCTest
@testable import MacRAR

/// Runs a second copy of the app with a command-line mode, as a Finder Quick Action does (launchApp), and checks
/// what it leaves behind. --set-default and --install-quick-actions change the user's LaunchServices and Finder
/// settings, so only their parsing and the workflows are tested (LaunchArgumentsTests, QuickActionsTests).
final class CommandLineModeTests: XCTestCase {
    private var workspace: Workspace!

    override func setUpWithError() throws {
        workspace = try Workspace()
    }

    override func tearDown() {
        workspace = nil
    }

    private func makeZip(level: Int32 = -1) -> String {
        let archive = workspace.path("sample.zip")
        update(archive, workspace.sources, SevenZipBridge.UpdateOptions(format: "zip", level: level))
        return archive
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

    /// 7-Zip writes ZIP only with a password of printable ASCII. One with letters such as ü or ş is explained before
    /// anything is written, where 7-Zip stopped with "E_INVALIDARG"; an ASCII one with spaces and symbols is taken.
    func testAZipPasswordBeyondAsciiIsExplained() throws {
        let file = workspace.path("src/a.txt")
        let refused = try launchApp(["--compress", file], environment: ["MACRAR_DEBUG_FORMAT": "zip", "MACRAR_DEBUG_PASSWORD": "şifre"])
        XCTAssertTrue(refused.output.contains(try english("zip_password_not_ascii")), refused.output)
        XCTAssertFalse(workspace.exists("src/a.zip"))

        let taken = try launchApp(["--compress", file], environment: ["MACRAR_DEBUG_FORMAT": "zip", "MACRAR_DEBUG_PASSWORD": "pass ~!@"])
        XCTAssertEqual(taken.status, 0, taken.output)
        XCTAssertEqual(run(.test(archive: workspace.path("src/a.zip"), password: "pass ~!@")).code, .ok)
    }
}
