# Language settings implementation plan

**Goal:** Move language selection into a native settings window opened from the Compositor application menu or Command-comma.

**Architecture:** A SwiftUI Settings scene hosts a localized form. Its picker reads and writes the existing LanguageSettings preference, so changes apply immediately without resetting the editor or changing stored identifiers.

**Constraints:** Keep first-launch language selection, English, Simplified Chinese, and Follow System. Remove the separate Language menu. No project format changes or new dependencies.

- [x] Add ApplicationSettingsView with a language picker. Replace appSettings on the Settings scene itself with a localized SettingsLink and Command-comma shortcut; attaching the replacement to the editor scene creates duplicate entries.
- [x] Register the Settings scene, remove LanguageCommands, and update onboarding text and English/Chinese resources.
- [x] Run LanguageSettingsTests, build, and verify menu entry, shortcut, switching, window reuse, and retained selection in the app.
- [x] Update the interface-language documentation and run git diff --check.

Validation: Release build and all 489 CompositorTests passed. Checked the single settings menu entry, Command-comma, closing/reopening the window, immediate language changes, and saved language after relaunch. English/Chinese resources have 1,029 matching keys.
