import Foundation
import Fluent
import Vapor

/// Owns the write path for reminders. Every mutation is wrapped in a transaction
/// that also writes an outbox row, so the API and the push pipeline cannot
/// drift out of sync (the dual-write problem).
struct ReminderService {
    let db: Database

    /// Upsert with last-writer-wins on `(updated_at, version)`.
    /// - Returns: the canonical row after the write.
    /// - Throws: `Abort(.conflict, …)` if the client's `clientUpdatedAt` is older than the stored row.
    func upsert(_ dto: ReminderDTO, ownerID: UUID, clientUpdatedAt: Date?) async throws -> Reminder {
        try await db.transaction { tx in
            let existing = try await Reminder.query(on: tx)
                .filter(\.$id == dto.id)
                .withDeleted()
                .first()

            if let existing = existing {
                if existing.$owner.id != ownerID {
                    throw Abort(.forbidden, reason: "not your reminder")
                }
                if let clientUpdatedAt, let storedUpdatedAt = existing.updatedAt, clientUpdatedAt < storedUpdatedAt {
                    throw Abort(.conflict, reason: "stale update")
                }
                existing.title = dto.title
                existing.notes = dto.notes
                existing.dueAt = dto.dueAt
                existing.timezone = dto.timezone
                existing.recurrenceRule = dto.recurrenceRule
                existing.reminderType = dto.reminderType
                existing.isCompleted = dto.isCompleted
                existing.deletedAt = dto.deletedAt
                existing.version += 1
                // Reset push state if due_at moves into the future.
                if dto.dueAt > Date() {
                    existing.pushedAt = nil
                }
                try await existing.save(on: tx)
                try await Self.enqueueOutbox(kind: .reminderUpserted, reminderID: dto.id, on: tx)
                return existing
            } else {
                let new = Reminder(
                    id: dto.id,
                    ownerID: ownerID,
                    title: dto.title,
                    notes: dto.notes,
                    dueAt: dto.dueAt,
                    timezone: dto.timezone,
                    recurrenceRule: dto.recurrenceRule,
                    reminderType: dto.reminderType,
                    isCompleted: dto.isCompleted,
                    version: 1
                )
                try await new.create(on: tx)
                try await Self.enqueueOutbox(kind: .reminderUpserted, reminderID: dto.id, on: tx)
                return new
            }
        }
    }

    func delete(id: UUID, ownerID: UUID) async throws {
        try await db.transaction { tx in
            guard let existing = try await Reminder.query(on: tx)
                .filter(\.$id == id)
                .first()
            else { return }
            if existing.$owner.id != ownerID {
                throw Abort(.forbidden, reason: "not your reminder")
            }
            // Soft-delete via Fluent's @Timestamp(on: .delete).
            try await existing.delete(on: tx)
            try await Self.enqueueOutbox(kind: .reminderDeleted, reminderID: id, on: tx)
        }
    }

    /// Returns reminders updated after `since`, including tombstones, ordered by updated_at.
    func list(ownerID: UUID, since: Date?, limit: Int = 200) async throws -> [Reminder] {
        var q = Reminder.query(on: db)
            .filter(\.$owner.$id == ownerID)
            .withDeleted()
            .sort(\.$updatedAt, .ascending)
            .limit(limit)
        if let since = since {
            q = q.filter(\.$updatedAt > since)
        }
        return try await q.all()
    }

    private static func enqueueOutbox(kind: OutboxEventKind, reminderID: UUID, on db: Database) async throws {
        let payload = #"{"reminderId":"\#(reminderID.uuidString)"}"#
        let event = OutboxEvent(kind: kind, payload: payload)
        try await event.save(on: db)
    }
}
