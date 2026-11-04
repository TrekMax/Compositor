import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class ShortcutSettings {
    static let shared = ShortcutSettings()
    private(set) var overrides: [String: ShortcutChord] = [:]
    @ObservationIgnored private let panel = FloatingPanelController(name: "keyboardShortcuts")
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "keyboardShortcuts.v1"
    /// `defaults` is the app's own everywhere but tests, which use a throwaway suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([String: ShortcutChord].self, from: data) else { return }
        let known = Set(ShortcutDefinition.all.map(\.id))
        let restored = Self.preservingAssignmentsBeforePaintBucket(saved.filter { known.contains($0.key) })
        if Self.problem(in: restored) == nil {
            overrides = restored
            return
        }
        // Saved shortcuts are taken one at a time, keeping each that still fits: one a new default now takes
        // drops alone rather than taking every other saved shortcut with it.
        var accepted: [String: ShortcutChord] = [:]
        let bucketID = "Canvas & Layers:Paint Bucket tool"
        if let bucket = restored[bucketID], Self.problem(in: [bucketID: bucket]) == nil {
            accepted[bucketID] = bucket
        }
        for (id, chord) in restored.sorted(by: { $0.key < $1.key }) where known.contains(id) {
            var trial = accepted
            trial[id] = chord
            if Self.problem(in: trial) == nil { accepted = trial }
        }
        overrides = accepted
    }
    /// Shift-G was available for customization before Paint Bucket existed. Keep those assignments
    /// and give the new tool an unused chord instead of rejecting the user's entire configuration.
    private static func preservingAssignmentsBeforePaintBucket(_ saved: [String: ShortcutChord]) -> [String: ShortcutChord] {
        guard let bucket = ShortcutDefinition.all.first(where: { $0.id == "Canvas & Layers:Paint Bucket tool" }),
              saved[bucket.id] == nil, saved.values.contains(bucket.original) else { return saved }
        let others = ShortcutDefinition.all.filter { $0.id != bucket.id }
        let used = Set(others.map { saved[$0.id] ?? $0.original })
        let candidates = [ShortcutChord("g", 10)] + others.map(\.original)
        guard let fallback = candidates.first(where: { !used.contains($0) }) else { return saved }
        var restored = saved
        restored[bucket.id] = fallback
        return restored
    }
    func chord(_ definition: ShortcutDefinition) -> ShortcutChord { overrides[definition.id] ?? definition.original }
    func menu(_ key: KeyEquivalent, modifiers: EventModifiers) -> ShortcutChord {
        let bits = (modifiers.contains(.command) ? 1 : 0) | (modifiers.contains(.option) ? 2 : 0)
            | (modifiers.contains(.control) ? 4 : 0) | (modifiers.contains(.shift) ? 8 : 0)
        let original = ShortcutChord(ShortcutChord.recorded(key), bits)
        guard let definition = ShortcutDefinition.all.first(where: { $0.isMenu && $0.original == original }) else { return original }
        return chord(definition)
    }
    /// The key the person gave a menu command that ships without one, by its title in the list; nil until they do.
    func assigned(_ title: String) -> KeyboardShortcut? {
        ShortcutDefinition.all.first { $0.isMenu && $0.original.isNone && $0.title == title }.flatMap { chord($0).keyboardShortcut }
    }
    func native(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> ShortcutChord {
        let bits = (modifiers.contains(.command) ? 1 : 0) | (modifiers.contains(.option) ? 2 : 0)
            | (modifiers.contains(.control) ? 4 : 0) | (modifiers.contains(.shift) ? 8 : 0)
        let original = ShortcutChord(ShortcutChord.recorded(key), bits)
        guard let definition = ShortcutDefinition.all.first(where: { !$0.isMenu && $0.original == original }) else { return original }
        return chord(definition)
    }
    func show() {
        panel.show(title: "Keyboard Shortcuts", content: KeyboardShortcutsSheet(settings: self))
    }
    func close() { panel.close() }
    func save(_ values: [String: ShortcutChord]) {
        guard Self.problem(in: values) == nil, let data = try? JSONEncoder().encode(values) else { return }
        overrides = values
        defaults.set(data, forKey: Self.storageKey)
        close()
    }
    static func problem(in values: [String: ShortcutChord]) -> String? {
        var assigned: [ShortcutChord: String] = [:]
        for definition in ShortcutDefinition.all {
            let chord = values[definition.id] ?? definition.original
            if chord.isNone { continue }
            guard chord.key.count == 1, (0...15).contains(chord.modifiers) else { return "Choose a single key with optional modifiers." }
            if definition.group == "Text Editing", chord.modifiers & 7 == 0 {
                return "Text-editing shortcuts need Command, Option, or Control so they do not replace normal typing."
            }
            if [ShortcutChord("q", 1), ShortcutChord(",", 1), ShortcutChord("m", 3)].contains(chord) {
                return "\(chord.label) is reserved by macOS."
            }
            if let other = assigned[chord] { return "\(chord.label) is assigned to both \(other) and \(definition.title)." }
            assigned[chord] = definition.title
        }
        return nil
    }

    /// Translate only at the existing canvas/layer responder boundary. Native text
    /// fields and dialog controls retain their normal typing and navigation behavior.
    func canvasEvent(_ event: NSEvent) -> NSEvent? {
        let event = LatinKeys.event(event)
        let input = ShortcutChord(event)
        // A key that types nothing (a dead key on some layouts) reads as no key, as an unassigned command's does.
        guard !overrides.isEmpty, !input.isNone else { return event }
        if let definition = ShortcutDefinition.all.first(where: { $0.group == "Canvas & Layers" && chord($0) == input }) {
            return definition.original == input ? event : definition.original.event(like: event)
        }
        if ShortcutDefinition.all.contains(where: { $0.group != "Text Editing" && $0.original == input && chord($0) != input }) { return nil }
        // Letter tool shortcuts traditionally also accept Shift. Follow the base
        // assignment unless Shift has its own explicit command (e.g. cycle shape).
        if input.modifiers == 8 {
            let plain = ShortcutChord(input.key)
            if let definition = ShortcutDefinition.all.first(where: { !$0.isMenu && $0.original.modifiers == 0 && chord($0) == plain }) {
                return ShortcutChord(definition.original.key, 8).event(like: event)
            }
            if ShortcutDefinition.all.contains(where: { !$0.isMenu && $0.original == plain && chord($0) != plain }) { return nil }
        }
        return event
    }

    func textEvent(_ event: NSEvent) -> NSEvent? {
        let input = ShortcutChord(event)
        guard !overrides.isEmpty, !input.isNone else { return event }
        let definitions = ShortcutDefinition.all.filter { $0.group == "Text Editing" || $0.original == ShortcutChord("\u{1b}") }
        if let definition = definitions.first(where: { chord($0) == input }) {
            return definition.original == input ? event : definition.original.event(like: event)
        }
        if definitions.contains(where: { $0.original == input && chord($0) != input }) { return nil }
        return event
    }
}
