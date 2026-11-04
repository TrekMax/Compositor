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
        let descriptor = ModuleDescriptor(id: "../outside", name: "Bad", summary: "", version: "1", source: URL(string: "https://example.invalid/")!, publisher: "Fixture", homepage: URL(string: "https://example.invalid/")!, releasePage: URL(string: "https://example.invalid/release")!, attributions: [], assets: [], capability: "depth", packageName: "a.mlpackage", compiledName: "a.mlmodelc", legacyPath: nil, inputName: "image", outputName: "depth")
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
        #expect(reopened.bytes == 11)
    }

    @Test func migrationCopiesValidatesAndRetainsHonestProvenance() async throws {
        let fixture = ModuleFixture()
        let legacy = fixture.root.appendingPathComponent("Legacy/Tiny.mlmodelc")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy.appendingPathComponent("model"))
        let installer = fixtureCoreInstaller(fixture)
        let migrated = try #require(try await installer.migrate(fixture.descriptor))
        #expect(migrated.provenance == .migratedCompiledCache)
        #expect(migrated.bytes == 3)
        #expect(!FileManager.default.fileExists(atPath: migrated.compiledURL.deletingLastPathComponent().appendingPathComponent("Tiny.mlpackage").path))
        let receipt = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: installer.storage.root.appendingPathComponent("tiny/receipt.json"))) as? [String: Any])
        #expect(receipt["packageName"] == nil)
        #expect(receipt["hasSourcePackage"] as? Bool == false)
        #expect(receipt["provenance"] as? String == "migratedCompiledCache")
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

extension ModuleStorageTests {
    @Test func catalogIncludesPublisherAndSeparateModelAttribution() {
        let descriptor = ModuleCatalog.depthMini
        #expect(descriptor.publisher == "Robbie Tilton")
        #expect(descriptor.homepage.absoluteString == "https://github.com/robbietilton/Compositor")
        #expect(descriptor.releasePage.absoluteString == "https://github.com/robbietilton/Compositor/releases/tag/depth-model-1")
        #expect(descriptor.attributions.map(\.license) == ["Apache-2.0", "BSD-3-Clause"])
        #expect(descriptor.attributions.allSatisfy { $0.homepage.scheme == "https" && $0.licenseURL.scheme == "https" })
    }

    @Test func retainedSourceReceiptIdentityAndChangedPins() async throws {
        let fixture = ModuleFixture(), installer = fixtureCoreInstaller(fixture)
        let before = Date()
        let installed = try await installer.install(fixture.descriptor) { _ in }
        let generation = installed.compiledURL.deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: generation.appendingPathComponent("Tiny.mlpackage/Data/weight.bin").path))
        #expect(installed.bytes == 11)
        let receiptURL = installer.storage.root.appendingPathComponent("tiny/receipt.json")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL)) as? [String: Any])
        #expect((object["catalogFingerprint"] as? String)?.count == 64)
        #expect(object["source"] as? String == "https://example.invalid/")
        #expect(object["packageName"] as? String == "Tiny.mlpackage")
        #expect(object["hasSourcePackage"] as? Bool == true)
        let timestamp = object["installedAt"] as? Double
        #expect(timestamp != nil)
        if let timestamp { #expect(Date(timeIntervalSinceReferenceDate: timestamp) >= before) }
        #expect(try await fixtureCoreInstaller(fixture).inspect(fixture.descriptor)?.bytes == 11)
        let old = fixture.descriptor
        let changed = ModuleDescriptor(id: old.id, name: old.name, summary: old.summary, version: old.version, source: old.source,
                                       publisher: old.publisher, homepage: old.homepage, releasePage: old.releasePage, attributions: old.attributions,
                                       assets: [.init(name: "weight.bin", path: "Data/weight.bin", bytes: 3, sha256: String(repeating: "0", count: 64))],
                                       capability: old.capability, packageName: old.packageName, compiledName: old.compiledName, legacyPath: old.legacyPath,
                                       inputName: old.inputName, outputName: old.outputName)
        await #expect(throws: (any Error).self) { try await installer.inspect(changed) }
        #expect(try await installer.inspect(old)?.compiledURL == installed.compiledURL)
    }
}
