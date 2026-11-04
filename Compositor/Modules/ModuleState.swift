import Foundation

nonisolated struct ModuleState: Sendable, Equatable {
    enum Phase: String, Sendable { case notInstalled, downloading, verifying, compiling, installed, loading, ready, disabled, removing, failed, cancelled }
    enum Provenance: String, Codable, Sendable { case verifiedDownload, migratedCompiledCache }
    struct Issue: Error, Sendable, Equatable {
        enum Code: String, Sendable { case invalidDescriptor, network, verification, compilation, storage, runtime, migration }
        let code: Code
        let message: String
    }
    var phase: Phase = .notInstalled
    var isInstalled = false
    var isEnabled = true
    var receivedBytes: Int64 = 0
    var totalBytes: Int64?
    var installedBytes: Int64 = 0
    var provenance: Provenance?
    var issue: Issue?
}
