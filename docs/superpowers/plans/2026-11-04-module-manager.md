# Module Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Manage optional models from Settings, migrate DepthMini into that manager, and establish the single integration path for future depth features.

**Architecture:** A catalog describes pinned resources; an installer owns disk transactions; a main-actor observable manager coalesces lifecycle requests and publishes progress. Model runtimes own inference and cancellation generations. Settings and Volumetric Light use the same manager.

**Tech Stack:** Swift, Observation, SwiftUI/AppKit, Foundation URLSession, CryptoKit, Core ML, Swift Testing. Existing macOS 26 minimum and single app module remain.

## Global Constraints

- Work in the user-approved `feat/module-manager` branch in the current checkout. Do not push or replace the installed system app.
- Approved specification: `docs/superpowers/specs/2026-11-04-module-manager-design.md`. No additional user approval is needed for implementation or routine fixes.
- Preserve `.comp` format, saved filter parameters, canonical identifiers, shortcuts and English/Simplified Chinese/Follow System language choices.
- Runtime resources live under the system-resolved Application Support URL plus `Compositor/Modules/`; show the actual sandbox-aware path.
- Sources are pinned to catalog versions and SHA-256 values. DepthMini is `depth-mini`, version `depth-model-1`, total 2,657,779 bytes. The source is `https://github.com/robbietilton/Compositor/releases/download/depth-model-1/`.
- Source sizes and hashes: Manifest.json 617 / cfaa07eae081a343ff0e011c2875206d832335e55073252c29c79f73fd938929; model.mlmodel 165354 / c9e2f4f1e44409a2b9f5fb0b072ba41fb42d03a555c333f635f5162676feb744; weight.bin 2491808 / 63d066f1aefc362f2cc0805a624e08df13b6cff3be45dc4307b20a531a2a9f86.
- Package paths remain Manifest.json, Data/com.apple.CoreML/model.mlmodel and Data/com.apple.CoreML/weights/weight.bin. Old compiled cache is Compositor/Depth Model 63d066f1aefc/DepthMini.mlmodelc under the same Application Support base.
- Never claim source-hash verification for a migrated compiled-only cache. Mark provenance and preserve the old copy on migration failure.
- Downloads use bounded disk storage and real received bytes; unknown totals are indeterminate. Compilation and verification are separate stages. Cancellation and stale callbacks cannot publish partial installs.
- No arbitrary executable plugins, custom sources, automatic version updates, root relocation UI, or second model selector in this iteration.
- Tests use unique temporary storage/preferences and deterministic transport/compiler/runtime seams; normal tests must not download from the Internet or alter real model caches.
- Use meaningful regression tests and test-first development for behavior. No tests that merely reproduce implementation details. Build/test invocations are serialized; only the current implementer may invoke Xcode.
- Use focused tests per task; run the full app test suite once on the integrated snapshot. Baseline production/test source is unchanged from the already verified 826/826 run at f02c5e1.
- Follow existing Swift naming/comment density. Keep units in focused files; do not rewrite unrelated rendering algorithms or concurrency settings.
- Commit intended paths only with `git commit -s` and Chinese messages; keep test evidence in the task report.

## Build and verification command

```sh
xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -destination 'platform=macOS' -derivedDataPath /tmp/compositor-module-manager-20261104 \
  -only-testing:CompositorTests/ModuleManagerTests \
  CODE_SIGN_IDENTITY=664768CC64435CAC16BB961B4ABA9A54B38794D3 \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=9BT9NV52NL \
  GCC_OPTIMIZATION_LEVEL=s SWIFT_OPTIMIZATION_LEVEL=-O test
```

Use the task's additional suites by adding `-only-testing` arguments. Keep long output in `/tmp/compositor-modules-<task>-<stage>.log`. For the final run use `-only-testing:CompositorTests`. The certificate avoids the known ad-hoc Sparkle hardened-runtime launch failure; do not change project signing or weaken library validation.

### Task 1: Catalog, verified installation, and observable lifecycle

**Files:**
- Create `Compositor/Modules/ModuleDescriptor.swift`, `ModuleCatalog.swift`, `ModuleState.swift`, `ModuleManager.swift`, `ModuleRuntime.swift`.
- Create `Compositor/Modules/Storage/ModuleStorage.swift`, `ModuleDownloader.swift`, `CoreMLModuleInstaller.swift`.
- Create `CompositorTests/ModuleManagerTests.swift`, `ModuleStorageTests.swift`, `ModuleDownloaderTests.swift`, and a focused test-support file if needed.
- No changes yet to the old DepthModel, filters, settings or localization catalogs.

**Interfaces:**
- `ModuleDescriptor`: immutable Sendable value, Identifiable, metadata/source/version/assets/capability/Core ML package and compiled names/legacy path. `ModuleCatalog.all` and `ModuleCatalog.depthMini` are the sole built-in catalog.
- `ModuleState`: observable snapshot with `phase`, `isInstalled`, `isEnabled`, `receivedBytes`, optional `totalBytes`, `installedBytes`, `provenance`, and structured `issue`; a display state must not imply runtime loading merely from installation.
- `ModuleRuntime: Sendable` contract: synchronous `invalidate()` to reject new inference and invalidate results; `activate(at: URL) async throws`; `unload() async` waits for active inference leases; `isReady: Bool`.
- `@MainActor @Observable final class ModuleManager`: injectable descriptors, root, UserDefaults, installer and `[String: any ModuleRuntime]`; `state(for id: String) -> ModuleState`, `refresh() async`, `prepare(_ id: String) async -> Bool`, `install(_ id: String) async`, `cancel(_ id: String)`, `setEnabled(_ enabled: Bool, for id: String) async`, `uninstall(_ id: String) async`, `root: URL`, `availabilityRevision: UInt64`.
- Provide a shared manager with the catalog. Task 2 will register its real DepthMini runtime; injectable test instances remain independent.
- Installer and transport interfaces may use concrete injectable closures or protocols. The concrete installer returns a validated installation/compiled URL; hooks distinguish inspect/migrate/install/remove. Keep those contracts in the task report for Task 2.

- [x] Add test-first coverage for catalog identity, aggregate size/hash metadata and normalized path containment. A descriptor with `../outside` must fail before disk/network activity. Add metadata and state declarations needed to compile behavioral tests, then capture an assertion failure from an unimplemented operation before implementing it.
- [x] Add isolated install/progress/cancellation tests, then implement disk-streamed downloads and the Core ML staging transaction. Use download delegates with actual byte counts; check HTTP 200, pinned size, maximum accepted size and streamed SHA-256. Unknown expected lengths remain indeterminate. Validate compiled model load and declared input/output interface before promotion. Preserve an existing good install on any replacement failure.
- [x] Add tests that release a held first download after cancellation/retry; implement operation IDs, shared tasks, and terminal-state guards so a late result never wins. Coalesce manager prepare/install calls into one operation.
- [x] Add persistence/disable/uninstall tests. Invalidation happens synchronously before awaiting runtime drain; uninstall awaits `unload()` before removing model files. Cancel and uninstall persist automatic-fetch suppression; explicit install resets it. A disabled valid install re-enables without another download.
- [x] Add migration tests using copied fake compiled directories and injected validation. Migrate using copy → validate → publish receipt → delete old copy. Failed migration leaves old resources intact and reports an error, with explicit install able to recover. Read receipts consistently and remove only manager-owned abandoned staging operations; never delete an active operation during refresh.
- [x] Run `ModuleManagerTests`, `ModuleStorageTests`, `ModuleDownloaderTests`; record failing and passing evidence. Self-review transitions, task cancellation, filesystem errors and old-install preservation; commit the focused engine change.

Example contract-level assertions (fixture construction belongs in tests):

```swift
await manager.install(module.id)
#expect(manager.state(for: module.id).isInstalled)
await manager.uninstall(module.id)
#expect(!manager.state(for: module.id).isInstalled)
#expect(await manager.prepare(module.id) == false)
// Independent manager, same test-only defaults: suppression persists.
#expect(await reopened.prepare(module.id) == false)
```

Use tiny deterministic payloads for transfer tests and a validator/compiler adapter that writes a realistic temporary directory. Assert final files, states and isolation, not only mock call counts. Disk failure can be exercised with a file at the expected root directory; hash mismatch must leave no promoted install. Include a held runtime lease test proving uninstall does not remove files prematurely.

### Task 2: Depth capability and Volumetric Light integration

**Files:**
- Move `Compositor/IO/DepthModel.swift` into `Compositor/Modules/Depth/DepthModel.swift`; extract `DepthMap.swift` and the runtime/provider implementation beside it as necessary.
- Modify `ModuleManager.swift` shared runtime wiring, `Compositor/Editor/Filters/Filters.swift`, `VolumetricLight.swift`, and `Compositor/Editor/Session/EditorSession.swift` only at model integration points.
- Modify `CompositorTests/VolumetricLightTests.swift`; create `CompositorTests/DepthModelTests.swift` and `CompositorTests/ModuleIntegrationTests.swift`.

**Interfaces:**
- Consume Task 1 manager/runtime contracts as implemented and reported.
- Preserve `DepthModel.prepare() async -> Bool`, `DepthModel.isReady`, `shape(for:)`, `depth(for:)`, `image(_:over:)`, and `DepthMap` output convention. Remove its production mutable source URL and embedded downloader; all prepares go through the manager.
- Expose a synchronous, lock-protected `DepthModel.revision: UInt64` plus `isReady`. Runtime load/disable/unload updates the revision and invalidates the one-image cache. The manager's runtime registration must avoid recursive shared-singleton initialization.
- Inference keeps a lease over the MLModel/files. `unload()` invalidates first and asynchronously waits for leases; predictions and cache publications validate the same revision afterward. Never hold a lock across `await`.
- Add a bounded test injection seam for EditorSession's depth preparation so the first-preview test no longer changes a process-global URL or touches real storage. Keep test fixture control in tests and dependencies semantically meaningful in production.

- [x] Write regression tests for depth disable/in-flight result invalidation and VolumetricLighting cache generation. Capture failing assertions, then introduce the runtime lease/generation machinery. Keep actual DepthMini pixel inference math unchanged.
- [x] Route first-use preparation and extraction through the shared manager. Preserve the first preview's five-second fallback. Disabled/canceled states must skip automatic retrieval and use the estimate immediately. Preparation completion from an old edit must not clear a newer edit's waiting state.
- [x] Include model revision in the prepared depth cache, checking both lookup and publish. A changed/disabled model must not return the earlier model's positive cached result. Expose the availability changes Task 3 can observe to re-render an open preview.
- [x] Update tests that used `DepthModel.source` to injected instances/explicit opt-in fixture paths; normal unit tests remain offline. Keep opt-in real-model timing/sample utilities functional through managed installation, not a separate downloader.
- [x] Run `DepthModelTests`, `VolumetricLightTests` and all Task 1 module suites, then commit. Report exact seams/API names used by Task 3 and whether real Core ML inference has been separately verified.

Regression shape:

```swift
let oldRevision = runtime.revision
runtime.invalidate()
#expect(runtime.revision != oldRevision)
#expect(!runtime.isReady)
// Complete a held old-revision inference: no cached depth is published.
// Request the same image from VolumetricLighting: the old depth is not reused.
```

DepthMini model-contract validation must check the actual feature description without inventing fixed output dimensions for its flexible input shapes. Provide one explicitly opt-in `ModuleIntegrationTests` real-model test, enabled only when `COMPOSITOR_MODULE_INTEGRATION=1`. It uses a unique temporary root and independent defaults, calls the production manager/downloader/compiler against the pinned release, and checks real depth inference, disable/re-enable, migration from a copy of that valid compiled installation into a second temporary root, and uninstall suppression. Capture byte/stage and normalized-depth evidence as attachments or concise test output. Never alter the original real cache. Root will run this test after task completion via a copied xctestrun with its test environment set; normal unit runs skip it and remain offline. Report real model acceptance separately from fixtures.

### Task 3: Settings, localized feedback, docs, and integration verification

**Files:**
- Modify `Compositor/UI/Settings/ApplicationSettings.swift`; create `Compositor/UI/Settings/Modules/ModuleSettingsView.swift` and a separate row/details view if needed.
- Modify `Compositor/UI/Filters/FilterSheet.swift`, the session alert/availability hooks in `Compositor/ContentView.swift`, and settings routing at `Compositor/CompositorApp.swift` only if necessary.
- Update both `Compositor/Localization/*/Localizable.strings`, `CompositorTests/LanguageSettingsTests.swift`, and add focused settings tests.
- Update `.github/workflows/verify.yml`, `README.md`, `README.zh-CN.md`, `docs/source-structure.md`, `docs/localization.md`; create `docs/module-management.md`.

**Interfaces:**
- UI consumes the manager's state and existing actions. No direct file mutation or download in views.
- Settings routing uses a shared observable category/selection, with a focused `openModules` entry or a notification plus SwiftUI `openSettings`; do not use private selectors. The exact routing type is owned here.
- Filter observes `availabilityRevision` and requests a fresh preview only for the still-active Volumetric Light edit. Status wording distinguishes disabled, absent, preparing and failure. Manage Modules opens the module category.

- [x] Add language and settings-state regression tests, capture RED, implement category/routing and module view. Show source/release/license links, actual storage location, download bytes versus installed disk bytes, and provenance. Render progress from actual manager counts; terminal download is followed by verification/compilation state. Include stable accessibility identifiers.
- [x] Connect download/cancel/retry/enable/uninstall. Use an in-app uninstall confirmation that explains fallback and manual reinstall. Respect installing/removing states and avoid duplicate buttons for contradictory actions. Opening settings triggers only local scan/migration, never a network metadata query.
- [x] Add filter feedback and Manager entry, immediate preview refresh on availability changes, and an extraction unavailable state instead of relying solely on a beep. Keep waiting/cancel/commit behavior consistent with existing filter flow.
- [x] Add every new visible string to both catalogs, preserving format placeholders. Verify switching language leaves module IDs, version, hashes and preference keys unchanged.
- [x] Document the single future registration path: catalog metadata + installer strategy + runtime adapter; all new depth features use the capability facade, never their own downloader/cache folder. Explain sandbox paths, verified-source versus migrated provenance, cancel/uninstall suppression and first-use behavior in both READMEs. Update source layout and CI matching for Modules/depth changes.
- [x] Run focused module, depth, language and settings tests. Verify actual CI regex positives and negatives, local documentation links, and `git diff --check`. Then run full `CompositorTests` once on the integrated snapshot. Report known external-change timing failures separately if they recur; do not change unrelated monitoring code.
- [x] Commit the UI/integration/docs change. Root then performs independent review and final actual-model/GUI acceptance. Do not claim GUI or real model acceptance solely from a green build.

Localized regression example:

```swift
#expect(L10n.text("Plug-ins & Modules", language: .simplifiedChinese) == "插件与模块")
#expect(L10n.text("Plug-ins & Modules", language: .english) == "Plug-ins & Modules")
```

## Final acceptance by coordinator

- [x] Broad independent review of the full feature diff after task reviews; resolve correctness findings with scoped verification.
- [x] Use a separate temporary model store to download/verify/compile/load real DepthMini and run depth inference, without replacing the user's existing cache. Verify old-cache migration against a copy of the real compiled model.
- [x] Launch the development app and verify actual settings/modules UI, source and size presentation, state transitions, and both languages. Use PID targeting so the installed app does not receive the actions; document any unavailable UI interactions.
- [x] Verify the final reviewed source and test snapshot, clean working tree and focused local commits. Record evidence and limitations; do not push or install.


## Execution and acceptance record — 2026-11-04

Implementation and independent review are complete on `feat/module-manager`, based on `68ed6ab`. Engine commits: `9d744f0`, `f1aa357`; depth integration: `8e85159`, `86e7546`; settings, localization and documentation: `7c80ee8`, `9bdd8a1`. The final reviewed production snapshot is `9bdd8a1`; subsequent edits only record acceptance and clarify the documented storage limitation. No push or system-app replacement was performed.

### Automated evidence

Counts below are test functions; parameterized execution counts are included separately where useful. These are the recorded executions, not a claim that the full suite is green.

| Snapshot / scope | Result |
| --- | --- |
| `f1aa357`, module engine | 32 passed / 39 parameter executions; no failures, skips or runtime warnings |
| `86e7546`, module engine + depth + Volumetric Light | 58 passed / 76 parameter executions; one opt-in integration skip; no failures or runtime warnings |
| `86e7546`, opt-in production DepthMini lifecycle | 1 passed, no skips/failures/runtime warnings |
| `7c80ee8`, integrated focused coverage | 76 passed / 100 parameter executions; one opt-in integration skip; no failures |
| `7c80ee8`, full `CompositorTests` | 878 passed, 3 failed, 1 skipped; 1,025 passing parameter executions |
| `7c80ee8`, isolated rerun of the failing suites | 12 passed / 18 parameter executions; no failures or runtime warnings |
| `9bdd8a1`, final settings/language regression coverage | 24 passed / 30 parameter executions; no failures, skips or runtime warnings |

The full-run failures were `TiledLayerTests.paintingAtTheLayersEdgeDoesNotChangeIt(zoom:)` at zoom 10.749 and `ExternalChangeTests.unsavedWorkIsNeverReplacedWithoutAsking()` / `writingThePackageElsewhereReloadsTheOpenProject()`. Both suites passed when run separately on the same snapshot. Their root cause remains unresolved; the isolated pass does not prove a baseline defect or a green full run. No unrelated rendering or file-monitoring source was changed to mask these results. Three full-run QoS warnings pointed to unchanged `FloatingPanel.swift` and `SubjectRemoval.swift`.

The real-model harness downloaded exactly 2,657,779 bytes, retained 5,325,308 source/compiled content bytes, and produced finite, nonconstant normalized depth at 640 × 480 (range 0.011106331…0.9960432). It exercised production download/SHA verification/compilation/load/inference, disable/re-enable without another download, migration from a copy of the real compiled installation, uninstall, and automatic-fetch suppression. Stores and preferences were temporary and isolated. The module engine/runtime did not change after this acceptance run.

For reproduction, run `build-for-testing` with the signing/build settings above. Copy the resulting `.xctestrun` beside the original to preserve `__TESTROOT__`, set the test target's `EnvironmentVariables.COMPOSITOR_MODULE_INTEGRATION` to `1`, then run `xcodebuild test-without-building -xctestrun <copy> -destination 'platform=macOS' -only-testing:CompositorTests/ModuleIntegrationTests`. Do not enable this variable in normal unit runs.

Local evidence retained for this session:

- `/tmp/compositor-modules-real-integration.xcresult`, `/tmp/compositor-modules-real-summary.json`, and `/tmp/compositor-modules-real-attachments/14EAFA06-1386-4351-8BC3-C3E89374C52B.txt`.
- `/tmp/compositor-modules-task3-full.xcresult`, `/tmp/compositor-modules-task3-full-summary.json`, and `/tmp/compositor-modules-task3-isolated-summary.json`.
- `/tmp/compositor-modules-task3-fix1-green-summary.json` and `/tmp/compositor-modules-task3-doc-ci-check.txt` (nine positive/five negative CI path cases and documentation links).

### Actual app acceptance

The signed development build at `/tmp/compositor-module-preview-20261104/Build/Products/Debug/Compositor.app` used the command-line-only bundle identifier `com.wonderassembly.compositor.modulepreview`. Build and deep-strict signature verification passed. Its separate sandbox/preferences kept the installed system app, original model cache and language preference untouched. GUI actions targeted this development app only.

Verified through the actual windows and accessibility state:

- English and Simplified Chinese settings, fixed version/source/license details, actual sandbox path, download versus installed size, aggregate installed content bytes, and Finder revealing the correct module folder.
- Actual downloading bytes and numeric percentage; cancel → canceled/retry; retry → installed; disabling preserves files and installed size.
- Volumetric Light immediately reports estimated depth when disabled. Its management button opens the correct settings category; enabling the existing model makes the open filter report ready without a download.
- Uninstall confirmation explains estimated-depth fallback and manual reinstall. After uninstall the page reports not installed and zero installed bytes; the active filter reports estimated depth.
- Extract Depth closes the filter and leaves a persistent unavailable alert on the document. The alert's management action opens the module category; the model remains absent with a Download action rather than silently redownloading.

The temporary image document was discarded and the development app quit. The preview model directory was removed by the app's uninstall action; the original user's legacy model directory still exists. Selected English/Chinese settings screenshots are retained under `/tmp/compositor-module-acceptance-20261104/gui/`.

### Review and remaining limits

All task findings were fixed and re-reviewed. Independent review of `68ed6ab..9bdd8a1` found no remaining Critical or Important issue. The accepted minor limitation is disk retention of unreferenced generations after a crash or corrupt-install repair; installed-size totals exclude them, and uninstall removes them. Future cleanup must preserve the referenced generation and active inference leases.

Final source-range and working-tree whitespace checks passed. The full-suite failures above remain explicit handoff limitations; this record does not certify a clean release/merge gate.
