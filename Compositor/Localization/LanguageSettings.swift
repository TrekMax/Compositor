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

    /// Resolve errors at the presentation boundary; their model descriptions stay independent of the UI language.
    static func errorDescription(_ error: Error, language: AppLanguage? = nil) -> String {
        let selected = language ?? LanguageSettings.shared.selection
        let locale = Locale(identifier: selected.resolvedIdentifier())
        switch error {
        case ImageImportError.tooLarge:
            return format("This import exceeds the current %lld-megapixel document budget or %@-pixel side limit.",
                          DocumentLimits.documentBudgetMegapixels, DocumentLimits.maxSide.formatted(.number.locale(locale)),
                          language: selected)
        case ImageImportError.tooManyFrames:
            return format("This animation has more than %@ frames, which exceeds the current timeline limit.",
                          GIFTimelineLimits.maxFrames.formatted(.number.locale(locale)), language: selected)
        case ProjectError.version(let version):
            return format("This project uses format version %lld. This app supports versions 1–%lld and 27.",
                          version, ProjectManifest.current, language: selected)
        case ProjectError.tooLarge:
            return format("This project exceeds the supported canvas, layer, file-size, or %lld-megapixel document limit.",
                          DocumentLimits.documentBudgetMegapixels, language: selected)
        case ExportError.tooLarge:
            return format("Image export supports canvases up to %lld megapixels and %@ pixels per side.",
                          DocumentLimits.maxSurfaceMegapixels, DocumentLimits.maxSide.formatted(.number.locale(locale)),
                          language: selected)
        case GIFExportError.tooLarge:
            return format("Animation export supports up to %@ frames, %lld megapixels across all exported frames, and 512 MiB of encoded data. Reduce the export size or frame count.",
                          GIFTimelineLimits.maxFrames.formatted(.number.locale(locale)), GIFExporter.pixelBudget / 1_000_000,
                          language: selected)
        default:
            return text(error.localizedDescription, language: selected)
        }
    }
}

extension Notification.Name {
    static let applicationLanguageDidChange = Notification.Name("Compositor.applicationLanguageDidChange")
}
