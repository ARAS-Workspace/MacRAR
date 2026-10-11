import XCTest
@testable import MacRAR

/// A language chosen in Settings applies at once: to the menus, the archive windows, the Settings window and the
/// names of the Finder Quick Actions. The tests switch the app's own language, so each one puts back the language
/// and the saved choice it found.
final class LanguageSwitchTests: XCTestCase {
    private var original: LocalizationManager.Language!
    private var saved: Any?

    override func setUp() {
        original = loc.current
        saved = UserDefaults.standard.object(forKey: LocalizationManager.defaultsKey)
    }

    override func tearDown() {
        loc.current = original
        UserDefaults.standard.set(saved, forKey: LocalizationManager.defaultsKey)
    }

    /// The language the app is not in.
    private var other: LocalizationManager.Language { loc.current == .tr ? .en : .tr }

    private func strings(_ language: LocalizationManager.Language) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: language.rawValue, withExtension: "json", subdirectory: "translations"))
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    private func views<T: NSView>(_ type: T.Type, in root: NSView?) -> [T] {
        guard let root else { return [] }
        return root.subviews.flatMap { child in [child].compactMap { $0 as? T } + views(type, in: child) }
    }

    func testChoosingALanguageInSettingsAppliesEverywhere() throws {
        let target = other
        let text = try strings(target)
        let archiveWindow = ArchiveWindowController()
        archiveWindow.showWindow(nil)
        defer { archiveWindow.window?.orderOut(nil) }
        let settings = try XCTUnwrap(PreferencesWindowController.shared.window?.contentView)

        let languages = LocalizationManager.Language.allCases
        let popup = try XCTUnwrap(views(NSPopUpButton.self, in: settings).first {
            $0.itemTitles == languages.map { "\($0.flag) \($0.displayName)" }
        })
        popup.selectItem(at: try XCTUnwrap(languages.firstIndex(of: target)))
        // What AppKit does when the user picks an item
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(popup.action), to: popup.target, from: popup))
        XCTAssertEqual(loc.current, target)
        XCTAssertEqual(UserDefaults.standard.string(forKey: LocalizationManager.defaultsKey), target.rawValue)

        // Menus
        let menus = NSApp.mainMenu?.items.compactMap { $0.submenu?.title } ?? []
        XCTAssertTrue(menus.contains(try XCTUnwrap(text["menu_file"])), "\(menus)")
        let window = try XCTUnwrap(archiveWindow.window)
        XCTAssertTrue(NSApp.windowsMenu?.items.contains { $0.target as? NSWindow === window } ?? false, "the window left the Window menu")

        // Settings window
        XCTAssertEqual(PreferencesWindowController.shared.window?.title, text["prefs_title"])
        XCTAssertTrue(views(NSButton.self, in: settings).map(\.title).contains(try XCTUnwrap(text["compress_solid"])))

        // Archive window
        let outline = try XCTUnwrap(views(NSOutlineView.self, in: window.contentView).first)
        XCTAssertEqual(outline.tableColumn(withIdentifier: ArchiveWindowController.nameCol)?.title, text["column_name"])
        XCTAssertEqual(outline.menu?.items.first?.title, text["open"])
        XCTAssertTrue(window.toolbar?.items.map(\.label).contains(try XCTUnwrap(text["toolbar_extract"])) ?? false)
        let labels = views(NSTextField.self, in: window.contentView).map(\.stringValue)
        XCTAssertTrue(labels.contains(try XCTUnwrap(text["status_no_archive"])), "\(labels)")
        XCTAssertTrue(labels.contains(try XCTUnwrap(text["window_empty_hint"])), "\(labels)")
    }

    /// Only workflows that call this copy of the app are rewritten. The host itself never renames the real ones in
    /// ~/Library/Services: that is left to the copy in /Applications (QuickActions.ownedByThisCopy).
    func testQuickActionsThatCallThisAppTakeTheNewNames() throws {
        let workspace = try Workspace()
        let ours = try workspace.makeDirectory("ours")
        let others = try workspace.makeDirectory("others")
        QuickActions.installAll(in: ours, registerWithFinder: false)
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: ours))
        let foreign = "\(others)/MacRAR: Extract Here.workflow/Contents"
        try FileManager.default.createDirectory(atPath: foreign, withIntermediateDirectories: true)
        try "open -n -a '/Applications/Elsewhere/MacRAR.app' --args --extract-here"
            .write(toFile: "\(foreign)/document.wflow", atomically: true, encoding: .utf8)

        loc.current = other
        QuickActions.relocalize(in: ours, registerWithFinder: false)
        QuickActions.relocalize(in: others, registerWithFinder: false)

        let after = Set(try FileManager.default.contentsOfDirectory(atPath: ours))
        XCTAssertEqual(after, Set(QuickActions.actions.map { "\($0.name).workflow" }))
        XCTAssertNotEqual(after, before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: others), ["MacRAR: Extract Here.workflow"])
    }
}
