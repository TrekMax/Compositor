# Editor Source Structure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Rename the broad `Compositor/Document` source area to `Compositor/Editor` and organize its contents by editing responsibility on `refactor/editor-structure`.

**Architecture:** Keep one app target and all existing types and behavior. Group feature implementation files together, even when a file includes both settings and `EditorSession` extensions. Extract only `ImageLayer`, `CanvasDocument`, and `NavigationTool` from the start of `EditorSession.swift` into their own files.

**Tech Stack:** Swift, SwiftUI/AppKit, Xcode file-system-synchronized source groups, Bash CI path matching.

## Global Constraints

- Base: `feat/tools` at `2eaa7b1`; work in the user-requested new branch in this clean checkout.
- Preserve type names, access levels, actor isolation, localization, shortcut identifiers, pixel algorithms, and saved project format v21.
- Keep `IO`, `Rendering`, `UI`, `Localization`, and bundled binary resources in place.
- No new dependency, public API, or behavior test for a source-only move. Verify content preservation and run existing tests.
- Create a focused signed-off local commit; do not push or reinstall the app.

## Task 1: Organize editor sources

**Files:** Move the 72 existing `Compositor/Document/*.swift` files under `Compositor/Editor`; create three extracted source files.

**Interfaces:** All Swift type and member names stay unchanged. Xcode's synchronized `Compositor` root discovers the new paths without a project-file edit.

| Destination | Existing files, without `.swift` |
| --- | --- |
| `Model/` | DocumentLimits, GIFAnimation, GIFFrameTiming; extracted ImageLayer and CanvasDocument |
| `Session/` | EditorSession, EditorSession+Brush, EditorSession+GIF, EditorSession+Navigator, EditorSession+Projects, DocumentHistory, GIFPreviewPlayback |
| `Workspace/` | ProjectWorkspace |
| `Preferences/` | ToolDefaults |
| `Tools/` | BlurTool, BrushStroke, CloneStamp, ColorPalette, Crop, Gradient, PaintBucket, ShapeTool, SmudgeLiquify, TypeTool; extracted NavigationTool |
| `Canvas/` | CanvasRotation, CanvasSize, Guides, ImageTrim |
| `Layers/` | DeepLayers, Distort, LayerAdjustment, LayerAlign, LayerAppearance, LayerDistances, LayerEffects, LayerFlip, LayerGroups, LayerMask, LayerMerge, LayerTransform, LiveLayerMask, SplitChannels |
| `Selection/` | ColorRangeSelection, FloatingSelection, MagicWand, MaskTracing, ObjectSelection, Selection, SelectionClipboard, SelectionEdits |
| `Adjustments/` | AdjustmentEditing, Curves, HueSaturation, ImageAdjustments, Levels, LevelsAutomatic, PixelAdjust, PixelInvert |
| `Adjustments/CameraRaw/` | CameraRaw, CameraRawColor, CameraRawDetailOptics, CameraRawGeometryCalibration, CameraRawReset, CameraRawShadows, CameraRawTables |
| `Filters/` | ContentFill, Dither, Filters, GuidedMatte, LensEffects, RimLight, Scanlines, SubjectRemoval, VolumetricLight |

- [x] Check that every old file maps to exactly one destination, then move with `git mv`.
- [x] Extract the three complete declarations unchanged, retaining `EditorSession`'s imports and private runtime state. Use `CoreGraphics` and `Foundation` for model files; the tool enum requires only standard-library types.
- [x] Compare every moved file with its base blob; reconstruct `EditorSession.swift` from the extracted declarations and remaining body to prove no implementation was lost or changed.

## Task 2: Update path consumers and document the boundary

**Files:** Modify `.github/workflows/verify.yml`, `AGENTS.md`, and the Paint Bucket plan's source path; create `docs/source-structure.md`.

**Interfaces:** The existing CI `filters` output and test runner remain unchanged. Only the changed-file matching rules recognize new source locations.

- [x] Match `Editor/Adjustments/`, `Editor/Filters/`, and `Editor/Layers/LayerAdjustment.swift` in the filter-suite gate. Retain the legacy `Document` pattern so deletions and comparisons against older branches still select the suites.
- [x] Check that every previously matched source still matches at its new path; check representative UI, rendering, workflow, and unrelated paths as positive and negative cases.
- [x] Explain the editor groups, the IO/rendering/UI boundary, unchanged module/type names, and how to place future files in `docs/source-structure.md`; link it from `AGENTS.md`.
- [x] Update the historical Paint Bucket plan's source pointer to `Editor/Tools/PaintBucket.swift`.

## Task 3: Verify and commit

**Files:** Existing `CompositorTests`; no test source changes planned.

- [x] Run `git diff --check`, source-preservation checks, old-path scans, and CI regex coverage checks.
- [x] Build and run the full `CompositorTests` with the CI optimization settings, local signing overrides, and DerivedData outside the repository. The successful test-host launch on this machine used its available Apple Development certificate:

```sh
xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -destination 'platform=macOS' -derivedDataPath /tmp/compositor-editor-structure-20261104 \
  -only-testing:CompositorTests CODE_SIGN_IDENTITY='Apple Development' CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=9BT9NV52NL \
  GCC_OPTIMIZATION_LEVEL=s SWIFT_OPTIMIZATION_LEVEL=-O test
```

- [x] If the known external-file-monitor timeouts recur, report them separately and run `ExternalChangeTests` alone. The same base commit already had 823/826 passing in an unoptimized full run and 6/6 passing in the isolated monitor suite.
- [x] Review the integrated rename/split and staged scope, create the local commit, and verify a clean worktree with `feat/tools` still at `2eaa7b1`.

## Validation results

- All 72 original files have one destination. The 71 intact moves match their base blobs byte for byte. The three extracted declarations, original separators, and remaining session body reconstruct the original `EditorSession.swift` exactly; only imports and file-ending whitespace were added or normalized in the extracted files.
- Independent review found no important defects. The actual `grep -E` rules retain all 59 previously covered tracked paths, including all 18 moved editor files; new filter paths and unrelated negative cases behave as intended.
- Compilation succeeded. The initial optimized ad-hoc test host exited before running any cases: dyld rejected Sparkle under Hardened Runtime's library validation. Re-running with the existing Apple Development identity resolved that launch failure without changing project signing settings.
- The complete optimized suite ran 826 tests: 824 passed. `ExternalChangeTests/unsavedWorkIsNeverReplacedWithoutAsking` and `writingThePackageElsewhereReloadsTheOpenProject` failed while waiting for file-monitor events. Both had also failed on the unmodified upstream baseline earlier in this session. A separate final run of the complete `ExternalChangeTests` suite passed 6/6. The full suite is not green; monitor code and timeouts were not changed.
- Logs: `/tmp/compositor-editor-structure-20261104-signed-full.log` and `/tmp/compositor-editor-structure-20261104-external.log`. The source-preservation map and independent review are `/tmp/compositor-editor-structure-map.json` and `/tmp/compositor-editor-structure-review.md`.
- Whitespace and old-path checks passed. Remaining `Document` source-path references are deliberate legacy CI matching or this plan's description of the original tree. Bundled data, translations, saved representations, and all other production files remain unchanged.
