import Foundation

/// The environment variables the app reads besides the user's own settings: the answers the tests give its questions
/// (DebugPrompter), the place and version a copy stands in for, the unseen windows, the language pinned, the update
/// check held back and the windows saved as pictures. The scheme's actions and the copies the tests start set them; a
/// user's run sets none. Each name is written here alone.
enum DebugVariable: String, CaseIterable {
    case confirm = "MACRAR_DEBUG_CONFIRM"
    case password = "MACRAR_DEBUG_PASSWORD"
    case passwordRetry = "MACRAR_DEBUG_PASSWORD_RETRY"
    case overwrite = "MACRAR_DEBUG_OVERWRITE"
    case update = "MACRAR_DEBUG_UPDATE"
    case choose = "MACRAR_DEBUG_CHOOSE"
    case rarTool = "MACRAR_DEBUG_RARTOOL"
    case format = "MACRAR_DEBUG_FORMAT"
    case encryptNames = "MACRAR_DEBUG_ENCNAMES"
    case placement = "MACRAR_DEBUG_PLACEMENT"
    case version = "MACRAR_DEBUG_VERSION"
    case unseen = "MACRAR_DEBUG_UNSEEN"
    case language = "MACRAR_LANG"
    case noUpdateCheck = "MACRAR_NO_UPDATE_CHECK"
    case snapshot = "MACRAR_SNAPSHOT"
    case snapshotDelay = "MACRAR_SNAPSHOT_DELAY"

    /// The value in `environment`, the process's unless one is given; nil when the variable is not set.
    func value(in environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        environment[rawValue]
    }
}
