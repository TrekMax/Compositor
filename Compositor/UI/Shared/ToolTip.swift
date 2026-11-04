import AppKit
import SwiftUI

extension View {
    func toolTip(_ key: String) -> some View { modifier(ToolTipModifier(key: key)) }
}

private struct ToolTipModifier: ViewModifier {
    let key: String
    func body(content: Content) -> some View {
        content.background(ToolTipAnchor(text: L10n.text(key), enabled: ToolTipSettings.shared.isEnabled,
                                         delay: ToolTipSettings.shared.delay))
    }
}

private struct ToolTipAnchor: NSViewRepresentable {
    let text: String
    let enabled: Bool
    let delay: Double

    func makeNSView(context: Context) -> ToolTipTrackingView { ToolTipTrackingView() }
    func updateNSView(_ view: ToolTipTrackingView, context: Context) {
        view.configure(text: text, enabled: enabled, delay: delay)
    }
    static func dismantleNSView(_ view: ToolTipTrackingView, coordinator: ()) { view.dismiss() }
}

/// A mouse-transparent anchor lets the SwiftUI button keep its clicks. The hint is a child panel so it
/// can extend past the tool rail's scroll view without being clipped or stealing focus.
final class ToolTipTrackingView: NSView {
    private var text = ""
    private var enabled = true
    private var delay = 0.5
    private var hovered = false
    private var tracking: NSTrackingArea?
    private var pending: Task<Void, Never>?
    private var inputMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private(set) var panel: NSPanel?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    func configure(text: String, enabled: Bool, delay: Double) {
        guard self.text != text || self.enabled != enabled || self.delay != delay else { return }
        self.text = text
        self.enabled = enabled
        self.delay = delay
        let wasHovered = hovered
        dismiss()
        hovered = wasHovered
        if hovered { schedule() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        schedule()
    }

    override func mouseExited(with event: NSEvent) { dismiss() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        dismiss()
        super.viewWillMove(toWindow: newWindow)
    }

    func dismiss() {
        hovered = false
        pending?.cancel()
        pending = nil
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    private func schedule() {
        guard enabled, hovered, let window, window.isKeyWindow else { return }
        pending?.cancel()
        if inputMonitor == nil {
            inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown,
                .otherMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
                self?.dismiss()
                return event
            }
            for name in [NSWindow.didResignKeyNotification, NSWindow.didMoveNotification,
                         NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window,
                                                                         queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dismiss() }
                })
            }
        }
        if delay == 0 { show(); return }
        pending = Task { [weak self, delay] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.show()
        }
    }

    private func show() {
        guard enabled, hovered, let window, window.isKeyWindow, !visibleRect.isEmpty, panel == nil else { return }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .labelColor
        let size = NSSize(width: ceil(label.fittingSize.width) + 16, height: ceil(label.fittingSize.height) + 12)
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .toolTip
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.masksToBounds = true
        label.frame = NSRect(x: 8, y: 6, width: size.width - 16, height: size.height - 12)
        background.addSubview(label)

        let anchor = window.convertToScreen(convert(bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? anchor.insetBy(dx: -1000, dy: -1000)
        var origin = NSPoint(x: anchor.maxX + 8, y: anchor.midY - size.height / 2)
        origin.x = max(screen.minX, min(origin.x, screen.maxX - size.width))
        origin.y = max(screen.minY, min(origin.y, screen.maxY - size.height))
        let hint = NSPanel(contentRect: NSRect(origin: origin, size: size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hint.isReleasedWhenClosed = false
        hint.isOpaque = false
        hint.backgroundColor = .clear
        hint.hasShadow = true
        hint.ignoresMouseEvents = true
        hint.level = .popUpMenu
        hint.contentView = background
        window.addChildWindow(hint, ordered: .above)
        hint.orderFront(nil)
        panel = hint
    }
}
