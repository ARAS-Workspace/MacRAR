import XCTest
@testable import MacRAR

/// What an archive window shows as the user browses it: the tree sorted by any column, folders first, in either
/// direction and all the way down; the filter's flat list of matching paths; and the status line for no archive, an
/// archive, a filter and a selection, with the archive's flags in the app's language. The windows are never shown, and
/// the test run keeps AppKit from saving their frames, columns and sort order (MACRAR_DEBUG_UNSEEN); each test puts
/// back the language it found.
final class ArchiveWindowBrowsingTests: XCTestCase {
    private var workspace: Workspace!
    private var language: LocalizationManager.Language!
    private var savedLanguage: Any?

    override func setUpWithError() throws {
        workspace = try Workspace()
        language = loc.current
        savedLanguage = UserDefaults.standard.object(forKey: LocalizationManager.defaultsKey)
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        loc.current = language
        UserDefaults.standard.set(savedLanguage, forKey: LocalizationManager.defaultsKey)
        workspace = nil
    }

    // MARK: Archives

    /// Bytes 7-Zip cannot shrink, the same on every run.
    private func noise(_ count: Int) -> Data {
        var state: UInt32 = 2_463_534_242
        return Data((0..<count).map { _ in
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return UInt8(truncatingIfNeeded: state)
        })
    }

    /// Writes `data` at `relative` in the workspace, modified at `year`-06-01.
    private func write(_ data: Data, _ relative: String, year: Int) throws {
        let url = workspace.url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        try setYear(year, of: relative)
    }

    private func setYear(_ year: Int, of relative: String) throws {
        let date = try XCTUnwrap(DateComponents(calendar: Calendar(identifier: .gregorian), year: year, month: 6, day: 1).date)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: workspace.path(relative))
    }

    /// A ZIP whose top-level items each sort elsewhere by name, size, packed size, ratio and date: two folders, one
    /// with two files inside, and four files, two of them named "file2" and "file10".
    private func browsingArchive() throws -> String {
        try write(Data(count: 3000), "tree/b-folder/inner-a.txt", year: 2015)
        try write(noise(50), "tree/b-folder/inner-b.bin", year: 2016)
        try write(noise(100), "tree/a-folder/deep/z.bin", year: 2017)
        try write(noise(5000), "tree/Big.bin", year: 2020)
        try write(Data(count: 10), "tree/small.txt", year: 2021)
        try write(Data(count: 200), "tree/file2.txt", year: 2022)
        try write(Data(count: 100), "tree/file10.txt", year: 2023)
        for (folder, year) in [("tree/a-folder/deep", 2018), ("tree/a-folder", 2019), ("tree/b-folder", 2024)] {
            try setYear(year, of: folder)
        }
        let archive = workspace.path("browse.zip")
        let items = ["a-folder", "b-folder", "Big.bin", "small.txt", "file2.txt", "file10.txt"].map { workspace.path("tree/\($0)") }
        update(archive, items, SevenZipBridge.UpdateOptions(format: "zip"))
        return archive
    }

    private func opened(_ archive: String) throws -> ArchiveWindowController {
        let controller = ArchiveWindowController()
        controller.open(archive)
        XCTAssertNotNil(controller.info, archive)
        return controller
    }

    // MARK: Reading the window

    /// The rows the outline shows, every folder expanded: paths while a filter is on, otherwise paths too.
    private func rows(_ controller: ArchiveWindowController) -> [String] {
        let outline = controller.outline
        outline.expandItem(nil, expandChildren: true)
        return (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? Node)?.path.precomposedStringWithCanonicalMapping }
    }

    private func topLevel(_ controller: ArchiveWindowController) -> [String] {
        let outline = controller.outline
        return (0..<outline.numberOfChildren(ofItem: nil)).compactMap { (outline.child($0, ofItem: nil) as? Node)?.path }
    }

    private func sort(_ controller: ArchiveWindowController, by key: String, ascending: Bool = true) {
        controller.outline.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
    }

    private func filter(_ controller: ArchiveWindowController, _ text: String) {
        controller.searchChanged(NSSearchField(string: text))
    }

    private func select(_ paths: [String], in controller: ArchiveWindowController) throws {
        let outline = controller.outline
        outline.expandItem(nil, expandChildren: true)
        let rows = try paths.map { path in
            try XCTUnwrap((0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? Node)?.path == path }, path)
        }
        outline.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
    }

    /// The status line under the outline.
    private func status(_ controller: ArchiveWindowController) throws -> String {
        func labels(_ view: NSView) -> [NSTextField] {
            ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(labels)
        }
        let content = try XCTUnwrap(controller.window?.contentView)
        return try XCTUnwrap(labels(content).first { $0.superview is NSVisualEffectView }).stringValue
    }

    private func text(_ key: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: loc.current.rawValue, withExtension: "json", subdirectory: "translations"))
        return try XCTUnwrap(JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))[key], key)
    }

    // MARK: Sorting

    /// Folders first whatever the column and direction; a name sorts as people count ("file2" before "file10"), and
    /// equal values keep the names' order.
    func testTheTreeSortsByEachColumnFoldersFirst() throws {
        let controller = try opened(try browsingArchive())
        defer { controller.close() }
        let byName = ["a-folder", "b-folder", "Big.bin", "file2.txt", "file10.txt", "small.txt"]
        XCTAssertEqual(topLevel(controller), byName)
        sort(controller, by: "name", ascending: false)
        XCTAssertEqual(topLevel(controller), ["b-folder", "a-folder", "small.txt", "file10.txt", "file2.txt", "Big.bin"])
        sort(controller, by: "size")
        XCTAssertEqual(topLevel(controller), ["a-folder", "b-folder", "small.txt", "file10.txt", "file2.txt", "Big.bin"])
        sort(controller, by: "size", ascending: false)
        XCTAssertEqual(topLevel(controller), ["b-folder", "a-folder", "Big.bin", "file2.txt", "file10.txt", "small.txt"])
        sort(controller, by: "date")
        XCTAssertEqual(topLevel(controller), ["a-folder", "b-folder", "Big.bin", "small.txt", "file2.txt", "file10.txt"])

        let nodes = controller.root.children
        for (key, value) in [("packed", { (node: Node) in Double(node.totalPacked) }),
                             ("ratio", { (node: Node) in node.totalSize > 0 ? Double(node.totalPacked) / Double(node.totalSize) : 0 })] {
            for ascending in [true, false] {
                sort(controller, by: key, ascending: ascending)
                let shown = topLevel(controller).compactMap { path in nodes.first { $0.path == path } }
                let folders = shown.prefix { $0.isDir }
                XCTAssertEqual(folders.count, 2, "\(key): folders are not first")
                for group in [Array(folders), Array(shown.dropFirst(folders.count))] {
                    for (left, right) in zip(group, group.dropFirst()) {
                        let inOrder = ascending ? value(left) <= value(right) : value(left) >= value(right)
                        let tied = value(left) == value(right)
                        XCTAssertTrue(inOrder && (!tied || left.name.localizedStandardCompare(right.name) == .orderedAscending),
                                      "\(key) \(ascending ? "up" : "down"): \(left.name) before \(right.name)")
                    }
                }
            }
        }
    }

    /// Items of equal value come in their names' order whatever came before: two files of one size, the later named
    /// first by date, sort by name once their size is the key.
    func testEqualValuesComeInTheirNamesOrder() throws {
        try write(Data(count: 64), "ties/tie-a.txt", year: 2023)
        try write(Data(count: 64), "ties/tie-b.txt", year: 2021)
        let archive = workspace.path("ties.zip")
        update(archive, ["tie-a.txt", "tie-b.txt"].map { workspace.path("ties/\($0)") }, SevenZipBridge.UpdateOptions(format: "zip"))
        let controller = try opened(archive)
        defer { controller.close() }
        sort(controller, by: "date")
        XCTAssertEqual(topLevel(controller), ["tie-b.txt", "tie-a.txt"])
        for ascending in [true, false] {
            sort(controller, by: "size", ascending: ascending)
            XCTAssertEqual(topLevel(controller), ["tie-a.txt", "tie-b.txt"], ascending ? "up" : "down")
            sort(controller, by: "date")
        }
    }

    /// A new sort reaches into every folder, and a filter on at the time follows it.
    func testANewSortReachesEveryFolderAndTheFilter() throws {
        let controller = try opened(try browsingArchive())
        defer { controller.close() }
        XCTAssertEqual(rows(controller).filter { $0.hasPrefix("b-folder/") }, ["b-folder/inner-a.txt", "b-folder/inner-b.bin"])
        sort(controller, by: "size")
        XCTAssertEqual(rows(controller).filter { $0.hasPrefix("b-folder/") }, ["b-folder/inner-b.bin", "b-folder/inner-a.txt"])
        filter(controller, "file")
        XCTAssertEqual(rows(controller), ["file10.txt", "file2.txt"])
        sort(controller, by: "size", ascending: false)
        XCTAssertEqual(rows(controller), ["file2.txt", "file10.txt"])
    }

    // MARK: Filtering

    /// The filter matches anywhere in an item's path, whatever the case, after the spaces around it are trimmed; it
    /// shows a flat list of paths that do not expand, and clearing it brings the tree back.
    func testTheFilterListsMatchingPaths() throws {
        let controller = try opened(try browsingArchive())
        defer { controller.close() }
        filter(controller, "  FILE ")
        XCTAssertEqual(rows(controller), ["file2.txt", "file10.txt"])
        filter(controller, "b-folder/inner")
        XCTAssertEqual(rows(controller), ["b-folder/inner-a.txt", "b-folder/inner-b.bin"])
        filter(controller, "deep")
        XCTAssertEqual(rows(controller), ["a-folder/deep", "a-folder/deep/z.bin"])
        // Sorted as one list by name, not in the tree's order, which would put a-folder's first
        filter(controller, ".bin")
        XCTAssertEqual(rows(controller), ["Big.bin", "b-folder/inner-b.bin", "a-folder/deep/z.bin"])
        filter(controller, "deep")
        XCTAssertFalse(controller.outline.isExpandable(try XCTUnwrap(controller.outline.item(atRow: 0))), "a folder in the list opens")
        filter(controller, "")
        XCTAssertEqual(topLevel(controller), ["a-folder", "b-folder", "Big.bin", "file2.txt", "file10.txt", "small.txt"])
        XCTAssertNil(controller.filtered)
    }

    /// A name is found whether the letters typed pair as in English or as in Turkish, in any language and region:
    /// "istanbul" finds "İstanbul", "I" finds "ılık" as well as "IRMAK", and "ILIK" and "ırmak" find their Turkish
    /// pairs. The filter followed the region's rules alone, and in en_TR found none of these.
    func testTheFilterKnowsTurkishCasePairs() throws {
        let names = ["\u{130}stanbul.txt", "\u{131}l\u{131}k.txt", "IRMAK.txt", "istanbul2.txt"]
        for name in names { try workspace.writeComposed(Data("t".utf8), to: name) }
        let archive = workspace.path("turkish.7z")
        update(archive, names.map { workspace.path($0) }, SevenZipBridge.UpdateOptions(format: "7z"))
        let controller = try opened(archive)
        defer { controller.close() }
        func found(_ text: String) -> Set<String> {
            filter(controller, text)
            return Set(rows(controller))
        }
        XCTAssertEqual(found("istanbul"), ["\u{130}stanbul.txt", "istanbul2.txt"])
        XCTAssertEqual(found("I"), ["\u{131}l\u{131}k.txt", "IRMAK.txt", "istanbul2.txt"])
        XCTAssertEqual(found("ILIK"), ["\u{131}l\u{131}k.txt"])
        XCTAssertEqual(found("\u{131}rmak"), ["IRMAK.txt"])
        XCTAssertEqual(found("irmak"), ["IRMAK.txt"])
    }

    // MARK: Status

    /// No archive, an archive's totals, a filter's matches, and a selection, which comes before the filter.
    func testTheStatusLineFollowsTheArchiveTheFilterAndTheSelection() throws {
        let empty = ArchiveWindowController()
        defer { empty.close() }
        XCTAssertEqual(try status(empty), try text("status_no_archive"))

        let controller = try opened(try browsingArchive())
        defer { controller.close() }
        let info = try XCTUnwrap(controller.info)
        XCTAssertEqual(info.fileCount, 7)
        let summary = String(format: try text("status_summary"), 7, Fmt.size(info.totalSize), Fmt.size(info.totalPacked))
        XCTAssertEqual(try status(controller), summary + "   •   ZIP")
        filter(controller, "file")
        XCTAssertEqual(try status(controller), String(format: try text("status_matches"), 2) + "   •   ZIP")
        try select(["file2.txt"], in: controller)
        XCTAssertEqual(try status(controller), String(format: try text("status_selection"), 1, Fmt.size(200)) + "   •   ZIP")
        filter(controller, "")
        try select(["Big.bin", "small.txt"], in: controller)
        XCTAssertEqual(try status(controller), String(format: try text("status_selection"), 2, Fmt.size(5010)) + "   •   ZIP")
    }

    /// A folder selected with a file inside it counts the file once, so the selection is as large as the folder; a
    /// file beside it whose name starts like the folder's is not inside it. It counted the file twice: 2 KB for a
    /// 1000-byte file and its folder.
    func testASelectionCountsEachItemsSizeOnce() throws {
        try write(noise(1000), "once/d/f.bin", year: 2020)
        try write(noise(500), "once/d-notes.txt", year: 2020)
        let archive = workspace.path("once.zip")
        update(archive, ["d", "d-notes.txt"].map { workspace.path("once/\($0)") }, SevenZipBridge.UpdateOptions(format: "zip"))
        let controller = try opened(archive)
        defer { controller.close() }
        try select(["d", "d/f.bin"], in: controller)
        XCTAssertEqual(try status(controller), String(format: try text("status_selection"), 2, Fmt.size(1000)) + "   •   ZIP")
        try select(["d", "d/f.bin", "d-notes.txt"], in: controller)
        XCTAssertEqual(try status(controller), String(format: try text("status_selection"), 3, Fmt.size(1500)) + "   •   ZIP")
    }

    /// The archive's flags in the status line, in both languages: solid, encrypted headers, encrypted files and the
    /// number of volumes.
    func testTheStatusLineNamesTheArchivesFlagsInTheAppsLanguage() throws {
        // Two files, as 7-Zip makes a single file's archive no solid block
        try write(noise(3000), "flags/data.bin", year: 2020)
        try write(Data(count: 3000), "flags/zeros.txt", year: 2020)
        let source = [workspace.path("flags/data.bin"), workspace.path("flags/zeros.txt")]
        let headers = workspace.path("headers.7z"), files = workspace.path("files.zip"), volumes = workspace.path("volumes.7z")
        update(headers, source, SevenZipBridge.UpdateOptions(format: "7z", password: "pw", encryptHeaders: true))
        update(files, source, SevenZipBridge.UpdateOptions(format: "zip", password: "pw"))
        update(volumes, source, SevenZipBridge.UpdateOptions(format: "7z", volumeSize: 1024))
        let parts = try FileManager.default.contentsOfDirectory(atPath: workspace.root.path).filter { $0.hasPrefix("volumes.7z.") }
        XCTAssertGreaterThan(parts.count, 1)
        for language in [LocalizationManager.Language.en, .tr] {
            loc.current = language
            let solid = try text("status_flag_solid")
            let expected = [
                headers: "7z, \(solid), \(try text("status_flag_encrypted_headers"))",
                files: "ZIP" + (try text("status_flag_encrypted_files")),
                volumes + ".001": "7z, \(solid), \(parts.count) \(try text("status_flag_volume"))",
            ]
            for (archive, flags) in expected {
                var controller: ArchiveWindowController?
                try withEnvironment(["MACRAR_DEBUG_PASSWORD": "pw"]) { controller = try opened(archive) }
                defer { controller?.close() }
                let shown = try status(try XCTUnwrap(controller))
                XCTAssertTrue(shown.hasSuffix("   •   " + flags), "\(language): \(shown)")
            }
        }
    }

    // MARK: The tree

    /// A file and a folder of one name are both shown, with the folder's items, whichever comes first in the archive.
    /// A ZIP holding "x" and then "x/y" showed one row, "x", which did not open: the file took in the folder's items.
    func testAFileAndAFolderOfOneNameAreBothShown() {
        func shown(_ entries: [ArchiveEntry]) -> [String] {
            var paths: [String] = []
            func walk(_ node: Node) {
                for child in node.children {
                    paths.append(child.path + (child.isDir ? "/" : ""))
                    if child.isDir { walk(child) }
                }
            }
            walk(Node.buildTree(entries))
            return paths
        }
        let file = ArchiveEntry(name: "x", isDirectory: false, size: 1), inside = ArchiveEntry(name: "x/y", isDirectory: false, size: 1)
        XCTAssertEqual(shown([inside, file]), ["x/", "x/y", "x"])
        XCTAssertEqual(shown([file, inside]), ["x/", "x/y", "x"])
    }
}
