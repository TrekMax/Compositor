import Foundation
import Observation

@MainActor @Observable final class ModuleManager {
    static let shared = ModuleManager()
    nonisolated static var defaultRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Compositor/Modules", isDirectory: true)
    }

    let root: URL
    let descriptors: [ModuleDescriptor]
    private(set) var availabilityRevision: UInt64 = 0
    private var states: [String: ModuleState] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let installer: any ModuleInstalling
    @ObservationIgnored private var runtimes: [String: any ModuleRuntime]
    @ObservationIgnored private var operations: [String: Operation] = [:]
    @ObservationIgnored private var draining: [String: Task<Void, Never>] = [:]

    private struct Operation {
        let id: UUID
        let task: Task<Bool, Never>
        var activate: Bool
        let download: Bool
        var removing = false
    }

    init(descriptors: [ModuleDescriptor] = ModuleCatalog.all, root: URL = ModuleManager.defaultRoot,
         defaults: UserDefaults = .standard, installer: (any ModuleInstalling)? = nil,
         runtimes: [String: any ModuleRuntime] = [:]) {
        self.descriptors = descriptors
        self.root = root
        self.defaults = defaults
        self.installer = installer ?? CoreMLModuleInstaller(root: root)
        self.runtimes = runtimes
        for descriptor in descriptors {
            var state = ModuleState()
            state.isEnabled = !defaults.bool(forKey: Self.disabledKey(descriptor.id))
            if !state.isEnabled { state.phase = .disabled }
            states[descriptor.id] = state
        }
    }

    /// Runtime registration does not load the model. The consumer calls prepare when needed.
    func register(_ runtime: any ModuleRuntime, for id: String) {
        guard runtimes[id] == nil else { return }
        runtimes[id] = runtime
    }

    func state(for id: String) -> ModuleState { states[id] ?? ModuleState() }

    func refresh() async {
        for descriptor in descriptors where operations[descriptor.id] == nil {
            _ = await run(descriptor.id, download: false, activate: false)
        }
    }

    func prepare(_ id: String) async -> Bool {
        guard states[id]?.isEnabled == true else { return false }
        if states[id]?.phase == .ready, runtimes[id]?.isReady == true { return true }
        let mayDownload = !defaults.bool(forKey: Self.suppressedKey(id))
        return await run(id, download: mayDownload, activate: true)
    }

    func install(_ id: String) async {
        guard states[id] != nil else { return }
        defaults.set(false, forKey: Self.suppressedKey(id))
        _ = await run(id, download: true, activate: false)
    }

    func cancel(_ id: String) {
        guard states[id] != nil, operations[id]?.removing != true else { return }
        defaults.set(true, forKey: Self.suppressedKey(id))
        stop(id)
        states[id]?.phase = .cancelled
        states[id]?.issue = nil
        availabilityRevision &+= 1
    }

    func setEnabled(_ enabled: Bool, for id: String) async {
        guard states[id] != nil else { return }
        defaults.set(!enabled, forKey: Self.disabledKey(id))
        states[id]?.isEnabled = enabled
        if operations[id]?.removing == true {
            availabilityRevision &+= 1
            return
        }
        if !enabled {
            stop(id)
            states[id]?.phase = .disabled
            availabilityRevision &+= 1
            await draining[id]?.value
        } else {
            let phase: ModuleState.Phase = states[id]?.isInstalled == true ? .installed : .notInstalled
            states[id]?.phase = phase
            availabilityRevision &+= 1
        }
    }

    func uninstall(_ id: String) async {
        guard let descriptor = descriptors.first(where: { $0.id == id }) else { return }
        if let operation = operations[id], operation.removing { _ = await operation.task.value; return }
        defaults.set(true, forKey: Self.suppressedKey(id))
        stop(id)
        states[id]?.phase = .removing
        let token = UUID()
        let task = Task { [self] in
            await draining[id]?.value
            guard operations[id]?.id == token else { return false }
            do {
                try await installer.remove(descriptor)
                guard operations[id]?.id == token else { return false }
                var state = ModuleState()
                state.isEnabled = states[id]?.isEnabled ?? true
                if !state.isEnabled { state.phase = .disabled }
                states[id] = state
                availabilityRevision &+= 1
            } catch { fail(error, id: id) }
            if operations[id]?.id == token { operations[id] = nil }
            return false
        }
        operations[id] = Operation(id: token, task: task, activate: false, download: false, removing: true)
        _ = await task.value
    }

    private func run(_ id: String, download: Bool, activate: Bool) async -> Bool {
        guard let descriptor = descriptors.first(where: { $0.id == id }) else { return false }
        if var operation = operations[id] {
            if activate { operation.activate = true; operations[id] = operation }
            let result = await operation.task.value
            if download && !operation.download && !operation.removing && states[id]?.isInstalled != true {
                return await run(id, download: true, activate: activate)
            }
            return activate ? result && runtimes[id]?.isReady == true : result
        }
        let token = UUID()
        let task = Task { [self] in
            await draining[id]?.value
            guard current(id, token) else { return false }
            states[id]?.issue = nil
            do {
                try ModuleStorage(root: root).validate(descriptor)
                var installation: ModuleInstallation?
                do { installation = try await installer.inspect(descriptor) }
                catch {
                    guard download else { throw error }
                    // Explicit recovery or the next permitted prepare repairs an invalid receipt.
                }
                guard current(id, token) else { return false }
                if installation == nil {
                    do { installation = try await installer.migrate(descriptor) }
                    catch { if !download || activate { throw error } }
                }
                guard current(id, token) else { return false }
                if installation == nil, download {
                    states[id]?.phase = .downloading
                    states[id]?.receivedBytes = 0
                    states[id]?.totalBytes = nil
                    installation = try await installer.install(descriptor) { progress in
                        Task { @MainActor [self] in
                            guard self.current(id, token), [.downloading, .verifying, .compiling].contains(self.states[id]?.phase) else { return }
                            self.states[id]?.phase = progress.phase
                            self.states[id]?.receivedBytes = progress.receivedBytes
                            self.states[id]?.totalBytes = progress.totalBytes
                        }
                    }
                }
                guard current(id, token) else { return false }
                guard let installation else {
                    let phase: ModuleState.Phase = states[id]?.isEnabled == true ? .notInstalled : .disabled
                    states[id]?.phase = phase
                    operations[id] = nil
                    return false
                }
                states[id]?.isInstalled = true
                states[id]?.installedBytes = installation.bytes
                states[id]?.provenance = installation.provenance
                let phase: ModuleState.Phase = states[id]?.isEnabled == true ? (runtimes[id]?.isReady == true ? .ready : .installed) : .disabled
                states[id]?.phase = phase
                if operations[id]?.activate == true, states[id]?.isEnabled == true, let runtime = runtimes[id] {
                    states[id]?.phase = .loading
                    do { try await runtime.activate(at: installation.compiledURL) }
                    catch {
                        runtime.invalidate()
                        await runtime.unload()
                        throw ModuleState.Issue(code: .runtime, message: error.localizedDescription)
                    }
                    guard current(id, token), states[id]?.isEnabled == true else {
                        runtime.invalidate()
                        await runtime.unload()
                        return false
                    }
                    states[id]?.phase = runtime.isReady ? .ready : .installed
                }
                guard current(id, token) else { return false }
                operations[id] = nil
                availabilityRevision &+= 1
                return true
            } catch {
                guard current(id, token) else { return false }
                fail(error, id: id)
                operations[id] = nil
                return false
            }
        }
        operations[id] = Operation(id: token, task: task, activate: activate, download: download)
        let result = await task.value
        return activate ? result && runtimes[id]?.isReady == true : result
    }

    private func current(_ id: String, _ token: UUID) -> Bool {
        operations[id]?.id == token && !Task.isCancelled
    }

    private func stop(_ id: String) {
        let wasLoading = states[id]?.phase == .loading
        let operation = operations.removeValue(forKey: id)
        operation?.task.cancel()
        let runtime = runtimes[id]
        runtime?.invalidate()
        let previous = draining[id]
        // A new operation waits for late activation and inference leases to finish before reusing the runtime.
        draining[id] = Task {
            await previous?.value
            if wasLoading, let operation { _ = await operation.task.value }
            runtime?.invalidate()
            await runtime?.unload()
        }
    }

    private func fail(_ error: Error, id: String) {
        states[id]?.phase = .failed
        let code: ModuleState.Issue.Code = error is URLError ? .network : .storage
        states[id]?.issue = error as? ModuleState.Issue ?? ModuleState.Issue(code: code, message: error.localizedDescription)
        availabilityRevision &+= 1
    }

    private static func disabledKey(_ id: String) -> String { "modules.\(id).disabled" }
    private static func suppressedKey(_ id: String) -> String { "modules.\(id).suppressAutomaticFetch" }
}
