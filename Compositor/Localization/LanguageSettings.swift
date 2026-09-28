import Foundation
import Observation

nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard self == .system else { return rawValue }
        return Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferredLanguages).first ?? "en"
    }
}

@MainActor @Observable
final class LanguageSettings {
    static let shared = LanguageSettings()
    static let storageKey = "appearance.language"
    private(set) var selection: AppLanguage
    private(set) var needsInitialSelection: Bool
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.storageKey).flatMap(AppLanguage.init(rawValue:))
        selection = saved ?? .system
        needsInitialSelection = saved == nil
    }

    var locale: Locale { Locale(identifier: selection.resolvedIdentifier()) }

    func select(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Self.storageKey)
        selection = language
        needsInitialSelection = false
        NotificationCenter.default.post(name: .applicationLanguageDidChange, object: self)
    }
}

/// Look up presentation text in the chosen bundle. Stored names and enum raw values remain unchanged.
enum L10n {
    static func text(_ key: String) -> String { text(key, language: LanguageSettings.shared.selection) }

    nonisolated static func text(_ key: String, language: AppLanguage) -> String {
        guard let path = Bundle.main.path(forResource: language.resolvedIdentifier(), ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg..., language: AppLanguage? = nil) -> String {
        let selected = language ?? LanguageSettings.shared.selection
        return String(format: text(key, language: selected), locale: Locale(identifier: selected.resolvedIdentifier()),
                      arguments: arguments)
    }
}

extension Notification.Name {
    static let applicationLanguageDidChange = Notification.Name("Compositor.applicationLanguageDidChange")
}
