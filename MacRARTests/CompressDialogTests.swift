import XCTest
@testable import MacRAR

/// The Create Archive dialog names the file that will be written: rar writes a self-extracting archive as .sfx, so the
/// path field follows the SFX box as well as the format.
final class CompressDialogTests: XCTestCase {
    func testArchiveNameFollowsTheFormatAndSfx() {
        XCTAssertEqual(CompressOptions.archivePath("/a/x.rar", format: .rar5, sfx: true), "/a/x.sfx")
        XCTAssertEqual(CompressOptions.archivePath("/a/x.sfx", format: .rar5, sfx: false), "/a/x.rar")
        XCTAssertEqual(CompressOptions.archivePath("/a/x.sfx", format: .sevenZip, sfx: true), "/a/x.7z")
        XCTAssertEqual(CompressOptions.archivePath("/a/x.7z", format: .rar5, sfx: true), "/a/x.sfx")
        // A name that already fits the format stays as the user wrote it
        XCTAssertEqual(CompressOptions.archivePath("/a/x.tgz", format: .tgz, sfx: false), "/a/x.tgz")
        XCTAssertEqual(CompressOptions.archivePath("/a/x.rar", format: .rar5, sfx: false), "/a/x.rar")
    }

    private func views<T: NSView>(_ type: T.Type, in root: NSView?) -> [T] {
        guard let root else { return [] }
        return root.subviews.flatMap { child in [child].compactMap { $0 as? T } + views(type, in: child) }
    }

    func testSfxBoxRenamesTheArchive() throws {
        var options = CompressOptions(archivePath: "/a/x.rar")
        options.format = .rar5
        let dialog = CompressDialog(options: options, itemCount: 1)
        let content = try XCTUnwrap(dialog.window?.contentView)
        let path = try XCTUnwrap(views(NSTextField.self, in: content).first { $0.stringValue == "/a/x.rar" })
        let sfx = try XCTUnwrap(views(NSButton.self, in: content).first { $0.title == loc.t("compress_sfx") })
        XCTAssertTrue(sfx.isEnabled)

        sfx.performClick(nil)
        XCTAssertEqual(path.stringValue, "/a/x.sfx")
        sfx.performClick(nil)
        XCTAssertEqual(path.stringValue, "/a/x.rar")

        sfx.performClick(nil)
        let format = try XCTUnwrap(views(NSPopUpButton.self, in: content).first { $0.itemTitles.contains("7z") })
        format.selectItem(withTitle: "7z")
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(format.action), to: format.target, from: format))
        XCTAssertEqual(path.stringValue, "/a/x.7z")
    }
}
