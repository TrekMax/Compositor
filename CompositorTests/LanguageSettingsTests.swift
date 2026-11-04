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

    private func catalog(_ language: AppLanguage) throws -> [String: String] {
        let path = try #require(Bundle.main.path(forResource: language.rawValue, ofType: "lproj"))
        let url = URL(fileURLWithPath: path).appendingPathComponent("Localizable.strings")
        return try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }

    @Test func catalogsHaveMatchingKeysAndFormattingArguments() throws {
        let english = try catalog(.english), chinese = try catalog(.simplifiedChinese)
        #expect(Set(english.keys) == Set(chinese.keys))
        // No space flag: a literal percentage followed by prose is not a format argument.
        let placeholder = try NSRegularExpression(pattern: #"%(?:\d+\$)?[-+0#]*(?:\d+|\*)?(?:\.\d+)?(?:hh|h|ll|l|z|t|j)?[@diuoxXfFeEgGcs%]"#)
        func arguments(_ value: String) -> [String] {
            placeholder.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
                (value as NSString).substring(with: $0.range)
            }
        }
        for (key, value) in english {
            let translated = try #require(chinese[key])
            #expect(value == key, "English key changed: \(key)")
            #expect(!translated.isEmpty, "Empty Chinese text: \(key)")
            #expect(arguments(value) == arguments(translated), "Format arguments differ: \(key)")
        }
    }

    @Test func currentFeatureNamesHaveTranslationsWithoutChangingStoredValues() throws {
        let english = try catalog(.english), chinese = try catalog(.simplifiedChinese)
        let keys = Set(FilterKind.allCases.map(\.rawValue) + AdjustmentKind.allCases.map(\.rawValue)
                       + LensEffect.allCases.map(\.rawValue) + BokehShape.allCases.map(\.rawValue)
                       + LayerAlignment.allCases.map(\.rawValue) + LayerDistribution.allCases.map(\.rawValue)
                       + ShapeLineStyle.allCases.map(\.rawValue) + ShapeLineCap.allCases.map(\.rawValue)
                       + NewCanvasBackground.allCases.map(\.title) + ["Show Layers", "Hide Layers"])
        for key in keys {
            #expect(english[key] == key, "Missing English feature: \(key)")
            #expect(chinese[key] != nil, "Missing Chinese feature: \(key)")
        }
        #expect(FilterKind.volumetricLight.rawValue == "Volumetric Light")
        #expect(AdjustmentKind.reduceNoise.rawValue == "Reduce Noise")
        #expect(L10n.text("Volumetric Light", language: .simplifiedChinese) == "体积光")
        #expect(L10n.text("Reduce Noise", language: .simplifiedChinese) == "降噪")
    }

    @Test func newFormattedLabelsPreserveUserNamesAndNumbers() {
        #expect(L10n.format("Export %lld Layers as PNGs", 3, language: .english) == "Export 3 Layers as PNGs")
        #expect(L10n.format("Last Filter: %@", L10n.text("Reduce Noise", language: .simplifiedChinese),
                           language: .simplifiedChinese) == "上次滤镜：降噪")
        let name = "Light / 原图 100%"
        #expect(L10n.format("“%@” has nothing to export", name, language: .simplifiedChinese).contains(name))
    }

    @Test(arguments: [AppLanguage.english, .simplifiedChinese])
    func nativeMenusAndConversionTitlesUseTheChosenLanguage(_ language: AppLanguage) throws {
        let previous = LanguageSettings.shared.selection
        defer { LanguageSettings.shared.select(previous) }
        LanguageSettings.shared.select(language)
        let session = EditorSession()
        session.createDocument(width: 20, height: 20)
        session.addBlankLayer()
        let coordinator = NativeLayerList.Coordinator(session: session)
        coordinator.update(NSTableView())
        let menu = try #require(coordinator.contextMenu(for: 0))
        let export = try #require(menu.items.first { $0.action == NSSelectorFromString("exportLayersAction:") })
        #expect(export.title == L10n.text("Export Layer as PNG…", language: language))
        let depth = try #require(menu.items.first { $0.title == L10n.text("Convert to 16-Bit", language: language) })
        #expect(depth.action != nil)
        let fileName = "Light / 原图 100%.psd"
        let request = PSDConversionRequest(title: "Open “\(fileName)”?", confirmTitle: "Import",
                                           conversions: [], sourceName: fileName)
        #expect(request.displayTitle == L10n.format("Open “%@”?", fileName, language: language))
        #expect(request.sourceName == fileName)
        #expect(projectTabOverflowLabel(for: 2, language: language) == L10n.format("%ld more tabs", 2, language: language))
    }

    @Test func exportLimitErrorsTranslateWithoutLosingTheirNumbers() {
        let english = L10n.errorDescription(ExportError.tooLarge, language: .english)
        let chinese = L10n.errorDescription(ExportError.tooLarge, language: .simplifiedChinese)
        #expect(english != chinese)
        #expect(chinese.contains(String(DocumentLimits.maxSurfaceMegapixels)))
        #expect(chinese.contains("像素"))
        let gif = L10n.errorDescription(GIFExportError.tooLarge, language: .simplifiedChinese)
        #expect(gif.contains("512 MiB") && gif.contains("帧"))
        let frames = L10n.errorDescription(ImageImportError.tooManyFrames, language: .simplifiedChinese)
        #expect(frames.contains("帧") && !frames.contains("This animation"))
        let project = L10n.errorDescription(ProjectError.version(99), language: .simplifiedChinese)
        #expect(project.contains("99") && project.contains(String(ProjectManifest.current)))
        #expect(project.contains("版本"))
        #expect(L10n.errorDescription(ImageImportError.locked, language: .simplifiedChinese).contains("密码"))
        let external = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "User text 100% 原图"])
        #expect(L10n.errorDescription(external, language: .simplifiedChinese) == external.localizedDescription)
    }
}
