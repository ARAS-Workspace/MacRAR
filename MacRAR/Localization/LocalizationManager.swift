import Foundation

let loc = LocalizationManager.shared

/// The interface language and its strings, read from translations/<language>.json, following phantom-wg's
/// LocalizationManager. Setting `current` saves the choice, loads the new strings and posts `didChange`; the menus,
/// open windows and Finder Quick Actions observe it and apply the language at once. The notification stands in
/// for SwiftUI's observation, which these AppKit views on macOS 13 do not have.
final class LocalizationManager: @unchecked Sendable {

    enum Language: String, CaseIterable, Identifiable, Sendable {
        case tr, en
        var id: String { rawValue }

        var flag: String {
            switch self {
            case .tr: return "\u{1F1F9}\u{1F1F7}"
            case .en: return "\u{1F1FA}\u{1F1F8}"
            }
        }

        var displayName: String {
            switch self {
            case .tr: return "Türkçe"
            case .en: return "English"
            }
        }

        init(identifier: String) {
            self = identifier.lowercased().hasPrefix("tr") ? .tr : .en
        }
    }

    static let shared = LocalizationManager()
    static let didChange = Notification.Name("LocalizationManagerDidChange")
    static let defaultsKey = "Language"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var language: Language
    private var strings: [String: String]

    var current: Language {
        get { lock.withLock { language } }
        set {
            guard newValue != current else { return }
            let loaded = Self.loadStrings(for: newValue)
            lock.withLock {
                language = newValue
                strings = loaded
            }
            defaults.set(newValue.rawValue, forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    init(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.defaults = defaults
        language = Self.resolveLanguage(defaults: defaults, environment: environment)
        strings = Self.loadStrings(for: language)
    }

    func t(_ key: String) -> String {
        lock.withLock { strings[key] } ?? key
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    /// MACRAR_LANG, then the saved choice, then the app's preferred localization (which follows the per-app
    /// language in System Settings).
    private static func resolveLanguage(defaults: UserDefaults, environment: [String: String]) -> Language {
        if let forced = DebugVariable.language.value(in: environment) {
            return Language(identifier: forced)
        }
        if let saved = defaults.string(forKey: defaultsKey), !saved.isEmpty {
            return Language(identifier: saved)
        }
        if let preferred = Bundle.main.preferredLocalizations.first {
            return Language(identifier: preferred)
        }
        return .en
    }

    private static func loadStrings(for language: Language) -> [String: String] {
        guard let url = Bundle.main.url(forResource: language.rawValue, withExtension: "json", subdirectory: "translations"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }
}
