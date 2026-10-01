import AppKit
import SwiftUI
import Testing
@testable import Compositor

@MainActor @Suite(.serialized)
struct ToolTipTests {
    @Test func preferencesPersistDisabledAndImmediateHints() {
        let name = "ToolTipTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = ToolTipSettings(defaults: defaults)
        settings.setEnabled(false)
        settings.setDelay(0)
        let reopened = ToolTipSettings(defaults: defaults)
        #expect(!reopened.isEnabled)
        #expect(reopened.delay == 0)
        settings.setEnabled(true)
        settings.setDelay(1.7)
        #expect(ToolTipSettings(defaults: defaults).delay == 1.7)
        #expect(ToolTipSettings(defaults: defaults).isEnabled)
    }

    @Test func invalidDelayCannotCreateAnUnboundedWait() {
        let name = "ToolTipTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(-2, forKey: ToolTipSettings.delayKey)
        let settings = ToolTipSettings(defaults: defaults)
        #expect(settings.delay == 0)
        settings.setDelay(9)
        #expect(settings.delay == 3)
        settings.setDelay(.nan)
        #expect(settings.delay == 0.5)
        defaults.set("invalid", forKey: ToolTipSettings.delayKey)
        #expect(ToolTipSettings(defaults: defaults).delay == 0.5)
    }

    @Test func hintWaitsAndExitCancelsPendingPresentation() async throws {
        let (window, view) = host()
        defer { view.dismiss(); window.orderOut(nil) }
        view.configure(text: "Move (V)", enabled: true, delay: 0.05)
        view.mouseEntered(with: NSEvent())
        #expect(view.panel == nil)
        // Other suites can occupy the main actor before the delayed task even starts.
        let deadline = ContinuousClock.now + .seconds(2)
        while view.panel == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(view.panel?.isVisible == true)
        #expect(view.panel?.ignoresMouseEvents == true)
        #expect(view.hitTest(.zero) == nil)
        view.mouseExited(with: NSEvent())
        #expect(view.panel == nil)
        view.mouseEntered(with: NSEvent())
        view.mouseExited(with: NSEvent())
        try await Task.sleep(for: .milliseconds(150))
        #expect(view.panel == nil)
    }

    @Test func disablingOrDismissingCancelsTheHint() async throws {
        let (window, view) = host()
        defer { view.dismiss(); window.orderOut(nil) }
        view.configure(text: "Move (V)", enabled: true, delay: 0)
        view.mouseEntered(with: NSEvent())
        #expect(view.panel?.isVisible == true)
        view.configure(text: "Move (V)", enabled: false, delay: 0)
        #expect(view.panel == nil)
        view.configure(text: "Move (V)", enabled: true, delay: 0.05)
        view.dismiss()
        try await Task.sleep(for: .milliseconds(150))
        #expect(view.panel == nil)
    }

    @Test func changingDelayReplacesThePendingWaitAndRemovalCancelsIt() async throws {
        let (window, view) = host()
        defer { view.dismiss(); window.orderOut(nil) }
        view.configure(text: "Move (V)", enabled: true, delay: 3)
        view.mouseEntered(with: NSEvent())
        view.configure(text: "移动（V）", enabled: true, delay: 0)
        #expect(view.panel?.isVisible == true)
        view.configure(text: "移动（V）", enabled: true, delay: 0.05)
        view.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(150))
        #expect(view.panel == nil)
    }

    @Test func clickingTheToolDismissesTheHintAndStillReachesTheButton() throws {
        let (window, view) = host()
        defer { view.dismiss(); window.orderOut(nil) }
        let button = ClickRecordingButton(frame: view.frame)
        window.contentView?.addSubview(button, positioned: .below, relativeTo: view)
        view.configure(text: "Move (V)", enabled: true, delay: 0)
        view.mouseEntered(with: NSEvent())
        #expect(view.panel?.isVisible == true)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
            location: NSPoint(x: view.frame.midX, y: view.frame.midY), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        NSApp.sendEvent(event)
        #expect(view.panel == nil)
        #expect(button.clickCount == 1)
    }

    @Test func deactivatingTheWindowDismissesTheHint() {
        let (window, view) = host()
        defer { view.dismiss(); window.orderOut(nil) }
        view.configure(text: "Move (V)", enabled: true, delay: 0)
        view.mouseEntered(with: NSEvent())
        #expect(view.panel?.isVisible == true)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(view.panel == nil)
    }

    private final class ClickRecordingButton: NSButton {
        var clickCount = 0
        override func mouseDown(with event: NSEvent) { clickCount += 1 }
    }

    @Test func hintExtendsBeyondTheHostedToolRailWithoutClipping() async throws {
        let window = HintTestWindow(contentRect: NSRect(x: 100, y: 100, width: 56, height: 100),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: IndicatorlessScrollView {
            Button {} label: { Image(systemName: "hand.draw").frame(width: 36, height: 36) }
                .toolTip("Hand (H)")
        }.frame(width: 56, height: 100))
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
        let view = try #require(findAnchor(in: hosting))
        defer { view.dismiss() }
        #expect(view.bounds.width > 0 && view.bounds.height > 0)
        view.configure(text: "抓手（H）", enabled: true, delay: 0)
        view.mouseEntered(with: NSEvent())
        let panel = try #require(view.panel)
        #expect(panel.isVisible)
        #expect(panel.parent === window)
        #expect(panel.frame.maxX > window.frame.maxX)
    }

    private func findAnchor(in view: NSView) -> ToolTipTrackingView? {
        if let anchor = view as? ToolTipTrackingView { return anchor }
        return view.subviews.lazy.compactMap { findAnchor(in: $0) }.first
    }

    // Other suites activate their own windows in parallel. Keep this fixture's focus stable while
    // exercising real tracking views, child panels and cancellation without stealing the user's focus.
    private final class HintTestWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    private func host() -> (NSWindow, ToolTipTrackingView) {
        let window = HintTestWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let view = ToolTipTrackingView(frame: NSRect(x: 10, y: 10, width: 36, height: 36))
        window.contentView?.addSubview(view)
        window.orderFront(nil)
        #expect(!view.visibleRect.isEmpty)
        return (window, view)
    }
}
