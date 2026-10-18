import XCTest
@testable import MacRAR

/// The settings read and write through a store given its UserDefaults: here a suite of the tests' own, the same one
/// every time and emptied before and after each test, so the user's settings are never touched. Prefs is the app's
/// store, on the standard defaults.
final class PrefsStoreTests: XCTestCase {
    private static let suite = "MacRARTests-PrefsStore"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suite))
        defaults.removePersistentDomain(forName: Self.suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suite)
        defaults = nil
    }

    private func store(rar: Bool = false) -> PrefsStore { PrefsStore(defaults: defaults, rarAvailable: { rar }) }

    func testNothingSavedReadsAsTheDefaults() {
        let store = store()
        XCTAssertEqual(store.defaultFormat, .zip)
        XCTAssertEqual(self.store(rar: true).defaultFormat, .rar5)
        XCTAssertEqual(store.defaultLevel, 3)
        XCTAssertFalse(store.solid)
        XCTAssertFalse(store.recoveryRecord)
        XCTAssertTrue(store.revealAfterExtract)
        XCTAssertTrue(store.revealAfterCompress)
        XCTAssertTrue(store.checkUpdates)
    }

    /// The level stays within store (0) and best (5); a format the app no longer has reads as the default one.
    func testSavedValuesOutOfRangeReadAsTheNearestKnown() {
        defaults.set(9, forKey: "DefaultLevel")
        XCTAssertEqual(store().defaultLevel, 5)
        defaults.set(-2, forKey: "DefaultLevel")
        XCTAssertEqual(store().defaultLevel, 0)
        defaults.set(1, forKey: "DefaultFormat")
        XCTAssertEqual(store().defaultFormat, .zip)
        XCTAssertEqual(store(rar: true).defaultFormat, .rar5)
    }

    func testWhatIsSetIsSavedUnderItsKey() {
        let store = store()
        store.defaultFormat = .sevenZip
        store.defaultLevel = 5
        store.solid = true
        store.recoveryRecord = true
        store.revealAfterExtract = false
        store.revealAfterCompress = false
        store.checkUpdates = false
        let saved = defaults.persistentDomain(forName: Self.suite) ?? [:]
        XCTAssertEqual(saved as NSDictionary, [
            "DefaultFormat": ArchiveFormat.sevenZip.rawValue, "DefaultLevel": 5, "DefaultSolid": true, "DefaultRecovery": true,
            "RevealAfterExtract": false, "RevealAfterCompress": false, "CheckUpdates": false,
        ] as NSDictionary)
        XCTAssertEqual(self.store().defaultFormat, .sevenZip)
    }

    /// Prefs reads the app's own settings, the argument domain first, as the copies the tests start rely on
    /// (-RevealAfterExtract NO).
    func testPrefsIsTheAppsStore() {
        XCTAssertTrue(Prefs.store.defaults === UserDefaults.standard)
        let standard = UserDefaults.standard
        let arguments = standard.volatileDomain(forName: UserDefaults.argumentDomain)
        standard.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        standard.setVolatileDomain(arguments.merging(["RevealAfterExtract": "NO", "DefaultLevel": "9"]) { $1 },
                                   forName: UserDefaults.argumentDomain)
        defer {
            standard.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
        XCTAssertFalse(Prefs.revealAfterExtract)
        XCTAssertEqual(Prefs.defaultLevel, 5)
    }
}
