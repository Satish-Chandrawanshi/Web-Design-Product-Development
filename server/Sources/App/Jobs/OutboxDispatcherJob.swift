import Foundation
import Fluent
import Vapor
import Metrics

/// Pumps `ScheduledPush` rows whose `next_attempt_at <= now` through APNs.
/// Marks rows `delivered` on success or backs them off with exponential delay
/// + jitter on failure (max 6 attempts, then `failed`).
struct OutboxDispatcherJob {
    let app: Application

    private static let breaker = CircuitBreaker()
    private static let maxAttempts = 6

    func runOnce() async throws {
        let due = try await ScheduledPush.query(on: app.db)
            .filter(\.$status == .pending)
            .filter(\.$nextAttemptAt <= Date())
            .sort(\.$nextAttemptAt)
            .limit(200)
            .all()

        guard !due.isEmpty else { return }

        let svc = APNsService(app: app, breaker: Self.breaker)
        for push in due {
            do {
                try await push.$reminder.load(on: app.db)
                try await push.$device.load(on: app.db)
                try await svc.send(reminder: push.reminder, to: push.device, occurrenceAt: push.occurrenceAt)
                push.status = .delivered
                try await push.save(on: app.db)
                Counter(label: "notifications_dispatched_total", dimensions: [("result", "ok")]).increment()
            } catch {
                push.attempt += 1
                push.lastError = "\(error)"
                if push.attempt >= Self.maxAttempts {
                    push.status = .failed
                    Counter(label: "notifications_dispatched_total", dimensions: [("result", "fail")]).increment()
                } else {
                    push.nextAttemptAt = Self.nextDelay(after: push.attempt)
                }
                try await push.save(on: app.db)
            }
        }
    }

    /// `min(60s · 2^n + jitter, 1h)`.
    static func nextDelay(after attempt: Int) -> Date {
        let base = min(60.0 * pow(2.0, Double(attempt)), 3600.0)
        let jitter = Double.random(in: 0..<min(base * 0.25, 60))
        return Date().addingTimeInterval(base + jitter)
    }
}
