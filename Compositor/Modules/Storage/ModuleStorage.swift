import CryptoKit
import Foundation

nonisolated struct ModuleStorage: Sendable {
    let root: URL
    private static let operations = Operations()
    private final class Operations: @unchecked Sendable {
        let lock = NSLock()
        var active: Set<String> = []
    }
    private struct Owner: Codable {
        let application: String
        let process: Int32
    }
    private struct Receipt: Codable {
        let id: String
        let version: String
        let generation: String
        let compiledName: String
        let bytes: Int64
        let provenance: ModuleState.Provenance
    }

    func validate(_ descriptor: ModuleDescriptor) throws {
        for path in [descriptor.id, descriptor.version, descriptor.packageName, descriptor.compiledName] {
            guard !path.isEmpty, !path.contains("/"), path != ".", path != ".." else { throw invalidPath() }
        }
        _ = try contained(descriptor.id, in: root)
        guard !descriptor.assets.isEmpty, descriptor.source.scheme == "https" else { throw invalidPath() }
        var paths = Set<String>()
        var total: Int64 = 0
        for asset in descriptor.assets {
            _ = try contained(asset.path, in: root)
            let sum = total.addingReportingOverflow(asset.bytes)
            guard !asset.name.isEmpty, !asset.name.contains("/"), asset.name != "..",
                  asset.bytes > 0, !sum.overflow, paths.insert(asset.path).inserted,
                  asset.sha256.count == 64, asset.sha256.allSatisfy({ $0.isHexDigit }) else { throw invalidPath() }
            total = sum.partialValue
        }
        if let path = descriptor.legacyPath { _ = try contained(path, in: root) }
    }

    func contained(_ path: String, in directory: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else { throw invalidPath() }
        let base = directory.standardizedFileURL.resolvingSymlinksInPath()
        var url = base
        for part in parts {
            url = url.appendingPathComponent(String(part)).resolvingSymlinksInPath()
            guard url.path.hasPrefix(base.path + "/") else { throw invalidPath() }
        }
        return url
    }

    func begin() throws -> URL {
        let path = try contained(".staging/module-op-\(UUID().uuidString)", in: root)
        Self.operations.lock.withLock { _ = Self.operations.active.insert(path.path) }
        do {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try JSONEncoder().encode(Owner(application: "Compositor.Modules", process: ProcessInfo.processInfo.processIdentifier))
                .write(to: path.appendingPathComponent(".owner"), options: .atomic)
            return path
        } catch { finish(path); throw error }
    }

    func finish(_ operation: URL) {
        try? FileManager.default.removeItem(at: operation)
        Self.operations.lock.withLock { _ = Self.operations.active.remove(operation.path) }
    }

    func cleanAbandonedOperations() throws {
        let staging = try contained(".staging", in: root)
        guard FileManager.default.fileExists(atPath: staging.path) else { return }
        for url in try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
            guard url.lastPathComponent.hasPrefix("module-op-"),
                  UUID(uuidString: String(url.lastPathComponent.dropFirst("module-op-".count))) != nil,
                  !Self.operations.lock.withLock({ Self.operations.active.contains(url.path) }),
                  let data = try? Data(contentsOf: url.appendingPathComponent(".owner")),
                  let owner = try? JSONDecoder().decode(Owner.self, from: data), owner.application == "Compositor.Modules",
                  owner.process == ProcessInfo.processInfo.processIdentifier || (owner.process > 0 && kill(owner.process, 0) != 0 && errno == ESRCH) else { continue }
            let safe = try contained(url.lastPathComponent, in: staging)
            try FileManager.default.removeItem(at: safe)
        }
    }

    func inspect(_ descriptor: ModuleDescriptor) throws -> ModuleInstallation? {
        try validate(descriptor)
        let directory = try contained(descriptor.id, in: root)
        let receiptURL = try contained("receipt.json", in: directory)
        guard FileManager.default.fileExists(atPath: receiptURL.path) else { return nil }
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receiptURL))
        guard receipt.id == descriptor.id, receipt.version == descriptor.version,
              receipt.compiledName == descriptor.compiledName, UUID(uuidString: receipt.generation) != nil, receipt.bytes >= 0 else {
            throw ModuleState.Issue(code: .verification, message: "The installed module receipt does not match this version.")
        }
        let compiled = try contained("generations/\(receipt.generation)/\(receipt.compiledName)", in: directory)
        guard FileManager.default.fileExists(atPath: compiled.path) else {
            throw ModuleState.Issue(code: .storage, message: "The installed model is missing.")
        }
        return ModuleInstallation(compiledURL: compiled, bytes: receipt.bytes, provenance: receipt.provenance)
    }

    func publish(_ compiled: URL, descriptor: ModuleDescriptor, provenance: ModuleState.Provenance) throws -> ModuleInstallation {
        try Task.checkCancellation()
        try validate(descriptor)
        let directory = try contained(descriptor.id, in: root)
        let generation = UUID().uuidString
        let destination = try contained("generations/\(generation)", in: directory)
        let receiptURL = try contained("receipt.json", in: directory)
        let previous = try? inspect(descriptor)
        let bytes = try diskBytes(at: compiled)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            try FileManager.default.moveItem(at: compiled, to: destination.appendingPathComponent(descriptor.compiledName))
            try Task.checkCancellation()
            let receipt = Receipt(id: descriptor.id, version: descriptor.version, generation: generation,
                                  compiledName: descriptor.compiledName, bytes: bytes, provenance: provenance)
            try JSONEncoder().encode(receipt).write(to: receiptURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        if let previous { try? FileManager.default.removeItem(at: previous.compiledURL.deletingLastPathComponent()) }
        return ModuleInstallation(compiledURL: destination.appendingPathComponent(descriptor.compiledName), bytes: bytes, provenance: provenance)
    }

    func verify(_ asset: ModuleDescriptor.Asset, at url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var bytes: Int64 = 0
        while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            guard Int64(data.count) <= asset.bytes - bytes else {
                throw ModuleState.Issue(code: .verification, message: "The source asset exceeds its pinned size.")
            }
            bytes += Int64(data.count)
            hash.update(data: data)
        }
        guard bytes == asset.bytes, hash.finalize().map({ String(format: "%02x", $0) }).joined() == asset.sha256.lowercased() else {
            throw ModuleState.Issue(code: .verification, message: "The source asset failed its size or SHA-256 check.")
        }
    }

    func remove(_ descriptor: ModuleDescriptor) throws {
        try validate(descriptor)
        let directory = try contained(descriptor.id, in: root)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func diskBytes(at url: URL) throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            throw CocoaError(.fileReadUnknown)
        }
        var bytes: Int64 = 0
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
        }
        return bytes
    }

    private func invalidPath() -> ModuleState.Issue {
        ModuleState.Issue(code: .invalidDescriptor, message: "The module contains an invalid path or asset.")
    }
}
