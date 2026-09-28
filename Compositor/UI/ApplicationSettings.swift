import SwiftUI

struct ApplicationSettingsView: View {
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
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 150)
        .navigationTitle(L10n.text("Settings"))
    }
}
