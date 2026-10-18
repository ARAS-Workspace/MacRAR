import XCTest
@testable import MacRAR

/// The commands an archive window enables in the File and View menus, on its toolbar and in its context menu, for
/// each state it can be in: no archive, an archive, a file or a folder selected in it, and a compressed tar, which
/// takes no additions or deletions. The window is never shown; the archives are opened in it directly.
final class ArchiveWindowCommandTests: XCTestCase {
    private var workspace: Workspace!

    override func setUpWithError() throws {
        workspace = try Workspace()
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        workspace = nil
    }

    /// What every state enables (the search field included), what an open archive adds whatever is selected, and
    /// what a selection adds.
    private static let always: Set = ["openArchive:", "newArchive:", "searchChanged:"]
    private static let archive = always.union([
        "extractHere:", "extractToFolder:", "extractTo:", "testArchive:", "showInfo:", "expandAll:", "collapseAll:",
        "refresh:", "revealArchive:",
    ])
    private static let selection: Set = ["extractSelectedHere:", "extractSelectedTo:", "openSelected:"]

    /// The commands enabled in each state; every other command on the three surfaces is disabled.
    private static let enabled: [String: Set<String>] = [
        "no archive": always.union(["addFiles:"]),
        "an archive": archive.union(["addFiles:"]),
        "a file selected": archive.union(selection).union(["addFiles:", "deleteSelected:", "quickLook:"]),
        "a folder selected": archive.union(selection).union(["addFiles:", "deleteSelected:"]),
        "a compressed tar with a file selected": archive.union(selection).union(["quickLook:"]),
    ]

    /// The commands each surface offers.
    private static let surfaces: [String: Set<String>] = [
        "menu bar": archive.subtracting(["searchChanged:"])
            .union(["extractSelectedHere:", "extractSelectedTo:", "addFiles:", "deleteSelected:", "quickLook:"]),
        "toolbar": always.union(["extractTo:", "extractHere:", "extractToFolder:", "testArchive:", "addFiles:",
                                 "deleteSelected:", "showInfo:"]),
        "context menu": selection.union(["deleteSelected:", "quickLook:"]),
    ]

    /// Whether the window enables each command a surface offers, by selector name: the File and View menus, the
    /// toolbar's buttons as AppKit asks the window for them, and the context menu.
    private func answers(_ controller: ArchiveWindowController) throws -> [String: [String: Bool]] {
        func menuAnswers(_ items: [NSMenuItem]) -> [String: Bool] {
            var answers: [String: Bool] = [:]
            for item in items {
                // The menus' other items (Open Recent, Close, the ones AppKit adds) are not the window's
                guard let action = item.action, ArchiveWindowController.instancesRespond(to: action) else { continue }
                answers[NSStringFromSelector(action)] = controller.validateMenuItem(item)
            }
            return answers
        }
        let bar = try XCTUnwrap(NSApp.mainMenu?.items)
        let toolbar = try XCTUnwrap(controller.window?.toolbar)
        var toolbarAnswers: [String: Bool] = [:]
        for id in controller.toolbarDefaultItemIdentifiers(toolbar) {
            guard let item = controller.toolbar(toolbar, itemForItemIdentifier: id, willBeInsertedIntoToolbar: false),
                  let action = item.action else { continue }
            toolbarAnswers[NSStringFromSelector(action)] = controller.validateToolbarItem(item)
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
}
