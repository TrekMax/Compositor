# UI Source Structure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Organize the flat UI source directory, then independently split its large layer-list and keyboard-shortcut files.

**Architecture:** Keep the existing app module and organize UI sources by feature. First move files without changing their contents and update CI path consumers. Commit that independently before extracting existing declarations into focused source files.

**Tech Stack:** SwiftUI, AppKit, Swift Testing, Xcode synchronized source groups, Bash CI path matching.

## Global Constraints

- Continue the user-requested `refactor/editor-structure` branch from `7971b2f`.
- Preserve visible layout, actions, drag/drop, focus, keyboard shortcuts, saved preferences, localization, and model identifiers.
- Preserve existing method bodies and actor isolation. Any access-level widening must be limited to declarations that now cross files.
- Keep IO, rendering, editor logic, translations and resources in their existing source areas.
- Two focused signed-off local commits: relocation first, declaration splitting second. Do not push or reinstall.
- Use the existing tests; this mechanical refactor does not need implementation-mirroring tests.

## Task 1: Move UI files and update path consumers

**Files:** Move all 60 `Compositor/UI/*.swift` files into the groups below. Modify `.github/workflows/verify.yml`, `docs/source-structure.md`, and the source-layout note in `AGENTS.md`.

**Interfaces:** All existing Swift declarations and bundle resource names stay unchanged; synchronized source discovery handles nested folders.

| Destination | Existing files, without `.swift` |
| --- | --- |
| `Workspace/` | ProjectTabs, ProjectTabLayout, ProjectWindowBridge |
| `Canvas/` | CanvasRulers, CanvasSizeSheet, CanvasThumbnail, GridSettingsSheet, ImageSizeSheet, NavigatorMinimap, NewCanvasSheet, TrimSheet |
| `Layers/` | BlendModePicker, EffectsSheet, GIFTimeline, LayerAppearanceControls, LayerMaskMenu, LayerSearchControls, LayersPanel, NativeLayerList, TransformInspector |
| `Tools/` | BrushControls, ColorPaletteControls, ColorPickerSheet, CropControls, FontListPanel, GradientControls, NavigationToolHeader, PaintBucketControls, ShapeControls, ToolHeaderStyle, ToolRail, TypeControls |
| `Selection/` | ColorRangeSheet, LassoControls |
| `Adjustments/` | CurvesControls, HueSaturationSheet, LevelsSheet |
| `Adjustments/CameraRaw/` | CameraRawColorControls, CameraRawControls, CameraRawDetailOpticsControls, CameraRawGeometryCalibrationControls, CameraRawSlider |
| `Filters/` | FilterSheet |
| `ImportExport/` | ExportAsSheet, PSDConversionSheet, RawDevelopSheet |
| `Settings/` | ApplicationSettings, LanguageSelection, ToolTipSettings |
| `Commands/` | CommandPalette, CommandPaletteView, KeyboardShortcuts |
| `Input/` | HeldModifiers, LatinKeys, PenInput |
| `Shared/` | FloatingPanel, IndicatorlessScrollView, NumericScrub, SliderSnap, ToolTip |

- [x] Verify a complete one-to-one map, move with `git mv`, and compare every file against its base blob.
- [x] Add CI filter-suite matching for `UI/Adjustments/` and `UI/Filters/`; retain the old flat UI rule for deleted paths. Check all previously matched tracked paths through the actual `grep -E` expression, plus positive and negative cases.
- [x] Update the source guide and agent note. Search the repository for stale source-path consumers.
- [x] Build and run focused UI-related suites: languages, shortcuts, tooltips, layer list/search/masks/dragging, command palette, project tabs and input-related behavior. Use optimized Debug with the available Apple Development certificate to avoid the previously diagnosed ad-hoc/Hardened Runtime Sparkle launch conflict.
- [x] Obtain a read-only review, verify staged scope, and create the first local commit.

## Task 2: Split the layer list and shortcuts

**Files:** Split `Compositor/UI/Layers/NativeLayerList.swift` into files for the representable/coordinator, table behavior, cell and row accessories, effect row, thumbnail drag behavior, and image-layer presentation values. Split `Compositor/UI/Commands/KeyboardShortcuts.swift` into chord/definition/settings files and SwiftUI integration; place the editor sheet and its private recorder in `Compositor/UI/Settings/KeyboardShortcutsSheet.swift`.

**Interfaces:** Preserve `NativeLayerList.Coordinator`, `LayerTableView`, `MaskDisabledMark`, `ShortcutChord`, `ShortcutDefinition`, `ShortcutSettings`, and the existing `View` extension entry points. Keep helper members private unless cross-file use requires internal visibility. Preserve selectors, notification names, drag pasteboard types and keys.

- [x] Extract complete declarations, including associated comments and extensions. Keep related private helpers together; add only the imports needed by each destination.
- [x] Compare declaration bodies with the relocation commit, accounting only for imports, file separators and the minimal access changes. Review every access-level adjustment.
- [x] Update `docs/source-structure.md` with the split responsibilities.
- [x] Run the focused suites first, then the complete `CompositorTests` suite on the final source snapshot. If known full-run file-monitor timeouts recur, report them and rerun `ExternalChangeTests` separately; do not change unrelated monitor behavior.
- [x] Launch the development build and smoke-check layer selection/rename/reorder, shortcut editor and language switching when GUI automation is available; report any interaction that cannot be verified.
- [x] Obtain a read-only review, resolve findings, create the second local commit, and verify a clean worktree.

## Validation commands

Use DerivedData `/tmp/compositor-ui-structure-20261104`. The local build overrides are `CODE_SIGN_IDENTITY='Apple Development' CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=9BT9NV52NL GCC_OPTIMIZATION_LEVEL=s SWIFT_OPTIMIZATION_LEVEL=-O`.

```sh
xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -destination 'platform=macOS' -derivedDataPath /tmp/compositor-ui-structure-20261104 \
  -only-testing:CompositorTests CODE_SIGN_IDENTITY='Apple Development' \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=9BT9NV52NL \
  GCC_OPTIMIZATION_LEVEL=s SWIFT_OPTIMIZATION_LEVEL=-O test
git diff --check
```

## Phase 1 validation

- All 60 moved UI files are byte-identical to `7971b2f`.
- The actual CI regex retains all 66 previously covered tracked paths, including the nine moved UI files; new-path positive and unrelated negative cases pass.
- The signed optimized build and 13 focused suites passed 87/87 tests. Log: `/tmp/compositor-ui-structure-20261104-move-tests.log`.
- Read-only review found no source or CI defect; its requested search-coverage supplement passed all eight `GroupTests`, bringing focused coverage to 95/95 tests. Log: `/tmp/compositor-ui-structure-20261104-move-group-tests.log`.

## Phase 2 validation

- The two original source files were split into 11 files (nine new). Every original declaration and method body is preserved; seven access changes allow existing collaborators to cross file boundaries. The remaining private helpers stay with their consumers.
- `NativeLayerList.swift` now contains 537 lines. Its largest extracted file is `LayerCell.swift` at 456 lines. The shortcut files range from 15 to 130 lines.
- Independent read-only review reconstructed both original source bodies byte-for-byte after restoring the seven access levels and file separators. It found no defects and verified that all 11 files appear exactly once in Xcode's actual source list.
- The signed optimized build and 14 focused suites passed 95/95 tests. The complete `CompositorTests` run passed 826/826 tests with zero failures or skips, including the file-monitor tests that had timed out in earlier full runs. Logs: `/tmp/compositor-ui-structure-20261104-split-tests.log` and `/tmp/compositor-ui-structure-20261104-full-tests.log`.
- GUI smoke validation confirmed the development build's Chinese window, canvas creation, adding a layer, and selecting the first layer through its thumbnail. The window and selection were checked through both accessibility state and screenshots.
- Rename, drag reordering, the shortcut editor and live language switching remain GUI-unverified: background synthetic input did not produce the expected state changes, and the foreground retry was refused after focus went to the separately installed app. No additional foreground retries were made. The test canvas was discarded and the development process exited; the stored language preference remained `system`.
- No saved project format, resource, localization catalog, shortcut assignment or preference key changed. The system app was not replaced and no branch was pushed.
