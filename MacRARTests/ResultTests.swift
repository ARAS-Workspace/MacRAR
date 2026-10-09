import XCTest
@testable import MacRAR

/// The library's outcomes in the shape the operations branch on.
final class ResultTests: XCTestCase {
    private func result(_ code: SevenZipBridge.Code, error: String = "", messages: [String] = []) -> RarResult {
        RarResult(SevenZipBridge.Outcome(code: code, error: error, messages: messages))
    }

    func testSuccessAndWarnings() {
        XCTAssertTrue(result(.ok).ok)
        XCTAssertEqual(result(.ok).code, 0)
        let warning = result(.warning, messages: ["WARNING: Permission denied : /src/locked"])
        XCTAssertTrue(warning.ok)
        XCTAssertEqual(warning.code, 1)
        XCTAssertTrue(warning.errorSummary.contains("denied"))
    }

    func testPasswordProblemsAskAgain() {
        for code in [SevenZipBridge.Code.passwordRequired, .wrongPassword] {
            let mapped = result(code, error: "Wrong password")
            XCTAssertFalse(mapped.ok)
            XCTAssertTrue(mapped.wrongPassword, "\(code)")
        }
        XCTAssertFalse(result(.dataError, error: "CRC Failed : a.txt").wrongPassword)
    }

    func testFailuresCarryTheirMessage() {
        let failed = result(.dataError, error: "Data Error : sub/b.bin", messages: ["ERROR: Data Error : sub/b.bin"])
        XCTAssertFalse(failed.ok)
        XCTAssertEqual(failed.output, "ERROR: Data Error : sub/b.bin")
        let unlisted = result(.failed, error: "Disk full")
        XCTAssertTrue(unlisted.output.contains("Disk full"))
        XCTAssertTrue(result(.notArchive, error: "Cannot open the file as archive").notArchive)
        XCTAssertTrue(result(.cancelled).cancelled)
    }
}
