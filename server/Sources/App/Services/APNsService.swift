import Foundation
import Vapor
import APNSCore
import VaporAPNS

/// Sends APNs pushes for due reminders. Wraps `vapor/apns` with a per-device
/// circuit breaker so a single bad token does not consume retry budget.
struct APNsService {
    let app: Application
    let breaker: CircuitBreaker

    struct PushPayload: Codable {
        var reminderId: String
        var occurrenceAt: String
        var dedupeKey: String
        var reminderType: String
    }

    func send(reminder: Reminder, to device: Device, occurrenceAt: Date) async throws {
        let key = device.apnsToken
        guard await breaker.canPass(key: key) else {
            throw Abort(.serviceUnavailable, reason: "circuit open for device")
        }

        let reminderID = reminder.id?.uuidString ?? ""
        let dedupeKey = "\(reminderID):\(Int(occurrenceAt.timeIntervalSince1970))"

        let sound: APNSAlertNotificationSound
        let interruption: APNSAlertNotificationInterruptionLevel
        switch reminder.reminderType {
        case .standard:
            sound = .sound("default")
            interruption = .active
        case .loud:
            if device.criticalAlertsOptIn && (Environment.get("CRITICAL_ALERTS_ENABLED") == "true") {
                sound = .critical(name: "alarm_long.caf", volume: 1.0)
            } else {
                sound = .sound("alarm_long.caf")
            }
            interruption = .timeSensitive
        }

        let payload = PushPayload(
            reminderId: reminderID,
            occurrenceAt: ISO8601DateFormatter().string(from: occurrenceAt),
            dedupeKey: dedupeKey,
            reminderType: reminder.reminderType.rawValue
        )

        let body = reminder.notes.isEmpty ? "It's time" : reminder.notes
        let alert = APNSAlertNotification(
            alert: .init(title: .raw(reminder.title), body: .raw(body)),
            expiration: .timeIntervalSince1970InSeconds(Int(Date().addingTimeInterval(120).timeIntervalSince1970)),
            priority: .immediately,
            topic: app.apnsBundleID,
            payload: payload,
            sound: sound,
            interruptionLevel: interruption,
            apnsID: nil,
            apnsCollapseID: reminderID
        )

        do {
            _ = try await app.apns.client.sendAlertNotification(alert, deviceToken: device.apnsToken)
            await breaker.recordSuccess(key: key)
        } catch {
            await breaker.recordFailure(key: key)
            throw error
        }
    }
}
