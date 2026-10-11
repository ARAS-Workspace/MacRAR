import AppKit

extension AppDelegate {
    /// MACRAR_SNAPSHOT=/path/prefix: the windows on screen are saved as PNG files, and the app quits.
    func scheduleDebugSnapshot() {
        guard let prefix = ProcessInfo.processInfo.environment["MACRAR_SNAPSHOT"] else { return }
        let delay = Double(ProcessInfo.processInfo.environment["MACRAR_SNAPSHOT_DELAY"] ?? "") ?? 2.0
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            var i = 0
            for window in NSApp.windows where window.isVisible {
                guard let frame = window.contentView?.superview else { continue }
                func dump(_ v: NSView) {
                    if let indicator = v as? NSProgressIndicator {
                        print("progress bar value:", indicator.doubleValue, "indeterminate:", indicator.isIndeterminate)
                    }
                    v.subviews.forEach(dump)
                }
                dump(frame)
                guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { continue }
                frame.cacheDisplay(in: frame.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(prefix)-\(i).png"))
                    i += 1
                }
            }
            exit(0)
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
