import Foundation
import Observation

@MainActor @Observable
final class ToolTipSettings {
    static let shared = ToolTipSettings()
    static let enabledKey = "toolTips.enabled"
    static let delayKey = "toolTips.delay"
    private(set) var isEnabled: Bool
    private(set) var delay: Double
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        delay = Self.validDelay(defaults.object(forKey: Self.delayKey) as? Double ?? 0.5)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        isEnabled = enabled
    }

    func setDelay(_ seconds: Double) {
        delay = Self.validDelay(seconds)
        defaults.set(delay, forKey: Self.delayKey)
    }

    private static func validDelay(_ seconds: Double) -> Double {
        seconds.isFinite ? min(3, max(0, seconds)) : 0.5
    }
}
