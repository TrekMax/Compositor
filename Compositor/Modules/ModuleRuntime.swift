import Foundation

nonisolated protocol ModuleRuntime: Sendable {
    func invalidate()
    func activate(at url: URL) async throws
    func unload() async
    var isReady: Bool { get }
}
