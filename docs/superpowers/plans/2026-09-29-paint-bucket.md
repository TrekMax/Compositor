# Paint Bucket Implementation Plan

**Goal:** Add the approved Paint Bucket tool to the existing editor.
**Architecture:** PaintBucketSettings and an EditorSession entry point coordinate matching through MagicWand and region filling through BrushStroke. ContentView, PaintBucketControls and CanvasView expose the tool and keyboard routing.
**Tech Stack:** SwiftUI, AppKit, Core Graphics, existing C flood fill, Swift Testing.

- [x] Write PaintBucketTests for output pixels, connected/global matching, opacity, selection, masks, transforms, history and invalid points; observe missing implementation failures.
- [x] Add Document/PaintBucket.swift. Snapshot the target/options; sample layer or mask, match off-main, fill a clipped region, and use commitRasterEdit for undo.
- [x] Extend BrushStroke.fill with optional region and opacity; bound affected tile allocation by the region as well as the canvas and selection.
- [x] Register NavigationTool.paintBucket, a bucket icon/label, Shift-G, numeric opacity shortcuts, top controls and localized status/help strings. Preserve G and existing tools.
- [x] Run focused tests, full CompositorTests, Release build, resource parity and whitespace checks. Inspect the toolbar and controls in a development build.

- [x] Preserve pre-existing Shift-G customizations during shortcut loading; regression tests cover the preferred fallback, an occupied fallback, explicit bucket assignments and translated events.

Review: independent read-only review found a legacy shortcut collision; fixed and re-reviewed without further findings. GUI smoke check confirmed the localized icon/options, Shift-G, click-to-fill on a transparent canvas, undo, and unchanged G routing to Gradient.

Validation note: full-suite runs exposed an intermittent existing tooltip assertion (the panel had not appeared after a fixed 150 ms wait). Its delayed main-actor task can start late under load. The functional test now waits for the panel with a two-second deadline; immediate-presentation, visibility and cancellation assertions remain. No tooltip production behavior changed. The test-only adjustment was reviewed separately.

Final verification (2026-09-29): `CompositorTests` succeeded (`/tmp/compositor-bucket-verified-tests.log`); signed Release build and deep strict signature verification succeeded (`/tmp/compositor-bucket-release-final.log`). Both language catalogs contain 1,046 matching keys with matching format placeholders. `git diff --check` passed.

Installation (2026-09-30): rebuilt and installed to `/Applications/Compositor.app` at the user's request; signature, executable identity and launch with the Paint Bucket controls were verified. The previous application was backed up before replacement.
