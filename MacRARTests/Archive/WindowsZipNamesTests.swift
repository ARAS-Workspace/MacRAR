import XCTest
@testable import MacRAR

/// Names in a ZIP made on Turkish Windows, stored as Windows' own zip stores them: in the OEM code page (CP857) with no
/// UTF-8 flag, and in the ANSI one (CP1254) for an entry another system made. Read as the app reads them in Turkey's
/// region, the window shows them, extraction writes them and a selected item is extracted by them as they were typed on
/// Windows; a name made on Unix in UTF-8 without the flag stays as it is. Each test puts back the code pages it found.
final class WindowsZipNamesTests: XCTestCase {
    private var workspace: Workspace!
    private var codePages: WindowsCodePages?

    override func setUpWithError() throws {
        workspace = try Workspace()
        codePages = SevenZipBridge.windowsCodePages
        SevenZipBridge.windowsCodePages = WindowsCodePages(Locale(identifier: "tr_TR"))
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        SevenZipBridge.windowsCodePages = codePages
        workspace = nil
    }

    /// Three names in CP857 from FAT, "Şube.txt" in CP1254 from VFAT and "Unix şarkı.txt" in UTF-8 from Unix.
    private func windowsArchive() throws -> String {
        var entries = ["Şirket Raporu.txt", "Ağustos Özetleri/İçerik ışık.txt", "ÇĞİÖŞÜ çğıöşü.txt"].map {
            WindowsZip.entry($0, codePage: 857)
        }
        entries.append(WindowsZip.entry("Şube.txt", codePage: 1254, host: 14))
        entries.append(WindowsZip.entry("Unix şarkı.txt", codePage: 65001, host: 3))
        let archive = workspace.path("windows.zip")
        try WindowsZip.data(entries).write(to: URL(fileURLWithPath: archive))
        return archive
    }

    /// The paths an archive window shows, every folder open.
    private func shown(_ archive: String) -> [String] {
        let controller = ArchiveWindowController()
        controller.open(archive)
        defer { controller.close() }
        controller.outline.expandItem(nil, expandChildren: true)
        return (0..<controller.outline.numberOfRows).compactMap { (controller.outline.item(atRow: $0) as? Node)?.path }.sorted()
    }

    /// The files under `folder`, by path.
    private func files(_ folder: String) -> [String] {
        (FileManager.default.subpaths(atPath: folder) ?? []).filter { path in
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent(path), isDirectory: &isFolder)
            return !isFolder.boolValue
        }.sorted()
    }

    private func extract(_ archive: String, _ names: [String]?, into folder: String) throws -> Bool {
        guard case .ok(let info) = ArchiveReader.list(archive, password: nil) else {
            XCTFail("\(archive) was not listed")
            return false
        }
        return finished { Ops.extract(.init(info: info, names: names, dest: folder), password: nil, host: nil, completion: $0) }
    }

    func testAUTF8NameWithoutTheFlagStaysAsItIs() throws {
        XCTAssertTrue(shown(try windowsArchive()).contains("Unix şarkı.txt"))
    }

    func testTheWindowShowsTheNames() throws {
        XCTAssertEqual(shown(try windowsArchive()), [
            "Ağustos Özetleri", "Ağustos Özetleri/İçerik ışık.txt", "ÇĞİÖŞÜ çğıöşü.txt", "Şirket Raporu.txt", "Şube.txt",
            "Unix şarkı.txt",
        ].sorted())
    }

    func testExtractionWritesTheNames() throws {
        let archive = try windowsArchive()
        let folder = try workspace.makeDirectory("all")
        XCTAssertTrue(try extract(archive, nil, into: folder))
        XCTAssertEqual(files(folder), [
            "Ağustos Özetleri/İçerik ışık.txt", "ÇĞİÖŞÜ çğıöşü.txt", "Şirket Raporu.txt", "Şube.txt", "Unix şarkı.txt",
        ].sorted())
    }

    /// A folder chosen by its name brings what it holds and nothing else.
    func testASelectedItemIsExtractedByItsName() throws {
        let archive = try windowsArchive()
        let folder = try workspace.makeDirectory("one")
        XCTAssertTrue(try extract(archive, ["Ağustos Özetleri"], into: folder))
        XCTAssertEqual(files(folder), ["Ağustos Özetleri/İçerik ışık.txt"])
    }
}
