import Foundation
import Testing
@testable import Compositor

struct ModuleStorageTests {
    @Test func catalogPinsCompletePackage() throws {
        let descriptor = ModuleCatalog.depthMini
        #expect(descriptor.id == "depth-mini")
        #expect(descriptor.downloadBytes == 2_657_779)
        #expect(descriptor.assets.count == 3)
        #expect(descriptor.assets.allSatisfy { $0.sha256.count == 64 })
        try ModuleStorage(root: FileManager.default.temporaryDirectory).validate(descriptor)
    }

    @Test func rejectsTraversalBeforeCreatingRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let descriptor = ModuleDescriptor(id: "../outside", name: "Bad", summary: "", version: "1", source: URL(string: "https://example.invalid/")!, assets: [], capability: "depth", packageName: "a.mlpackage", compiledName: "a.mlmodelc", legacyPath: nil, inputName: "image", outputName: "depth")
        #expect(throws: (any Error).self) { try ModuleStorage(root: root).validate(descriptor) }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

extension ModuleStorageTests {
    @Test func installationReceiptSurvivesReopenAndFailedReplacement() async throws {
        let fixture = ModuleFixture()
        let installer = fixtureCoreInstaller(fixture)
        let installed = try await installer.install(fixture.descriptor) { _ in }
        #expect(try Data(contentsOf: installed.compiledURL.appendingPathComponent("model")) == Data("compiled".utf8))
        #expect(installed.provenance == .verifiedDownload)
        let broken = fixtureCoreInstaller(fixture, corrupt: true)
        await #expect(throws: (any Error).self) { try await broken.install(fixture.descriptor) { _ in } }
        let reopened = try #require(try await fixtureCoreInstaller(fixture).inspect(fixture.descriptor))
        #expect(reopened.compiledURL == installed.compiledURL)
        #expect(reopened.bytes == 8)
    }

    @Test func migrationCopiesValidatesAndRetainsHonestProvenance() async throws {
        let fixture = ModuleFixture()
        let legacy = fixture.root.appendingPathComponent("Legacy/Tiny.mlmodelc")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy.appendingPathComponent("model"))
        let installer = fixtureCoreInstaller(fixture)
        let migrated = try #require(try await installer.migrate(fixture.descriptor))
        #expect(migrated.provenance == .migratedCompiledCache)
        #expect(try Data(contentsOf: migrated.compiledURL.appendingPathComponent("model")) == Data("old".utf8))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(try await installer.inspect(fixture.descriptor)?.provenance == .migratedCompiledCache)
    }

    @Test func failedMigrationPreservesLegacyAndExplicitInstallRecovers() async throws {
        let fixture = ModuleFixture()
        let legacy = fixture.root.appendingPathComponent("Legacy/Tiny.mlmodelc")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy.appendingPathComponent("model"))
        await #expect(throws: (any Error).self) { try await fixtureCoreInstaller(fixture, invalid: true).migrate(fixture.descriptor) }
        #expect(try Data(contentsOf: legacy.appendingPathComponent("model")) == Data("old".utf8))
        let recovered = try await fixtureCoreInstaller(fixture).install(fixture.descriptor) { _ in }
        #expect(recovered.provenance == .verifiedDownload)
    }

    @Test func rejectsSymlinkEscapeAndInvalidPackagePath() throws {
        let fixture = ModuleFixture()
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("escape"), withDestinationURL: FileManager.default.temporaryDirectory)
        #expect(throws: (any Error).self) { try ModuleStorage(root: fixture.root).contained("escape/outside", in: fixture.root) }
    }
}

extension ModuleStorageTests {
    @Test func sourceValidationPrecedesCompilerAndPreservesGoodInstall() async throws {
        let fixture = ModuleFixture()
        let good = try await fixtureCoreInstaller(fixture).install(fixture.descriptor) { _ in }
        await #expect(throws: (any Error).self) {
            try await fixtureCoreInstaller(fixture, payload: "bad").install(fixture.descriptor) { _ in }
        }
        let inspected = try #require(try await fixtureCoreInstaller(fixture).inspect(fixture.descriptor))
        #expect(inspected.compiledURL == good.compiledURL)
    }

    @Test func cancellationDuringCompilationCannotPublishAndRefreshPreservesStage() async throws {
        let fixture = ModuleFixture(), gate = ModuleGate()
        let installer = CoreMLModuleInstaller(root: fixture.root, legacyBase: fixture.root, transport: FixtureTransport(), compile: { package in
            await gate.wait()
            #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("Data/weight.bin").path))
            let built = package.deletingLastPathComponent().appendingPathComponent("compiled")
            try FileManager.default.createDirectory(at: built, withIntermediateDirectories: true)
            return built
        }, validate: { _, _ in })
        let installing = Task { try await installer.install(fixture.descriptor) { _ in } }
        await waitForModuleCondition { gate.isWaiting }
        #expect(gate.isWaiting)
        #expect(try await installer.inspect(fixture.descriptor) == nil)
        installing.cancel()
        gate.release()
        await #expect(throws: CancellationError.self) { try await installing.value }
        #expect(try await installer.inspect(fixture.descriptor) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent(".staging").path).isEmpty)
    }

    @Test func cleanupOnlyRemovesAbandonedOwnedStages() throws {
        let fixture = ModuleFixture()
        let ownedStorage = ModuleStorage(root: fixture.root)
        let active = try ownedStorage.begin()
        defer { ownedStorage.finish(active) }
        let abandoned = fixture.root.appendingPathComponent(".staging/module-op-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        let owner = "{\"application\":\"Compositor.Modules\",\"process\":\(ProcessInfo.processInfo.processIdentifier)}"
        try Data(owner.utf8).write(to: abandoned.appendingPathComponent(".owner"))
        let unrelated = fixture.root.appendingPathComponent(".staging/user-files")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try ownedStorage.cleanAbandonedOperations()
        #expect(FileManager.default.fileExists(atPath: active.path))
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }
}
