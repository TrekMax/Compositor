import Foundation
import Testing
@testable import Compositor

@MainActor struct ModuleManagerTests {
    @Test func installDoesNotImplyRuntimeReady() async throws {
        let fixture = ModuleFixture(), runtime = FixtureRuntime()
        let installer = FixtureInstaller(root: fixture.root)
        let manager = moduleManager(fixture, installer: installer, runtime: runtime)
        await manager.install("tiny")
        #expect(manager.state(for: "tiny").isInstalled)
        #expect(manager.state(for: "tiny").phase == .installed)
        #expect(!runtime.isReady)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("model/weights").path))
        #expect(await manager.prepare("tiny"))
        #expect(manager.state(for: "tiny").phase == .ready)
    }

    @Test func disabledInstallationReenablesWithoutDownload() async {
        let fixture = ModuleFixture(), runtime = FixtureRuntime()
        let installer = FixtureInstaller(root: fixture.root)
        let manager = moduleManager(fixture, installer: installer, runtime: runtime)
        #expect(await manager.prepare("tiny"))
        await manager.setEnabled(false, for: "tiny")
        #expect(!runtime.isReady)
        #expect(manager.state(for: "tiny").isInstalled)
        #expect(await manager.prepare("tiny") == false)
        let reopened = moduleManager(fixture, installer: installer, runtime: runtime)
        await reopened.refresh()
        #expect(!reopened.state(for: "tiny").isEnabled)
        await reopened.setEnabled(true, for: "tiny")
        #expect(await reopened.prepare("tiny"))
    }

    @Test func uninstallDrainsRuntimeAndPersistsSuppression() async {
        let fixture = ModuleFixture(), runtime = FixtureRuntime()
        let installer = FixtureInstaller(root: fixture.root)
        let manager = moduleManager(fixture, installer: installer, runtime: runtime)
        #expect(await manager.prepare("tiny"))
        runtime.holdLease()
        let removing = Task { await manager.uninstall("tiny") }
        await waitForModuleCondition { runtime.isDraining }
        #expect(!runtime.isReady)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("model").path))
        runtime.releaseLease()
        await removing.value
        #expect(!manager.state(for: "tiny").isInstalled)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("model").path))
        #expect(await manager.prepare("tiny") == false)
        let reopened = moduleManager(fixture, installer: installer, runtime: runtime)
        #expect(await reopened.prepare("tiny") == false)
        await reopened.install("tiny")
        #expect(await reopened.prepare("tiny"))
    }

    @Test func cancelledDownloadCannotOverwriteRetry() async {
        let fixture = ModuleFixture()
        let installer = FixtureInstaller(root: fixture.root)
        let manager = moduleManager(fixture, installer: installer)
        installer.hold()
        let first = Task { await manager.install("tiny") }
        await waitForModuleCondition { installer.isHeld }
        manager.cancel("tiny")
        #expect(manager.state(for: "tiny").phase == .cancelled)
        #expect(await manager.prepare("tiny") == false)
        await manager.install("tiny")
        #expect(manager.state(for: "tiny").phase == .installed)
        installer.release()
        await first.value
        #expect(manager.state(for: "tiny").phase == .installed)
        #expect(manager.state(for: "tiny").issue == nil)
    }

    @Test func concurrentPrepareAndInstallShareOperation() async {
        let fixture = ModuleFixture(), runtime = FixtureRuntime()
        let installer = FixtureInstaller(root: fixture.root)
        let manager = moduleManager(fixture, installer: installer, runtime: runtime)
        installer.hold()
        let first = Task { await manager.prepare("tiny") }
        await waitForModuleCondition { installer.isHeld }
        let second = Task { await manager.install("tiny") }
        await Task.yield()
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("model").path))
        installer.release()
        #expect(await first.value)
        await second.value
        #expect(manager.state(for: "tiny").phase == .ready)
    }
}

extension ModuleManagerTests {
    @Test func automaticFetchSuppressionStillLoadsExistingInstall() async {
        let fixture = ModuleFixture(), runtime = FixtureRuntime()
        let installer = FixtureInstaller(root: fixture.root)
        let manager = moduleManager(fixture, installer: installer, runtime: runtime)
        await manager.install("tiny")
        manager.cancel("tiny")
        let reopened = moduleManager(fixture, installer: installer, runtime: runtime)
        #expect(await reopened.prepare("tiny"))
    }

    @Test func disableRejectsLateActivation() async {
        let fixture = ModuleFixture(), runtime = HeldActivationRuntime()
        let manager = ModuleManager(descriptors: [fixture.descriptor], root: fixture.root, defaults: fixture.defaults,
                                    installer: FixtureInstaller(root: fixture.root), runtimes: ["tiny": runtime])
        let preparing = Task { await manager.prepare("tiny") }
        await waitForModuleCondition { runtime.gate.isWaiting }
        #expect(runtime.gate.isWaiting)
        let disabling = Task { await manager.setEnabled(false, for: "tiny") }
        await waitForModuleCondition { !manager.state(for: "tiny").isEnabled }
        runtime.gate.release()
        #expect(await preparing.value == false)
        await disabling.value
        #expect(!runtime.isReady)
        #expect(manager.state(for: "tiny").phase == .disabled)
        #expect(manager.state(for: "tiny").isInstalled)
    }

    @Test func refreshingReadyRuntimeKeepsReadiness() async {
        let fixture = ModuleFixture(), runtime = FixtureRuntime()
        let manager = moduleManager(fixture, installer: FixtureInstaller(root: fixture.root), runtime: runtime)
        #expect(await manager.prepare("tiny"))
        await manager.refresh()
        #expect(manager.state(for: "tiny").phase == .ready)
    }

    @Test func invalidDescriptorCannotCreateFiles() async {
        let fixture = ModuleFixture()
        let descriptor = ModuleDescriptor(id: "../outside", name: "Bad", summary: "", version: "1", source: fixture.descriptor.source,
                                          publisher: "Fixture", homepage: URL(string: "https://example.invalid/")!, releasePage: URL(string: "https://example.invalid/release")!, attributions: [], assets: fixture.descriptor.assets, capability: "depth", packageName: "Tiny.mlpackage",
                                          compiledName: "Tiny.mlmodelc", legacyPath: nil, inputName: "image", outputName: "depth")
        let manager = ModuleManager(descriptors: [descriptor], root: fixture.root, defaults: fixture.defaults, installer: FixtureInstaller(root: fixture.root))
        await manager.install(descriptor.id)
        #expect(manager.state(for: descriptor.id).issue?.code == .invalidDescriptor)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
    }
}

extension ModuleManagerTests {
    @Test func activationFailureRetainsInstallAndReportsRuntimeIssue() async {
        let fixture = ModuleFixture(), runtime = FailingModuleRuntime()
        let manager = ModuleManager(descriptors: [fixture.descriptor], root: fixture.root, defaults: fixture.defaults,
                                    installer: FixtureInstaller(root: fixture.root), runtimes: ["tiny": runtime])
        #expect(await manager.prepare("tiny") == false)
        #expect(manager.state(for: "tiny").isInstalled)
        #expect(manager.state(for: "tiny").issue?.code == .runtime)
        #expect(!runtime.isReady)
        #expect(await manager.prepare("tiny") == false)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("model/weights").path))
    }

    @Test func explicitInstallRecoversFromFailedLegacyValidation() async throws {
        let fixture = ModuleFixture(), normal = fixtureCoreInstaller(fixture)
        let legacy = fixture.root.appendingPathComponent("Legacy/Tiny.mlmodelc")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy.appendingPathComponent("model"))
        let installer = CoreMLModuleInstaller(root: normal.storage.root, legacyBase: fixture.root, transport: FixtureTransport(), compile: normal.compile) { url, descriptor in
            if try Data(contentsOf: url.appendingPathComponent("model")) == Data("old".utf8) { throw CocoaError(.fileReadCorruptFile) }
            try await normal.validate(url, descriptor)
        }
        let manager = ModuleManager(descriptors: [fixture.descriptor], root: normal.storage.root, defaults: fixture.defaults, installer: installer)
        await manager.refresh()
        #expect(manager.state(for: "tiny").issue?.code == .migration)
        #expect(FileManager.default.fileExists(atPath: legacy.path))
        await manager.install("tiny")
        #expect(manager.state(for: "tiny").isInstalled)
        #expect(manager.state(for: "tiny").provenance == .verifiedDownload)
        #expect(manager.state(for: "tiny").receivedBytes == 3)
    }
}

extension ModuleManagerTests {
    @Test func enableChangeDuringUninstallKeepsRemovingState() async {
        let fixture = ModuleFixture(), runtime = FixtureRuntime()
        let manager = moduleManager(fixture, installer: FixtureInstaller(root: fixture.root), runtime: runtime)
        #expect(await manager.prepare("tiny"))
        runtime.holdLease()
        let removing = Task { await manager.uninstall("tiny") }
        await waitForModuleCondition { runtime.isDraining }
        await manager.setEnabled(true, for: "tiny")
        #expect(manager.state(for: "tiny").phase == .removing)
        runtime.releaseLease()
        await removing.value
        #expect(!manager.state(for: "tiny").isInstalled)
    }
}

extension ModuleManagerTests {
    @Test(arguments: [false, true], [false, true])
    func revokedScanCannotRestartThroughWaiter(disable: Bool, prepare: Bool) async {
        let fixture = ModuleFixture(), installer = FixtureInstaller(root: fixture.root)
        let manager = moduleManager(fixture, installer: installer, runtime: FixtureRuntime())
        installer.holdNextInspection()
        let scan = Task { await manager.refresh() }
        await waitForModuleCondition { installer.inspection.isWaiting }
        var joined = false
        let waiter = Task {
            joined = true
            if prepare { _ = await manager.prepare("tiny") } else { await manager.install("tiny") }
        }
        await waitForModuleCondition { joined }
        if disable { await manager.setEnabled(false, for: "tiny") } else { manager.cancel("tiny") }
        installer.inspection.release()
        await scan.value
        await waiter.value
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("model").path))
        #expect(!manager.state(for: "tiny").isInstalled)
        #expect(manager.state(for: "tiny").phase == (disable ? .disabled : .cancelled))
        await manager.install("tiny")
        #expect(manager.state(for: "tiny").isInstalled)
    }

    @Test func refreshClearsMissingInstallationAndRuntime() async throws {
        let fixture = ModuleFixture(), runtime = FixtureRuntime()
        let manager = moduleManager(fixture, installer: FixtureInstaller(root: fixture.root), runtime: runtime)
        #expect(await manager.prepare("tiny"))
        let revision = manager.availabilityRevision
        try FileManager.default.removeItem(at: fixture.root)
        await manager.refresh()
        let state = manager.state(for: "tiny")
        #expect(state.phase == .notInstalled)
        #expect(!state.isInstalled)
        #expect(state.installedBytes == 0)
        #expect(state.provenance == nil)
        #expect(!runtime.isReady)
        #expect(manager.availabilityRevision > revision)
    }

    @Test func migrationPublishesIndeterminatePhaseWhileValidating() async throws {
        let fixture = ModuleFixture(), gate = ModuleGate(), normal = fixtureCoreInstaller(fixture)
        let legacy = fixture.root.appendingPathComponent("Legacy/Tiny.mlmodelc")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy.appendingPathComponent("model"))
        let installer = CoreMLModuleInstaller(root: normal.storage.root, legacyBase: fixture.root, transport: FixtureTransport(), compile: normal.compile) { _, _ in await gate.wait() }
        let manager = ModuleManager(descriptors: [fixture.descriptor], root: normal.storage.root, defaults: fixture.defaults, installer: installer)
        let scan = Task { await manager.refresh() }
        await waitForModuleCondition { gate.isWaiting }
        await waitForModuleCondition { manager.state(for: "tiny").phase == .migrating }
        #expect(manager.state(for: "tiny").phase == .migrating)
        #expect(manager.state(for: "tiny").totalBytes == nil)
        gate.release()
        await scan.value
        #expect(manager.state(for: "tiny").phase == .installed)
    }

    @Test func reorderedProgressCannotRegressBytesOrPhase() async {
        let fixture = ModuleFixture(), installer = ReorderedProgressInstaller(root: fixture.root)
        let manager = moduleManager(fixture, installer: installer)
        let installing = Task { await manager.install("tiny") }
        await waitForModuleCondition { installer.gate.isWaiting }
        await installer.emit(ModuleProgress(phase: .downloading, receivedBytes: 3, totalBytes: 3))
        await waitForModuleCondition { manager.state(for: "tiny").receivedBytes == 3 }
        await installer.emit(ModuleProgress(phase: .compiling, receivedBytes: 3, totalBytes: nil))
        await waitForModuleCondition { manager.state(for: "tiny").phase == .compiling }
        await installer.emit(ModuleProgress(phase: .downloading, receivedBytes: 1, totalBytes: 3))
        await installer.emit(ModuleProgress(phase: .verifying, receivedBytes: 2, totalBytes: nil))
        #expect(manager.state(for: "tiny").phase == .compiling)
        #expect(manager.state(for: "tiny").receivedBytes == 3)
        installer.gate.release()
        await installing.value
    }
}
