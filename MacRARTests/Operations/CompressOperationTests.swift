import XCTest
@testable import MacRAR

/// What Ops.compress reports when it finishes: the archive file the Create Archive dialog reveals in Finder and the
/// window opens. A split archive has no file under its own name, so its first volume is reported.
final class CompressOperationTests: XCTestCase {
    private var workspace: Workspace!

    override func setUpWithError() throws {
        workspace = try Workspace()
        setDebugAnswers()
    }

    override func tearDown() {
        clearDebugAnswers()
        try? FileManager.default.removeItem(atPath: Ops.testTrash)
        workspace = nil
    }

    /// "Move source files to the Trash after archiving" trashes the chosen items once the archive is written and
    /// reads back, in every format; a folder goes with the link in it, and what the link points to stays. 7-Zip's
    /// -sdel and rar's -df deleted for good and followed the link: the folder it pointed to was emptied.
    func testMovingSourcesToTheTrashTakesTheChosenItemsAlone() throws {
        var formats: [ArchiveFormat] = [.zip, .sevenZip, .tar, .tgz]
        if let rar = try? RarTool.locate() {
            formats.append(.rar5)
            let defaults = UserDefaults.standard
            let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(arguments.merging(["RarPath": rar.url.path]) { $1 }, forName: UserDefaults.argumentDomain)
            addTeardownBlock {
                defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
                defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            }
        }
        for format in formats {
            let base = try workspace.makeDirectory("trash-\(format.ext)")
            for (path, text) in [("chosen.txt", "chosen"), ("folder/inside.txt", "inside"), ("real/keep.txt", "keep")] {
                let url = URL(fileURLWithPath: "\(base)/\(path)")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url)
            }
            try FileManager.default.createSymbolicLink(atPath: "\(base)/folder/link", withDestinationPath: "../real")
            var options = options(format, "trash-\(format.ext)/out.\(format.ext)")
            options.deleteAfter = true
            let made = compress(["\(base)/chosen.txt", "\(base)/folder"], options)
            XCTAssertTrue(made.ok, "\(format)")
            guard case .ok(let info) = ArchiveReader.list(made.path, password: nil) else { XCTFail("\(format) did not list"); continue }
            XCTAssertTrue(info.entries.contains { $0.name == "chosen.txt" }, "\(format)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: "\(base)/chosen.txt") || FileManager.default.fileExists(atPath: "\(base)/folder"),
                           "\(format): a chosen item stayed")
            XCTAssertEqual(try? String(contentsOfFile: "\(base)/real/keep.txt", encoding: .utf8), "keep", "\(format): the linked folder lost its file")
        }
        let trashed = try FileManager.default.contentsOfDirectory(atPath: Ops.testTrash)
        XCTAssertEqual(trashed.filter { $0.hasPrefix("chosen") }.count, formats.count, "\(trashed)")

        // An archive whose names are encrypted reads back with its password, and its sources go too
        let locked = try workspace.makeDirectory("trash-locked")
        try Data("secret".utf8).write(to: URL(fileURLWithPath: "\(locked)/secret.txt"))
        var options = options(.sevenZip, "trash-locked/out.7z")
        options.password = "pw"
        options.encryptNames = true
        options.deleteAfter = true
        let told = printed { XCTAssertTrue(compress(["\(locked)/secret.txt"], options).ok) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(locked)/secret.txt"), told)
    }

    private func options(_ format: ArchiveFormat, _ name: String, split: String? = nil) -> CompressOptions {
        var options = CompressOptions(archivePath: workspace.path(name))
        options.format = format
        options.level = 0
        options.volumeSize = split
        return options
    }

    /// A compressed tar is packed into a tar in the temporary folder first. That tar takes the archive's name, which gzip
    /// keeps in the archive, and goes away once it is compressed; it used to be Archiver-<UUID>.tar.
    func testCompressedTarsPackATarNamedAfterThem() throws {
        let temporary = NSTemporaryDirectory()
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: temporary))
        for format in [ArchiveFormat.tgz, .txz, .tbz2] {
            var options = options(format, "packed.\(format.ext)")
            options.level = 1
            let made = compress(workspace.sources, options)
            XCTAssertTrue(made.ok, format.ext)
            guard case .ok(let info) = ArchiveReader.list(made.path, password: nil) else { return XCTFail("\(made.path) did not list") }
            XCTAssertEqual(Set(info.entries.map(\.name)), ["a.txt", "sub", "sub/b.bin", "sub/çalışma ğüş.txt"], format.ext)
        }
        XCTAssertEqual(try gzipName(workspace.path("packed.tar.gz")), "packed.tar")
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: temporary)).subtracting(before)
        XCTAssertEqual(left.filter { $0.hasPrefix("Archiver-") }, [])
    }

    func testWholeArchiveIsReportedAsIs() {
        let made = compress(workspace.sources, options(.sevenZip, "whole.7z"))
        XCTAssertTrue(made.ok)
        XCTAssertEqual(made.path, workspace.path("whole.7z"))
    }

    func testSplitArchivesReportTheirFirstVolume() throws {
        for (format, name) in [(ArchiveFormat.sevenZip, "split.7z"), (.zip, "split.zip")] {
            let made = compress(workspace.sources, options(format, name, split: "300k"))
            XCTAssertTrue(made.ok, name)
            XCTAssertEqual(made.path, workspace.path(name + ".001"))
            XCTAssertFalse(workspace.exists(name))
            guard case .ok(let info) = ArchiveReader.list(made.path, password: nil) else { return XCTFail("\(made.path) did not list") }
            XCTAssertTrue(info.details.contains("volume"), info.details)
        }
    }

    /// An earlier split set under the same name is left alone: the question it raises, answered with Create New by
    /// MACRAR_DEBUG_CONFIRM, gives the new set a free name. 7-Zip used to fail with "Updating for multivolume
    /// archives is not implemented".
    func testSplittingOverAnEarlierSetMakesANewOne() throws {
        XCTAssertTrue(compress(workspace.sources, options(.sevenZip, "set.7z", split: "200k")).ok)
        let earlier = try workspace.files(startingWith: "set.7z.")
        XCTAssertGreaterThan(earlier.count, 2)

        let again = compress(workspace.sources, options(.sevenZip, "set.7z", split: "700k"))
        XCTAssertTrue(again.ok)
        XCTAssertEqual(again.path, workspace.path("set 2.7z.001"))
        XCTAssertEqual(try workspace.files(startingWith: "set.7z."), earlier, "the earlier set changed")
        guard case .ok = ArchiveReader.list(again.path, password: nil) else { return XCTFail("\(again.path) did not list") }
    }

    /// rar numbers its volumes with as many digits as their count needs, and a self-extracting set starts with .sfx.
    func testRarVolumeNames() throws {
        for volume in ["many.part01.rar", "sfx.part1.sfx"] {
            try Data().write(to: workspace.url(volume))
        }
        XCTAssertEqual(Ops.firstVolume(of: workspace.path("many.rar")), workspace.path("many.part01.rar"))
        XCTAssertEqual(Ops.firstVolume(of: workspace.path("sfx.sfx")), workspace.path("sfx.part1.sfx"))
        XCTAssertEqual(Ops.firstVolume(of: workspace.path("none.rar")), workspace.path("none.rar"))
        XCTAssertTrue(Ops.isTaken(workspace.path("many.rar")))
        XCTAssertFalse(Ops.isTaken(workspace.path("none.rar")))
    }
}
