import Foundation

/// App identity
enum AppInfo {
    static let name: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MacRAR"
    /// "1.4.2+ARAS.Patch.1": the original developer's release and the ARAS patch round on top of it
    static let version: String = Bundle.main.object(forInfoDictionaryKey: "ARASDistributionVersion") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    /// The user's home folder, from the user database
    static let realHome: String = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }()
    static func abbreviate(_ path: String) -> String {
        path == realHome ? "~" : (path.hasPrefix(realHome + "/") ? "~" + path.dropFirst(realHome.count) : path)
    }
    static var supportDir: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.path
        return (base as NSString).appendingPathComponent(name)
    }
}
