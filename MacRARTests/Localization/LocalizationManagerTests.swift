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
        XCTAssertEqual(LocalizationManager(defaults: defaults, environment: [DebugVariable.language.rawValue: "en"]).current, .en)
    }

    /// The menus, the AppKit windows and the Quick Actions apply the language on didChange: it comes once, before
    /// the setter returns, and finds the new strings and the saved choice in place.
    func testChoosingALanguageAppliesSavesAndAnnouncesItOnce() throws {
        let manager = LocalizationManager(defaults: defaults, environment: [DebugVariable.language.rawValue: "en"])
        var announced: [String] = []
        let observer = NotificationCenter.default.addObserver(forName: LocalizationManager.didChange, object: manager,
                                                              queue: nil) { _ in
            let saved = self.defaults.string(forKey: LocalizationManager.defaultsKey) ?? "unsaved"
            announced.append("\(manager.current.rawValue) \(manager.t("menu_file")) \(saved)")
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        manager.current = .tr
        XCTAssertEqual(announced, ["tr \(try text("menu_file", in: .tr)) tr"])
    }

    func testChoosingTheCurrentLanguageChangesNothing() {
        let manager = LocalizationManager(defaults: defaults, environment: [DebugVariable.language.rawValue: "en"])
        let announced = expectation(forNotification: LocalizationManager.didChange, object: manager)
        announced.isInverted = true
        manager.current = .en
        wait(for: [announced], timeout: 0.2)
        XCTAssertNil(defaults.string(forKey: LocalizationManager.defaultsKey))
    }

    /// Operations read their texts on their own threads, while the main thread may be changing the language.
    func testTextsCanBeReadOffTheMainThreadWhileTheLanguageChanges() throws {
        let manager = LocalizationManager(defaults: defaults, environment: [DebugVariable.language.rawValue: "en"])
        let texts = Set(try LocalizationManager.Language.allCases.map { try text("menu_file", in: $0) })
        let readers = 4
        let read = expectation(description: "every text read off the main thread is one of the two")
        read.expectedFulfillmentCount = readers
        for _ in 0..<readers {
            DispatchQueue.global().async {
                if (0..<2_000).allSatisfy({ _ in texts.contains(manager.t("menu_file")) }) { read.fulfill() }
            }
        }
        for _ in 0..<100 {
            for language in LocalizationManager.Language.allCases { manager.current = language }
        }
        wait(for: [read], timeout: 10)
    }
}
