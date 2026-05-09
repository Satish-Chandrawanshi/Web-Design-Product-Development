import Fluent

struct M005_CreateScheduledPush: AsyncMigration {
    func prepare(on database: Database) async throws {
        let status = try await database.enum("scheduled_push_status")
            .case("pending")
            .case("delivered")
            .case("failed")
            .create()

        try await database.schema("scheduled_pushes")
            .id()
            .field("reminder_id", .uuid, .required, .references("reminders", "id", onDelete: .cascade))
            .field("device_id", .uuid, .required, .references("devices", "id", onDelete: .cascade))
            .field("occurrence_at", .datetime, .required)
            .field("status", status, .required, .sql(.default("pending")))
            .field("attempt", .int, .required, .sql(.default(0)))
            .field("next_attempt_at", .datetime, .required)
            .field("last_error", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("scheduled_pushes").delete()
        try await database.enum("scheduled_push_status").delete()
    }
}
