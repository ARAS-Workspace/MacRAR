import XCTest
@testable import MacRAR

/// The language layer on its own: an instance with defaults of its own, so the app's saved choice is untouched. The
/// suite is the same one every time and each test starts it empty: removing a suite leaves its file in
/// ~/Library/Preferences, so a suite named anew for each test left a file behind every run.
final class LocalizationManagerTests: XCTestCase {
    private let suiteName = "MacRARTests-LocalizationManager"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func text(_ key: String, in language: LocalizationManager.Language) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: language.rawValue, withExtension: "json", subdirectory: "translations"))
        return try XCTUnwrap(JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))[key], key)
    }

    func testLanguageIdentifiers() {
        XCTAssertEqual(LocalizationManager.Language(identifier: "tr-TR"), .tr)
        XCTAssertEqual(LocalizationManager.Language(identifier: "en-GB"), .en)
        XCTAssertEqual(LocalizationManager.Language(identifier: "de"), .en)
    }

    func testTheSavedChoiceWins() throws {
        defaults.set("tr", forKey: LocalizationManager.defaultsKey)
        let manager = LocalizationManager(defaults: defaults, environment: [:])
        XCTAssertEqual(manager.current, .tr)
        XCTAssertEqual(manager.t("menu_file"), try text("menu_file", in: .tr))
    }

    func testMacrarLangOverridesTheSavedChoice() {
        defaults.set("tr", forKey: LocalizationManager.defaultsKey)
        XCTAssertEqual(LocalizationManager(defaults: defaults, environment: ["MACRAR_LANG": "en"]).current, .en)
    }

    func testChoosingALanguageAppliesSavesAndAnnouncesIt() throws {
        let manager = LocalizationManager(defaults: defaults, environment: ["MACRAR_LANG": "en"])
        let announced = expectation(forNotification: LocalizationManager.didChange, object: manager)
        manager.current = .tr
        wait(for: [announced], timeout: 1)
        XCTAssertEqual(manager.t("menu_file"), try text("menu_file", in: .tr))
        XCTAssertEqual(defaults.string(forKey: LocalizationManager.defaultsKey), "tr")
    }

    func testChoosingTheCurrentLanguageChangesNothing() {
        let manager = LocalizationManager(defaults: defaults, environment: ["MACRAR_LANG": "en"])
        let announced = expectation(forNotification: LocalizationManager.didChange, object: manager)
        announced.isInverted = true
        manager.current = .en
        wait(for: [announced], timeout: 0.2)
        XCTAssertNil(defaults.string(forKey: LocalizationManager.defaultsKey))
    }
}
