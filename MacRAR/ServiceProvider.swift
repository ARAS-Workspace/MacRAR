import AppKit

#if APPSTORE
/// App Store edition: the commands in Finder's context menu come from the app's own Services
/// (~/Library/Services is not writable inside the sandbox). They are defined in Info.plist → NSServices.
final class ServiceProvider: NSObject {
    private func paths(_ pboard: NSPasteboard) -> [String] {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.map { $0.path }
    }
    private func run(_ make: ([String]) -> Command, _ pboard: NSPasteboard) {
        let selected = paths(pboard)
        guard !selected.isEmpty else { return }
        let cmd = make(selected)
        DispatchQueue.main.async { AppDelegate.shared.runServiceCommand(cmd) }
    }
    @objc func extractHere(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        run({ .extractHere(Formats.filterArchives($0)) }, pboard)
    }
    @objc func extractToFolder(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        run({ .extractFolder(Formats.filterArchives($0)) }, pboard)
    }
    @objc func extractTo(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        run({ .extractTo(Formats.filterArchives($0)) }, pboard)
    }
    @objc func testArchive(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        run({ .test(Formats.filterArchives($0)) }, pboard)
    }
    @objc func compress(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        run({ .compressDialog($0) }, pboard)
    }
    @objc func quickCompress(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        run({ .compress($0) }, pboard)
    }
}
#endif
