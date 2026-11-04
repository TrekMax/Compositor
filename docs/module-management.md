# Plug-ins & Modules

Open **Compositor → Settings… → Plug-ins & Modules**, or **Manage Modules…** in Volumetric Light. This page manages optional bundled-catalog resources. It does not load arbitrary executable plug-ins, accept custom sources, choose a second depth model, relocate storage, or automatically update model versions.

## DepthMini

The built-in `depth-mini` descriptor pins `depth-model-1` from [the upstream release](https://github.com/robbietilton/Compositor/releases/tag/depth-model-1). The three assets total **2,657,779 bytes**. Their names, package paths, exact sizes and SHA-256 pins live in `Compositor/Modules/ModuleCatalog.swift`. The source base is an asset-download directory, not a browsable release page; the settings page provides separate source/release and license links. DepthMini is distilled from Depth Anything V2 Small (Apache-2.0) and uses torchvision MobileNetV3 ImageNet weights (BSD-3-Clause); the app's MIT license does not replace those licenses.

Download size is the pinned network payload. Installed size is the content byte count of retained source and compiled files, so it can differ from the download size and from filesystem allocated space. Download progress uses actual received bytes; a missing total is indeterminate. Verification, compilation, migration and runtime loading have separate indeterminate stages. A completed transfer alone is not an installed model.

## Storage and provenance

The root is the system-resolved Application Support URL plus `Compositor/Modules/`. Settings displays the actual path. A sandboxed build normally resolves inside `~/Library/Containers/com.wonderassembly.compositor/Data/Library/Application Support/`; an unsandboxed build uses the user's normal Application Support directory.

```text
Modules/
  .staging/module-op-<UUID>/
    .owner
    DepthMini.mlpackage/
  depth-mini/
    receipt.json
    generations/<UUID>/
      DepthMini.mlpackage/       # retained verified source, new downloads only
      DepthMini.mlmodelc/
```

A complete generation is moved into place before `receipt.json` is atomically replaced. The receipt records ID, version, catalog fingerprint, source, installation time, generation, compiled name, byte count, source-package presence and provenance. Consumers resolve the generation through the receipt; version is not a directory name. Failure before publication preserves the previous receipt/generation. Only owned inactive staging is cleaned; unrelated files are not swept. Unreferenced generations after abrupt process death are not currently garbage-collected.

Legacy cache: `Compositor/Depth Model 63d066f1aefc/DepthMini.mlmodelc` beneath the same Application Support base. Local inspection can copy it to staging, validate loading and the model interface, publish a receipt, then remove the old compiled copy. Failed migration preserves the old copy before publication. A failure removing the old copy is reported even if the new copy was published. A migrated generation has no retained source package and is explicitly labeled **Migrated compiled cache; source hashes not verified**. It cannot prove the hashes of unavailable original source bytes.

## User actions and first use

Settings opening performs local inspection/migration only, with no network metadata request. There is no unconditional app-start scan. First Volumetric Light use may fetch the pinned model automatically, retaining the five-second initial preview wait and estimated-depth fallback. Disabled resources fall back immediately. Cancel and uninstall persist automatic-fetch suppression, so reopening the filter does not redownload. **Download** or **Retry** explicitly restores fetch permission. Suppressed but existing resources can still be inspected/migrated/loaded locally in the background without holding the estimated preview.

Disable keeps installed files. Enable allows the next use to load them without redownloading. Cancellation stops the shared operation for all callers; it does not offer resumable transfers. Uninstall asks for confirmation, invalidates results immediately, waits for active inference leases, and removes only that module's managed files. Volumetric Light uses its estimate afterward; depth extraction requires the model and offers feedback plus the management entry when unavailable. A stale download, inference or preview cannot republish results after cancellation or availability changes.

## Adding a resource or depth feature

There is one registration path:

1. Add immutable metadata to `ModuleCatalog`: stable ID/version, capability, publisher, source/release/licenses, package paths, pinned sizes/hashes and interface names.
2. Supply a compatible installer strategy through `ModuleInstalling` (the existing `CoreMLModuleInstaller` handles pinned Core ML packages) and a `ModuleRuntime` adapter for the capability.
3. Register the runtime with the manager and consume the capability facade. All future depth features use `DepthModel` / `DepthPreparation` and the shared `DepthRuntime`; never add a separate downloader, compilation cache or model folder to a filter.

`ModuleManager` is the observable MainActor lifecycle owner. `ModulePresentation` maps its snapshots to localized UI labels and permitted actions without doing IO. `SettingsRouting` holds the shared category, and SwiftUI's public `openSettings` action opens that category. The session root observes availability revisions; runtime revisions protect inference and prepared-preview caches independently. These revisions are runtime state, not saved project data. `.comp` format, canonical filter identifiers and saved parameters are unchanged.

## Verification

`ModuleManagerTests`, `ModuleStorageTests`, `ModuleDownloaderTests`, `DepthModelTests`, `ModuleSettingsTests`, `LanguageSettingsTests` and `VolumetricLightTests` cover lifecycle, storage, transfer, inference leases, UI decisions, translation and preview behavior with isolated temporary storage and preferences. Normal tests do not fetch the model or migrate the user's cache. `ModuleIntegrationTests.pinnedDepthModelLifecycle` is opt-in with `COMPOSITOR_MODULE_INTEGRATION=1`, and uses fresh temporary stores for the real download, compile, inference, migration and uninstall checks. GUI acceptance is separate from unit/build evidence.
