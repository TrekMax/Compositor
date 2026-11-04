import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import Compositor

struct DepthModelTests {
    @Test func invalidationRejectsInFlightPredictionAndDrainsItsLease() async throws {
        let predictor = HeldDepthPredictor()
        let runtime = DepthRuntime(load: { _ in predictor })
        try await runtime.activate(at: URL(fileURLWithPath: "/unused"))
        let image = try depthFixtureImage()
        let oldRevision = runtime.revision
        let prediction = Task.detached { runtime.depth(for: image) }
        await waitForModuleCondition { predictor.isWaiting }
        #expect(predictor.isWaiting)
        runtime.invalidate()
        #expect(runtime.revision != oldRevision)
        #expect(!runtime.isReady)
        let drained = DepthTestFlag()
        let unloading = Task { await runtime.unload(); drained.set() }
        try await Task.sleep(for: .milliseconds(30))
        #expect(!drained.value, "files must remain leased while inference is running")
        predictor.release()
        #expect(await prediction.value == nil, "invalidated prediction must not be returned or cached")
        await unloading.value
        #expect(drained.value)
        #expect(runtime.depth(for: image) == nil)
    }

    @Test func invalidationDuringLoadCannotReactivateTheRuntime() async throws {
        let gate = ModuleGate()
        let runtime = DepthRuntime(load: { _ in await gate.wait(); return ConstantDepthPredictor(value: 0.25) })
        let activation = Task { try await runtime.activate(at: URL(fileURLWithPath: "/unused")) }
        await waitForModuleCondition { gate.isWaiting }
        runtime.invalidate()
        gate.release()
        do { try await activation.value; Issue.record("Invalidated loading must not activate") }
        catch { #expect(error is CancellationError) }
        #expect(!runtime.isReady)
    }

    @Test func reloadDiscardsTheOneImageCache() async throws {
        let runtime = DepthRuntime(load: { url in ConstantDepthPredictor(value: url.lastPathComponent == "first" ? 0.25 : 0.75) })
        let image = try depthFixtureImage()
        try await runtime.activate(at: URL(fileURLWithPath: "/first"))
        #expect(runtime.depth(for: image)?.values == [0.25])
        let revision = runtime.revision
        await runtime.unload()
        try await runtime.activate(at: URL(fileURLWithPath: "/second"))
        #expect(runtime.revision != revision)
        #expect(runtime.depth(for: image)?.values == [0.75])
    }

    @MainActor @Test(arguments: ["none", "cancel", "disable"])
    func repairWaitsForInferenceAndHonorsRevocation(action: String) async throws {
        let fixture = ModuleFixture()
        let installer = LeaseRepairInstaller(root: fixture.root)
        let predictor = HeldDepthPredictor()
        let runtime = DepthRuntime(load: { _ in predictor })
        let manager = ModuleManager(descriptors: [fixture.descriptor], root: fixture.root, defaults: fixture.defaults,
                                    installer: installer, runtimes: ["tiny": runtime])
        #expect(await manager.prepare("tiny"))
        let image = try depthFixtureImage()
        let prediction = Task.detached { runtime.depth(for: image) }
        await waitForModuleCondition { predictor.isWaiting }
        let revision = manager.availabilityRevision
        installer.requireRepair()
        let repairing = Task { await manager.install("tiny") }
        await waitForModuleCondition { !runtime.isReady || installer.installCount > 1 }
        #expect(!runtime.isReady)
        #expect(manager.availabilityRevision != revision)
        #expect(installer.installCount == 1, "repair must not remove leased files")
        #expect(try String(contentsOf: installer.marker, encoding: .utf8) == "1")
        var disabling: Task<Void, Never>?
        if action == "cancel" { manager.cancel("tiny") }
        if action == "disable" {
            disabling = Task { await manager.setEnabled(false, for: "tiny") }
            await waitForModuleCondition { !manager.state(for: "tiny").isEnabled }
        }
        predictor.release()
        #expect(await prediction.value == nil)
        await repairing.value
        await disabling?.value
        #expect(installer.installCount == (action == "none" ? 2 : 1))
        #expect(try String(contentsOf: installer.marker, encoding: .utf8) == (action == "none" ? "2" : "1"))
        #expect(!runtime.isReady)
    }

    @MainActor @Test func uninstallAnnouncesInvalidationBeforeItsLeaseDrains() async throws {
        let fixture = ModuleFixture()
        let installer = LeaseRepairInstaller(root: fixture.root)
        let predictor = HeldDepthPredictor()
        let runtime = DepthRuntime(load: { _ in predictor })
        let manager = ModuleManager(descriptors: [fixture.descriptor], root: fixture.root, defaults: fixture.defaults,
                                    installer: installer, runtimes: ["tiny": runtime])
        #expect(await manager.prepare("tiny"))
        let image = try depthFixtureImage()
        let prediction = Task.detached { runtime.depth(for: image) }
        await waitForModuleCondition { predictor.isWaiting }
        let revision = manager.availabilityRevision
        let removing = Task { await manager.uninstall("tiny") }
        await waitForModuleCondition { manager.state(for: "tiny").phase == .removing }
        #expect(manager.availabilityRevision != revision)
        #expect(!runtime.isReady)
        #expect(FileManager.default.fileExists(atPath: installer.marker.path))
        predictor.release()
        #expect(await prediction.value == nil)
        await removing.value
        #expect(!FileManager.default.fileExists(atPath: installer.marker.path))
    }

    @Test func preparedDepthRejectsAnEarlierGeneration() throws {
        let generation = DepthTestRevision()
        let cache = VolumetricLighting.PreparedDepth(revision: { generation.value })
        let image = try depthFixtureImage()
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let first = cache.depth(source: image, extent: extent, contrast: 0, keepsSubjectClear: true, keeps: true) {
            (CIImage.white.cropped(to: extent), [0.25])
        }
        #expect(first != nil)
        generation.advance()
        let disabled = cache.depth(source: image, extent: extent, contrast: 0, keepsSubjectClear: true, keeps: true) { nil }
        #expect(disabled == nil, "disabled generation must not reuse positive depth")
    }

    @Test func preparedDepthRejectsInvalidationDuringMake() throws {
        let generation = DepthTestRevision()
        let cache = VolumetricLighting.PreparedDepth(revision: { generation.value })
        let image = try depthFixtureImage()
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let result = cache.depth(source: image, extent: extent, contrast: 0, keepsSubjectClear: true, keeps: true) {
            generation.advance()
            return (CIImage.white.cropped(to: extent), [0.25])
        }
        #expect(result == nil)
        #expect(cache.depth(source: image, extent: extent, contrast: 0, keepsSubjectClear: true, keeps: true) { nil } == nil)
    }
}

nonisolated final class DepthTestRevision: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: UInt64 = 0
    var value: UInt64 { lock.withLock { stored } }
    func advance() { lock.withLock { stored &+= 1 } }
}
nonisolated final class DepthTestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.withLock { stored } }
    func set() { lock.withLock { stored = true } }
}
nonisolated final class HeldDepthPredictor: DepthPredicting, @unchecked Sendable {
    private let condition = NSCondition()
    private var waiting = false
    private var released = false
    var isWaiting: Bool { condition.withLock { waiting } }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
    func depth(for image: CGImage) -> DepthMap? {
        condition.lock(); waiting = true
        while !released { condition.wait() }
        condition.unlock()
        return DepthMap(values: [0, 1], width: 2, height: 1)
    }
}
nonisolated func depthFixtureImage() throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 0.5, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    return try #require(context.makeImage())
}

nonisolated struct ConstantDepthPredictor: DepthPredicting {
    let value: Float
    func depth(for image: CGImage) -> DepthMap? { DepthMap(values: [value], width: 1, height: 1) }
}

nonisolated final class LeaseRepairInstaller: ModuleInstalling, @unchecked Sendable {
    private let lock = NSLock()
    private let root: URL
    private var repair = false
    private var count = 0
    init(root: URL) { self.root = root }
    var marker: URL { root.appendingPathComponent("model/generation") }
    var installCount: Int { lock.withLock { count } }
    func requireRepair() { lock.withLock { repair = true } }
    func inspect(_ descriptor: ModuleDescriptor) async throws -> ModuleInstallation? {
        guard !lock.withLock({ repair }), FileManager.default.fileExists(atPath: marker.path) else { return nil }
        return ModuleInstallation(compiledURL: marker.deletingLastPathComponent(), bytes: 1, provenance: .verifiedDownload)
    }
    func migrate(_ descriptor: ModuleDescriptor, progress: @escaping @Sendable (ModuleProgress) async -> Void) async throws -> ModuleInstallation? { nil }
    func install(_ descriptor: ModuleDescriptor, progress: @escaping @Sendable (ModuleProgress) async -> Void) async throws -> ModuleInstallation {
        let generation = lock.withLock { count += 1; repair = false; return count }
        let model = marker.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: model.path) { try FileManager.default.removeItem(at: model) }
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data(String(generation).utf8).write(to: marker)
        return ModuleInstallation(compiledURL: model, bytes: 1, provenance: .verifiedDownload)
    }
    func remove(_ descriptor: ModuleDescriptor) async throws { try FileManager.default.removeItem(at: root) }
}
