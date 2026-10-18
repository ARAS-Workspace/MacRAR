import Foundation

/// An open panel, or a save panel, as a value.
struct Panel: Equatable {
    enum Kind: Equatable { case open, save }
    var kind = Kind.open
    var title = ""
    var message: String?
    var prompt: String?
    var files = true
    var folders = false
    var createFolders = false
    var multiple = false
    /// Only the archives the app opens, though other files may still be chosen
    var archivesOnly = false
    var directory: URL?
    /// The name a save panel starts with
    var name: String?
}
