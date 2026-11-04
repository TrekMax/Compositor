import CoreGraphics
import Foundation

/// A prediction retains its provider and leases the installed files until it finishes. Invalidation is synchronous;
/// draining suspends without holding the lock, so the manager can safely remove files afterward.
nonisolated final class DepthRuntime: ModuleRuntime, @unchecked Sendable {
    typealias Loader = @Sendable (URL) async throws -> any DepthPredicting
    private let lock = NSLock()
    private let load: Loader
    private var predictor: (any DepthPredicting)?
    private var generation: UInt64 = 0
    private var cached: (image: CGImage, depth: DepthMap)?
    private var leases = 0
    private var drains: [CheckedContinuation<Void, Never>] = []

    init(load: @escaping Loader = { try CoreMLDepthPredictor(at: $0) }) { self.load = load }
    var revision: UInt64 { lock.withLock { generation } }
    var isReady: Bool { lock.withLock { predictor != nil } }

    @concurrent func activate(at url: URL) async throws {
        let before = revision
        let loaded = try await load(url)
        try lock.withLock {
            guard generation == before else { throw CancellationError() }
            predictor = loaded
            cached = nil
            generation &+= 1
        }
    }

    func invalidate() {
        lock.withLock {
            generation &+= 1
            predictor = nil
            cached = nil
        }
    }

    func unload() async {
        invalidate()
        await withCheckedContinuation { continuation in
            let waiting = lock.withLock {
                if leases == 0 { return false }
                drains.append(continuation)
                return true
            }
            if !waiting { continuation.resume() }
        }
    }

    func depth(for image: CGImage) -> DepthMap? {
        let lease: (any DepthPredicting, UInt64, DepthMap?)? = lock.withLock {
            guard let predictor else { return nil }
            leases += 1
            return (predictor, generation, cached.flatMap { $0.image === image ? $0.depth : nil })
        }
        guard let (predictor, revision, cached) = lease else { return nil }
        defer { releaseLease() }
        let made = cached ?? predictor.depth(for: image)
        return lock.withLock {
            guard generation == revision, self.predictor != nil else { return nil }
            if let made { self.cached = (image, made) }
            return made
        }
    }

    private func releaseLease() {
        let waiting: [CheckedContinuation<Void, Never>] = lock.withLock {
            leases -= 1
            guard leases == 0 else { return [] }
            let waiting = drains
            drains.removeAll()
            return waiting
        }
        for continuation in waiting { continuation.resume() }
    }
}
