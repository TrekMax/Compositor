import AppKit
import Testing
@testable import Compositor

@MainActor struct ShortcutSettingsTests {
    @Test(arguments: [false, true])
    func addingBucketPreservesExistingShortcutAssignments(fallbackOccupied: Bool) throws {
        let name = "ShortcutSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let brush = try definition("Brush tool")
        let move = try definition("Move / Transform tool")
        let bucket = try definition("Paint Bucket tool")
        var saved = [brush.id: ShortcutChord("g", 8), move.id: ShortcutChord("v", 2)]
        if fallbackOccupied { saved[try definition("Zoom tool").id] = ShortcutChord("g", 10) }
        defaults.set(try JSONEncoder().encode(saved), forKey: "keyboardShortcuts.v1")

        let settings = ShortcutSettings(defaults: defaults)
        for (id, chord) in saved { #expect(settings.overrides[id] == chord) }
        #expect(settings.chord(bucket) != ShortcutChord("g", 8))
        #expect(ShortcutSettings.problem(in: settings.overrides) == nil)
        #expect(ShortcutSettings(defaults: defaults).overrides == settings.overrides)
        let input = try #require(ShortcutChord("g", 8).event(like: keyEvent()))
        let routed = try #require(settings.canvasEvent(input))
        #expect(ShortcutChord(routed) == brush.original)
        let bucketInput = try #require(settings.chord(bucket).event(like: keyEvent()))
        #expect(ShortcutChord(try #require(settings.canvasEvent(bucketInput))) == bucket.original)
    }

    @Test func explicitBucketAssignmentIsKept() throws {
        let name = "ShortcutSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let saved = [try definition("Brush tool").id: ShortcutChord("g", 8),
                     try definition("Paint Bucket tool").id: ShortcutChord("g", 10)]
        defaults.set(try JSONEncoder().encode(saved), forKey: "keyboardShortcuts.v1")
        #expect(ShortcutSettings(defaults: defaults).overrides == saved)
    }

    private func definition(_ title: String) throws -> ShortcutDefinition {
        try #require(ShortcutDefinition.all.first { $0.title == title })
    }

    private func keyEvent() throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "g",
            charactersIgnoringModifiers: "g", isARepeat: false, keyCode: 5))
    }
}
