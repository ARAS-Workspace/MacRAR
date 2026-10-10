import Foundation

/// What the app was launched to do. Finder Quick Actions call "open -n -a MacRAR --args --command file...";
/// anything else is a list of files to open.
struct LaunchArguments: Equatable {
    var command: Command?
    var files: [String] = []

    init(_ arguments: [String]) {
        // Drop arguments macOS adds, such as -psn_... / -NSDocumentRevisionsDebugMode
        let args = arguments.filter { !$0.hasPrefix("-psn_") && $0 != "-NSDocumentRevisionsDebugMode" && $0 != "YES" }
        guard let flagIndex = args.firstIndex(where: { $0.hasPrefix("--") }) else {
            files = args.filter { !$0.hasPrefix("-") }.map(Self.standardized)
            return
        }
        let paths = args[(flagIndex + 1)...].filter { !$0.hasPrefix("--") }.map(Self.standardized)
        switch args[flagIndex] {
        case "--extract-here":     command = .extractHere(paths)
        case "--extract-folder":   command = .extractFolder(paths)
        case "--extract-to":       command = .extractTo(paths)
        case "--test":             command = .test(paths)
        case "--compress":         command = .compress(paths)
        case "--compress-dialog":  command = .compressDialog(paths)
        case "--set-default":      command = .setDefault
        case "--install-quick-actions": command = .installQuickActions
        default:
            files = paths
        }
    }

    private static func standardized(_ path: String) -> String { (path as NSString).standardizingPath }
}
