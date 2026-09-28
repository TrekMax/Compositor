import AppKit
import Testing
@testable import Compositor

@MainActor struct LanguageSettingsTests {
    private func preferences() -> UserDefaults {
        UserDefaults(suiteName: "LanguageSettingsTests.\(UUID().uuidString)")!
    }

    @Test func firstLaunchRemainsPendingUntilChoiceIsSaved() {
        let defaults = preferences()
        let settings = LanguageSettings(defaults: defaults)
        #expect(settings.needsInitialSelection)
        #expect(settings.selection == .system)
        settings.select(.system)
        let reopened = LanguageSettings(defaults: defaults)
        #expect(!reopened.needsInitialSelection)
        #expect(reopened.selection == .system)
        defaults.removeObject(forKey: LanguageSettings.storageKey)
    }

    @Test func explicitChoiceSurvivesRelaunchAndCanReturnToSystem() {
        let defaults = preferences()
        let settings = LanguageSettings(defaults: defaults)
        let systemLanguages = defaults.stringArray(forKey: "AppleLanguages")
        settings.select(.simplifiedChinese)
        #expect(LanguageSettings(defaults: defaults).selection == .simplifiedChinese)
        settings.select(.english)
        #expect(LanguageSettings(defaults: defaults).selection == .english)
        settings.select(.system)
        #expect(LanguageSettings(defaults: defaults).selection == .system)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == systemLanguages)
        defaults.removeObject(forKey: LanguageSettings.storageKey)
    }

    @Test func invalidPreferenceRequestsAChoiceAgain() {
        let defaults = preferences()
        defaults.set("removed-language", forKey: LanguageSettings.storageKey)
        let settings = LanguageSettings(defaults: defaults)
        #expect(settings.needsInitialSelection)
        #expect(settings.selection == .system)
        defaults.removeObject(forKey: LanguageSettings.storageKey)
    }

    @Test func systemMatchesSupportedLanguagesInPreferenceOrder() {
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-Hans-CN", "en-US"]) == "zh-Hans")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["en-GB", "zh-Hans"]) == "en")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["fr-FR", "zh-CN"]) == "zh-Hans")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["de-DE"]) == "en")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: []) == "en")
        #expect(AppLanguage.english.resolvedIdentifier(preferredLanguages: ["zh-Hans"]) == "en")
        #expect(AppLanguage.simplifiedChinese.resolvedIdentifier(preferredLanguages: ["en"]) == "zh-Hans")
    }

    @Test func shortcutIdentifiersKeepCanonicalTextAcrossLanguages() throws {
        let finish = try #require(ShortcutDefinition.all.first {
            $0.group == "Text Editing" && $0.original == ShortcutChord("\r", 1)
        })
        #expect(finish.id == "Text Editing:Finish editing text")
        #expect(L10n.text(finish.title, language: .simplifiedChinese) == "完成文本编辑")
    }

    @Test func translatedBlendMenuStillSelectsTheStoredMode() throws {
        let session = EditorSession()
        session.createDocument(width: 20, height: 20)
        session.addBlankLayer()
        let coordinator = BlendModePicker.Coordinator(session: session)
        let button = NSPopUpButton()
        button.addItem(withTitle: "正片叠底")
        button.lastItem?.representedObject = "Multiply"
        coordinator.menuWillOpen(try #require(button.menu))
        coordinator.choose(button)
        #expect(session.activeLayer?.blendMode == .multiply)
        #expect(session.activeLayer?.blendMode.rawValue == "Multiply")
    }

    @Test func explicitBundleLookupSwitchesAndFallsBackWithoutChangingUserText() {
        #expect(L10n.text("Save", language: .simplifiedChinese) == "保存")
        #expect(L10n.text("Save", language: .english) == "Save")
        #expect(L10n.text("An unknown label", language: .simplifiedChinese) == "An unknown label")
        #expect(L10n.format("Save changes to %@?", "My photo", language: .simplifiedChinese) == "要保存对“My photo”的更改吗？")
    }
}
