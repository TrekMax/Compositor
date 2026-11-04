struct ShortcutDefinition: Identifiable {
    let title: String
    let group: String
    let original: ShortcutChord
    var id: String { "\(group):\(title)" }
    var isMenu: Bool { group == "Menus" }

    static let all: [ShortcutDefinition] = {
        func entry(_ title: String, _ key: String, _ modifiers: Int = 0, menu: Bool = false) -> ShortcutDefinition {
            .init(title: title, group: menu ? "Menus" : "Canvas & Layers", original: ShortcutChord(key, modifiers))
        }
        var result: [ShortcutDefinition] = [
            entry("Undo", "z", 1, menu: true), entry("Redo", "z", 9, menu: true),
            entry("New Canvas", "n", 1, menu: true), entry("Open Project", "o", 1, menu: true),
            entry("Save", "s", 1, menu: true), entry("Save As", "s", 9, menu: true),
            entry("Export JPEG", "s", 11, menu: true), entry("Export PNG", "e", 9, menu: true), entry("Export As", "w", 11, menu: true),
            entry("Close Project", "w", 1, menu: true), entry("Fit Canvas", "0", 1, menu: true), entry("Search Commands", "f", 1, menu: true),
            entry("Actual Pixels", "1", 1, menu: true), entry("Zoom In", "=", 1, menu: true),
            entry("Zoom Out", "-", 1, menu: true), entry("Show Transform Controls", "h", 1, menu: true),
            entry("Hide Compositor", "h", 3, menu: true), entry("Cut", "x", 1, menu: true),
            entry("Copy", "c", 1, menu: true), entry("Copy Merged", "c", 9, menu: true),
            entry("Paste", "v", 1, menu: true), entry("Fill with Foreground", "\u{7f}", 2, menu: true),
            entry("Fill with Background", "\u{7f}", 1, menu: true), entry("Content-Aware Fill", "\u{7f}", 8, menu: true),
            entry("Select All", "a", 1, menu: true), entry("Deselect", "d", 1, menu: true),
            entry("Inverse Selection", "i", 9, menu: true), entry("Select Subject", "a", 3, menu: true),
            entry("Last Filter", "f", 5, menu: true), entry("Curves", "m", 1, menu: true), entry("Levels", "l", 1, menu: true),
            entry("Hue/Saturation", "u", 1, menu: true), entry("Invert Pixels / Mask", "i", 1, menu: true),
            entry("Canvas Size", "c", 3, menu: true), entry("Image Size", "i", 3, menu: true),
            entry("Transform Layer / Selection", "t", 1, menu: true), entry("Duplicate / Layer via Copy", "j", 1, menu: true),
            entry("Toggle Clipping Mask", "g", 3, menu: true), entry("Group Layers", "g", 1, menu: true),
            entry("Ungroup Layers", "g", 9, menu: true),
            entry("New Blank Layer", "n", 9, menu: true), entry("Move Layer Up", "]", 1, menu: true),
            entry("Move Layer Down", "[", 1, menu: true), entry("Merge Layers", "e", 1, menu: true),
            entry("Show Grid", "'", 1, menu: true), entry("Show Guides", ";", 1, menu: true),
            entry("Show Rulers", "r", 1, menu: true), entry("Snap", ";", 9, menu: true),
            entry("Lock Guides", ";", 3, menu: true),
            // No key by default, so they aren't hit by mistake; Photoshop's are ⌘Y and ⇧⌘Y.
            .init(title: "CMYK Proof Colors", group: "Menus", original: .unassigned),
            .init(title: "CMYK Gamut Warning", group: "Menus", original: .unassigned),
        ]
        for (title, key) in [("Toggle Fullscreen: the canvas alone on black (Esc also leaves)", "f"), ("Select tool", "a"), ("Move / Transform tool", "v"), ("Hand tool", "h"),
            ("Zoom tool", "z"), ("Brush tool", "b"), ("Eraser", "e"), ("Spot Healing", "j"),
            ("Clone Stamp", "s"), ("Type tool", "t"), ("Gradient tool", "g"), ("Shape tool", "u"),
            ("Eyedropper tool", "i"), ("Marquee / cycle shape", "m"), ("Magic", "w"),
            ("Lasso / cycle mode", "l"), ("Blur / Smudge / Liquify", "r"), ("Crop tool", "c"),
            ("Swap foreground/background", "x"), ("Reset colors", "d"), ("Cycle tool mode", "\t"),
            ("Temporary Hand tool (hold)", " "), ("Delete selection / layer / effect / lasso point", "\u{7f}"),
            ("Apply current canvas operation", "\r"), ("Cancel current canvas operation", "\u{1b}"),
            ("Decrease brush size", "["), ("Increase brush size", "]")] {
            result.append(entry(title, key))
        }
        result += [entry("Decrease brush hardness", "[", 8), entry("Increase brush hardness", "]", 8),
                   entry("Previous blend mode", "-", 8), entry("Next blend mode", "=", 8),
                   entry("Cycle shape kind", "u", 8), entry("Paint Bucket tool", "g", 8)]
        for digit in 0...9 { result.append(entry("Opacity digit \(digit) (type two for exact %)", String(digit))) }
        for (direction, key) in [("Left", "\u{f702}"), ("Right", "\u{f703}"), ("Up", "\u{f700}"), ("Down", "\u{f701}")] {
            result += [entry("Nudge \(direction) 1 px", key), entry("Nudge \(direction) 10 px", key, 8),
                       entry("Move selected pixels \(direction) 1 px", key, 1), entry("Move selected pixels \(direction) 10 px", key, 9)]
        }
        result.append(.init(title: "Finish editing text", group: "Text Editing", original: ShortcutChord("\r", 1)))
        for (title, key) in [("Decrease tracking", "\u{f702}"), ("Increase tracking", "\u{f703}"),
                             ("Decrease leading", "\u{f700}"), ("Increase leading", "\u{f701}")] {
            result.append(.init(title: title, group: "Text Editing", original: ShortcutChord(key, 2)))
            result.append(.init(title: title + " by 10", group: "Text Editing", original: ShortcutChord(key, 10)))
        }
        result.append(entry("Toggle Levels preview", "p", 2))
        return result
    }()
}
