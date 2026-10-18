import XCTest
@testable import MacRAR

/// Names and paths are taken as they are written, through the app's own flows. A name with "*" or "?" in it, which
/// macOS allows, names that one item: deleting, extracting, adding or archiving it with "delete after" touches it
/// alone, never the items it would match as a wildcard, and a "*" in a parent folder's name matches nothing else.
/// An item's name is its whole path: in a tar written with tar -C dir ., "./a.txt" is not "a.txt", and "." is the
/// folder "." alone. A "*" in the destination stays, and an archive without an extension is the file changed.
final class LiteralNameTests: XCTestCase {
    private var workspace: Workspace!

    /// One name with each wildcard, and the items each would match
    private let names = ["a*.txt", "a1.txt", "a2.txt", "b?.txt", "bx.txt"]

    override func setUpWithError() throws {
        workspace = try Workspace()
        _ = try workspace.makeDirectory("names")
        for name in names { try Data(name.utf8).write(to: workspace.url("names/\(name)")) }
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        try? FileManager.default.removeItem(atPath: Ops.testTrash)
        workspace = nil
    }

    private func listed(_ path: String) throws -> ArchiveInfo {
        guard case .ok(let info) = ArchiveReader.list(path, password: nil) else { throw XCTSkip("\(path) did not list") }
        return info
    }

    private func entries(_ path: String) -> [String] {
        ((try? listed(path)).map { $0.entries.map(\.name) } ?? []).sorted()
    }

    /// An archive of `format` holding `items` of the names; a wildcard among them matches only items that are in it
    /// anyway.
    private func sevenZip(_ format: String, _ items: [String]) throws -> ArchiveInfo {
        let path = workspace.path("names.\(format)")
        update(path, items.map { workspace.path("names/\($0)") }, SevenZipBridge.UpdateOptions(format: format))
        XCTAssertEqual(entries(path), items.sorted(), "7-Zip wrote the archive as asked")
        return try listed(path)
    }

    // MARK: Wildcard characters

    /// Deleting "a*.txt" and "b?.txt" deleted a1.txt, a2.txt and bx.txt with them: the whole archive.
    func testDeletingANameWithAWildcardDeletesItAlone() throws {
        for format in ["zip", "7z"] {
            let info = try sevenZip(format, names)
            XCTAssertTrue(finished { Ops.delete(info: info, names: ["a*.txt", "b?.txt"], password: nil, host: nil, completion: $0) })
            XCTAssertEqual(entries(info.path), ["a1.txt", "a2.txt", "bx.txt"], format)
        }
    }

    /// Extracting the selected "a*.txt", as the window, a drag and opening an item do, wrote a1.txt and a2.txt too.
    func testExtractingANameWithAWildcardExtractsItAlone() throws {
        let info = try sevenZip("zip", names)
        let destination = try workspace.makeDirectory("out")
        let extraction = Ops.Extraction(info: info, names: ["a*.txt"], dest: destination)
        XCTAssertTrue(finished { Ops.extract(extraction, password: nil, host: nil, completion: $0) })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination).sorted(), ["a*.txt"])
    }

    /// Adding the file "a*.txt" added a1.txt and a2.txt from its folder too; a file in a folder named "x*y" came with
    /// the same file of every folder that name matches, each under its folder's name.
    func testAddingAFileWithAWildcardAddsItAlone() throws {
        let info = try sevenZip("zip", ["bx.txt"])
        XCTAssertTrue(finished { Ops.add(info: info, items: [workspace.path("names/a*.txt")], password: nil, host: nil, completion: $0) })
        XCTAssertEqual(entries(info.path), ["a*.txt", "bx.txt"])

        for folder in ["x*y", "xay"] {
            _ = try workspace.makeDirectory(folder)
            try Data(folder.utf8).write(to: workspace.url("\(folder)/in.txt"))
        }
        let created = compress([workspace.path("x*y/in.txt")], CompressOptions(archivePath: workspace.path("folder.zip"), format: .zip))
        XCTAssertTrue(created.ok)
        XCTAssertEqual(entries(created.path), ["in.txt"])
    }

    /// Archiving "a*.txt" with "delete source files after archiving" archived and deleted a1.txt and a2.txt too.
    func testDeletingAfterArchivingDeletesTheChosenFileAlone() throws {
        var options = CompressOptions(archivePath: workspace.path("after.zip"), format: .zip)
        options.deleteAfter = true
        let created = compress([workspace.path("names/a*.txt")], options)
        XCTAssertTrue(created.ok)
        XCTAssertEqual(entries(created.path), ["a*.txt"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: workspace.path("names")).sorted(),
                       ["a1.txt", "a2.txt", "b?.txt", "bx.txt"])
    }

    // MARK: Paths

    /// A tar written as tar -C dir . writes it, with a top-level a.txt and an absolute name beside.
    private func dottedTar() throws -> ArchiveInfo {
        let folder = HostileArchive.TarEntry(name: "./", data: Data(), type: 0x35, link: "")
        let tar = HostileArchive.tar([folder, .file("./a.txt", "inner"), .file("./sub/b.txt"), .file("a.txt", "top"),
                                      .file("/abs.txt"), .file("abs.txt")])
        try tar.write(to: workspace.url("dots.tar"))
        return try listed(workspace.path("dots.tar"))
    }

    /// Deleting "./a.txt" deleted the top-level a.txt instead, "/abs.txt" deleted abs.txt, and "." deleted every item.
    func testDeletingANameWithDotsDeletesThatItem() throws {
        let info = try dottedTar()
        XCTAssertEqual(entries(info.path), [".", "./a.txt", "./sub/b.txt", "/abs.txt", "a.txt", "abs.txt"])
        XCTAssertTrue(finished { Ops.delete(info: info, names: ["./a.txt"], password: nil, host: nil, completion: $0) })
        XCTAssertEqual(entries(info.path), [".", "./sub/b.txt", "/abs.txt", "a.txt", "abs.txt"], "./a.txt")
        XCTAssertTrue(finished { Ops.delete(info: info, names: ["/abs.txt"], password: nil, host: nil, completion: $0) })
        XCTAssertEqual(entries(info.path), [".", "./sub/b.txt", "a.txt", "abs.txt"], "/abs.txt")
        XCTAssertTrue(finished { Ops.delete(info: info, names: ["."], password: nil, host: nil, completion: $0) })
        XCTAssertEqual(entries(info.path), ["a.txt", "abs.txt"], ".")
    }

    /// Extracting into a folder with "*" in its name wrote into a folder named after the archive instead, which the
    /// overwrite question and the quarantine never looked at.
    func testADestinationWithAStarIsTheFolderWrittenInto() throws {
        let info = try sevenZip("zip", ["bx.txt"])
        let destination = try workspace.makeDirectory("out*star")
        XCTAssertTrue(finished { Ops.extract(.init(info: info, names: nil, dest: destination), password: nil, host: nil, completion: $0) })
        let written = (try? FileManager.default.contentsOfDirectory(atPath: workspace.root.path)) ?? []
        XCTAssertTrue(workspace.exists("out*star/bx.txt"), "\(written)")
    }

    /// Adding to and deleting from an archive without an extension wrote "noext.zip" or "noext.7z" beside it and
    /// reported success, the archive unchanged.
    func testAnArchiveWithoutAnExtensionIsTheFileChanged() throws {
        update(workspace.path("noext.zip"), [workspace.path("names/bx.txt")], SevenZipBridge.UpdateOptions(format: "zip"))
        try FileManager.default.moveItem(atPath: workspace.path("noext.zip"), toPath: workspace.path("noext"))
        let info = try listed(workspace.path("noext"))
        XCTAssertTrue(finished { Ops.add(info: info, items: [workspace.path("names/a1.txt")], password: nil, host: nil, completion: $0) })
        XCTAssertEqual(entries(info.path), ["a1.txt", "bx.txt"])
        XCTAssertTrue(finished { Ops.delete(info: info, names: ["bx.txt"], password: nil, host: nil, completion: $0) })
        XCTAssertEqual(entries(info.path), ["a1.txt"])
        XCTAssertFalse(workspace.exists("noext.zip") || workspace.exists("noext.7z"), "a change went to another archive")
    }

    // MARK: rar

    /// rar reads every name and path it is given as a pattern, and has no switch to stop it, so a name or path with
    /// "*", "?" or a line break in it never goes to rar: the app says so instead, and the archive and the files stay
    /// as they were. rar deleted a1.txt and a2.txt with "a*.txt", added them with it, and archived and deleted them
    /// with "delete source files after archiving".
    private func usingRar() throws -> RarTool {
        let tool = try RarTool.locate()
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(arguments.merging(["RarPath": tool.url.path]) { $1 }, forName: UserDefaults.argumentDomain)
        addTeardownBlock {
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
        return tool
    }

    /// A RAR archive of the names, written by rar from a list; a wildcard among them matches only items in it anyway.
    private func rarArchive() throws -> ArchiveInfo {
        let tool = try usingRar()
        try Data(names.map { "\($0)\n" }.joined().utf8).write(to: workspace.url("list.txt"))
        let result = try tool.run(["a", "-y", "-scfl", workspace.path("names.rar"), "@" + workspace.path("list.txt")],
                                  in: workspace.path("names"))
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(entries(workspace.path("names.rar")), names.sorted())
        return try listed(workspace.path("names.rar"))
    }

    func testRarIsNeverGivenANameWithAWildcardToDelete() throws {
        let info = try rarArchive()
        var deleted = true
        let told = printed { deleted = finished { Ops.delete(info: info, names: ["a*.txt"], password: nil, host: nil, completion: $0) } }
        XCTAssertFalse(deleted)
        XCTAssertTrue(told.contains(loc.t("rar_wildcard_delete", "a*.txt")), told)
        XCTAssertEqual(entries(info.path), names.sorted())
    }

    func testRarIsNeverGivenAFileWithAWildcardToAdd() throws {
        let info = try rarArchive()
        try Data("new".utf8).write(to: workspace.url("names/n?w.txt"))
        var added = true
        let told = printed {
            added = finished { Ops.add(info: info, items: [workspace.path("names/n?w.txt")], password: nil, host: nil, completion: $0) }
        }
        XCTAssertFalse(added)
        XCTAssertTrue(told.contains(loc.t("rar_wildcard_add", "n?w.txt")), told)
        XCTAssertEqual(entries(info.path), names.sorted())
    }

    /// Archiving with rar names the first part of the path with a wildcard character, a parent folder's too, and
    /// writes and deletes nothing.
    func testRarIsNeverGivenAPathWithAWildcardToArchive() throws {
        _ = try usingRar()
        _ = try workspace.makeDirectory("x*y")
        try Data("in".utf8).write(to: workspace.url("x*y/in.txt"))
        for (item, named) in [("names/a*.txt", "a*.txt"), ("x*y/in.txt", "x*y")] {
            var options = CompressOptions(archivePath: workspace.path("out.rar"), format: .rar5)
            options.deleteAfter = true
            var created = (ok: true, path: "")
            let told = printed { created = compress([workspace.path(item)], options) }
            XCTAssertFalse(created.ok, item)
            XCTAssertTrue(told.contains(loc.t("rar_wildcard_compress", named)), told)
            XCTAssertFalse(workspace.exists("out.rar"), item)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: workspace.path("names")).sorted(), names.sorted())
        XCTAssertTrue(workspace.exists("x*y/in.txt"))
    }

    /// A line break would split a name in rar's list into two names.
    func testRarIsNeverGivenANameWithALineBreak() throws {
        let info = try rarArchive()
        let told = printed { _ = finished { Ops.delete(info: info, names: ["a1.txt\na2.txt"], password: nil, host: nil, completion: $0) } }
        XCTAssertTrue(told.contains(loc.t("rar_wildcard_delete", "a1.txt\na2.txt")), told)
        XCTAssertEqual(entries(info.path), names.sorted())
    }
}
