import Foundation
import Testing
@testable import Compositor

nonisolated final class ModuleURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let name = request.url!.lastPathComponent
        let status = name == "http-error" ? 404 : 200
        let body = ["oversized", "stream-overflow"].contains(name) ? "abcdef" : name == "bad-hash" ? "abd" : name == "short" ? "ab" : "abc"
        let headers = ["unknown", "stream-overflow", "held"].contains(name) ? [:] : ["Content-Length": name == "short" ? "3" : "\(body.utf8.count)"]
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if name == "held" { client?.urlProtocol(self, didLoad: Data("a".utf8)); return }
        for byte in body.utf8 { client?.urlProtocol(self, didLoad: Data([byte])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

nonisolated final class DownloadObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ModuleDownloadProgress] = []
    func append(_ value: ModuleDownloadProgress) { lock.withLock { values.append(value) } }
    var last: ModuleDownloadProgress? { lock.withLock { values.last } }
}

struct ModuleDownloaderTests {
    private func downloader() -> ModuleDownloader {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ModuleURLProtocol.self]
        return ModuleDownloader(configuration: config)
    }

    @Test func streamsVerifiedBytesAndReportsUnknownLength() async throws {
        let fixture = ModuleFixture(), observations = DownloadObservations()
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let destination = fixture.root.appendingPathComponent("payload")
        try await downloader().download(fixture.descriptor.assets[0], from: URL(string: "https://example.invalid/unknown")!, to: destination) { observations.append($0) }
        #expect(try Data(contentsOf: destination) == Data("abc".utf8))
        #expect(observations.last?.receivedBytes == 3)
        #expect(observations.last?.totalBytes == nil)
    }

    @Test(arguments: ["http-error", "bad-hash", "oversized", "stream-overflow", "short"])
    func rejectsUntrustedResponseAndRemovesPartialFile(_ name: String) async throws {
        let fixture = ModuleFixture()
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let destination = fixture.root.appendingPathComponent("payload")
        await #expect(throws: (any Error).self) {
            try await downloader().download(fixture.descriptor.assets[0], from: URL(string: "https://example.invalid/\(name)")!, to: destination) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func diskFailureIsReported() async throws {
        let fixture = ModuleFixture()
        try Data("file".utf8).write(to: fixture.root)
        await #expect(throws: (any Error).self) {
            try await downloader().download(fixture.descriptor.assets[0], from: URL(string: "https://example.invalid/good")!, to: fixture.root.appendingPathComponent("payload")) { _ in }
        }
    }
}

extension ModuleDownloaderTests {
    @Test func cancellationClosesAndRemovesOpenDownload() async throws {
        let fixture = ModuleFixture(), observations = DownloadObservations()
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let destination = fixture.root.appendingPathComponent("partial")
        let transfer = Task {
            try await downloader().download(fixture.descriptor.assets[0], from: URL(string: "https://example.invalid/held")!, to: destination) { observations.append($0) }
        }
        await waitForModuleCondition { FileManager.default.fileExists(atPath: destination.path) }
        #expect(FileManager.default.fileExists(atPath: destination.path))
        transfer.cancel()
        await #expect(throws: CancellationError.self) { try await transfer.value }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

extension ModuleDownloaderTests {
    @Test func installerRetainsPinnedAggregateForUnknownResponseLength() async throws {
        let fixture = ModuleFixture(), normal = fixtureCoreInstaller(fixture), observations = ModuleProgressObservations()
        // URLProtocol uses the asset name to omit Content-Length for this pinned transfer.
        let old = fixture.descriptor
        let descriptor = ModuleDescriptor(id: old.id, name: old.name, summary: old.summary, version: old.version, source: old.source,
                                          publisher: old.publisher, homepage: old.homepage, releasePage: old.releasePage, attributions: old.attributions,
                                          assets: [.init(name: "unknown", path: "Data/weight.bin", bytes: 3, sha256: old.assets[0].sha256)],
                                          capability: old.capability, packageName: old.packageName, compiledName: old.compiledName, legacyPath: nil,
                                          inputName: old.inputName, outputName: old.outputName)
        let installer = CoreMLModuleInstaller(root: normal.storage.root, legacyBase: fixture.root, transport: downloader(), compile: normal.compile, validate: normal.validate)
        _ = try await installer.install(descriptor) { observations.append($0) }
        let downloading = observations.values.filter { $0.phase == .downloading }
        #expect(!downloading.isEmpty)
        #expect(downloading.allSatisfy { $0.totalBytes == 3 })
        #expect(downloading.last?.receivedBytes == 3)
    }
}
