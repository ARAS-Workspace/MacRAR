import AppKit

/// User settings (UserDefaults)
enum Prefs {
    private static let defaults = UserDefaults.standard
    static var defaultFormat: ArchiveFormat {
        get {
            let fallback: ArchiveFormat = RarTools.available ? .rar5 : .zip
            guard defaults.object(forKey: "DefaultFormat") != nil,
                  let f = ArchiveFormat(rawValue: defaults.integer(forKey: "DefaultFormat")) else { return fallback }
            return f
        }
        set { defaults.set(newValue.rawValue, forKey: "DefaultFormat") }
    }
    static var defaultLevel: Int {
        get { defaults.object(forKey: "DefaultLevel") == nil ? 3 : max(0, min(5, defaults.integer(forKey: "DefaultLevel"))) }
        set { defaults.set(newValue, forKey: "DefaultLevel") }
    }
    static var solid: Bool { get { defaults.bool(forKey: "DefaultSolid") } set { defaults.set(newValue, forKey: "DefaultSolid") } }
    static var recoveryRecord: Bool {
        get { defaults.bool(forKey: "DefaultRecovery") }
        set { defaults.set(newValue, forKey: "DefaultRecovery") }
    }
    static var revealAfterExtract: Bool {
        get { defaults.object(forKey: "RevealAfterExtract") == nil ? true : defaults.bool(forKey: "RevealAfterExtract") }
        set { defaults.set(newValue, forKey: "RevealAfterExtract") }
    }
    static var revealAfterCompress: Bool {
        get { defaults.object(forKey: "RevealAfterCompress") == nil ? true : defaults.bool(forKey: "RevealAfterCompress") }
        set { defaults.set(newValue, forKey: "RevealAfterCompress") }
    }
    static var checkUpdates: Bool {
        get { defaults.object(forKey: "CheckUpdates") == nil ? true : defaults.bool(forKey: "CheckUpdates") }
        set { defaults.set(newValue, forKey: "CheckUpdates") }
    }
}
