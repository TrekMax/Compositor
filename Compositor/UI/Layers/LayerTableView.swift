import AppKit

final class LayerTableView: NSTableView {
    weak var session: EditorSession?
    /// The layers the list is showing: the panel's filtered rows when a search or filter is on, so a row
    /// index here means the same row it does in the coordinator.
    var displayedRows: [ImageLayer] {
        if let coordinator = delegate as? NativeLayerList.Coordinator { return coordinator.rows }
        // Without the coordinator (never in the panel) there is no honest answer; an empty list only
        // disables the row's cursor and clicks, where a wrong-order guess would act on the wrong layer.
        return []
    }
    private var clippingTracking: NSTrackingArea?
    private var clippingMonitor: Any?
    private var clippingCursorActive = false
    private var middleScrollY: CGFloat?

    /// Grab the layer list with the middle button without selecting or dragging any rows.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, enclosingScrollView != nil else { super.otherMouseDown(with: event); return }
        middleScrollY = event.locationInWindow.y
        NSCursor.closedHand.set()
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard event.buttonNumber == 2, let lastY = middleScrollY, let scroll = enclosingScrollView else {
            super.otherMouseDragged(with: event)
            return
        }
        let y = event.locationInWindow.y
        middleScrollY = y
        let clip = scroll.contentView
        var bounds = clip.bounds
        bounds.origin.y += (y - lastY) * (clip.isFlipped ? 1 : -1)
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        scroll.reflectScrolledClipView(clip)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, middleScrollY != nil else { super.otherMouseUp(with: event); return }
        middleScrollY = nil
        NSCursor.arrow.set()
        refreshClippingCursor(event.modifierFlags, at: event.locationInWindow)
        window?.invalidateCursorRects(for: self)
    }

    /// Cmd-A selects the whole canvas, as Select > All does, even with the Layers panel just clicked — never every layer.
    /// A layer's name being edited keeps its own Select All: its field editor answers first.
    override func selectAll(_ sender: Any?) {
        guard let session = session ?? (delegate as? NativeLayerList.Coordinator)?.session, session.document != nil else { return }
        session.selectAll()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0, row < numberOfRows else { return nil }
        guard let coordinator = delegate as? NativeLayerList.Coordinator else { return nil }
        guard let targetLayer = coordinator.layer(for: row) else { return nil }
        let currentSession = session ?? coordinator.session

        let cell = view(atColumn: 0, row: row, makeIfNecessary: false) as? LayerCell
        let isEffect = cell?.selectEffect(at: event.locationInWindow, editing: false) == true
        if !isEffect {
            currentSession.effectSelection = nil
            let thumb = thumbnail(at: point)
            let isMaskThumb = thumb?.isMaskTarget == true
            let isLayerThumb = thumb?.loadsSelection == true

            if selectedRowIndexes.contains(row) {
                if isMaskThumb {
                    currentSession.selectLayerTarget(targetLayer.id, mask: true)
                } else if isLayerThumb {
                    currentSession.selectLayerTarget(targetLayer.id, mask: false)
                } else {
                    currentSession.selectLayers(currentSession.selectedLayerIDs, primary: targetLayer.id)
                }
            } else {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                window?.makeFirstResponder(self)
                if isMaskThumb {
                    currentSession.selectLayerTarget(targetLayer.id, mask: true)
                } else {
                    currentSession.selectLayerTarget(targetLayer.id, mask: false)
                }
            }
        }

        return coordinator.contextMenu(for: row)
    }
    private static func clippingCursor(releasing: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 30, height: 28), flipped: false) { _ in
            let arrow = NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: nil)!
            let box = NSImage(systemSymbolName: releasing ? "rectangle.badge.minus" : "rectangle.badge.plus", accessibilityDescription: nil)!
            func drawOutlined(_ symbol: NSImage, in rect: NSRect) {
                let white = symbol.withSymbolConfiguration(.init(paletteColors: [.white]))!
                let black = symbol.withSymbolConfiguration(.init(paletteColors: [.black]))!
                for step in 0..<16 {
                    let angle = CGFloat(step) * .pi / 8
                    white.draw(in: rect.offsetBy(dx: cos(angle), dy: sin(angle)))
                }
                black.draw(in: rect)
            }
            drawOutlined(arrow, in: NSRect(x: 1, y: 11, width: 16, height: 15))
            drawOutlined(box, in: NSRect(x: 10, y: 1, width: 19, height: 17))
            return true
        }
        image.accessibilityDescription = L10n.text(releasing ? "Release clipping mask" : "Create clipping mask")
        return NSCursor(image: image, hotSpot: NSPoint(x: 3, y: 3))
    }
    private static let createClippingCursor = clippingCursor(releasing: false)
    private static let releaseClippingCursor = clippingCursor(releasing: true)
    /// Option over a mask thumbnail: the duplicate pointer with a small eye at its lower right — an Option-click shows
    /// the mask alone on the canvas, and an Option-drag still copies it onto another layer.
    private static let showMaskCursor: NSCursor = {
        let base = CanvasView.duplicateCursor
        let eye = NSRect(x: base.hotSpot.x + 15, y: base.hotSpot.y + 18, width: 7.5, height: 5.5)
        let size = NSSize(width: max(base.image.size.width, eye.maxX + 2), height: max(base.image.size.height, eye.maxY + 2))
        let image = NSImage(size: size, flipped: true) { _ in
            // The eye first, so the arrows sit in front of it.
            let symbol = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)!
            let white = symbol.withSymbolConfiguration(.init(paletteColors: [.white]))!
            let black = symbol.withSymbolConfiguration(.init(paletteColors: [.black]))!
            for step in 0..<16 {
                let angle = CGFloat(step) * .pi / 8
                white.draw(in: eye.offsetBy(dx: cos(angle), dy: sin(angle)))
            }
            black.draw(in: eye)
            base.image.draw(in: NSRect(origin: .zero, size: base.image.size), from: .zero, operation: .sourceOver,
                            fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
        image.accessibilityDescription = L10n.text("Show mask alone")
        return NSCursor(image: image, hotSpot: base.hotSpot)
    }()
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let clippingTracking { removeTrackingArea(clippingTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate], owner: self)
        addTrackingArea(area); clippingTracking = area
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        middleScrollY = nil
        if let clippingMonitor { NSEvent.removeMonitor(clippingMonitor); self.clippingMonitor = nil }
        if window != nil {
            clippingMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else { return event }
                self.refreshClippingCursor(event.modifierFlags)
                // A modifier change is not a mouse event: AppKit restores its own cursor once this one is handled,
                // so the cursor is worked out again right after, from wherever the pointer is by then.
                DispatchQueue.main.async { [weak self] in self?.refreshClippingCursor(NSEvent.modifierFlags) }
                return event
            }
        }
    }
    /// Keeps the cursor right over the layer list: with Option held, the clipping cursor over the bottom quarter
    /// of a row, as in Photoshop, and the duplicate cursor over the rest of it (a mask thumbnail shows the mask alone); a thumbnail's own cursor with Command held over
    /// it; otherwise the arrow — even when a
    /// tool's cursor followed the mouse in. `location` is in window coordinates; without one
    /// (a modifier change) the current mouse position is used.
    func refreshClippingCursor(_ flags: NSEvent.ModifierFlags, at location: NSPoint? = nil) {
        if middleScrollY != nil { NSCursor.closedHand.set(); return }
        guard let window else { return }
        let point = convert(location ?? window.mouseLocationOutsideOfEventStream, from: nil)
        let inside = visibleRect.contains(point)
        guard inside, flags.contains(.option), !flags.contains(.command) else {
            // Outside the list, a modifier change must not touch another view's cursor.
            if clippingCursorActive || (inside && !thumbnailOwnsCursor(at: point, flags: flags)) { NSCursor.arrow.set() }
            clippingCursorActive = false
            return
        }
        clippingCursorActive = true
        (clippingCursor(at: point) ?? .arrow).set()
    }

    /// With Option held, the cursor for whatever is under `point`: the clipping cursor over the bottom of a row,
    /// the duplicate cursor over the rest of it, and over a mask thumbnail the one for showing the mask alone.
    private func clippingCursor(at point: NSPoint) -> NSCursor? {
        let index = row(at: point)
        guard let session, displayedRows.indices.contains(index) else { return nil }
        let layer = displayedRows[index]
        // Option-click on a mask shows it alone (Option-dragging it onto another layer still copies it).
        if let thumbnail = thumbnail(at: point), thumbnail.isMaskTarget, !thumbnail.isHidden {
            Self.showMaskCursor.image.accessibilityDescription = L10n.text("Show mask alone")
            return Self.showMaskCursor
        }
        guard isClippingZone(point, row: index) else {
            return session.canEditLayers ? CanvasView.duplicateCursor : NSCursor.arrow
        }
        guard session.canToggleClippingMask(layer.id) else { return NSCursor.arrow }
        let cursor = layer.maskSourceID == nil ? Self.createClippingCursor : Self.releaseClippingCursor
        cursor.image.accessibilityDescription = L10n.text(layer.maskSourceID == nil ? "Create clipping mask" : "Release clipping mask")
        return cursor
    }

    /// Option-click clips along the bottom edge of a row: a fixed strip, not a share of the row's height, so a row
    /// listing several effects keeps the rest of itself free for Option-dragging those effects.
    private static let clippingStrip: CGFloat = 10
    private func isClippingZone(_ point: NSPoint, row: Int) -> Bool {
        guard row >= 0 else { return false }
        if displayedRows.indices.contains(row), displayedRows[row].isGroup == true { return false }
        let rect = rect(ofRow: row)
        return point.y >= rect.maxY - min(Self.clippingStrip, rect.height / 3)
    }
    /// Command held over a thumbnail that loads a selection: that thumbnail shows its cursor.
    private func thumbnailOwnsCursor(at point: NSPoint, flags: NSEvent.ModifierFlags) -> Bool {
        guard flags.contains(.command), let thumbnail = thumbnail(at: point) else { return false }
        return thumbnail.cmdClickLoads && thumbnail.isEnabled
    }
    /// The layer or mask thumbnail under a point in this view's coordinates, if any.
    private func thumbnail(at point: NSPoint) -> LayerThumbnailButton? {
        guard let superview else { return nil }
        var view = superview.hitTest(convert(point, to: superview))
        while let current = view, current !== self {
            if let thumbnail = current as? LayerThumbnailButton { return thumbnail }
            view = current.superview
        }
        return nil
    }
    override func mouseEntered(with event: NSEvent) { refreshClippingCursor(event.modifierFlags, at: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { refreshClippingCursor(event.modifierFlags, at: event.locationInWindow) }
    override func cursorUpdate(with event: NSEvent) { refreshClippingCursor(event.modifierFlags, at: event.locationInWindow) }
    override func mouseExited(with event: NSEvent) {
        // Reloading rows (after a brush stroke, say) rebuilds the tracking areas, which sends an exit even though
        // the pointer never left: taking the cursor back then makes it flicker. Only a real exit resets it.
        if let window, visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
            refreshClippingCursor(NSEvent.modifierFlags)
            return
        }
        if clippingCursorActive { NSCursor.arrow.set(); clippingCursorActive = false }
    }

    /// Effect rows are interactive subviews. In the clipping zone, Option-click belongs to the table
    /// instead, so the same region that advertises the clipping cursor also handles the click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard hit != nil else { return nil }
        // Middle dragging belongs to the list even over thumbnails, visibility buttons and effects.
        if let event = NSApp.currentEvent, event.buttonNumber == 2,
           [.otherMouseDown, .otherMouseDragged, .otherMouseUp].contains(event.type) { return self }
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        let local = convert(point, from: superview)
        guard flags.contains(.option), !flags.contains(.command),
              isClippingZone(local, row: row(at: local)) else { return hit }
        // Option-dragging a mask thumbnail must still copy its mask.
        var target = hit
        while let view = target, view !== self {
            if let thumbnail = view as? LayerThumbnailButton, thumbnail.isMaskTarget { return hit }
            target = view.superview
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        // Handle clipping before effect selection: effects occupy the lower portion of taller rows.
        if event.modifierFlags.contains(.option), !event.modifierFlags.contains(.command), isClippingZone(point, row: row),
           thumbnail(at: point)?.isMaskTarget != true, displayedRows.indices.contains(row) {
            session?.effectSelection = nil
            session?.toggleClippingMask(displayedRows[row].id)
            refreshClippingCursor(event.modifierFlags)
            return
        }
        if row >= 0, let cell = view(atColumn: 0, row: row, makeIfNecessary: false) as? LayerCell,
           cell.selectEffect(at: event.locationInWindow, editing: event.clickCount > 1) {
            window?.makeFirstResponder(self)
            return
        }
        session?.effectSelection = nil
        if row >= 0, event.modifierFlags.intersection([.command, .shift]).isEmpty,
           !(selectedRowIndexes.count > 1 && selectedRowIndexes.contains(row)) {
            // Paint selection before AppKit enters its click/drag tracking loop.
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            window?.makeFirstResponder(self)
            displayIfNeeded()
        }
        super.mouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        guard let event = ShortcutSettings.shared.canvasEvent(event) else { return }
        let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if event.keyCode == 53, session?.transformEdit != nil {
            session?.cancelTransform()
        } else if [36, 76].contains(event.keyCode), session?.transformEdit != nil {
            session?.commitTransform()
        } else if plain, event.keyCode == 48 {
            session?.cycleToolMode()
        } else if plain, event.charactersIgnoringModifiers?.lowercased() == "x" {
            session?.swapPaletteColors()
        } else if plain, event.charactersIgnoringModifiers?.lowercased() == "d" {
            session?.resetPaletteColors()
        } else if plain, event.charactersIgnoringModifiers?.lowercased() == "t" {
            session?.selectTool(.type)
        } else if plain, ["a", "v", "h", "z", "b", "e", "g", "l", "m", "w", "j", "s", "u", "r", "i", "c"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "") {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if key == "m" { if !event.isARepeat { session?.pressMarqueeKey() } }
            else if key == "l" { if !event.isARepeat { session?.pressLassoKey() } }
            else if key == "b" || key == "e" {
                session?.selectTool(.brush)
                session?.brushMode = key == "e" ? .erase : .paint
            }
            else if key == "w" { if !event.isARepeat { session?.pressWandKey() } }
            else { session?.selectTool(key == "a" ? .idle : key == "i" ? .eyedropper : key == "c" ? .crop : key == "r" ? .blur : key == "b" ? .brush : key == "g" ? .gradient : key == "l" ? .lasso : key == "m" ? .marquee : key == "j" ? .spotHealing : key == "s" ? .cloneStamp : key == "u" ? .shape : key == "v" ? .move : key == "h" ? .hand : .zoom) }
        } else if plain, let digit = Int(event.charactersIgnoringModifiers ?? ""), session?.usesOpacityKeys == true {
            session?.typeOpacityDigit(digit)
        // With the Move tool the arrows move the layer, as on the canvas, rather than changing the row selection.
        } else if plain, session?.transformEdit != nil || session?.tool == .move, [123, 124, 125, 126].contains(event.keyCode) {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            session?.nudgeLayer(dx: event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0,
                                dy: event.keyCode == 126 ? -step : event.keyCode == 125 ? step : 0)
        } else if [51, 117].contains(event.keyCode), plain {
            session?.deleteKeyPressed()
        } else { super.keyDown(with: event) }
    }
}
