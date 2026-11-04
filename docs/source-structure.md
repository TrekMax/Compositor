# Source structure

`Compositor/Editor` contains the state and operations of the image editor. It was previously named `Document`, but its responsibilities include editing tools, image adjustments, multiple open projects, and user preferences as well as the document itself.

## Editor groups

| Directory | Responsibility |
| --- | --- |
| `Model` | Shared document values: `CanvasDocument`, `ImageLayer`, GIF animation/frame timing, and document limits. |
| `Session` | `EditorSession`, its shared integration extensions, document history, and GIF preview playback. |
| `Workspace` | Multiple open projects, tab selection and lifetime, and coordination with each project's controller. |
| `Preferences` | Tool preferences that persist across documents and launches. |
| `Tools` | Brush, clone, blur, crop, gradient, Paint Bucket, shape and type behavior; tool selection and the color palette. |
| `Canvas` | Canvas size and rotation, trimming, guides, grid and snapping behavior. |
| `Layers` | Layer transforms, alignment, grouping, compositing properties, masks, effects, adjustments and channel operations. |
| `Selection` | Selection geometry and edits, clipboard and floating selections, color-range, wand and object selection, and mask tracing. |
| `Adjustments` | Levels, curves, Hue/Saturation, other tonal/color adjustments, and their edit lifecycle. `CameraRaw` keeps that larger feature's settings, calculations, reset behavior, and lookup-data readers together. |
| `Filters` | Filter orchestration, previews, and feature implementations such as content-aware fill, lens effects, matting, rim light and volumetric light. |

The groups organize source files within the existing app module; they are not separate Swift modules or new dependency boundaries. Feature files can contain settings, an algorithm wrapper, and related `EditorSession` extensions together. Shared session state belongs in `Session`; an extension that implements a particular feature belongs with that feature. Selection tools live in `Selection` alongside their selection operations.

`ImageLayer`, `CanvasDocument`, and `NavigationTool` have their own files. Their type names and access levels are unchanged; `EditorSession.swift` owns the editing session rather than also declaring those shared types.

## UI groups

`Compositor/UI` contains presentation and input integration. It follows the editor's feature groups where useful, with separate areas for application settings and reusable UI infrastructure. SwiftUI and AppKit implementations of the same feature stay together.

| Directory | Responsibility |
| --- | --- |
| `Workspace` | Project tabs, their layout and window integration. |
| `Canvas` | Rulers, navigator and thumbnails, new canvas, size, trim and grid dialogs. |
| `Layers` | Layer list, search, blend mode, masks, effects, transform inspector and GIF timeline. |
| `Tools` | Tool rail and headers, individual tool controls, palette/color picker and font selection. |
| `Selection` | Lasso and color-range controls. |
| `Adjustments` | Curves, Hue/Saturation and Levels panels; `CameraRaw` keeps its controls and native slider together. |
| `Filters` | Filter panels and previews. |
| `ImportExport` | Export preview/options and PSD/RAW import dialogs. |
| `Settings` | Application settings, language selection, tooltip preferences, module management (`Settings/Modules`) and the keyboard-shortcut editor. |
| `Commands` | Command search, shortcut definitions, saved assignments and shortcut UI integration. |
| `Input` | Modifier keys, keyboard-layout translation and tablet-pen detection. |
| `Shared` | Reusable scrolling, numeric/slider interaction, tooltips and floating-panel hosting. |

UI-specific layout values, such as the project tab layout, belong beside their views even when they do not conform to `View`. These source groups do not change the Swift module or dependency boundaries.

### Layer list and shortcuts

`Layers/NativeLayerList.swift` owns the SwiftUI bridge and its coordinator. `LayerTableView` handles native table selection, keyboard input and drag tracking; `LayerCell` owns the row's controls and private drawing helpers. Effect rows and thumbnail drag behavior live in `LayerEffectRow` and `LayerThumbnailButton`. `ImageLayer+Presentation.swift` contains the size and bit-depth labels used by the UI, beside the views that display them.

`Commands/ShortcutChord.swift` represents and converts key combinations. `ShortcutDefinition` lists the stable command identifiers and defaults; `ShortcutSettings` owns saved assignments, validation and event routing. `KeyboardShortcuts.swift` contains the SwiftUI shortcut modifiers. `Settings/KeyboardShortcutsSheet.swift` owns the editor and its private key recorder. Moving these declarations does not change shortcut IDs, stored assignments or preference keys.

## Neighboring source areas

- `UI`: SwiftUI/AppKit controls, panels, menus, shortcuts and other presentation code.
- `Rendering`: Canvas drawing, caches and overlays, Metal implementations, and C pixel kernels used by the editor.
- `IO`: Project persistence and format records, import/export codecs, file monitoring, application lifecycle and update integration. `ProjectController` coordinates file operations with an editor session; `ProjectStore` reads and writes the saved representation.
- `Modules`: Built-in resource catalog, observable lifecycle manager, transactional storage/download/compile, and the shared depth runtime/capability under `Depth`. See [module management](module-management.md) before adding a resource or depth feature.
- `Localization`: Language selection and translated interface resources.
- `Resources`: Bundled data, including the Camera Raw color tables and shadow coefficients. Their bundle resource names stay independent of the Swift source folders.

The `.comp` format, canonical identifiers, and preference keys are independent of this directory layout. Moving a Swift source file does not change the saved project format.

## Adding or moving source files

Place new files beside the feature they serve. Keep pixel kernels and GPU implementations in `Rendering`, file-format handling in `IO`, and view code in `UI`.

The Xcode project uses file-system-synchronized roots for the app and tests. Swift files under `Compositor` are discovered automatically, including files in nested editor groups; ordinary source moves do not need entries in `project.pbxproj`.

When moving filter-related files, also check the changed-path rules in `.github/workflows/verify.yml`. Those rules decide whether the filter test suites run. The legacy `Document` and flat `UI` patterns remain to recognize deleted old paths and comparisons against older branches.
