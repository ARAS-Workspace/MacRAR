import XCTest
@testable import MacRAR

/// The listing the window shows: 7-Zip's listing turned into ArchiveInfo the way the 7zz -slt parser used to.
final class ArchiveReaderTests: XCTestCase {
    private var workspace: Workspace!

    override func setUpWithError() throws {
        workspace = try Workspace()
    }

    override func tearDown() {
        workspace = nil
    }

    private func info(_ archive: String, password: String? = nil, file: StaticString = #filePath, line: UInt = #line) -> ArchiveInfo? {
        guard case .ok(let info) = ArchiveReader.list(archive, password: password) else {
            XCTFail("\(archive) did not list", file: file, line: line)
            return nil
        }
        return info
    }

    func testSevenZipDetailsAndEntries() throws {
        let archive = workspace.path("plain.7z")
        update(archive, workspace.sources, SevenZipBridge.UpdateOptions(format: "7z", solid: 1))
        let info = try XCTUnwrap(info(archive))

        XCTAssertEqual(info.details, "7z, solid")
        XCTAssertEqual(info.type, "7z")
        XCTAssertEqual(info.kind, .other)
        XCTAssertFalse(info.tarCompressed)
        XCTAssertTrue(info.supportsModification)
        XCTAssertEqual(info.fileCount, 3)

        let binary = try XCTUnwrap(info.entries.first { $0.name == "sub/b.bin" })
        XCTAssertEqual(binary.size, 1 << 20)
        XCTAssertNotNil(binary.crc.range(of: #"^[0-9A-F]{8}$"#, options: .regularExpression), binary.crc)
        XCTAssertNotNil(binary.mtime.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#, options: .regularExpression), binary.mtime)
        XCTAssertFalse(binary.compression.isEmpty)

        let folder = try XCTUnwrap(info.entries.first { $0.name == "sub" })
        XCTAssertTrue(folder.isDirectory)
    }

    func testCompressedTarIsShownAsTar() throws {
        let tar = workspace.path("pack.tar")
        update(tar, workspace.sources, SevenZipBridge.UpdateOptions(format: "tar"))
        let archive = workspace.path("pack.tgz")
        update(archive, [tar], SevenZipBridge.UpdateOptions(format: "gzip"))

        let info = try XCTUnwrap(info(archive))
        XCTAssertEqual(info.details, "tar + gzip")
        XCTAssertTrue(info.tarCompressed)
        XCTAssertFalse(info.supportsModification)
    }

    func testEncryptedHeadersAskForThePassword() throws {
        let archive = workspace.path("secret.7z")
        var options = SevenZipBridge.UpdateOptions(format: "7z", password: "pw")
        options.encryptHeaders = true
        update(archive, workspace.sources, options)

        guard case .wrongPassword = ArchiveReader.list(archive, password: nil) else {
            return XCTFail("an archive with encrypted headers listed without a password")
        }
        let info = try XCTUnwrap(info(archive, password: "pw"))
        XCTAssertTrue(info.headersEncrypted)
        XCTAssertTrue(info.hasEncryptedFiles)
    }

    func testNotAnArchiveIsReportedAsSuch() {
        guard case .error(let result) = ArchiveReader.list(workspace.path("src/a.txt"), password: nil) else {
            return XCTFail("a text file listed")
        }
        XCTAssertTrue(result.notArchive)
        XCTAssertFalse(result.ok)
    }
}
