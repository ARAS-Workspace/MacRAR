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

    /// --compress-dialog is still waiting on Create Archive's window when the snapshot hook saves the open windows and
    /// quits, and it has written nothing.
    func testTheCompressDialogWaitsForTheUser() throws {
        let before = try FileManager.default.contentsOfDirectory(atPath: workspace.path("src")).sorted()
        let exit = try launchApp(["--compress-dialog", workspace.path("src/a.txt")],
                                 environment: [.snapshot: workspace.path("shot"), .snapshotDelay: "3"])
        XCTAssertEqual(exit.status, 0, exit.output)
        XCTAssertGreaterThanOrEqual(exit.seconds, 3)
        XCTAssertTrue(workspace.exists("shot-0.png"), "--compress-dialog showed no window")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: workspace.path("src")).sorted(), before)
    }

    /// --extract-to asks for the destination folder, which MACRAR_DEBUG_CHOOSE answers in the copy; unanswered, the
    /// panel is cancelled and nothing is written. The panel used to come up and wait.
    func testExtractTo() throws {
        let archive = makeZip()
        let asked = "choose \(try english("panel_extract_destination"))"
        try FileManager.default.createDirectory(atPath: workspace.path("out"), withIntermediateDirectories: true)
        let chosen = try launchApp(["--extract-to", archive], environment: [.choose: workspace.path("out")])
        XCTAssertEqual(chosen.status, 0, chosen.output)
        XCTAssertTrue(chosen.output.contains(asked), chosen.output)
        XCTAssertEqual(workspace.contents("out/a.txt"), workspace.contents("src/a.txt"))
        XCTAssertEqual(workspace.contents("out/sub/b.bin"), workspace.contents("src/sub/b.bin"))

        let cancelled = try launchApp(["--extract-to", archive])
        XCTAssertEqual(cancelled.status, 0, cancelled.output)
        XCTAssertTrue(cancelled.output.contains(asked), cancelled.output)
        XCTAssertFalse(workspace.exists("a.txt"))
        XCTAssertFalse(workspace.exists("sample"))
    }

    /// 7-Zip writes ZIP only with a password of printable ASCII. One with letters such as ü or ş is explained before
    /// anything is written, where 7-Zip stopped with "E_INVALIDARG"; an ASCII one with spaces and symbols is taken.
    func testAZipPasswordBeyondAsciiIsExplained() throws {
        let file = workspace.path("src/a.txt")
        let refused = try launchApp(["--compress", file], environment: [.format: "zip", .password: "şifre"])
        XCTAssertTrue(refused.output.contains(try english("zip_password_not_ascii")), refused.output)
        XCTAssertFalse(workspace.exists("src/a.zip"))

        let taken = try launchApp(["--compress", file], environment: [.format: "zip", .password: "pass ~!@"])
        XCTAssertEqual(taken.status, 0, taken.output)
        XCTAssertEqual(run(.test(archive: workspace.path("src/a.zip"), password: "pass ~!@")).code, .ok)
    }
}
