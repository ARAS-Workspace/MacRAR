import Foundation

func isDirectoryPath(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
}

func uniquePath(_ path: String, taken: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
    guard taken(path) else { return path }
    let ns = path as NSString
    let dir = ns.deletingLastPathComponent
    let ext = ns.pathExtension
    let base = (ns.deletingPathExtension as NSString).lastPathComponent
    var i = 2
    while true {
        let candidate = (dir as NSString).appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
        if !taken(candidate) { return candidate }
        i += 1
    }
}
