import Foundation

/// Temporary folders created during the session; removed on quit
enum TempDirs {
    private static var created: [String] = []
    private static let lock = NSLock()
    static func make(_ prefix: String = "Archiver") -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)").path
        lock.lock(); created.append(path); lock.unlock()
        return path
    }
    static func cleanupAll() {
        lock.lock(); let list = created; created = []; lock.unlock()
        for path in list { try? FileManager.default.removeItem(atPath: path) }
    }
}
