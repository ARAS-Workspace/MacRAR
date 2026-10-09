import Foundation

let loc = LocalizationManager.shared

final class LocalizationManager: Sendable {

    enum Language: String, CaseIterable, Identifiable, Sendable {
        case tr, en
        var id: String { rawValue }

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

    let current: Language
    private let strings: [String: String]

    init() {
        current = Self.resolveLanguage()
        strings = Self.loadStrings(for: current)
    }

    func t(_ key: String) -> String {
        strings[key] ?? key
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        let template = strings[key] ?? key
        return String(format: template, arguments: args)
    }

    private static func resolveLanguage() -> Language {
        if let forced = ProcessInfo.processInfo.environment["MACRAR_LANG"] {
            return Language(identifier: forced)
        }
        if let saved = UserDefaults.standard.string(forKey: "Language"), !saved.isEmpty {
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
