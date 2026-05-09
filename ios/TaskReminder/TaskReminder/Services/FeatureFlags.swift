import Foundation

/// Compile-time feature flags. Wire-on-the-day-Apple-approves switches.
enum FeatureFlags {
    /// `true` requires the **Critical Alerts** entitlement from Apple. Without
    /// it, requesting `.criticalAlert` authorization or using
    /// `defaultCriticalSound` is silently ignored on stock builds. Flip this
    /// flag the day Apple grants the entitlement; no other code changes
    /// required.
    static let criticalAlertsEnabled: Bool = false

    /// Base URL for the Vapor backend. Override at runtime via the
    /// `BACKEND_BASE_URL` environment variable (useful for dev / test schemes).
    static var backendBaseURL: URL {
        if let raw = ProcessInfo.processInfo.environment["BACKEND_BASE_URL"], let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://reminder-backend.fly.dev")!
    }
}
