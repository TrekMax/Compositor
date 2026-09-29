# Tool Hover Hints Implementation Plan

> Execute inline using the executing-plans workflow in the existing feature branch.

**Goal:** Configurable, persistent localized tool name hints.
**Architecture:** Observable ToolTipSettings stores preferences. ToolTipAnchor is an NSViewRepresentable background whose tracking view schedules a nonactivating panel. General settings bind to the shared preferences.
**Tech Stack:** SwiftUI, AppKit, Observation, UserDefaults, Swift Testing.

## Constraints

Default enabled; delay 0.5 seconds, range 0...3 seconds. Only tool buttons are affected. Preserve tool actions and accessibility. Do not change the saved project format.

## Steps

- [x] Add `CompositorTests/ToolTipTests.swift`: isolated defaults round-trip for off/zero delay, clamped and malformed delays; host a real tracking view to check delay, exit, click, preference changes and mouse pass-through. Run focused tests and observe missing implementation failures.
- [x] Add `Compositor/UI/ToolTipSettings.swift`: shared observable settings, `setEnabled(_:)`, `setDelay(_:)`, bounds validation and persistence.
- [x] Add `Compositor/UI/ToolTip.swift`: tracking view + cancellable delayed presentation + screen-clamped nonactivating panel; cancellation on input and view/window changes. `configure(text:enabled:delay:)` applies live configuration.
- [x] Replace `.help` on tool buttons in `ContentView.swift` with the tracking background; bind settings and localized `tool.label` explicitly across the separate hosting root.
- [x] Add a Tool Tips section to `ApplicationSettings.swift`, with toggle and delay slider, translated labels, automatic saving and disabled delay control when hints are off.
- [x] Add matching English/Simplified Chinese resource strings, run focused and full CompositorTests, resource parity and `git diff --check`.
- [x] Inspect the settings and tooltip presentation in a development build. Keep changes available for review; commit and update the system installation when requested. Do not push without a request.

## Validation

- Initial focused build failed on the missing ToolTipSettings and ToolTipTrackingView types.
- All 8 tooltip tests passed, including hosted scroll-rail geometry, delayed presentation, cancellation, click pass-through, preference persistence and window deactivation.
- Full CompositorTests passed: 517 tests, zero failures (before the final additional hosted-rail test).
- Signed Release build and signature verification passed.
- English/Chinese catalogs have 1,040 matching keys and matching format placeholders; git diff --check passed.
- Inspected the native settings layout, toggled hints off, set 1.2 seconds, relaunched and verified both values survived. Restored enabled/0.5 seconds. The actual pointer-hover appearance is covered by tracking-view tests; GUI inspection covered settings.
