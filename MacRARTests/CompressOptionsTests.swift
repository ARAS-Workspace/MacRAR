import XCTest
@testable import MacRAR

/// What the Create Archive dialog's choices become: 7-Zip update options or rar switches.
final class CompressOptionsTests: XCTestCase {
    private func options(_ format: ArchiveFormat, _ configure: (inout CompressOptions) -> Void = { _ in }) -> CompressOptions {
        var options = CompressOptions(archivePath: "/tmp/out." + format.ext)
        options.format = format
        configure(&options)
        return options
    }

    private struct Update {
        let archive: String
        let sources: [String]
        let options: SevenZipBridge.UpdateOptions
    }

    private func sevenZip(_ step: CompressOptions.Step, file: StaticString = #filePath, line: UInt = #line) -> Update? {
        guard case let .sevenZip(.update(archive, sources, options)) = step.work else {
            XCTFail("expected a 7-Zip update", file: file, line: line)
            return nil
        }
        return Update(archive: archive, sources: sources, options: options)
    }

    func testVolumeSizes() {
        let cases: [(String?, UInt64?)] = [
            (nil, 0), ("", 0), ("  ", 0),
            ("700", 700), ("700b", 700), ("12k", 12 << 10), ("12 K", 12 << 10),
            ("100M", 100 << 20), ("1g", 1 << 30),
            ("0", nil), ("1.5G", nil), ("abc", nil), ("10T", nil), ("-5M", nil),
        ]
        for (text, expected) in cases {
            let volumeBytes = options(.sevenZip) { $0.volumeSize = text }.volumeBytes
            XCTAssertEqual(volumeBytes, expected, "volume size \(text ?? "nil")")
        }
    }

    func testSevenZipWithEncryptedNames() throws {
        let steps = options(.sevenZip) {
            $0.level = 3
            $0.solid = true
            $0.password = "pw"
            $0.encryptNames = true
            $0.volumeSize = "100M"
            $0.deleteAfter = true
        }.buildSteps(items: ["/src/a", "/src/b"])
        XCTAssertEqual(steps.count, 1)
        let update = try XCTUnwrap(sevenZip(steps[0]))
        XCTAssertEqual(update.archive, "/tmp/out.7z")
        XCTAssertEqual(update.sources, ["/src/a", "/src/b"])
        XCTAssertEqual(update.options.format, "7z")
        XCTAssertEqual(update.options.level, 5)
        XCTAssertEqual(update.options.solid, 1)
        XCTAssertEqual(update.options.password, "pw")
        XCTAssertTrue(update.options.encryptHeaders)
        XCTAssertEqual(update.options.volumeSize, 100 << 20)
        XCTAssertTrue(update.options.deleteSources)
    }

    func testEmptyPasswordMeansNoEncryption() throws {
        let steps = options(.sevenZip) {
            $0.password = ""
            $0.encryptNames = true
        }.buildSteps(items: ["/src/a"])
        let update = try XCTUnwrap(sevenZip(steps[0]))
        XCTAssertNil(update.options.password)
        XCTAssertFalse(update.options.encryptHeaders)
    }

    func testZipUsesAESWithAPassword() throws {
        let update = try XCTUnwrap(sevenZip(options(.zip) { $0.password = "pw"; $0.level = 0 }.buildSteps(items: ["/src/a"])[0]))
        XCTAssertEqual(update.options.format, "zip")
        XCTAssertEqual(update.options.level, 0)
        XCTAssertTrue(update.options.zipAES256)
        XCTAssertEqual(update.options.solid, -1)
    }

    func testTarGzIsPackedThenCompressed() throws {
        let steps = options(.tgz) { $0.level = 5; $0.deleteAfter = true }.buildSteps(items: ["/src/a"])
        XCTAssertEqual(steps.count, 2)
        let pack = try XCTUnwrap(sevenZip(steps[0]))
        let compress = try XCTUnwrap(sevenZip(steps[1]))
        XCTAssertEqual(pack.options.format, "tar")
        XCTAssertTrue(pack.options.deleteSources)
        XCTAssertTrue(pack.archive.hasSuffix(".tar"))
        XCTAssertEqual(compress.options.format, "gzip")
        XCTAssertEqual(compress.options.level, 9)
        XCTAssertEqual(compress.sources, [pack.archive])
        XCTAssertEqual(compress.archive, "/tmp/out.tar.gz")
        XCTAssertNotNil(steps[1].cleanup)
    }

    func testRarGoesToTheRarTool() throws {
        let steps = options(.rar5) {
            $0.password = "pw"
            $0.encryptNames = true
            $0.recoveryRecord = true
            $0.volumeSize = "100M"
        }.buildSteps(items: ["/src/a"])
        guard case .rar(let args) = steps[0].work else { return XCTFail("expected rar switches") }
        XCTAssertEqual(Array(args.suffix(3)), ["--", "/tmp/out.rar", "/src/a"])
        for expected in ["-ma5", "-rr3", "-v100M", "-hppw"] {
            XCTAssertTrue(args.contains(expected), "\(expected) missing from \(args)")
        }
    }

    func testSplitIsTheVolumeSizeOfAFormatThatSplits() {
        XCTAssertTrue(options(.rar5) { $0.volumeSize = "100M" }.isSplit)
        XCTAssertTrue(options(.sevenZip) { $0.volumeSize = "300k" }.isSplit)
        XCTAssertFalse(options(.rar5).isSplit)
        XCTAssertFalse(options(.zip) { $0.volumeSize = " " }.isSplit)
        XCTAssertFalse(options(.tar) { $0.volumeSize = "1m" }.isSplit)
    }

    /// rar writes a self-extracting archive as name.sfx, so that is the name asked for and reported.
    func testSelfExtractingRarIsWrittenAsSfx() throws {
        let sfx = options(.rar5) { $0.sfx = true }
        XCTAssertEqual(sfx.writtenPath, "/tmp/out.sfx")
        guard case .rar(let args) = sfx.buildSteps(items: ["/src/a"])[0].work else { return XCTFail("expected rar switches") }
        XCTAssertEqual(Array(args.suffix(3)), ["--", "/tmp/out.sfx", "/src/a"])
        XCTAssertTrue(args.contains { $0.hasPrefix("-sfx") }, "\(args)")

        XCTAssertEqual(options(.rar5).writtenPath, "/tmp/out.rar")
        XCTAssertEqual(options(.sevenZip) { $0.sfx = true }.writtenPath, "/tmp/out.7z")
    }
}
