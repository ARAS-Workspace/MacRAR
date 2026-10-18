import AppKit

/// User settings (UserDefaults): the app's own, through the store the Settings window, Create Archive and the
/// operations share.
enum Prefs {
    static let store = PrefsStore()

    static var defaultFormat: ArchiveFormat {
        get { store.defaultFormat }
        set { store.defaultFormat = newValue }
    }
    static var defaultLevel: Int {
        get { store.defaultLevel }
        set { store.defaultLevel = newValue }
    }
    static var solid: Bool { get { store.solid } set { store.solid = newValue } }
    static var recoveryRecord: Bool {
        get { store.recoveryRecord }
        set { store.recoveryRecord = newValue }
    }
    static var revealAfterExtract: Bool {
        get { store.revealAfterExtract }
        set { store.revealAfterExtract = newValue }
    }
    static var revealAfterCompress: Bool {
        get { store.revealAfterCompress }
        set { store.revealAfterCompress = newValue }
    }
    static var checkUpdates: Bool {
        get { store.checkUpdates }
        set { store.checkUpdates = newValue }
    }
}

/// The settings in the UserDefaults the store is given: the app's own for Prefs, a suite of their own for tests and
/// previews, which then leave the user's settings alone. A format is RAR 5 by default when rar is there, as
/// `rarAvailable` says.
final class PrefsStore {
    let defaults: UserDefaults
    private let rarAvailable: () -> Bool

    init(defaults: UserDefaults = .standard, rarAvailable: @escaping () -> Bool = { RarTools.available }) {
        self.defaults = defaults
        self.rarAvailable = rarAvailable
    }

    var defaultFormat: ArchiveFormat {
        get {
            let fallback: ArchiveFormat = rarAvailable() ? .rar5 : .zip
            guard defaults.object(forKey: "DefaultFormat") != nil,
                  let f = ArchiveFormat(rawValue: defaults.integer(forKey: "DefaultFormat")) else { return fallback }
            return f
        }
        set { defaults.set(newValue.rawValue, forKey: "DefaultFormat") }
    }
    var defaultLevel: Int {
        get { defaults.object(forKey: "DefaultLevel") == nil ? 3 : max(0, min(5, defaults.integer(forKey: "DefaultLevel"))) }
        set { defaults.set(newValue, forKey: "DefaultLevel") }
    }
    var solid: Bool { get { defaults.bool(forKey: "DefaultSolid") } set { defaults.set(newValue, forKey: "DefaultSolid") } }
    var recoveryRecord: Bool {
        get { defaults.bool(forKey: "DefaultRecovery") }
        set { defaults.set(newValue, forKey: "DefaultRecovery") }
    }
    var revealAfterExtract: Bool {
        get { defaults.object(forKey: "RevealAfterExtract") == nil ? true : defaults.bool(forKey: "RevealAfterExtract") }
        set { defaults.set(newValue, forKey: "RevealAfterExtract") }
    }
    var revealAfterCompress: Bool {
        get { defaults.object(forKey: "RevealAfterCompress") == nil ? true : defaults.bool(forKey: "RevealAfterCompress") }
        set { defaults.set(newValue, forKey: "RevealAfterCompress") }
    }
    var checkUpdates: Bool {
        get { defaults.object(forKey: "CheckUpdates") == nil ? true : defaults.bool(forKey: "CheckUpdates") }
        set { defaults.set(newValue, forKey: "CheckUpdates") }
    }
}
