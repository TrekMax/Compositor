# Tools branch localization for Compositor 1.6.3

**Goal:** Preserve the five tools commits on upstream/main 7f703b4 and complete English/Simplified Chinese presentation for the newer interface.

**Architecture:** Keep LanguageSettings, L10n and the two Localizable.strings catalogs. SwiftUI literal keys use applicationLanguage; dynamic strings and AppKit labels use L10n.text/format. Keep stored enum values, shortcut IDs, project metadata, file names and user text unchanged.

**Constraints:** The user selected local main/upstream/main instead of the stale origin/main. Do not push. Preserve English, Simplified Chinese and Follow System, saved shortcuts, Paint Bucket and configurable tool tips. No new dependencies or project-format changes beyond upstream's v21.

- [x] Back up feat/tools, rebase its five commits and resolve changed control/command paths while retaining upstream behavior.
- [x] Add matching English/Chinese entries for the newer filters, export, GIF, layer/font search, align/distribute, menus, help and accessibility labels; check duplicate keys and format placeholders.
- [x] Localize new AppKit controls and dynamic SwiftUI labels, retaining stable identifiers and current actions.
- [x] Add focused catalog/lookup/menu regression coverage and exercise both explicit languages.
- [x] Run CompositorTests, build, review the integrated diff and verify ancestry, range-diff, conflict state and staged scope.

Baseline: LanguageSettingsTests, ShortcutSettingsTests and PaintBucketTests passed on f2a6870 before rebase. Backup: backup/feat-tools-before-rebase-20261104.

## Integration and validation

- The selected base is `upstream/main` / local `main` at `7f703b4` (1.6.3), 173 commits beyond `origin/main` at `365b574`. Upstream adds GIF frame editing/export, layer and font search, align/distribute, adaptive tool rails, more filters and adjustment layers, and 16-bit editing improvements.
- Range-diff preserves the original five commits in order. Conflict resolutions retain the newer tool rail, selected-layer actions, Save/Open text editing, and test-host updater behavior.
- The catalogs contain 1,610 matching keys per language, 556 additions. Duplicate-key, placeholder, English-key and compiler-extracted literal checks pass. The remaining extracted literals are numbers/symbols, the app name, or intentionally bilingual language choices.
- Paint Bucket now matches against the selected GIF frame that it edits. Its regression failed before the fix, then passed; it checks region boundaries, preservation of another frame, and undo.
- Focused tests passed 77/77, covering languages, native menus, Paint Bucket, shortcut persistence, tooltips, layer/export behavior, tab labels, and external changes.
- An unmodified archive of `upstream/main` ran 792 tests: 790 passed; `ExternalChangeTests/unsavedWorkIsNeverReplacedWithoutAsking` and `writingThePackageElsewhereReloadsTheOpenProject` failed while waiting for external-file monitoring. The latter also failed in the first integrated full run. The focused external-change suite passed.
- English and Simplified Chinese Debug windows were launched and checked in screenshots. Accessibility-tree reads were blocked by the host, so this is visual smoke evidence, not mouse-interaction acceptance. No system installation or push was performed.
- Final stable-snapshot build succeeded and the full suite ran 826 tests: 823 passed, with only the three external-monitor tests failing (`halfWrittenPackagesAreIgnoredUntilTheyLoad`, `unsavedWorkIsNeverReplacedWithoutAsking`, and `writingThePackageElsewhereReloadsTheOpenProject`). The last two reproduced on the upstream baseline; the first did not fail in that baseline run. A separate final run of all six `ExternalChangeTests` passed. The full suite is therefore not green; no external-monitor behavior or timeout was changed to mask the failures.
- Integrated source review found no remaining important findings in the scoped fixes. Ancestry, five-commit range-diff, unresolved-conflict and whitespace checks passed. The original branch remains available at the backup ref above.
