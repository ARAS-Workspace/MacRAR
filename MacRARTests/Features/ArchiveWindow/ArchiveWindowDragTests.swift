import XCTest
@testable import MacRAR

/// Items dragged out of an archive window to Finder, as file promises Finder asks the window to keep. A drag asks once
/// and extracts once, whatever the number of items; a cancelled one writes nothing; an encrypted archive asks for its
/// password once. The drag is set up as AppKit sets it up, through the outline's delegate, and each promise is kept on
/// the window's promise queue, as Finder has it kept, into a folder of the test's own. The questions go to a
/// prompter of the test's own, which says yes or no and writes down what it was asked.
final class ArchiveWindowDragTests: XCTestCase {
    /// Answers a confirmation with `yes`, a password with "pw" and an overwrite question with `overwrite`, and keeps
    /// what it was asked, in order.
    private final class Answering: Prompter {
        private let yes: Bool
        private let overwrite: Dialogs.OverwriteMode
        private(set) var asked: [String] = []

        init(yes: Bool = true, overwrite: Dialogs.OverwriteMode = .cancel) {
            self.yes = yes
            self.overwrite = overwrite
        }

        func ask(_ question: Question) -> Answer {
            asked.append(question.title)
            return Answer(button: yes ? 0 : 1)
        }

        func report(_ report: Report) { asked.append("report: \(report.detail)") }

        func askPassword(archiveName: String, wrong: Bool) -> String? {
            asked.append("password")
            return "pw"
        }

        func askOverwrite(existing: [String], dest: String) -> Dialogs.OverwriteMode {
            asked.append("overwrite \(existing.sorted())")
            return overwrite
        }

        func choose(_ panel: Panel) -> [URL] { [] }
        func openInBrowser(_ page: URL) {}
    }

    private var workspace: Workspace!

    override func setUpWithError() throws {
        workspace = try Workspace()
        for (name, size) in [("src/a.txt", 100), ("src/dir/b.txt", 200), ("src/dir/c.txt", 300)] {
            try FileManager.default.createDirectory(at: workspace.url(name).deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 65, count: size).write(to: workspace.url(name))
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: Ops.testTrash)
        workspace = nil
    }

    /// A ZIP of a.txt (100 B) and dir/ holding b.txt (200 B) and c.txt (300 B), open in a window no one sees.
    private func opened(password: String? = nil) throws -> ArchiveWindowController {
        let archive = workspace.path(password == nil ? "drag.zip" : "locked.zip")
        var options = SevenZipBridge.UpdateOptions(format: "zip")
        options.password = password
        options.zipAES256 = password != nil
        update(archive, [workspace.path("src/a.txt"), workspace.path("src/dir")], options)
        let controller = ArchiveWindowController()
        controller.open(archive)
        XCTAssertNotNil(controller.info)
        addTeardownBlock { controller.close() }
        return controller
    }

    private func folder() throws -> URL {
        URL(fileURLWithPath: try workspace.makeDirectory("out-\(UUID().uuidString)"))
    }

    /// Drags the items at `paths` to `destination` and keeps every promise, as Finder does once the user drops them:
    /// what each promise ended with, by path ("ok", or the error's code).
    private func drag(_ paths: [String], from controller: ArchiveWindowController, to destination: URL,
                      answering prompter: Answering) throws -> [String: String] {
        let outline = controller.outline
        outline.expandItem(nil, expandChildren: true)
        let shown = (0..<outline.numberOfRows).compactMap { outline.item(atRow: $0) as? Node }
        let nodes = try paths.map { path in try XCTUnwrap(shown.first { $0.path == path }, path) }
        var results: [String: String] = [:]
        let lock = NSLock()
        withPrompter(prompter) {
            controller.outlineView(outline, draggingSession: NSDraggingSession(), willBeginAt: .zero, forItems: nodes)
            for node in nodes {
                guard let provider = controller.outlineView(outline, pasteboardWriterForItem: node) as? NSFilePromiseProvider else {
                    return XCTFail("\(node.path) is no file promise")
                }
                let url = destination.appendingPathComponent(controller.filePromiseProvider(provider, fileNameForType: provider.fileType))
                controller.promiseQueue.addOperation {
                    controller.filePromiseProvider(provider, writePromiseTo: url) { error in
                        lock.withLock { results[node.path] = error.map { "\(($0 as NSError).code)" } ?? "ok" }
                    }
                }
            }
            // The promises are kept off the main thread and wait on it, so the main run loop turns meanwhile
            let end = Date(timeIntervalSinceNow: 30)
            while lock.withLock({ results.count < nodes.count }), Date() < end {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            }
            XCTAssertEqual(lock.withLock { results.count }, nodes.count, "the promises were not all kept")
        }
        return results
    }

    /// The files under `folder` by path, a folder ending in "/", each file with its size.
    private func contents(_ folder: URL) -> [String] {
        let root = folder.resolvingSymlinksInPath().path
        return (FileManager.default.subpaths(atPath: root) ?? []).sorted().map { path in
            let full = (root as NSString).appendingPathComponent(path)
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: full, isDirectory: &isFolder)
            return isFolder.boolValue ? path + "/" : "\(path) \(FileManager.default.contents(atPath: full)?.count ?? -1)"
        }
    }

    /// The temporary folders drags extract into, which go once the last promise is kept.
    private func dragFolders() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []
        return Set(names.filter { $0.hasPrefix("drag-") })
    }

    func testAFewItemsAskOnceAndArrive() throws {
        let controller = try opened()
        let destination = try folder()
        let before = dragFolders()
        let prompter = Answering()
        let results = try drag(["a.txt", "dir/b.txt"], from: controller, to: destination, answering: prompter)
        XCTAssertEqual(results, ["a.txt": "ok", "dir/b.txt": "ok"])
        XCTAssertEqual(prompter.asked, [loc.t("drag_extract_confirm_multiple", 2, destination.lastPathComponent)])
        XCTAssertEqual(contents(destination), ["a.txt 100", "b.txt 200"])
        XCTAssertEqual(dragFolders().subtracting(before), [], "the temporary folder stays")
    }

    func testACancelledDragWritesNothing() throws {
        let controller = try opened()
        let destination = try folder()
        let prompter = Answering(yes: false)
        let results = try drag(["a.txt", "dir"], from: controller, to: destination, answering: prompter)
        let cancelled = "\(CocoaError.Code.userCancelled.rawValue)"
        XCTAssertEqual(results, ["a.txt": cancelled, "dir": cancelled])
        XCTAssertEqual(prompter.asked.count, 1)
        XCTAssertEqual(contents(destination), [])
    }

    /// Each drag asks for itself, once, and a folder arrives with what it holds.
    func testEachDragAsksAgain() throws {
        let controller = try opened()
        let drags = [(["dir"], ["dir/", "dir/b.txt 200", "dir/c.txt 300"]), (["a.txt", "dir/c.txt"], ["a.txt 100", "c.txt 300"])]
        for (paths, expected) in drags {
            let destination = try folder()
            let prompter = Answering()
            _ = try drag(paths, from: controller, to: destination, answering: prompter)
            XCTAssertEqual(prompter.asked.count, 1, "\(paths)")
            XCTAssertEqual(contents(destination), expected)
        }
    }

    /// The items are extracted in one go: an encrypted archive asks for its password once, for two items.
    func testAnEncryptedArchiveAsksItsPasswordOnce() throws {
        let controller = try opened(password: "pw")
        let destination = try folder()
        let prompter = Answering()
        let results = try drag(["a.txt", "dir/b.txt"], from: controller, to: destination, answering: prompter)
        XCTAssertEqual(results, ["a.txt": "ok", "dir/b.txt": "ok"])
        XCTAssertEqual(prompter.asked, [loc.t("drag_extract_confirm_multiple", 2, destination.lastPathComponent), "password"])
        XCTAssertEqual(contents(destination), ["a.txt 100", "b.txt 200"])
    }

    /// A folder dragged with a file inside it arrives with what it holds, and the file arrives beside it, as Finder
    /// copies a folder and an item in it, whichever Finder asks for first. The file's promise failed (no such file):
    /// the folder had taken it along.
    func testAFolderAndAFileInItBothArrive() throws {
        let controller = try opened()
        for paths in [["dir", "dir/b.txt"], ["dir/b.txt", "dir"]] {
            let destination = try folder()
            let results = try drag(paths, from: controller, to: destination, answering: Answering())
            XCTAssertEqual(results, ["dir": "ok", "dir/b.txt": "ok"], "\(paths)")
            XCTAssertEqual(contents(destination), ["b.txt 200", "dir/", "dir/b.txt 200", "dir/c.txt 300"], "\(paths)")
        }
    }

    /// A destination holding a.txt (3 B) and a folder dir with old.txt in it, which the archive does not have.
    private func crowded() throws -> URL {
        let destination = try folder()
        try Data("old".utf8).write(to: destination.appendingPathComponent("a.txt"))
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("dir"), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appendingPathComponent("dir/old.txt"))
        return destination
    }

    /// Items already at the destination are asked about once, together, before anything is extracted, and Cancel
    /// leaves the destination as it was. They were replaced without a word: the 3-byte a.txt by the archive's, and the
    /// folder dir together with old.txt.
    func testItemsAlreadyThereAreAskedAboutOnce() throws {
        let controller = try opened()
        let destination = try crowded()
        let prompter = Answering(overwrite: .cancel)
        let results = try drag(["a.txt", "dir", "dir/c.txt"], from: controller, to: destination, answering: prompter)
        let cancelled = "\(CocoaError.Code.userCancelled.rawValue)"
        XCTAssertEqual(results, ["a.txt": cancelled, "dir": cancelled, "dir/c.txt": cancelled])
        XCTAssertEqual(prompter.asked, [loc.t("drag_extract_confirm_multiple", 3, destination.lastPathComponent),
                                        "overwrite [\"a.txt\", \"dir\"]"])
        XCTAssertEqual(Set(contents(destination)), ["a.txt 3", "dir/", "dir/old.txt 3"])
    }

    /// Replace puts the archive's items in place of those there, as Finder's Replace does; Keep Both puts them beside
    /// under a new name; Skip leaves those there alone. An item not there arrives whatever the answer.
    func testReplaceKeepBothAndSkip() throws {
        let controller = try opened()
        let expected: [(Dialogs.OverwriteMode, Set<String>)] = [
            (.overwrite, ["a.txt 100", "c.txt 300", "dir/", "dir/b.txt 200", "dir/c.txt 300"]),
            (.rename, ["a.txt 3", "a 2.txt 100", "c.txt 300", "dir/", "dir/old.txt 3", "dir 2/", "dir 2/b.txt 200", "dir 2/c.txt 300"]),
            (.skip, ["a.txt 3", "c.txt 300", "dir/", "dir/old.txt 3"]),
        ]
        for (answer, after) in expected {
            let destination = try crowded()
            let prompter = Answering(overwrite: answer)
            let results = try drag(["a.txt", "dir", "dir/c.txt"], from: controller, to: destination, answering: prompter)
            XCTAssertEqual(results, ["a.txt": "ok", "dir": "ok", "dir/c.txt": "ok"], "\(answer)")
            XCTAssertEqual(Set(contents(destination)), after, "\(answer)")
        }
        // What Replace replaced went to the Trash, folder and all, where it can be put back: it was deleted for good
        let trashed = (FileManager.default.subpaths(atPath: Ops.testTrash) ?? []).sorted()
        XCTAssertTrue(trashed.contains("a.txt") && trashed.contains("dir/old.txt"), "\(trashed)")
    }

    /// An item whose name climbs out ("dir/../../x.txt") is the archive's own item, which 7-Zip writes as "dir/x.txt",
    /// never a file of the same name outside the temporary folder: the drag took the path from the raw name and moved
    /// a local file the archive pointed at into the destination.
    func testANameThatClimbsOutBringsTheArchivesItem() throws {
        let victimName = "victim-\(UUID().uuidString).txt"
        let victim = FileManager.default.temporaryDirectory.appendingPathComponent(victimName)
        try Data("local".utf8).write(to: victim)
        defer { try? FileManager.default.removeItem(at: victim) }
        let archive = workspace.path("climb.zip")
        try HostileArchive.zip([.file("dir/../../\(victimName)", "archived")]).write(to: URL(fileURLWithPath: archive))
        let controller = ArchiveWindowController()
        controller.open(archive)
        addTeardownBlock { controller.close() }
        let destination = try folder()
        let results = try drag(["dir/../../\(victimName)"], from: controller, to: destination, answering: Answering())
        XCTAssertEqual(results.values.first, "ok")
        XCTAssertEqual(try? String(contentsOf: victim, encoding: .utf8), "local", "the local file was taken")
        XCTAssertEqual(try? String(contentsOf: destination.appendingPathComponent(victimName), encoding: .utf8), "archived")
    }
}
