import CoreML
import Foundation

nonisolated struct ModuleInstallation: Sendable {
    let compiledURL: URL
    let bytes: Int64
    let provenance: ModuleState.Provenance
}

nonisolated struct ModuleProgress: Sendable {
    let phase: ModuleState.Phase
    var receivedBytes: Int64 = 0
    var totalBytes: Int64?
}

nonisolated protocol ModuleInstalling: Sendable {
    func inspect(_ descriptor: ModuleDescriptor) async throws -> ModuleInstallation?
    func migrate(_ descriptor: ModuleDescriptor) async throws -> ModuleInstallation?
    func install(_ descriptor: ModuleDescriptor, progress: @escaping @Sendable (ModuleProgress) -> Void) async throws -> ModuleInstallation
    func remove(_ descriptor: ModuleDescriptor) async throws
}

nonisolated struct CoreMLModuleInstaller: ModuleInstalling {
    let storage: ModuleStorage
    let legacyBase: URL
    let transport: any ModuleTransport
    let compile: @Sendable (URL) async throws -> URL
    let validate: @Sendable (URL, ModuleDescriptor) async throws -> Void
    init(root: URL, legacyBase: URL? = nil, transport: any ModuleTransport = ModuleDownloader(),
         compile: @escaping @Sendable (URL) async throws -> URL = { try await MLModel.compileModel(at: $0) },
         validate: @escaping @Sendable (URL, ModuleDescriptor) async throws -> Void = CoreMLModuleInstaller.validateModel) {
        self.storage = ModuleStorage(root: root)
        self.legacyBase = legacyBase ?? root.deletingLastPathComponent().deletingLastPathComponent()
        self.transport = transport
        self.compile = compile
        self.validate = validate
    }
    @concurrent func inspect(_ descriptor: ModuleDescriptor) async throws -> ModuleInstallation? {
        try storage.validate(descriptor)
        try storage.cleanAbandonedOperations()
        guard let installation = try storage.inspect(descriptor) else { return nil }
        try await validate(installation.compiledURL, descriptor)
        try Task.checkCancellation()
        return installation
    }

    @concurrent func migrate(_ descriptor: ModuleDescriptor) async throws -> ModuleInstallation? {
        try storage.validate(descriptor)
        guard let path = descriptor.legacyPath else { return nil }
        let legacy = try storage.contained(path, in: legacyBase)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return nil }
        let operation = try storage.begin()
        defer { storage.finish(operation) }
        do {
            let copied = try storage.contained(descriptor.compiledName, in: operation)
            try FileManager.default.copyItem(at: legacy, to: copied)
            try await validate(copied, descriptor)
            try Task.checkCancellation()
            let installation = try storage.publish(copied, descriptor: descriptor, provenance: .migratedCompiledCache)
            // The original is removed only after the new receipt is durable.
            try FileManager.default.removeItem(at: legacy)
            return installation
        } catch is CancellationError { throw CancellationError() }
        catch { throw ModuleState.Issue(code: .migration, message: error.localizedDescription) }
    }

    @concurrent func install(_ descriptor: ModuleDescriptor, progress: @escaping @Sendable (ModuleProgress) -> Void) async throws -> ModuleInstallation {
        try storage.validate(descriptor)
        let operation = try storage.begin()
        defer { storage.finish(operation) }
        let package = try storage.contained(descriptor.packageName, in: operation)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        var completed: Int64 = 0
        for asset in descriptor.assets {
            try Task.checkCancellation()
            let destination = try storage.contained(asset.path, in: package)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let previous = completed
            let aggregate = descriptor.downloadBytes
            try await transport.download(asset, from: descriptor.source.appendingPathComponent(asset.name), to: destination) { value in
                progress(ModuleProgress(phase: .downloading, receivedBytes: previous + value.receivedBytes,
                                        totalBytes: value.totalBytes == nil ? nil : aggregate))
            }
            completed += asset.bytes
        }
        try Task.checkCancellation()
        progress(ModuleProgress(phase: .verifying, receivedBytes: completed, totalBytes: descriptor.downloadBytes))
        for asset in descriptor.assets {
            try Task.checkCancellation()
            try storage.verify(asset, at: storage.contained(asset.path, in: package))
        }
        progress(ModuleProgress(phase: .compiling, receivedBytes: completed, totalBytes: descriptor.downloadBytes))
        let built: URL
        do { built = try await compile(package) }
        catch { throw ModuleState.Issue(code: .compilation, message: error.localizedDescription) }
        defer { try? FileManager.default.removeItem(at: built) }
        try Task.checkCancellation()
        try await validate(built, descriptor)
        try Task.checkCancellation()
        return try storage.publish(built, descriptor: descriptor, provenance: .verifiedDownload)
    }

    @concurrent func remove(_ descriptor: ModuleDescriptor) async throws { try storage.remove(descriptor) }

    @concurrent static func validateModel(at url: URL, descriptor: ModuleDescriptor) async throws {
        let model = try MLModel(contentsOf: url)
        guard model.modelDescription.inputDescriptionsByName[descriptor.inputName]?.type == .image,
              model.modelDescription.outputDescriptionsByName[descriptor.outputName]?.type == .multiArray else {
            throw ModuleState.Issue(code: .verification, message: "The model does not provide the required image and depth interface.")
        }
    }
}
