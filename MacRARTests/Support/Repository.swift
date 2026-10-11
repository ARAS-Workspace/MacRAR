import Foundation

/// The repository the tests belong to, found from this file (MacRARTests/Support/Repository.swift), so a test finds
/// the sources and External/ wherever in MacRARTests it sits.
enum Repository {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// MacRAR/, the app's sources.
    static let sources = root.appendingPathComponent("MacRAR")

    /// External/, where the fetched rar and the generated large files are.
    static let external = root.appendingPathComponent("External")
}
