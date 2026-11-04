import CryptoKit
import Foundation

nonisolated struct ModuleDownloadProgress: Sendable {
    let receivedBytes: Int64
    let totalBytes: Int64?
}

nonisolated protocol ModuleTransport: Sendable {
    func download(_ asset: ModuleDescriptor.Asset, from source: URL, to destination: URL,
                  progress: @escaping @Sendable (ModuleDownloadProgress) -> Void) async throws
}

nonisolated struct ModuleDownloader: ModuleTransport {
    let configuration: URLSessionConfiguration
    init(configuration: URLSessionConfiguration = .ephemeral) { self.configuration = configuration }

    func download(_ asset: ModuleDescriptor.Asset, from source: URL, to destination: URL,
                  progress: @escaping @Sendable (ModuleDownloadProgress) -> Void) async throws {
        let transfer = Transfer(asset: asset, destination: destination, progress: progress)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                transfer.start(source: source, configuration: configuration, continuation: continuation)
            }
        } onCancel: { transfer.cancel() }
    }

    /// URLSession delivers bounded chunks; only the digest and byte counters stay in memory.
    private final class Transfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let asset: ModuleDescriptor.Asset
        let destination: URL
        let progress: @Sendable (ModuleDownloadProgress) -> Void
        let lock = NSLock()
        var session: URLSession?
        var continuation: CheckedContinuation<Void, Error>?
        var handle: FileHandle?
        var hasher = SHA256()
        var received: Int64 = 0
        var total: Int64?
        var cancelled = false
        var finished = false

        init(asset: ModuleDescriptor.Asset, destination: URL, progress: @escaping @Sendable (ModuleDownloadProgress) -> Void) {
            self.asset = asset
            self.destination = destination
            self.progress = progress
        }

        func start(source: URL, configuration: URLSessionConfiguration, continuation: CheckedContinuation<Void, Error>) {
            lock.lock()
            self.continuation = continuation
            if cancelled { lock.unlock(); complete(.failure(CancellationError())); return }
            do {
                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
                handle = try FileHandle(forWritingTo: destination)
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.dataTask(with: source)
                lock.unlock()
                task.resume()
            } catch { lock.unlock(); complete(.failure(error)) }
        }

        func cancel() {
            let started = lock.withLock { cancelled = true; return continuation != nil }
            if started { complete(.failure(CancellationError())) }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                completionHandler(.cancel)
                complete(.failure(ModuleState.Issue(code: .network, message: "The module server did not return HTTP 200.")))
                return
            }
            let expected = response.expectedContentLength
            guard expected < 0 || expected == asset.bytes else {
                completionHandler(.cancel)
                complete(.failure(ModuleState.Issue(code: .verification, message: "The download size does not match the pinned asset.")))
                return
            }
            lock.withLock { total = expected >= 0 ? expected : nil }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            do {
                guard Int64(data.count) <= asset.bytes - received else {
                    throw ModuleState.Issue(code: .verification, message: "The module download exceeded its maximum size.")
                }
                try handle?.write(contentsOf: data)
                hasher.update(data: data)
                received += Int64(data.count)
                let value = ModuleDownloadProgress(receivedBytes: received, totalBytes: total)
                lock.unlock()
                progress(value)
            } catch { lock.unlock(); complete(.failure(error)) }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { complete(.failure(error)); return }
            let valid = lock.withLock {
                !finished && received == asset.bytes && hasher.finalize().map { String(format: "%02x", $0) }.joined() == asset.sha256.lowercased()
            }
            complete(valid ? .success(()) : .failure(ModuleState.Issue(code: .verification, message: "The downloaded module failed its SHA-256 check.")))
        }

        private func complete(_ result: Result<Void, Error>) {
            lock.lock()
            guard !finished, let continuation else { lock.unlock(); return }
            finished = true
            self.continuation = nil
            try? handle?.close()
            handle = nil
            let session = self.session
            self.session = nil
            if case .failure = result { try? FileManager.default.removeItem(at: destination) }
            lock.unlock()
            session?.invalidateAndCancel()
            continuation.resume(with: result)
        }
    }
}
