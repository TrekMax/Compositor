import CoreGraphics
import Foundation
import Testing
@testable import Compositor

/// Explicit network/Core ML acceptance, isolated from the user's model cache and preferences.
struct ModuleIntegrationTests {
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["COMPOSITOR_MODULE_INTEGRATION"] == "1"))
    func pinnedDepthModelLifecycle() async throws {
        let fixture = ModuleFixture(), migrated = ModuleFixture()
        let descriptor = ModuleCatalog.depthMini
        let observations = ModuleProgressObservations()
        let installer = RecordingDepthInstaller(root: fixture.root, progress: observations)
        let runtime = DepthRuntime()
        let manager = ModuleManager(root: fixture.root, defaults: fixture.defaults, installer: installer,
                                    runtimes: [descriptor.id: runtime])
        #expect(await manager.prepare(descriptor.id))
        let installation = try #require(try await installer.inspect(descriptor))
        #expect(manager.state(for: descriptor.id).phase == .ready)
        #expect(installation.provenance == .verifiedDownload)
        let progress = observations.values
        #expect(progress.contains { $0.phase == .downloading && $0.receivedBytes == descriptor.downloadBytes })
        #expect(progress.contains { $0.phase == .verifying })
        #expect(progress.contains { $0.phase == .compiling })
        let image = try integrationDepthImage()
        let depth = try #require(await Task.detached { runtime.depth(for: image) }.value)
        #expect(depth.values.count == depth.width * depth.height)
        #expect(depth.values.allSatisfy { $0.isFinite && (0...1).contains($0) })
        #expect((depth.values.max() ?? 0) > (depth.values.min() ?? 0))
        Attachment.record("received=\(descriptor.downloadBytes) installed=\(installation.bytes) stages=\(progress.map { $0.phase.rawValue }) depth=\(depth.width)x\(depth.height) range=\(depth.values.min()!)...\(depth.values.max()!)", named: "depth-integration.txt")
        let before = runtime.revision
        await manager.setEnabled(false, for: descriptor.id)
        #expect(!runtime.isReady && runtime.revision != before)
        #expect(runtime.depth(for: image) == nil)
        await manager.setEnabled(true, for: descriptor.id)
        #expect(await manager.prepare(descriptor.id))
        #expect(runtime.depth(for: image) != nil)
        #expect(observations.values.count == progress.count, "reenable uses the installed model")

        // Copy only into a second fixture's legacy location; never inspect the user's old cache.
        let legacy = migrated.root.appendingPathComponent(descriptor.legacyPath!)
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: installation.compiledURL, to: legacy)
        let migratedRoot = migrated.root.appendingPathComponent("Compositor/Modules")
        let migratedRuntime = DepthRuntime()
        let migratedManager = ModuleManager(root: migratedRoot, defaults: migrated.defaults,
                                            installer: CoreMLModuleInstaller(root: migratedRoot, legacyBase: migrated.root),
                                            runtimes: [descriptor.id: migratedRuntime])
        #expect(await migratedManager.prepare(descriptor.id))
        #expect(migratedManager.state(for: descriptor.id).provenance == .migratedCompiledCache)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(migratedRuntime.depth(for: image) != nil)
        await migratedManager.uninstall(descriptor.id)
        #expect(!(await migratedManager.prepare(descriptor.id)))
        #expect(!migratedRuntime.isReady)
        await manager.uninstall(descriptor.id)
        #expect(!(await manager.prepare(descriptor.id)))
        #expect(observations.values.count == progress.count, "uninstall suppresses automatic download")
    }
}

nonisolated struct RecordingDepthInstaller: ModuleInstalling {
    let base: CoreMLModuleInstaller
    let progress: ModuleProgressObservations
    init(root: URL, progress: ModuleProgressObservations) {
        base = CoreMLModuleInstaller(root: root, legacyBase: root.appendingPathComponent("legacy"))
        self.progress = progress
    }
    func inspect(_ descriptor: ModuleDescriptor) async throws -> ModuleInstallation? { try await base.inspect(descriptor) }
    func migrate(_ descriptor: ModuleDescriptor, progress: @escaping @Sendable (ModuleProgress) async -> Void) async throws -> ModuleInstallation? {
        try await base.migrate(descriptor, progress: progress)
    }
    func install(_ descriptor: ModuleDescriptor, progress: @escaping @Sendable (ModuleProgress) async -> Void) async throws -> ModuleInstallation {
        try await base.install(descriptor) { value in self.progress.append(value); await progress(value) }
    }
    func remove(_ descriptor: ModuleDescriptor) async throws { try await base.remove(descriptor) }
}

nonisolated func integrationDepthImage() throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: 512, height: 384, bitsPerComponent: 8, bytesPerRow: 512 * 4,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    for y in 0..<384 {
        context.setFillColor(CGColor(gray: CGFloat(y) / 384, alpha: 1))
        context.fill(CGRect(x: 0, y: y, width: 512, height: 1))
    }
    context.setFillColor(CGColor(red: 0.7, green: 0.2, blue: 0.1, alpha: 1))
    context.fillEllipse(in: CGRect(x: 140, y: 60, width: 150, height: 280))
    return try #require(context.makeImage())
}
