import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        }
    }
}

struct ApplicationSettingsView: View {
    @State private var selectedCategory: SettingsCategory? = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(L10n.text(category.title), systemImage: category.systemImage)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .navigationTitle(L10n.text("Settings"))
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .accessibilityIdentifier("settingsSidebar")
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selectedCategory ?? .general {
                case .general: GeneralSettingsView()
                }
            }
            .navigationTitle(L10n.text((selectedCategory ?? .general).title))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 420)
    }
}

private struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section {
                Picker("Language / 语言", selection: Binding(
                    get: { LanguageSettings.shared.selection },
                    set: { LanguageSettings.shared.select($0) }
                )) {
                    Text("Follow System / 跟随系统").tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese)
                }
                .accessibilityIdentifier("settingsLanguagePicker")
            } footer: {
                Text("Language changes take effect immediately and are saved automatically.")
            }
            Section {
                Toggle("Show tool names on hover", isOn: Binding(
                    get: { ToolTipSettings.shared.isEnabled },
                    set: { ToolTipSettings.shared.setEnabled($0) }
                ))
                .accessibilityIdentifier("settingsToolTipsEnabled")
                LabeledContent("Show after") {
                    Slider(value: Binding(
                        get: { ToolTipSettings.shared.delay },
                        set: { ToolTipSettings.shared.setDelay($0) }
                    ), in: 0...3, step: 0.1)
                    .accessibilityLabel("Tool tip delay")
                    .accessibilityIdentifier("settingsToolTipDelay")
                    Text(L10n.format("%.1f seconds", ToolTipSettings.shared.delay))
                        .monospacedDigit()
                        .frame(minWidth: 80, alignment: .trailing)
                }
                .disabled(!ToolTipSettings.shared.isEnabled)
            } header: {
                Text("Tool Tips")
            } footer: {
                Text("Tool names appear beside the left toolbar. Changes are saved automatically.")
            }
        }
        .formStyle(.grouped)
    }
}
