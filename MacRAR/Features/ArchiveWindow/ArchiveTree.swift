import Foundation

final class Node: NSObject {
    let name: String
    let path: String
    let isDir: Bool
    var entry: ArchiveEntry?
    var children: [Node] = []
    weak var parent: Node?

    init(name: String, path: String, isDir: Bool) {
        self.name = name; self.path = path; self.isDir = isDir
    }

    var totalSize: Int64 {
        if !isDir { return entry?.size ?? 0 }
        return children.reduce(0) { $0 + $1.totalSize }
    }
    var totalPacked: Int64 {
        if !isDir { return entry?.packedSize ?? 0 }
        return children.reduce(0) { $0 + $1.totalPacked }
    }
    var containsEncrypted: Bool {
        if !isDir { return entry?.encrypted ?? false }
        return children.contains { $0.containsEncrypted }
    }

    func sortRecursively(key: String = "name", ascending: Bool = true) {
        children.sort { Node.compare($0, $1, key: key, ascending: ascending) }
        children.forEach { $0.sortRecursively(key: key, ascending: ascending) }
    }

    /// Folders always first; then by the selected column
    static func compare(_ lhs: Node, _ rhs: Node, key: String, ascending: Bool) -> Bool {
        if lhs.isDir != rhs.isDir { return lhs.isDir }
        var result: ComparisonResult
        func cmp<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
            left < right ? .orderedAscending : (left == right ? .orderedSame : .orderedDescending)
        }
        switch key {
        case "size": result = cmp(lhs.totalSize, rhs.totalSize)
        case "packed": result = cmp(lhs.totalPacked, rhs.totalPacked)
        case "date": result = (lhs.entry?.mtime ?? "").compare(rhs.entry?.mtime ?? "")
        case "ratio":
            let ra = lhs.totalSize > 0 ? Double(lhs.totalPacked) / Double(lhs.totalSize) : 0
            let rb = rhs.totalSize > 0 ? Double(rhs.totalPacked) / Double(rhs.totalSize) : 0
            result = cmp(ra, rb)
        default: result = lhs.name.localizedStandardCompare(rhs.name)
        }
        if result == .orderedSame { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }

    static func buildTree(_ entries: [ArchiveEntry]) -> Node {
        let root = Node(name: "", path: "", isDir: true)
        // The folders by path. A file is never in it, so one named like a folder does not take in the folder's items.
        var folders: [String: Node] = ["": root]
        // A name starting with "/" sits at the top, where 7-Zip extracts it; "/" above it was looked for without end
        func parent(of path: String) -> String {
            let above = (path as NSString).deletingLastPathComponent
            return above == "/" ? "" : above
        }
        func ensure(_ path: String) -> Node {
            if let existing = folders[path] { return existing }
            let parent = ensure(parent(of: path))
            let node = Node(name: (path as NSString).lastPathComponent, path: path, isDir: true)
            node.parent = parent
            parent.children.append(node)
            folders[path] = node
            return node
        }
        for entry in entries {
            let clean = entry.name.hasSuffix("/") ? String(entry.name.dropLast()) : entry.name
            if entry.isDirectory {
                ensure(clean).entry = entry
            } else {
                let parent = ensure(parent(of: clean))
                let node = Node(name: (clean as NSString).lastPathComponent, path: clean, isDir: false)
                node.entry = entry
                node.parent = parent
                parent.children.append(node)
            }
        }
        root.sortRecursively()
        return root
    }

    func flatten(into out: inout [Node]) {
        for child in children {
            out.append(child)
            child.flatten(into: &out)
        }
    }
}
