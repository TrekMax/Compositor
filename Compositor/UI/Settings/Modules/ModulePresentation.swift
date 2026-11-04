import Foundation

/// Presentation decisions shared by the settings page and the depth feature's feedback.
struct ModulePresentation {
    let state: ModuleState

    var canCancel: Bool {
        switch state.phase {
        case .migrating, .downloading, .verifying, .compiling, .loading: true
        default: false
        }
    }
    var canToggle: Bool { !canCancel && state.phase != .removing }
    var canInstall: Bool { canToggle && (!state.isInstalled || state.phase == .failed || state.phase == .cancelled) }
    var canUninstall: Bool { canToggle && state.isInstalled }
    var isRetry: Bool { state.phase == .failed || state.phase == .cancelled }
    var downloadFraction: Double? {
        guard state.phase == .downloading, let total = state.totalBytes, total > 0 else { return nil }
        return min(1, max(0, Double(state.receivedBytes) / Double(total)))
    }
    var downloadPercent: Int? {
        guard let fraction = downloadFraction else { return nil }
        // Rounding must not announce completion before all bytes have arrived.
        return fraction < 1 ? min(99, Int((fraction * 100).rounded())) : 100
    }

    static func installedBytes(in states: [ModuleState]) -> Int64 {
        states.filter(\.isInstalled).reduce(0) { $0 + $1.installedBytes }
    }

    static func revealURL(for root: URL) -> URL {
        var location = root
        while !FileManager.default.fileExists(atPath: location.path) {
            let parent = location.deletingLastPathComponent()
            guard parent.path != location.path else { break }
            location = parent
        }
        return location
    }

    var status: String {
        switch state.phase {
        case .notInstalled: "Not installed"
        case .migrating: "Migrating…"
        case .downloading: "Downloading…"
        case .verifying: "Verifying…"
        case .compiling: "Compiling…"
        case .installed: "Installed"
        case .loading: "Loading…"
        case .ready: "Ready"
        case .disabled: "Disabled"
        case .removing: "Uninstalling…"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
    var depthFeedback: String {
        if !state.isEnabled { return "Depth model is disabled. Volumetric Light uses estimated depth." }
        switch state.phase {
        case .ready: return "Depth model is ready."
        case .installed: return "Depth model will load when needed."
        case .migrating, .downloading, .verifying, .compiling, .loading:
            return "Preparing depth model. Estimated depth is used until it is ready."
        case .failed: return "Depth model failed. Volumetric Light uses estimated depth."
        case .cancelled: return "Depth preparation was cancelled. Download manually to try again."
        case .removing: return "Depth model is being uninstalled. Volumetric Light uses estimated depth."
        default: return "Depth model is not installed. Volumetric Light uses estimated depth."
        }
    }
    var extractionFeedback: String {
        state.phase == .ready
            ? "The depth model could not produce a depth map for this image."
            : depthFeedback
    }

    var issueTitle: String? {
        guard let issue = state.issue else { return nil }
        switch issue.code {
        case .invalidDescriptor: return "Invalid module description"
        case .network: return "Download failed"
        case .verification: return "Source verification failed"
        case .compilation: return "Model compilation failed"
        case .storage: return "Module storage failed"
        case .runtime: return "Model loading failed"
        case .migration: return "Legacy cache migration failed"
        }
    }
}
