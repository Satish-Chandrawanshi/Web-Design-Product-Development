import Foundation
import Fluent
import SQLKit
import Vapor

/// Polls Postgres every tick for reminders whose `due_at` is in the past and
/// have not yet been pushed. Uses `FOR UPDATE SKIP LOCKED` so multiple
/// worker replicas can share the load safely.
struct DueReminderPollerJob {
    let app: Application

    func runOnce() async throws {
        guard let sql = app.db as? SQLDatabase else { return }

        let dueIDs = try await sql.raw("""
            SELECT id FROM reminders
            WHERE due_at <= now()
              AND deleted_at IS NULL
              AND is_completed = false
              AND pushed_at IS NULL
            ORDER BY due_at
            LIMIT 100
            FOR UPDATE SKIP LOCKED
        """).all(decoding: ReminderID.self)

        guard !dueIDs.isEmpty else { return }
        app.logger.info("scheduler: \(dueIDs.count) reminders due")

        for row in dueIDs {
            try await app.db.transaction { tx in
                guard let reminder = try await Reminder.find(row.id, on: tx) else { return }
                let devices = try await Device.query(on: tx)
                    .filter(\.$user.$id == reminder.$owner.id)
                    .all()

                for device in devices {
                    let push = ScheduledPush(
                        reminderID: reminder.id!,
                        deviceID: device.id!,
                        occurrenceAt: reminder.dueAt,
                        nextAttemptAt: Date()
                    )
                    try await push.save(on: tx)
                }
                reminder.pushedAt = Date()
                try await reminder.save(on: tx)
            }
        }
    }

    private struct ReminderID: Decodable {
        let id: UUID
    }
}
