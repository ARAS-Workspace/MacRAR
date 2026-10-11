import Foundation

/// What goes into an archive that is open: never the archive itself. rar leaves the archive it updates out of the
/// items, while 7-Zip packs a copy of it into itself.
extension Ops {
    /// Whether two paths name the same file, whatever the Unicode form of their names or the links on the way.
    static func sameFile(_ lhs: String, _ rhs: String) -> Bool {
        func identifier(_ path: String) -> (any NSCopying & NSSecureCoding & NSObjectProtocol)? {
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            return try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        }
        guard let left = identifier(lhs), let right = identifier(rhs) else { return false }
        return left.isEqual(right)
    }

    /// The items to add to the archive at `archive`: the ones given, the archive itself left out.
    static func itemsToAdd(_ items: [String], into archive: String) -> [String] {
        items.filter { !sameFile($0, archive) }
    }

    /// The folder among `items` that holds the archive at `archive`, however deep.
    static func folder(holding archive: String, among items: [String]) -> String? {
        var ancestors: [String] = []
        var parent = URL(fileURLWithPath: archive).resolvingSymlinksInPath().deletingLastPathComponent()
        while parent.path != "/" {
            ancestors.append(parent.path)
            parent = parent.deletingLastPathComponent()
        }
        return items.first { item in ancestors.contains { sameFile($0, item) } }
    }

    /// Why `items` cannot go into the archive `info` describes, for the user; nil when they can. 7-Zip, which the app
    /// cannot tell to leave a file out, packs a copy of the archive into itself along with the folder that holds it;
    /// rar leaves the archive out.
    static func addProblem(_ items: [String], into info: ArchiveInfo) -> String? {
        guard info.kind != .rar, let folder = folder(holding: info.path, among: items) else { return nil }
        return loc.t("add_folder_holds_archive", (folder as NSString).lastPathComponent)
    }
}
