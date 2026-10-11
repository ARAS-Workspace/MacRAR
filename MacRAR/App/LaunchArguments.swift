import Foundation

/// What a launch asks the app to do instead of opening windows: a Finder Quick Action's mode, or a setup step.
enum Command: Equatable {
    case extractHere([String])
    case extractFolder([String])
    case extractTo([String])
    case test([String])
    case compress([String])
    case compressDialog([String])
    case setDefault
    case installQuickActions
}

/// What the app was launched to do. Finder Quick Actions call "open -n -a MacRAR --args --command file...";
/// anything else is a list of files to open.
struct LaunchArguments: Equatable {
    var command: Command?
    var files: [String] = []

    init(_ arguments: [String]) {
        let args = Self.droppingDefaults(arguments)
        guard let flagIndex = args.firstIndex(where: { $0.hasPrefix("--") }) else {
            files = args.map(Self.standardized)
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

    /// Drops what is neither a command nor a file: "-psn_…" from LaunchServices, and "-Key value" pairs, which
    /// UserDefaults reads into its argument domain (-NSDocumentRevisionsDebugMode YES from Xcode,
    /// -ApplePersistenceIgnoreState YES and -NSTreatUnknownArgumentsAsOpen NO from XCTest, -AppleLanguages (tr)).
    private static func droppingDefaults(_ arguments: [String]) -> [String] {
        var kept: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if argument.hasPrefix("-psn_") {
                index += 1
            } else if argument.hasPrefix("-"), !argument.hasPrefix("--") {
                index += 2
            } else {
                kept.append(argument)
                index += 1
            }
        }
        return kept
    }

    private static func standardized(_ path: String) -> String { (path as NSString).standardizingPath }
}
