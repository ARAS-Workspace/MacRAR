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
    /// without a word, while the rest went in; every dropped item goes in.
    func testFilesAndArchivesDroppedTogetherAreAllAdded() throws {
        let extra = try makeArchive("extra.zip", of: [workspace.path("src/a.txt")])
        try Data("note\n".utf8).write(to: workspace.url("note.txt"))
        let turkish = "öğrenci notu.txt".precomposedStringWithCanonicalMapping
        try workspace.writeComposed(Data("not\n".utf8), to: turkish)
        for format in formats {
            let target = try window(showing: try makeArchive("target.\(format)"))
            target.handleDrop([URL(fileURLWithPath: extra), workspace.url("note.txt"), workspace.url(turkish)])
            XCTAssertTrue(eventually { names(target).contains("note.txt") }, "\(format): nothing was added")
            XCTAssertTrue(names(target).contains(turkish), "\(format): \(names(target))")
            XCTAssertTrue(names(target).contains("extra.zip"), "\(format): \(names(target))")
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

    /// The archive is known among the items by the file it is, not by how its path is spelled: a name with Turkish
    /// letters in the other Unicode form, in other letter case (the disk ignores case, String comparison does not), or a
    /// link to it, is left out as well.
    func testTheArchiveIsLeftOutOfItsOwnItemsHoweverItIsNamed() throws {
        let name = "öğrenci arşivi.7z".precomposedStringWithCanonicalMapping
        try workspace.writeComposed(Data(), to: name)
        let archive = workspace.path(name)
        let decomposed = workspace.path(name.decomposedStringWithCanonicalMapping)
        let upper = workspace.path(name.uppercased())
        XCTAssertNotEqual(upper, archive)
        let link = workspace.path("link.7z")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: archive)
        let note = workspace.path("src/a.txt")
        XCTAssertEqual(Ops.itemsToAdd([archive, decomposed, upper, link, note], into: archive), [note])
        XCTAssertEqual(Ops.itemsToAdd([note], into: decomposed), [note])
    }

    /// The folder that holds the open archive, however deep, added to it by a drop or Add Files: 7-Zip packed a copy
    /// of the archive into itself along with the folder, so for 7z and ZIP the folder is refused with an explanation
    /// and the archive is left as it was. rar leaves the archive out, so RAR takes the folder.
    func testAFolderHoldingTheOpenArchiveIsNotPackedIntoIt() throws {
        let turkish = "kutu ğüş".precomposedStringWithCanonicalMapping
        for format in formats {
            try workspace.makeComposedDirectory("\(turkish) \(format)/iç")
            let folder = workspace.path("\(turkish) \(format)")
            let archive = try makeArchive("\(turkish) \(format)/iç/in.\(format)", of: [workspace.path("src/a.txt")])
            try Data("n\n".utf8).write(to: URL(fileURLWithPath: folder).appendingPathComponent("n.txt"))
            guard case .ok(let info) = ArchiveReader.list(archive, password: nil) else { return XCTFail("\(format) did not list") }
            let before = names(in: archive)
            // The folder as Foundation spells it, decomposed (NFD), while the disk has it composed
            let dropped = folder.decomposedStringWithCanonicalMapping
            let added = finished { Ops.add(info: info, items: [dropped], password: nil, host: nil, completion: $0) }
            let after = names(in: archive)
            XCTAssertFalse(after.contains { $0.hasSuffix("in.\(format)") }, "\(format): the archive was packed into itself")
            if format == "rar" {
                XCTAssertTrue(added, "rar refused the folder")
                XCTAssertNil(Ops.addProblem([dropped], into: info))
                XCTAssertTrue(after.contains("\(turkish) \(format)/n.txt"), "\(after)")
            } else {
                XCTAssertFalse(added, "\(format): the folder was added")
                XCTAssertEqual(after, before, format)
                XCTAssertEqual(Ops.addProblem([workspace.path("src/a.txt"), dropped], into: info),
                               loc.t("add_folder_holds_archive", "\(turkish) \(format)"))
                XCTAssertNil(Ops.addProblem([workspace.path("src")], into: info), "\(format): a folder beside it was refused")
                // A link to the folder: 7-Zip follows it and packs the archive all the same
                let link = workspace.path("link \(format)")
                try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: folder)
                XCTAssertNotNil(Ops.addProblem([link], into: info), "\(format): a link to the folder was taken")
            }
        }
    }

    // MARK: Volume sets

    /// A split archive rar writes (vol.part1.rar …) and the same volumes copied under old-style names (old.rar, old.r00
    /// …), which 7-Zip reads the same; rar 7 no longer writes those itself.
    private func makeVolumeSets() throws -> (new: [String], old: [String]) {
        guard let rar else { throw XCTSkip("RARLAB's rar is not fetched; run External/fetch-rar.sh") }
        let made = try rar.run(RarRunner.addArguments + ["-ma5", "-v300k", "--", workspace.path("vol.rar")] + workspace.sources,
                               in: workspace.root.path)
        XCTAssertEqual(made.status, 0, made.output)
        let parts = try FileManager.default.contentsOfDirectory(atPath: workspace.root.path).filter { $0.hasPrefix("vol.part") }.sorted()
        XCTAssertGreaterThan(parts.count, 2, "\(parts)")
        var old: [String] = []
        for (index, part) in parts.enumerated() {
            let piece = workspace.path(index == 0 ? "old.rar" : String(format: "old.r%02d", index - 1))
            try FileManager.default.copyItem(atPath: workspace.path(part), toPath: piece)
            old.append(piece)
        }
        return (parts.map(workspace.path), old)
    }

    /// The archives the app's windows show, by name.
    private var shown: [String] { app.windows.compactMap { $0.archivePath.map { ($0 as NSString).lastPathComponent } }.sorted() }

    /// Upstream 1.4.3 (533ce7e) brought a set down to its first volume only for the extracting and testing Quick
    /// Actions. Opened from Finder or through the Open Quick Action, and dropped onto the empty window, every volume
    /// opened in a window of its own, a later one showing only the items that start in it; the set now opens once.
    func testOpeningAVolumeSetOpensItOnce() throws {
        let sets = try makeVolumeSets()
        app.handleOpen(sets.old)
        XCTAssertEqual(shown, ["old.rar"], "an old-style set")
        settle()
        app.handleOpen([sets.new[1]])
        XCTAssertEqual(shown, ["vol.part1.rar"], "a later volume, the first beside it")
        settle()
        let empty = try XCTUnwrap(app.windows.first)
        empty.handleDrop(sets.old.dropFirst().map { URL(fileURLWithPath: $0) })
        XCTAssertEqual(shown, ["old.rar"], "later volumes dropped onto the empty window")
        XCTAssertNotNil(app.windows.first?.info)
    }

    // MARK: Failed opens

    /// A file that does not open, from Finder, dropped onto the empty window or locked with a password the user does
    /// not give, leaves the empty window the user had. Upstream 1.4.3 (533ce7e) found the window closed whenever
    /// another one was open.
    func testAFailedOpenKeepsTheEmptyWindowTheUserHad() throws {
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
            XCTAssertTrue(app.windows.contains { $0 === empty } && empty.window?.isVisible == true, attempt)
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

    /// A file that does not open as the app starts leaves the app its window: the one made for the file is the only
    /// window, and closing it would quit the app. A second copy opens the file and, with MACRAR_SNAPSHOT, saves its
    /// visible windows and quits.
    func testAFileThatDoesNotOpenAtLaunchLeavesAWindow() throws {
        let broken = workspace.path("broken.rar")
        try Data(repeating: 0x41, count: 4096).write(to: URL(fileURLWithPath: broken))
        let exit = try launchApp([broken], environment: [.snapshot: workspace.path("shot"), .snapshotDelay: "2"])
        XCTAssertEqual(exit.status, 0, exit.output)
        XCTAssertTrue(workspace.exists("shot-0.png"), "the copy had no window left: \(exit.output)")
    }
}
