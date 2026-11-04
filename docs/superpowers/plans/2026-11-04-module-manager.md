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

- [ ] Add test-first coverage for catalog identity, aggregate size/hash metadata and normalized path containment. A descriptor with `../outside` must fail before disk/network activity. Add metadata and state declarations needed to compile behavioral tests, then capture an assertion failure from an unimplemented operation before implementing it.
- [ ] Add isolated install/progress/cancellation tests, then implement disk-streamed downloads and the Core ML staging transaction. Use download delegates with actual byte counts; check HTTP 200, pinned size, maximum accepted size and streamed SHA-256. Unknown expected lengths remain indeterminate. Validate compiled model load and declared input/output interface before promotion. Preserve an existing good install on any replacement failure.
- [ ] Add tests that release a held first download after cancellation/retry; implement operation IDs, shared tasks, and terminal-state guards so a late result never wins. Coalesce manager prepare/install calls into one operation.
- [ ] Add persistence/disable/uninstall tests. Invalidation happens synchronously before awaiting runtime drain; uninstall awaits `unload()` before removing model files. Cancel and uninstall persist automatic-fetch suppression; explicit install resets it. A disabled valid install re-enables without another download.
- [ ] Add migration tests using copied fake compiled directories and injected validation. Migrate using copy → validate → publish receipt → delete old copy. Failed migration leaves old resources intact and reports an error, with explicit install able to recover. Read receipts consistently and remove only manager-owned abandoned staging operations; never delete an active operation during refresh.
- [ ] Run `ModuleManagerTests`, `ModuleStorageTests`, `ModuleDownloaderTests`; record failing and passing evidence. Self-review transitions, task cancellation, filesystem errors and old-install preservation; commit the focused engine change.

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
- Modify `CompositorTests/VolumetricLightTests.swift`; create `CompositorTests/DepthModelTests.swift`.

**Interfaces:**
- Consume Task 1 manager/runtime contracts as implemented and reported.
- Preserve `DepthModel.prepare() async -> Bool`, `DepthModel.isReady`, `shape(for:)`, `depth(for:)`, `image(_:over:)`, and `DepthMap` output convention. Remove its production mutable source URL and embedded downloader; all prepares go through the manager.
- Expose a synchronous, lock-protected `DepthModel.revision: UInt64` plus `isReady`. Runtime load/disable/unload updates the revision and invalidates the one-image cache. The manager's runtime registration must avoid recursive shared-singleton initialization.
- Inference keeps a lease over the MLModel/files. `unload()` invalidates first and asynchronously waits for leases; predictions and cache publications validate the same revision afterward. Never hold a lock across `await`.
- Add a bounded test injection seam for EditorSession's depth preparation so the first-preview test no longer changes a process-global URL or touches real storage. Keep test fixture control in tests and dependencies semantically meaningful in production.

- [ ] Write regression tests for depth disable/in-flight result invalidation and VolumetricLighting cache generation. Capture failing assertions, then introduce the runtime lease/generation machinery. Keep actual DepthMini pixel inference math unchanged.
- [ ] Route first-use preparation and extraction through the shared manager. Preserve the first preview's five-second fallback. Disabled/canceled states must skip automatic retrieval and use the estimate immediately. Preparation completion from an old edit must not clear a newer edit's waiting state.
- [ ] Include model revision in the prepared depth cache, checking both lookup and publish. A changed/disabled model must not return the earlier model's positive cached result. Expose the availability changes Task 3 can observe to re-render an open preview.
- [ ] Update tests that used `DepthModel.source` to injected instances/explicit opt-in fixture paths; normal unit tests remain offline. Keep opt-in real-model timing/sample utilities functional through managed installation, not a separate downloader.
- [ ] Run `DepthModelTests`, `VolumetricLightTests` and all Task 1 module suites, then commit. Report exact seams/API names used by Task 3 and whether real Core ML inference has been separately verified.

Regression shape:

```swift
let oldRevision = runtime.revision
runtime.invalidate()
#expect(runtime.revision != oldRevision)
#expect(!runtime.isReady)
// Complete a held old-revision inference: no cached depth is published.
// Request the same image from VolumetricLighting: the old depth is not reused.
```

DepthMini model-contract validation must check the actual feature description without inventing fixed output dimensions for its flexible input shapes. Test the inference adapter with the installed real model only as an explicit integration run; report it separately from fakes.

### Task 3: Settings, localized feedback, docs, and integration verification

**Files:**
- Modify `Compositor/UI/Settings/ApplicationSettings.swift`; create `Compositor/UI/Settings/Modules/ModuleSettingsView.swift` and a separate row/details view if needed.
- Modify `Compositor/UI/Filters/FilterSheet.swift` and settings routing at `Compositor/CompositorApp.swift` only if necessary.
- Update both `Compositor/Localization/*/Localizable.strings`, `CompositorTests/LanguageSettingsTests.swift`, and add focused settings tests.
- Update `.github/workflows/verify.yml`, `README.md`, `README.zh-CN.md`, `docs/source-structure.md`, `docs/localization.md`; create `docs/module-management.md`.

**Interfaces:**
- UI consumes the manager's state and existing actions. No direct file mutation or download in views.
- Settings routing uses a shared observable category/selection, with a focused `openModules` entry or a notification plus SwiftUI `openSettings`; do not use private selectors. The exact routing type is owned here.
- Filter observes `availabilityRevision` and requests a fresh preview only for the still-active Volumetric Light edit. Status wording distinguishes disabled, absent, preparing and failure. Manage Modules opens the module category.

- [ ] Add language and settings-state regression tests, capture RED, implement category/routing and module view. Show source/release/license links, actual storage location, download bytes versus installed disk bytes, and provenance. Render progress from actual manager counts; terminal download is followed by verification/compilation state. Include stable accessibility identifiers.
- [ ] Connect download/cancel/retry/enable/uninstall. Use an in-app uninstall confirmation that explains fallback and manual reinstall. Respect installing/removing states and avoid duplicate buttons for contradictory actions. Opening settings triggers only local scan/migration, never a network metadata query.
- [ ] Add filter feedback and Manager entry, immediate preview refresh on availability changes, and an extraction unavailable state instead of relying solely on a beep. Keep waiting/cancel/commit behavior consistent with existing filter flow.
- [ ] Add every new visible string to both catalogs, preserving format placeholders. Verify switching language leaves module IDs, version, hashes and preference keys unchanged.
- [ ] Document the single future registration path: catalog metadata + installer strategy + runtime adapter; all new depth features use the capability facade, never their own downloader/cache folder. Explain sandbox paths, verified-source versus migrated provenance, cancel/uninstall suppression and first-use behavior in both READMEs. Update source layout and CI matching for Modules/depth changes.
- [ ] Run focused module, depth, language and settings tests. Verify actual CI regex positives and negatives, local documentation links, and `git diff --check`. Then run full `CompositorTests` once on the integrated snapshot. Report known external-change timing failures separately if they recur; do not change unrelated monitoring code.
- [ ] Commit the UI/integration/docs change. Root then performs independent review and final actual-model/GUI acceptance. Do not claim GUI or real model acceptance solely from a green build.

Localized regression example:

```swift
#expect(L10n.text("Plug-ins & Modules", language: .simplifiedChinese) == "插件与模块")
#expect(L10n.text("Plug-ins & Modules", language: .english) == "Plug-ins & Modules")
```

## Final acceptance by coordinator

- [ ] Broad independent review of the full feature diff after task reviews; resolve correctness findings with scoped verification.
- [ ] Use a separate temporary model store to download/verify/compile/load real DepthMini and run depth inference, without replacing the user's existing cache. Verify old-cache migration against a copy of the real compiled model.
- [ ] Launch the development app and verify actual settings/modules UI, source and size presentation, state transitions, and both languages. Use PID targeting so the installed app does not receive the actions; document any unavailable UI interactions.
- [ ] Verify the final reviewed source and test snapshot, clean working tree and focused local commits. Record evidence and limitations; do not push or install.
