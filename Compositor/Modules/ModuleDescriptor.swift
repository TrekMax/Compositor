import CryptoKit
import Foundation

nonisolated struct ModuleDescriptor: Identifiable, Sendable {
    struct Asset: Codable, Sendable {
        let name: String
        let path: String
        let bytes: Int64
        let sha256: String
    }

    struct Attribution: Sendable {
        let name: String
        let homepage: URL
        let license: String
        let licenseURL: URL
    }

    let id: String
    let name: String
    let summary: String
    let version: String
    let source: URL
    let publisher: String
    let homepage: URL
    let releasePage: URL
    let attributions: [Attribution]
    let assets: [Asset]
    let capability: String
    let packageName: String
    let compiledName: String
    let legacyPath: String?
    let inputName: String
    let outputName: String
    var downloadBytes: Int64 { assets.reduce(0) { $0 + $1.bytes } }

    func catalogFingerprint() throws -> String {
        struct Identity: Encodable {
            let id: String
            let version: String
            let source: URL
            let assets: [Asset]
            let capability: String
            let packageName: String
            let compiledName: String
            let inputName: String
            let outputName: String
        }
        let identity = Identity(id: id, version: version, source: source, assets: assets.sorted { $0.path < $1.path },
                                capability: capability, packageName: packageName, compiledName: compiledName,
                                inputName: inputName, outputName: outputName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(identity)).map { String(format: "%02x", $0) }.joined()
    }

}
