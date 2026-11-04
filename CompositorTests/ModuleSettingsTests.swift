import Foundation
import Testing
@testable import Compositor

@MainActor struct ModuleSettingsTests {
    @Test func moduleEntrySelectsTheSharedCategoryWithoutChangingGeneralSettings() {
        let routing = SettingsRouting()
        #expect(routing.selectedCategory == .general)
        routing.openModules()
        #expect(routing.selectedCategory == .modules)
        #expect(SettingsCategory.modules.title == "Plug-ins & Modules")
        routing.selectedCategory = .general
        routing.openModules()
        #expect(routing.selectedCategory == .modules)
    }

    @Test func downloadingUsesReceivedBytesAndNeverInventsUnknownProgress() {
        var state = ModuleState(phase: .downloading, receivedBytes: 25, totalBytes: 100)
        #expect(ModulePresentation(state: state).downloadFraction == 0.25)
        state.totalBytes = nil
        #expect(ModulePresentation(state: state).downloadFraction == nil)
        state.totalBytes = 0
        #expect(ModulePresentation(state: state).downloadFraction == nil)
        state.phase = .compiling
        state.totalBytes = 100
        #expect(ModulePresentation(state: state).downloadFraction == nil)
    }

    @Test(arguments: [ModuleState.Phase.migrating, .downloading, .verifying, .compiling, .loading, .removing])
    func busyPhasesPreventConflictingActions(_ phase: ModuleState.Phase) {
        let presentation = ModulePresentation(state: ModuleState(phase: phase, isInstalled: true))
        #expect(!presentation.canInstall)
        #expect(!presentation.canUninstall)
        #expect(!presentation.canToggle)
        #expect(presentation.canCancel == (phase != .removing))
    }

    @Test func absentDisabledAndFailedResourcesOfferRecoveryWithoutContradictoryActions() {
        let absent = ModulePresentation(state: ModuleState())
        #expect(absent.canInstall && absent.canToggle && !absent.canUninstall)
        let disabled = ModulePresentation(state: ModuleState(phase: .disabled, isInstalled: true, isEnabled: false))
        #expect(!disabled.canInstall && disabled.canToggle && disabled.canUninstall)
        let failed = ModulePresentation(state: ModuleState(phase: .failed, isInstalled: true))
        #expect(failed.canInstall && failed.canUninstall && failed.canToggle)
        #expect(absent.depthFeedback != disabled.depthFeedback)
        #expect(failed.depthFeedback != absent.depthFeedback)
    }

    @Test func extractionFailureDoesNotClaimTheModelIsReady() {
        let presentation = ModulePresentation(state: ModuleState(phase: .ready, isInstalled: true))
        #expect(presentation.extractionFeedback == "The depth model could not produce a depth map for this image.")
        let disabled = ModulePresentation(state: ModuleState(phase: .disabled, isEnabled: false))
        #expect(disabled.extractionFeedback == disabled.depthFeedback)
    }

    @Test func downloadCompletionStillReportsVerificationAndCompilation() {
        let download = ModulePresentation(state: ModuleState(phase: .downloading, receivedBytes: 100, totalBytes: 100))
        #expect(download.downloadFraction == 1)
        #expect(download.status == "Downloading…")
        #expect(ModulePresentation(state: ModuleState(phase: .verifying)).status == "Verifying…")
        #expect(ModulePresentation(state: ModuleState(phase: .compiling)).status == "Compiling…")
    }
}
