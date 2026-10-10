import XCTest
@testable import MacRAR

/// The command-line modes the README lists, as main.swift reads them from "open -n -a MacRAR --args ...".
final class LaunchArgumentsTests: XCTestCase {
    func testEveryModeParses() {
        let given = ["/a/x.zip", "/a/../b/y.part1.rar"]
        let paths = ["/a/x.zip", "/b/y.part1.rar"]
        let modes: [(flag: String, command: Command)] = [
            ("--extract-here", .extractHere(paths)),
            ("--extract-folder", .extractFolder(paths)),
            ("--extract-to", .extractTo(paths)),
            ("--test", .test(paths)),
            ("--compress", .compress(paths)),
            ("--compress-dialog", .compressDialog(paths)),
            ("--set-default", .setDefault),
            ("--install-quick-actions", .installQuickActions),
        ]
        for mode in modes {
            let launch = LaunchArguments([mode.flag] + given)
            XCTAssertEqual(launch.command, mode.command, mode.flag)
            XCTAssertEqual(launch.files, [], mode.flag)
        }
    }

    func testArgumentsMacOSAddsAreIgnored() {
        XCTAssertEqual(LaunchArguments(["-psn_0_12345", "--test", "/a/x.zip"]).command, .test(["/a/x.zip"]))
        let launch = LaunchArguments(["-NSDocumentRevisionsDebugMode", "YES", "/a/x.zip"])
        XCTAssertNil(launch.command)
        XCTAssertEqual(launch.files, ["/a/x.zip"])
    }

    func testFilesWithoutAFlagAreOpened() {
        let launch = LaunchArguments(["/a/x.zip", "/a/./y.7z"])
        XCTAssertNil(launch.command)
        XCTAssertEqual(launch.files, ["/a/x.zip", "/a/y.7z"])
    }

    func testAnUnknownFlagOpensItsFiles() {
        let launch = LaunchArguments(["--frobnicate", "/a/x.zip"])
        XCTAssertNil(launch.command)
        XCTAssertEqual(launch.files, ["/a/x.zip"])
    }
}
