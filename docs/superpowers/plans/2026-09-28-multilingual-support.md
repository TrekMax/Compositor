# Multilingual support implementation plan

**Goal:** Support English, Simplified Chinese, and the system language, with a first-launch choice and persistent menu selection.

**Architecture:** An observable language preference owns a namespaced UserDefaults key and resolves supported languages. SwiftUI roots receive its locale; AppKit and dynamic labels use an explicit resource-bundle lookup. Presentation strings are translated without changing persisted enum values, shortcut identifiers, project names, or user content.

**Constraints:** macOS 26; no new dependency; no project format change; keep the editor and document history alive when switching languages.

- [x] Add tests for first-run state, selection persistence, invalid saved preferences, system-language fallback, and resource lookup.
- [x] Implement language preferences and shared localization lookup, plus English and Chinese resources.
- [x] Present the first-run language chooser once at app launch; add a checked Language menu and update all SwiftUI hosting roots.
- [x] Localize menus, controls, dynamic option names, tooltips, and AppKit dialogs at presentation boundaries.
- [x] Run focused tests, the existing CompositorTests suite, a build, resource checks, and git diff --check. Inspect first-run and switching behavior in the app where possible.

## Validation

- Xcode-beta build with signing disabled succeeded.
- Final full `CompositorTests` run: 489 passed, 0 failed.
- Final resource update: all 7 `LanguageSettingsTests` passed; 1,026 English/Chinese keys and their format placeholders match.
- Native UI checked: first-run language preview and confirmation, immediate English/Chinese/system switching, unchanged canvas dimensions and layers, menu headings after creating a canvas, localized save confirmation, and restored language without repeated onboarding after relaunch.
- An earlier concurrent run hit the existing external-change test's fixed-delay `pending` assertion. The isolated six-test group and the final complete suite passed without changing file-watcher behavior.
- Temporary canvases were discarded and the test-only language preference was removed, restoring the original first-run state.
