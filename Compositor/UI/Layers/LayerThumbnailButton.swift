import AppKit

/// Select on mouse-down, then let the table retain native drag and multiselect tracking.
final class LayerThumbnailButton: NSButton, NSDraggingSource {
    /// The row's layer, for a mask thumbnail's Option-drag.
    var layerID: UUID?
    var isMaskTarget = false { didSet { updateTrackingAreas() } }
    /// Image thumbnails also load a selection on Cmd-click (masks always do).
    var loadsSelection = false { didSet { updateTrackingAreas() } }
    var cmdClickLoads: Bool { isMaskTarget || loadsSelection }
    private var hoverArea: NSTrackingArea?
    private var hovering = false
    private var modifierMonitor: Any?

    // Mask thumbnails show the load-selection cursor while hovered with Cmd held.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        hoverArea = nil
        guard cmdClickLoads else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate,
                                                         .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) {
        guard cmdClickLoads else { return }
        hovering = true
        if modifierMonitor == nil {
            modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else { return event }
                self.updateCursor(event.modifierFlags)
                DispatchQueue.main.async { [weak self] in self?.updateCursor(NSEvent.modifierFlags) }
                return event
            }
        }
        updateCursor(event.modifierFlags)
    }
    override func mouseMoved(with event: NSEvent) { if hovering { updateCursor(event.modifierFlags) } }
    override func cursorUpdate(with event: NSEvent) {
        if hovering { updateCursor(event.modifierFlags) } else { super.cursorUpdate(with: event) }
    }
    override func mouseExited(with event: NSEvent) {
        guard hovering else { return }
        hovering = false
        if let modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }
        modifierMonitor = nil
        // The list decides what the cursor is anywhere else in the row; leaving a thumbnail is not a reason to
        // drop the clipping or duplicate cursor it is showing.
        var ancestor = superview
        while ancestor != nil && !(ancestor is LayerTableView) { ancestor = ancestor?.superview }
        if let table = ancestor as? LayerTableView { table.refreshClippingCursor(NSEvent.modifierFlags) }
        else { NSCursor.arrow.set() }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, let modifierMonitor { NSEvent.removeMonitor(modifierMonitor); self.modifierMonitor = nil }
    }
    private func updateCursor(_ flags: NSEvent.ModifierFlags) {
        guard hovering, isEnabled else { return }
        if flags.contains(.option), !flags.contains(.command) {
            var ancestor = superview
            while ancestor != nil && !(ancestor is LayerTableView) { ancestor = ancestor?.superview }
            (ancestor as? LayerTableView)?.refreshClippingCursor(flags)
            return
        }
        (flags.contains(.command) ? CanvasView.loadSelectionCursor : NSCursor.arrow).set()
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        var ancestor = superview
        while ancestor != nil && !(ancestor is NSTableView) { ancestor = ancestor?.superview }
        guard let table = ancestor as? NSTableView else { super.mouseDown(with: event); return }
        if event.modifierFlags.contains(.option), !event.modifierFlags.contains(.command) {
            if isMaskTarget, !isHidden { dragMaskCopy(event); return }
            table.mouseDown(with: event)
            return
        }
        if cmdClickLoads && event.modifierFlags.contains(.command) {
            // Cmd-click on a thumbnail loads a selection; elsewhere in the row it multi-selects.
            _ = target?.perform(isMaskTarget ? #selector(LayerCell.loadMaskSelection) : #selector(LayerCell.loadLayerSelection))
            return
        }
        if isMaskTarget && event.modifierFlags.contains(.shift) {
            sendAction(action, to: target)
            return
        }
        if event.modifierFlags.intersection([.command, .shift]).isEmpty { sendAction(action, to: target) }
        table.mouseDown(with: event)
    }
}

extension LayerThumbnailButton {
    /// Option-drag from a mask thumbnail carries a copy of the mask to another row; a click without a drag shows
    /// the mask alone on the canvas, or the composite again, as in Photoshop.
    fileprivate func dragMaskCopy(_ down: NSEvent) {
        guard let window, let layerID else { return }
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseUp { _ = target?.perform(#selector(LayerCell.toggleMaskAlone)); return }
            let dx = event.locationInWindow.x - down.locationInWindow.x, dy = event.locationInWindow.y - down.locationInWindow.y
            guard dx * dx + dy * dy >= 9 else { continue }
            let item = NSPasteboardItem()
            item.setString(layerID.uuidString, forType: NativeLayerList.Coordinator.maskType)
            let dragging = NSDraggingItem(pasteboardWriter: item)
            let snapshot = NSImage(size: bounds.size)
            if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
                cacheDisplay(in: bounds, to: rep)
                snapshot.addRepresentation(rep)
            }
            dragging.setDraggingFrame(bounds, contents: snapshot)
            beginDraggingSession(with: [dragging], event: down, source: self)
            return
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .copy : []
    }
}
