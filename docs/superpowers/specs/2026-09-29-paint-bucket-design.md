# Paint Bucket

Approved scope: a separate left-rail Paint Bucket tool, Shift-G, localized name/help, foreground-color fill on the current pixel target, tolerance 0...255 (default 32), opacity 0...100% (default 100%), contiguous on by default. Honor selections, transparent pixels and layer masks. Each click is one undoable edit; G remains Gradient.

Reuse MagicWand's color matching in document coordinates and BrushStroke's selection clipping, transformed native-resolution tiles, pixel budgets and commit machinery. On a mask, sample the mask's own placement and background, not the layer image. Snapshot the target and options before asynchronous matching; reject invalid coordinates, disabled targets and zero opacity. Do not modify the user's selection or saved project format.

Tests cover connected/disconnected colors, tolerance, opacity/transparency, selection preservation, masks, layer transforms, undo/redo, rejected input, and keyboard routing. No automatic commit, push or installation for this feature unless requested.
