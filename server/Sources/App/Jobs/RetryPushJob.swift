import Foundation
import Fluent
import Vapor

/// Periodic housekeeping: clean up old idempotency keys and old delivered/failed
/// pushes so the tables don't grow unbounded.
struct RetryPushJob {
    let app: Application

    private static var lastHousekeepingAt: Date?

    func runOnce() async throws {
        // Run housekeeping once per hour from any worker.
        if let last = Self.lastHousekeepingAt, Date().timeIntervalSince(last) < 3600 {
            return
        }
        Self.lastHousekeepingAt = Date()

        try await IdempotencyKey.query(on: app.db)
            .filter(\.$createdAt < Date().addingTimeInterval(-24 * 3600))
            .delete()

        try await ScheduledPush.query(on: app.db)
            .group(.or) { g in
                g.filter(\.$status == .delivered)
                g.filter(\.$status == .failed)
            }
            .filter(\.$updatedAt < Date().addingTimeInterval(-7 * 24 * 3600))
            .delete()

        try await OutboxEvent.query(on: app.db)
            .filter(\.$dispatchedAt != nil)
            .filter(\.$createdAt < Date().addingTimeInterval(-7 * 24 * 3600))
            .delete()
    }
}
