import Foundation
import UIKit

/// Sends the APNs device token (received from
/// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`) to the
/// backend. Retries until success — the token is stable per-install, so
/// failure here just delays push delivery, not correctness.
struct DeviceRegistrar {
    let api: APIClient

    static let shared = DeviceRegistrar(api: APIClient())

    func register(deviceToken: Data, accessToken: String) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        struct Body: Encodable {
            let apnsToken: String
            let locale: String
            let timezone: String
            let appVersion: String
            let criticalAlertsOptIn: Bool
        }
        let body = Body(
            apnsToken: hex,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            criticalAlertsOptIn: FeatureFlags.criticalAlertsEnabled
        )

        var attempt = 0
        while attempt < 5 {
            do {
                let _: EmptyResponse = try await api.send(
                    "POST",
                    path: "/devices",
                    body: body,
                    accessToken: accessToken
                )
                return
            } catch {
                attempt += 1
                let backoff = UInt64(min(60, pow(2.0, Double(attempt))) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: backoff)
            }
        }
        print("DeviceRegistrar: gave up after 5 attempts")
    }
}
