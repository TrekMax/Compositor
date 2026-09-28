# Interface languages

Compositor supports English and Simplified Chinese. On first launch, choose a language or **Follow System**. Open **Compositor → Settings…** (Command-comma) to change the interface language. Changes apply immediately and are remembered for future launches.

Settings uses a native sidebar and detail layout. Language options live under **General**. To add a settings page, extend `SettingsCategory` and its detail switch in `ApplicationSettings.swift`, and implement the page as a separate view. The window starts at 760 × 480 points and can resize down to 680 × 420 points.

The preference lives in `UserDefaults` under `appearance.language` (`system`, `en`, or `zh-Hans`). A missing or invalid value requests a choice again. System mode matches the Mac's preferred languages against the supported languages, with English as the fallback. It does not modify macOS's `AppleLanguages` preference.

## Adding or changing text

- Keep matching keys in `Compositor/Localization/en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings`.
- SwiftUI literal labels use the locale supplied by `applicationLanguage()` at hosting roots. `roundedControls()` includes this modifier for editor dialogs and detached panels.
- Use `L10n.text` for dynamic application labels and AppKit text, and `L10n.format` for formatted messages. SwiftUI command menus need explicit lookups because they do not inherit the editor view's environment.
- Keep format placeholders identical across translations. Pass user-provided names as format arguments, rather than looking them up as translation keys.
- Do not translate enum raw values, shortcut IDs, project metadata, file names, or user text. For native menu selections, use an identifier or `representedObject`, not the displayed title.
- macOS-owned file dialog controls, Services, and third-party updater UI follow their own system localization. Application-owned labels and dialog titles use the selected language.

Run `LanguageSettingsTests` for initial choice, preference persistence, language matching, resource lookup, and translated blend-mode selection. Existing layer-menu and save-alert tests use localized display labels. The project format is unchanged.
