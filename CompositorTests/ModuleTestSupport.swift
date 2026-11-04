import Foundation
@testable import Compositor

nonisolated final class ModuleFixture: @unchecked Sendable {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CompositorModuleTests-\(UUID().uuidString)")
    let suite = "CompositorModuleTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    var descriptor: ModuleDescriptor {
        ModuleDescriptor(id: "tiny", name: "Tiny", summary: "Fixture", version: "1", source: URL(string: "https://example.invalid/")!,
                         publisher: "Fixture", homepage: URL(string: "https://example.invalid/")!, releasePage: URL(string: "https://example.invalid/release")!, attributions: [], assets: [.init(name: "weight.bin", path: "Data/weight.bin", bytes: 3, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")],
                         capability: "depth", packageName: "Tiny.mlpackage", compiledName: "Tiny.mlmodelc", legacyPath: "Legacy/Tiny.mlmodelc", inputName: "image", outputName: "depth")
    }
    deinit {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }
}

nonisolated final class FixtureRuntime: ModuleRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false
    private var drain: CheckedContinuation<Void, Never>?
    private var hold = false
    var isReady: Bool { lock.withLock { ready } }
    var isDraining: Bool { lock.withLock { drain != nil } }
    func holdLease() { lock.withLock { hold = true } }
    func releaseLease() {
        let continuation = lock.withLock { let c = drain; drain = nil; hold = false; return c }
        continuation?.resume()
    }
    func invalidate() { lock.withLock { ready = false } }
    func activate(at url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
        lock.withLock { ready = true }
    }
    func unload() async {
        await withCheckedContinuation { continuation in
            let waiting = lock.withLock { if hold { drain = continuation; return true }; return false }
            if !waiting { continuation.resume() }
        }
    }
}

nonisolated final class FixtureInstaller: ModuleInstalling, @unchecked Sendable {
    let lock = NSLock()
    let root: URL
    var held: CheckedContinuation<Void, Never>?
    var holdNext = false
    private var holdInspect = false
    let inspection = ModuleGate()
    func holdNextInspection() { lock.withLock { holdInspect = true } }
    var isHeld: Bool { lock.withLock { held != nil } }
    init(root: URL) { self.root = root }
    func hold() { lock.withLock { holdNext = true } }
    func release() { let continuation = lock.withLock { let c = held; held = nil; return c }; continuation?.resume() }
    func inspect(_ descriptor: ModuleDescriptor) async throws -> ModuleInstallation? {
        let shouldHold = lock.withLock { let value = holdInspect; holdInspect = false; return value }
        if shouldHold { await inspection.wait() }
        let url = root.appendingPathComponent("model")
        return FileManager.default.fileExists(atPath: url.path) ? ModuleInstallation(compiledURL: url, bytes: 3, provenance: .verifiedDownload) : nil
    }
    func migrate(_ descriptor: ModuleDescriptor, progress: @escaping @Sendable (ModuleProgress) async -> Void) async throws -> ModuleInstallation? { nil }
    func install(_ descriptor: ModuleDescriptor, progress: @escaping @Sendable (ModuleProgress) async -> Void) async throws -> ModuleInstallation {
        let shouldHold = lock.withLock { let value = holdNext; holdNext = false; return value }
        if shouldHold { await withCheckedContinuation { continuation in lock.withLock { held = continuation } } }
        await progress(ModuleProgress(phase: .downloading, receivedBytes: 3, totalBytes: nil))
        try Task.checkCancellation()
        let url = root.appendingPathComponent("model")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: url.appendingPathComponent("weights"))
        return ModuleInstallation(compiledURL: url, bytes: 3, provenance: .verifiedDownload)
    }
    func remove(_ descriptor: ModuleDescriptor) async throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }
}

@MainActor func moduleManager(_ fixture: ModuleFixture, installer: any ModuleInstalling, runtime: FixtureRuntime? = nil) -> ModuleManager {
    ModuleManager(descriptors: [fixture.descriptor], root: fixture.root, defaults: fixture.defaults, installer: installer,
                  runtimes: runtime.map { ["tiny": $0] } ?? [:])
}

func waitForModuleCondition(_ condition: () async -> Bool) async {
    for _ in 0..<500 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
}

nonisolated struct FixtureTransport: ModuleTransport {
    var corrupt = false
    var payload = "abc"
    func download(_ asset: ModuleDescriptor.Asset, from source: URL, to destination: URL, progress: @escaping @Sendable (ModuleDownloadProgress) -> Void) async throws {
        if corrupt { throw ModuleState.Issue(code: .verification, message: "Wrong hash") }
        try Data(payload.utf8).write(to: destination)
        progress(ModuleDownloadProgress(receivedBytes: 3, totalBytes: 3))
    }
}

nonisolated func fixtureCoreInstaller(_ fixture: ModuleFixture, corrupt: Bool = false, invalid: Bool = false, payload: String = "abc") -> CoreMLModuleInstaller {
    CoreMLModuleInstaller(root: fixture.root.appendingPathComponent("Compositor/Modules"), legacyBase: fixture.root,
                          transport: FixtureTransport(corrupt: corrupt, payload: payload), compile: { package in
        let built = package.deletingLastPathComponent().appendingPathComponent("built.mlmodelc")
        try FileManager.default.createDirectory(at: built, withIntermediateDirectories: true)
        try Data("compiled".utf8).write(to: built.appendingPathComponent("model"))
        return built
    }, validate: { url, _ in
        guard !invalid, FileManager.default.fileExists(atPath: url.appendingPathComponent("model").path) else {
            throw ModuleState.Issue(code: .compilation, message: "Invalid model")
        }
    })
}

nonisolated final class ModuleGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { lock.withLock { continuation != nil } }
    func wait() async { await withCheckedContinuation { value in lock.withLock { continuation = value } } }
    func release() { let value = lock.withLock { let value = continuation; continuation = nil; return value }; value?.resume() }
}

nonisolated final class HeldActivationRuntime: ModuleRuntime, @unchecked Sendable {
    let gate = ModuleGate()
    private let lock = NSLock()
    private var ready = false
    var isReady: Bool { lock.withLock { ready } }
    func invalidate() { lock.withLock { ready = false } }
    func activate(at url: URL) async throws {
        await gate.wait()
        lock.withLock { ready = true }
    }
    func unload() async { lock.withLock { ready = false } }
}

nonisolated final class FailingModuleRuntime: ModuleRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false
    var isReady: Bool { lock.withLock { ready } }
    func invalidate() { lock.withLock { ready = false } }
    func unload() async { }
    func activate(at url: URL) async throws {
        lock.withLock { ready = true }
        throw CocoaError(.fileReadCorruptFile)
    }
}

nonisolated final class ModuleProgressObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ModuleProgress] = []
    func append(_ value: ModuleProgress) { lock.withLock { stored.append(value) } }
    var values: [ModuleProgress] { lock.withLock { stored } }
}

nonisolated final class ReorderedProgressInstaller: ModuleInstalling, @unchecked Sendable {
    let fixture: FixtureInstaller
    let gate = ModuleGate()
    private let lock = NSLock()
    private var callback: (@Sendable (ModuleProgress) async -> Void)?
    init(root: URL) { fixture = FixtureInstaller(root: root) }
    func inspect(_ descriptor: ModuleDescriptor) async throws -> ModuleInstallation? { try await fixture.inspect(descriptor) }
    func migrate(_ descriptor: ModuleDescriptor, progress: @escaping @Sendable (ModuleProgress) async -> Void) async throws -> ModuleInstallation? { nil }
    func install(_ descriptor: ModuleDescriptor, progress: @escaping @Sendable (ModuleProgress) async -> Void) async throws -> ModuleInstallation {
        lock.withLock { callback = progress }
        await gate.wait()
        return try await fixture.install(descriptor, progress: progress)
    }
    func emit(_ progress: ModuleProgress) async {
        let callback = lock.withLock { self.callback }
        await callback?(progress)
    }
    func remove(_ descriptor: ModuleDescriptor) async throws { try await fixture.remove(descriptor) }
}
