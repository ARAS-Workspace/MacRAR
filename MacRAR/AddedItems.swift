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
}
