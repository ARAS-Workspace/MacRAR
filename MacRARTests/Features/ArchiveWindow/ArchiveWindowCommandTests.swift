import XCTest
@testable import MacRAR

/// The commands an archive window enables in the File and View menus, on its toolbar and in its context menu, for
/// each state it can be in: no archive, an archive, a file or a folder selected in it, and a compressed tar, which
/// takes no additions or deletions; and that each surface runs the commands it sends. The window is never shown; the
/// archives are opened in it directly, and what is extracted is not revealed in Finder (RevealAfterExtract NO in the
/// argument domain).
final class ArchiveWindowCommandTests: XCTestCase {
    private var workspace: Workspace!
    private var savedArguments: [String: Any] = [:]

    override func setUpWithError() throws {
        workspace = try Workspace()
        let defaults = UserDefaults.standard
        savedArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(savedArguments.merging(["RevealAfterExtract": "NO"]) { $1 }, forName: UserDefaults.argumentDomain)
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain)
        workspace = nil
    }

    /// What every state enables (the search field included), what an open archive adds whatever is selected, and
    /// what a selection adds.
    private static let always: Set = ["openArchive", "newArchive", "searchChanged:"]
    private static let archive = always.union([
        "extractHere", "extractToFolder", "extractTo", "testArchive", "showInfo", "expandAll", "collapseAll",
        "refresh", "revealArchive",
    ])
    private static let selection: Set = ["extractSelectedHere", "extractSelectedTo", "openSelected"]

    /// The commands enabled in each state; every other command on the three surfaces is disabled.
    private static let enabled: [String: Set<String>] = [
        "no archive": always.union(["addFiles"]),
        "an archive": archive.union(["addFiles"]),
        "a file selected": archive.union(selection).union(["addFiles", "deleteSelected", "quickLook"]),
        "a folder selected": archive.union(selection).union(["addFiles", "deleteSelected"]),
        "a compressed tar with a file selected": archive.union(selection).union(["quickLook"]),
    ]

    /// The commands each surface offers.
    private static let surfaces: [String: Set<String>] = [
        "menu bar": archive.subtracting(["searchChanged:"])
            .union(["extractSelectedHere", "extractSelectedTo", "addFiles", "deleteSelected", "quickLook"]),
        "toolbar": always.union(["extractTo", "extractHere", "extractToFolder", "testArchive", "addFiles",
                                 "deleteSelected", "showInfo"]),
        "context menu": selection.union(["deleteSelected", "quickLook"]),
    ]

    /// Whether the window enables each command a surface offers, by its name: the File and View menus, the toolbar's
    /// buttons as AppKit asks the window for them, and the context menu. The search field, which is no command, is named
    /// by its action.
    private func answers(_ controller: ArchiveWindowController) throws -> [String: [String: Bool]] {
        func menuAnswers(_ items: [NSMenuItem]) -> [String: Bool] {
            var answers: [String: Bool] = [:]
            // The menus' other items (Open Recent, Close, the ones AppKit adds) are not the window's
            for item in items {
                if let command = Command(sender: item) { answers[command.rawValue] = controller.validateMenuItem(item) }
            }
            return answers
        }
        let bar = try XCTUnwrap(NSApp.mainMenu?.items)
        let toolbar = try XCTUnwrap(controller.window?.toolbar)
        var toolbarAnswers: [String: Bool] = [:]
        for id in controller.toolbarDefaultItemIdentifiers(toolbar) {
            guard let item = controller.toolbar(toolbar, itemForItemIdentifier: id, willBeInsertedIntoToolbar: false),
                  let action = item.action else { continue }
            toolbarAnswers[controller.command(for: item)?.rawValue ?? NSStringFromSelector(action)] = controller.validateToolbarItem(item)
        }
        return [
            "menu bar": menuAnswers([1, 3].flatMap { bar[$0].submenu?.items ?? [] }),
            "toolbar": toolbarAnswers,
            "context menu": menuAnswers(controller.outline.menu?.items ?? []),
        ]
    }

    private func check(_ controller: ArchiveWindowController, _ state: String,
                       file: StaticString = #filePath, line: UInt = #line) throws {
        let enabled = try XCTUnwrap(Self.enabled[state])
        for (surface, answered) in try answers(controller) {
            XCTAssertEqual(Set(answered.keys), Self.surfaces[surface], "\(surface) offers other commands", file: file, line: line)
            for (command, isEnabled) in answered.sorted(by: { $0.key < $1.key }) {
                XCTAssertEqual(isEnabled, enabled.contains(command), "\(state), \(surface): \(command)", file: file, line: line)
            }
        }
    }

    private func select(_ name: String, in controller: ArchiveWindowController) throws {
        let outline = controller.outline
        let row = try XCTUnwrap((0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? Node)?.name == name }, name)
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func opened(_ archive: String) throws -> ArchiveWindowController {
        let controller = ArchiveWindowController()
        controller.open(archive)
        XCTAssertNotNil(controller.info, archive)
        return controller
    }

    func testEachStateEnablesTheCommandsItAllows() throws {
        let zip = workspace.path("pack.zip")
        update(zip, workspace.sources, SevenZipBridge.UpdateOptions(format: "zip"))
        let tar = workspace.path("pack.tar")
        update(tar, workspace.sources, SevenZipBridge.UpdateOptions(format: "tar"))
        let tgz = workspace.path("pack.tgz")
        update(tgz, [tar], SevenZipBridge.UpdateOptions(format: "gzip"))

        try check(ArchiveWindowController(), "no archive")
        let archive = try opened(zip)
        try check(archive, "an archive")
        try select("a.txt", in: archive)
        try check(archive, "a file selected")
        try select("sub", in: archive)
        try check(archive, "a folder selected")
        let compressedTar = try opened(tgz)
        try select("a.txt", in: compressedTar)
        try check(compressedTar, "a compressed tar with a file selected")
    }

    // MARK: Running the commands

    /// A ZIP of the sources in a folder of its own, so that what is extracted next to it stays apart.
    private func makeArchive(in folder: String) throws -> String {
        let archive = (try workspace.makeDirectory(folder) as NSString).appendingPathComponent("pack.zip")
        update(archive, workspace.sources, SevenZipBridge.UpdateOptions(format: "zip"))
        return archive
    }

    private func node(_ name: String, in controller: ArchiveWindowController) throws -> Node {
        let outline = controller.outline
        return try XCTUnwrap((0..<outline.numberOfRows).compactMap { outline.item(atRow: $0) as? Node }.first { $0.name == name }, name)
    }

    private func menuItem(_ command: Command) throws -> NSMenuItem {
        let items = try XCTUnwrap(NSApp.mainMenu?.items).flatMap { $0.submenu?.items ?? [] }
        return try XCTUnwrap(items.first { Command(sender: $0) == command }, command.rawValue)
    }

    private func contextItem(_ command: Command, of controller: ArchiveWindowController) throws -> NSMenuItem {
        try XCTUnwrap(controller.outline.menu?.items.first { Command(sender: $0) == command }, command.rawValue)
    }

    /// The toolbar button saved under `identifier`, as AppKit asks the window for it.
    private func button(_ identifier: String, of controller: ArchiveWindowController) throws -> NSToolbarItem {
        let toolbar = try XCTUnwrap(controller.window?.toolbar)
        let id = NSToolbarItem.Identifier(identifier)
        return try XCTUnwrap(controller.toolbar(toolbar, itemForItemIdentifier: id, willBeInsertedIntoToolbar: false), identifier)
    }

    /// Runs the main run loop until the operations started have finished, as their progress windows count them; an
    /// operation reports and reveals in the same turn that ends its count.
    private func waitForOperations(file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date(timeIntervalSinceNow: 60)
        while ProgressPanel.running > 0, Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
        XCTAssertEqual(ProgressPanel.running, 0, "an operation did not finish", file: file, line: line)
    }

    /// The View menu's Expand All and Collapse All, and Refresh, which reads the archive again once it has changed.
    func testTheMenuRunsTheViewCommands() throws {
        let archive = try makeArchive(in: "view")
        let controller = try opened(archive)
        controller.performCommand(try menuItem(.expandAll))
        XCTAssertTrue(controller.outline.isItemExpanded(try node("sub", in: controller)))
        controller.performCommand(try menuItem(.collapseAll))
        XCTAssertFalse(controller.outline.isItemExpanded(try node("sub", in: controller)))
        try Data("new\n".utf8).write(to: workspace.url("new.txt"))
        update(archive, [workspace.path("new.txt")], SevenZipBridge.UpdateOptions(format: "zip"))
        controller.performCommand(try menuItem(.refresh))
        XCTAssertEqual(controller.info?.entries.contains { $0.name == "new.txt" }, true)
    }

    /// The toolbar's Extract Here and Extract to Folder, each by the button the toolbar saves.
    func testTheToolbarExtracts() throws {
        let here = try opened(try makeArchive(in: "here"))
        here.performCommand(try button("extractHere", of: here))
        waitForOperations()
        XCTAssertEqual(workspace.contents("here/sub/b.bin"), workspace.contents("src/sub/b.bin"))
        let folder = try opened(try makeArchive(in: "folder"))
        folder.performCommand(try button("extractFolder", of: folder))
        waitForOperations()
        XCTAssertEqual(workspace.contents("folder/pack/a.txt"), workspace.contents("src/a.txt"))
        XCTAssertFalse(workspace.exists("folder/a.txt"))
    }

    /// The File menu's Test and Info report through the debug answers.
    func testTheMenuTestsAndDescribesTheArchive() throws {
        let controller = try opened(try makeArchive(in: "test"))
        let tested = try printed {
            controller.performCommand(try menuItem(.testArchive))
            waitForOperations()
        }
        XCTAssertTrue(tested.hasPrefix(loc.t("test_passed_title") + ": "), tested)
        let described = try printed { controller.performCommand(try menuItem(.showInfo)) }
        XCTAssertTrue(described.hasPrefix("pack.zip: "), described)
    }

    /// The context menu's Extract Selected Here takes the selection alone, and Delete from Archive removes it once
    /// MACRAR_DEBUG_CONFIRM has confirmed.
    func testTheContextMenuExtractsAndDeletesTheSelection() throws {
        let controller = try opened(try makeArchive(in: "context"))
        try select("a.txt", in: controller)
        controller.performCommand(try contextItem(.extractSelectedHere, of: controller))
        waitForOperations()
        XCTAssertEqual(workspace.contents("context/a.txt"), workspace.contents("src/a.txt"))
        XCTAssertFalse(workspace.exists("context/sub"))
        try select("a.txt", in: controller)
        controller.performCommand(try contextItem(.deleteSelected, of: controller))
        waitForOperations()
        XCTAssertEqual(controller.info?.entries.map(\.name).contains("a.txt"), false)
    }
}
