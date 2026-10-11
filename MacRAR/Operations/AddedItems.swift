import Foundation

/// What goes into an archive that is open: never the archive itself. rar leaves the archive it updates out of the
/// items, while 7-Zip packs a copy of it into itself.
extension Ops {
    /// A file's identity on its volume, whatever the Unicode form of its name or the links on the way to it, and whether
    /// it is a folder; nil for a path that names nothing.
    private static func identity(of path: String) -> (id: any NSObjectProtocol, isFolder: Bool)? {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey, .isDirectoryKey]),
              let id = values.fileResourceIdentifier else { return nil }
        return (id, values.isDirectory ?? false)
    }

    /// The items to add to the archive at `archive`: the ones given, the archive itself left out.
    static func itemsToAdd(_ items: [String], into archive: String) -> [String] {
        guard let own = identity(of: archive)?.id else { return items }
        return items.filter { item in identity(of: item).map { !$0.id.isEqual(own) } ?? true }
    }

    /// The folder among `items` that holds the archive at `archive`, however deep. The folders above the archive are
    /// known first, and only the items that are folders are looked at, each once: a drop of thousands of files spent
    /// seconds here on the main thread when every item was compared with every folder above.
    static func folder(holding archive: String, among items: [String]) -> String? {
        var ancestors: [any NSObjectProtocol] = []
        var parent = URL(fileURLWithPath: archive).resolvingSymlinksInPath().deletingLastPathComponent()
        while parent.path != "/" {
            if let id = identity(of: parent.path)?.id { ancestors.append(id) }
            parent = parent.deletingLastPathComponent()
        }
        return items.first { item in
            guard let found = identity(of: item), found.isFolder else { return false }
            return ancestors.contains { $0.isEqual(found.id) }
        }
    }

    /// Why `items` cannot go into the archive `info` describes, for the user; nil when they can. 7-Zip, which the app
    /// cannot tell to leave a file out, packs a copy of the archive into itself along with the folder that holds it;
    /// rar leaves the archive out.
    static func addProblem(_ items: [String], into info: ArchiveInfo) -> String? {
        guard info.kind != .rar, let folder = folder(holding: info.path, among: items) else { return nil }
        return loc.t("add_folder_holds_archive", (folder as NSString).lastPathComponent)
    }
}
