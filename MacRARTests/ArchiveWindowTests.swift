import XCTest
@testable import MacRAR

/// Archive windows the way the user reaches them: what is dropped onto an open archive goes into it, the archive is
/// never packed into itself, and a file that does not open leaves the windows the user had. Drops go through
/// handleDrop, as AppKit's drop does, and the app's questions get the tests' debug answers. Each test starts and ends
/// with the host as it launched, one empty window. RAR archives are made and changed with RarTool when it is fetched.
final class ArchiveWindowTests: XCTestCase {
    private var workspace: Workspace!
    private var app: AppDelegate!
    private var rar: RarTool?
    private var savedArguments: [String: Any]?

    override func setUpWithError() throws {
        workspace = try Workspace()
        app = try XCTUnwrap(AppDelegate.shared)
        rar = try? RarTool.locate()
        if let rar {
            let defaults = UserDefaults.standard
            let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
            savedArguments = arguments
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(arguments.merging(["RarPath": rar.url.path]) { $1 }, forName: UserDefaults.argumentDomain)
        }
        setDebugAnswers()
        settle()
    }

    override func tearDown() {
        settle()
        clearDebugAnswers()
        if let savedArguments {
            UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            UserDefaults.standard.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain)
        }
        savedArguments = nil
        workspace = nil
    }

    // MARK: Helpers

    /// Leaves the app's windows as the host launched with them: one empty window.
    private func settle() {
        let empty = app.windows.first { $0.info == nil && $0.archivePath == nil } ?? app.showEmptyWindow()
        for controller in app.windows where controller !== empty { controller.close() }
        empty.showWindow(nil)
    }

    /// The formats the drops are tried on: 7z and ZIP through 7-Zip, RAR through rar when it is fetched.
    private var formats: [String] { ["7z", "zip"] + (rar == nil ? [] : ["rar"]) }

    /// An archive at `relative` holding `sources`, written by 7-Zip or, for .rar, by rar.
    private func makeArchive(_ relative: String, of sources: [String]? = nil) throws -> String {
        let archive = workspace.path(relative)
        let items = sources ?? workspace.sources
        if (relative as NSString).pathExtension == "rar" {
            let rar = try XCTUnwrap(rar)
            let made = try rar.run(RarRunner.addArguments + ["-ma5", "--", archive] + items, in: workspace.root.path)
            XCTAssertEqual(made.status, 0, made.output)
        } else {
            update(archive, items, SevenZipBridge.UpdateOptions(format: (relative as NSString).pathExtension))
        }
        return archive
    }

    /// A window with `archive` open in it, outside the app's list of windows: a target to drop onto.
    private func window(showing archive: String) throws -> ArchiveWindowController {
        let controller = ArchiveWindowController()
        controller.showWindow(nil)
        controller.open(archive)
        XCTAssertNotNil(controller.info, "\(archive) did not open")
        addTeardownBlock { controller.close() }
        return controller
    }

    /// The names in an archive, composed (NFC) so that Turkish names compare as typed.
    private func names(in archive: String) -> Set<String> {
        guard case .ok(let info) = ArchiveReader.list(archive, password: nil) else { return [] }
        return Set(info.entries.map { $0.name.precomposedStringWithCanonicalMapping })
    }

    private func names(_ controller: ArchiveWindowController) -> Set<String> {
        Set(controller.info?.entries.map { $0.name.precomposedStringWithCanonicalMapping } ?? [])
    }

    /// Runs the main loop until `condition` holds or `timeout` passes, and says whether it held.
    private func eventually(timeout: TimeInterval = 60, _ condition: () -> Bool) -> Bool {
        let end = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < end { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
        return condition()
    }

    // MARK: Drops

    /// Upstream 1.4.3 (533ce7e): archives dropped onto an open archive together with other items were left out
    /// without a word, while the rest went in; every dropped item should go in.
    func testFilesAndArchivesDroppedTogetherAreAllAddedIsAKnownIssue() throws {
        let extra = try makeArchive("extra.zip", of: [workspace.path("src/a.txt")])
        try Data("note\n".utf8).write(to: workspace.url("note.txt"))
        let turkish = "öğrenci notu.txt".precomposedStringWithCanonicalMapping
        try workspace.writeComposed(Data("not\n".utf8), to: turkish)
        for format in formats {
            let target = try window(showing: try makeArchive("target.\(format)"))
            target.handleDrop([URL(fileURLWithPath: extra), workspace.url("note.txt"), workspace.url(turkish)])
            XCTAssertTrue(eventually { names(target).contains("note.txt") }, "\(format): nothing was added")
            XCTAssertTrue(names(target).contains(turkish), "\(format): \(names(target))")
            XCTExpectFailure("\(format): an archive dropped with other items is left out") {
                XCTAssertTrue(names(target).contains("extra.zip"), "\(format): \(names(target))")
            }
        }
    }

    /// Archives dropped on their own onto an open archive open in windows of their own; nothing is added.
    func testArchivesDroppedAloneOpenInTheirOwnWindows() throws {
        let target = try window(showing: try makeArchive("target.7z"))
        let other = try makeArchive("other.zip")
        let before = names(target)
        target.handleDrop([URL(fileURLWithPath: other)])
        XCTAssertTrue(app.windows.contains { $0.archivePath.map(AppDelegate.resolved) == AppDelegate.resolved(other) },
                      "the dropped archive did not open")
        XCTAssertEqual(names(target), before)
        XCTAssertEqual(names(in: target.archivePath ?? ""), before)
    }

    /// 7-Zip packs a copy of the archive it updates when the archive is among the items, and rar leaves it out: the
    /// open archive dropped onto its own window with other items never ends up inside itself.
    func testTheOpenArchiveDroppedWithOtherItemsIsNotPackedIntoItself() throws {
        try Data("note\n".utf8).write(to: workspace.url("note.txt"))
        for format in formats {
            let archive = try makeArchive("own.\(format)")
            let target = try window(showing: archive)
            target.handleDrop([URL(fileURLWithPath: archive), workspace.url("note.txt")])
            XCTAssertTrue(eventually { names(target).contains("note.txt") }, "\(format): nothing was added")
            XCTAssertFalse(names(target).contains("own.\(format)"), "\(format): the archive was packed into itself")
            XCTAssertEqual(run(.test(archive: archive, password: nil)).code, .ok, format)
        }
    }

    /// The folder that holds the open archive, added to it by a drop or Add Files: 7-Zip packs a copy of the archive
    /// along with the folder's other items, and rar leaves it out. The archive should never end up inside itself.
    func testAFolderHoldingTheOpenArchiveIsNotPackedIntoItIsAKnownIssue() throws {
        for format in formats {
            let folder = try workspace.makeDirectory("box-\(format)")
            let archive = try makeArchive("box-\(format)/in.\(format)", of: [workspace.path("src/a.txt")])
            try Data("n\n".utf8).write(to: workspace.url("box-\(format)/n.txt"))
            guard case .ok(let info) = ArchiveReader.list(archive, password: nil) else { return XCTFail("\(format) did not list") }
            _ = finished { Ops.add(info: info, items: [folder], password: nil, host: nil, completion: $0) }
            let inside = "box-\(format)/in.\(format)"
            if format == "rar" {
                XCTAssertFalse(names(in: archive).contains(inside), "rar packed the archive into itself")
            } else {
                XCTExpectFailure("\(format): 7-Zip packs a copy of the archive into itself") {
                    XCTAssertFalse(names(in: archive).contains(inside), "\(format): \(names(in: archive))")
                }
            }
        }
    }

    // MARK: Failed opens

    /// A file that does not open, from Finder, dropped onto the empty window or locked with a password the user does
    /// not give, leaves the empty window the user had. Upstream 1.4.3 (533ce7e) found the window closed whenever
    /// another one was open.
    func testAFailedOpenKeepsTheEmptyWindowTheUserHadIsAKnownIssue() throws {
        let broken = workspace.path("broken.rar")
        try Data(repeating: 0x41, count: 4096).write(to: URL(fileURLWithPath: broken))
        var locked = SevenZipBridge.UpdateOptions(format: "7z", password: "pw")
        locked.encryptHeaders = true
        update(workspace.path("locked.7z"), workspace.sources, locked)
        let shown = ArchiveWindowController()
        app.windows.append(shown)
        shown.showWindow(nil)
        shown.open(try makeArchive("shown.zip"))

        let attempts: [(String, (ArchiveWindowController) -> Void)] = [
            ("opened from Finder", { _ in self.app.openArchive(broken, reuse: nil) }),
            ("dropped onto the empty window", { $0.handleDrop([URL(fileURLWithPath: broken)]) }),
            ("password not given", { _ in self.app.openArchive(self.workspace.path("locked.7z"), reuse: nil) }),
        ]
        for (attempt, open) in attempts {
            let empty = app.windows.first { $0.info == nil && $0.archivePath == nil } ?? app.showEmptyWindow()
            open(empty)
            XCTExpectFailure("\(attempt): the empty window is closed") {
                XCTAssertTrue(app.windows.contains { $0 === empty } && empty.window?.isVisible == true, attempt)
            }
            XCTAssertTrue(app.windows.contains { $0 === shown } && shown.info != nil, "\(attempt): the archive window changed")
        }
    }

    /// The window a file that does not open was given closes again, and none is left behind empty.
    func testAFailedOpenLeavesNoWindowOfItsOwn() throws {
        let broken = workspace.path("broken.rar")
        try Data(repeating: 0x41, count: 4096).write(to: URL(fileURLWithPath: broken))

        // Only archive windows: the one opened for the broken file goes again
        let only = try XCTUnwrap(app.windows.first)
        only.open(try makeArchive("shown.zip"))
        XCTAssertNotNil(only.info)
        app.openArchive(broken, reuse: nil)
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.windows.allSatisfy { $0.info != nil })

        // Only the empty window: it stays
        settle()
        app.openArchive(broken, reuse: nil)
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertNil(app.windows.first?.info)
        XCTAssertEqual(app.windows.first?.window?.isVisible, true)
    }
}
