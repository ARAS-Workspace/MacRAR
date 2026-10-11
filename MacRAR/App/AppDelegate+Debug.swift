import AppKit

extension AppDelegate {
    /// The debug modes a launch asks for in its environment. MACRAR_SNAPSHOT, MACRAR_DEBUG_ABOUT and MACRAR_DEBUG_PREFS
    /// add to a launch; MACRAR_DEBUG_ASSOC_APPLY and MACRAR_DEBUG_RARINSTALL do one thing and quit, and true says the
    /// launch is theirs.
    func runDebugLaunch() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        scheduleDebugSnapshot()
        if environment["MACRAR_DEBUG_ABOUT"] != nil { showAbout(nil) }
        if environment["MACRAR_DEBUG_PREFS"] != nil { showPreferences(nil) }
        if let ext = environment["MACRAR_DEBUG_ASSOC_APPLY"] {
            Associations.apply(Associations.types(for: [ext]), quiet: true) { ok, failed in
                print("assoc \(ext): ok=\(ok) failed=\(failed) handler=\(Associations.currentHandler(for: [ext]))"); exit(0)
            }
            return true
        }
        if let path = environment["MACRAR_DEBUG_RARINSTALL"] {
            do {
                try RarTools.install(from: URL(fileURLWithPath: path))
                print("RAR installed:", RarTools.version ?? "?", RarTools.installDir)
            } catch {
                print("RAR install failed:", error.localizedDescription)
            }
            exit(0)
        }
        return false
    }

    /// MACRAR_SNAPSHOT=/path/prefix: the windows on screen are saved as PNG files, and the app quits.
    private func scheduleDebugSnapshot() {
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
