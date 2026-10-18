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

    /// Browse asks for a save panel that starts in the archive's folder with its name; cancelled, it leaves the path
    /// as it was.
    func testBrowseAsksForASavePanel() throws {
        var options = CompressOptions(archivePath: "/a/x.zip")
        options.format = .zip
        let dialog = CompressDialog(options: options, itemCount: 1)
        let content = try XCTUnwrap(dialog.window?.contentView)
        let path = try XCTUnwrap(views(NSTextField.self, in: content).first { $0.stringValue == "/a/x.zip" })
        let browse = try XCTUnwrap(views(NSButton.self, in: content).first { $0.title == loc.t("compress_browse") })
        let screen = UnseenScreen()
        withPrompter(screen) { browse.performClick(nil) }
        XCTAssertEqual(screen.reached, [
            .choose(Panel(kind: .save, title: loc.t("compress_save_panel_title"), directory: URL(fileURLWithPath: "/a"), name: "x.zip")),
        ])
        XCTAssertEqual(path.stringValue, "/a/x.zip")
    }

    /// The path chosen in Browse's save panel goes into the path field (MACRAR_DEBUG_CHOOSE answers the panel).
    func testBrowseTakesThePathChosen() throws {
        setDebugAnswers()
        defer { clearDebugAnswers() }
        var options = CompressOptions(archivePath: "/a/x.zip")
        options.format = .zip
        let dialog = CompressDialog(options: options, itemCount: 1)
        let content = try XCTUnwrap(dialog.window?.contentView)
        let path = try XCTUnwrap(views(NSTextField.self, in: content).first { $0.stringValue == "/a/x.zip" })
        let browse = try XCTUnwrap(views(NSButton.self, in: content).first { $0.title == loc.t("compress_browse") })
        withEnvironment(["MACRAR_DEBUG_CHOOSE": "/b/çıktı.zip"]) {
            XCTAssertEqual(printed { browse.performClick(nil) }, "choose \(loc.t("compress_save_panel_title"))\n")
        }
        XCTAssertEqual(path.stringValue, "/b/çıktı.zip")
    }

    /// Runs a Create Archive window modally, unseen, with `action` done to it once the run is up: what run() returned,
    /// or nil when the run did not end by itself and was stopped after five seconds.
    @MainActor
    private func leave(by action: @escaping @MainActor (NSWindow) -> Void) -> CompressOptions?? {
        let dialog = CompressDialog(options: CompressOptions(archivePath: NSTemporaryDirectory() + "unwritten.zip"), itemCount: 1)
        defer { dialog.close() }
        var stopped = false
        RunLoop.main.perform(inModes: [.modalPanel]) {
            MainActor.assumeIsolated { if let window = dialog.window { action(window) } }
        }
        let stop = DispatchWorkItem {
            guard NSApp.modalWindow != nil else { return }
            stopped = true
            NSApp.abortModal()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: stop)
        let returned = dialog.run()
        stop.cancel()
        return stopped ? nil : .some(returned)
    }

    @MainActor
    func testEscCancels() {
        let returned = leave { window in
            let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                       charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)
            if let esc { window.sendEvent(esc) }
        }
        XCTAssertEqual(returned.map { $0 == nil }, true, "the run did not end")
    }

    /// The close button cancels, as Esc does. It took the window off the screen and left the app in its modal run,
    /// with no window to answer.
    @MainActor
    func testTheCloseButtonCancels() {
        let returned = leave { $0.performClose(nil) }
        XCTAssertEqual(returned.map { $0 == nil }, true, "the run did not end")
    }
}
