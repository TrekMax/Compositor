import AppKit

/// An effect belongs visually to its layer but has its own selection and visibility control.
final class LayerEffectRow: NSView, NSDraggingSource {
    weak var session: EditorSession?
    let layerID: UUID
    let kind: LayerEffectKind
    private var copyDown: NSEvent?
    private let eye = NSButton()
    private let label: NSTextField
    init(session: EditorSession, layerID: UUID, kind: LayerEffectKind, enabled: Bool, indent: CGFloat) {
        self.session = session; self.layerID = layerID; self.kind = kind
        label = NSTextField(labelWithString: L10n.text(kind.rawValue))
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        eye.isBordered = false
        eye.image = NSImage(systemSymbolName: enabled ? "eye" : "eye.slash", accessibilityDescription: nil)
        eye.imagePosition = .imageOnly
        eye.contentTintColor = .secondaryLabelColor
        eye.target = self; eye.action = #selector(toggle)
        eye.isEnabled = session.canEditLayers
        eye.setAccessibilityLabel(L10n.format(enabled ? "Hide %@" : "Show %@", L10n.text(kind.rawValue)))
        label.font = .systemFont(ofSize: 11)
        label.textColor = enabled ? .labelColor : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        for view in [eye, label] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            eye.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 38 + indent),
            eye.centerYAnchor.constraint(equalTo: centerYAnchor),
            eye.widthAnchor.constraint(equalToConstant: 20), eye.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: eye.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
        toolTip = L10n.format("Click to select; double-click to edit; Option-drag to copy %@", L10n.text(kind.rawValue))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L10n.format("%@ effect", L10n.text(kind.rawValue)))
        updateSelection()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        if flags.contains(.option), !flags.contains(.command) { return self }
        return eye.frame.contains(local) ? eye : self
    }
    func select(editing: Bool) {
        session?.selectEffect(kind, on: layerID, editing: editing)
        var ancestor = superview
        while let view = ancestor, !(view is NSTableView) { ancestor = view.superview }
        if let ancestor { window?.makeFirstResponder(ancestor) }
        updateSelection()
    }
    override func mouseDown(with event: NSEvent) {
        copyDown = nil
        if event.modifierFlags.contains(.option), !event.modifierFlags.contains(.command), session?.canEditLayers == true {
            copyDown = event
        } else { select(editing: event.clickCount > 1) }
    }
    override func mouseUp(with event: NSEvent) {
        if copyDown != nil { copyDown = nil; select(editing: false) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down = copyDown else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy >= 9 else { return }
        copyDown = nil
        guard event.modifierFlags.contains(.option), session?.canEditLayers == true else { return }
        let item = NSPasteboardItem()
        item.setString(layerID.uuidString + ":" + kind.rawValue, forType: NativeLayerList.Coordinator.effectType)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        let snapshot = NSImage(size: bounds.size)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            snapshot.addRepresentation(rep)
        }
        dragging.setDraggingFrame(bounds, contents: snapshot)
        beginDraggingSession(with: [dragging], event: down, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .copy : []
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { select(editing: false); return true }
    @objc private func toggle() { session?.toggleEffect(kind, on: layerID) }
    func updateSelection() {
        let selected = session?.selectedEffect == LayerEffectSelection(layerID: layerID, kind: kind)
        layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor : NSColor.clear.cgColor
    }
}
