import Foundation

nonisolated struct ModuleDescriptor: Identifiable, Sendable {
    struct Asset: Sendable {
        let name: String
        let path: String
        let bytes: Int64
        let sha256: String
    }

    let id: String
    let name: String
    let summary: String
    let version: String
    let source: URL
    let assets: [Asset]
    let capability: String
    let packageName: String
    let compiledName: String
    let legacyPath: String?
    let inputName: String
    let outputName: String
    var downloadBytes: Int64 { assets.reduce(0) { $0 + $1.bytes } }
}
