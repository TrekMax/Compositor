import SwiftUI

/// Applied at every hosting root, including the editor's detached panels.
private struct ApplicationLanguageModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.environment(\.locale, LanguageSettings.shared.locale)
    }
}

extension View {
    func applicationLanguage() -> some View { modifier(ApplicationLanguageModifier()) }
}

struct InitialLanguageSelection: ViewModifier {
    let applicationDelegate: CompositorApplicationDelegate
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .task { isPresented = LanguageSettings.shared.needsInitialSelection }
            .sheet(isPresented: $isPresented) {
                LanguageSelectionSheet {
                    isPresented = false
                    applicationDelegate.finishLanguageSelection()
                }
            }
    }
}

struct LanguageSelectionSheet: View {
    @State private var choice = LanguageSettings.shared.selection
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose Your Language / 选择语言").font(.title2.bold())
            Picker("Language / 语言", selection: $choice) {
                Text("Follow System / 跟随系统").tag(AppLanguage.system)
                Text(verbatim: "English").tag(AppLanguage.english)
                Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese)
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("initialLanguagePicker")
            Text("You can change this later in Compositor Settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Continue") {
                    LanguageSettings.shared.select(choice)
                    onContinue()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("confirmInitialLanguage")
            }
        }
        .padding(28)
        .frame(width: 420)
        .environment(\.locale, Locale(identifier: choice.resolvedIdentifier()))
        .interactiveDismissDisabled()
    }
}
