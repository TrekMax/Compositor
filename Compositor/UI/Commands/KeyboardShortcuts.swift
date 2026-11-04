import SwiftUI

extension View {
    func configuredNativeShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> some View {
        // nil when the person cleared it: no key at all.
        keyboardShortcut(ShortcutSettings.shared.native(key, modifiers: modifiers).keyboardShortcut)
    }
    func configuredKeyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        keyboardShortcut(ShortcutSettings.shared.menu(key, modifiers: modifiers).keyboardShortcut)
    }
    /// For a menu item that ships without a key: the one the person gave it in Keyboard Shortcuts, if any.
    func assignableShortcut(_ title: String) -> some View {
        keyboardShortcut(ShortcutSettings.shared.assigned(title))
    }
}
