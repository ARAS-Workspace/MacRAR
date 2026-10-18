import Foundation

/// A question the app puts to the user, as a value: what the alert says, the buttons it offers (the first is the
/// default) and what it asks besides, a box against seeing it again or boxes to tick. AppKitPrompter shows it,
/// DebugPrompter answers it by its topic, and tests read it without an alert.
struct Question: Equatable {
    /// What the question is about, which decides how DebugPrompter answers it.
    enum Topic: Equatable {
        /// A question Dialogs.ask puts: an archive already under the new name, the placement warning
        case question
        /// Dialogs.confirm: deleting from an archive, extracting what is dragged out
        case confirmation
        /// Which files the app opens
        case associations
        /// A newer release
        case update
        /// RARLAB's rar is missing: choose it, or download it first
        case rarToolMissing
        /// The download page is open: choose the tool once it is downloaded
        case rarToolDownloading
    }

    enum Style: Equatable { case informational, warning }

    /// A box to tick, with a line beneath it, orange when it warns.
    struct Choice: Equatable {
        let title: String
        let detail: String
        let warns: Bool
        let isOn: Bool
    }

    var topic: Topic
    var title = ""
    var message = ""
    var style: Style = .informational
    /// The app's icon set on the alert, rather than the one an alert shows by default
    var appIcon = false
    var buttons: [String] = []
    /// The first button destroys something
    var destructive = false
    /// The title of a box against seeing the question again
    var suppression: String?
    var choices: [Choice] = []
}

/// What the user answered: the button, 0 for the first, whether the box against seeing the question again was ticked,
/// and the choices ticked, by their place.
struct Answer: Equatable {
    var button: Int
    var suppressed = false
    var chosen: [Int] = []
}
