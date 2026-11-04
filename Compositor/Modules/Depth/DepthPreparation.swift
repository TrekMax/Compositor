import Foundation

/// Per-session capability dependencies keep preview preparation independent from storage and inference.
@MainActor struct DepthPreparation {
    var isReady: () -> Bool
    var permitsPreparation: () -> Bool
    var prepareAfterAvailabilityChange: () -> Bool
    var prepare: () async -> Bool
    var prepareExisting: (() async -> Bool)?
    var revision: @Sendable () -> UInt64

    init() {
        self.init(isReady: { DepthModel.isReady },
                  permitsPreparation: { ModuleManager.shared.permitsPreparation(ModuleCatalog.depthMini.id) },
                  prepare: { await DepthModel.prepare() }, revision: { DepthModel.revision },
                  prepareAfterAvailabilityChange: {
                      let phase = ModuleManager.shared.state(for: ModuleCatalog.depthMini.id).phase
                      return phase == .installed || phase == .notInstalled
                  }, prepareExisting: { await ModuleManager.shared.prepareExisting(ModuleCatalog.depthMini.id) })
    }

    init(isReady: @escaping () -> Bool, permitsPreparation: @escaping () -> Bool,
         prepare: @escaping () async -> Bool, revision: @escaping @Sendable () -> UInt64,
         prepareAfterAvailabilityChange: @escaping () -> Bool = { true }, prepareExisting: (() async -> Bool)? = nil) {
        self.isReady = isReady
        self.permitsPreparation = permitsPreparation
        self.prepare = prepare
        self.revision = revision
        self.prepareAfterAvailabilityChange = prepareAfterAvailabilityChange
        self.prepareExisting = prepareExisting
    }
}
