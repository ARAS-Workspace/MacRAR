import XCTest
@testable import MacRAR

/// The settings as the app reads them, given here in the argument domain (never saved), the way the copies the tests
/// start get theirs: a level out of range reads as the nearest one, a format the app does not have as the default, and
/// the switches as given.
final class PrefsTests: XCTestCase {
    /// Runs body with values on top of the argument domain, which takes them as strings the way launch arguments
    /// arrive, and puts the domain back afterwards.
    private func reading(_ values: [String: String], _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(arguments.merging(values) { $1 }, forName: UserDefaults.argumentDomain)
        defer {
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
        body()
    }

    func testALevelOutOfRangeReadsAsTheNearest() {
        reading(["DefaultLevel": "9"]) { XCTAssertEqual(Prefs.defaultLevel, 5) }
        reading(["DefaultLevel": "-2"]) { XCTAssertEqual(Prefs.defaultLevel, 0) }
        reading(["DefaultLevel": "1"]) { XCTAssertEqual(Prefs.defaultLevel, 1) }
    }

    /// 1 was a format once and is none now.
    func testAFormatTheAppDoesNotHaveReadsAsTheDefault() {
        reading(["DefaultFormat": "1"]) { XCTAssertEqual(Prefs.defaultFormat, RarTools.available ? .rar5 : .zip) }
        reading(["DefaultFormat": "\(ArchiveFormat.sevenZip.rawValue)"]) { XCTAssertEqual(Prefs.defaultFormat, .sevenZip) }
    }

    func testTheSwitchesReadAsGiven() {
        let off = ["RevealAfterExtract", "RevealAfterCompress", "CheckUpdates"]
        reading(Dictionary(uniqueKeysWithValues: off.map { ($0, "NO") })) {
            XCTAssertEqual([Prefs.revealAfterExtract, Prefs.revealAfterCompress, Prefs.checkUpdates], [false, false, false])
        }
        reading(["DefaultSolid": "YES", "DefaultRecovery": "YES"]) {
            XCTAssertEqual([Prefs.solid, Prefs.recoveryRecord], [true, true])
        }
    }
}
