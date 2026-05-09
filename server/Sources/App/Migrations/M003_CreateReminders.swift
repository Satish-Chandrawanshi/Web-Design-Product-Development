import Fluent
import SQLKit

struct M003_CreateReminders: AsyncMigration {
    func prepare(on database: Database) async throws {
        let reminderType = try await database.enum("reminder_type")
            .case("standard")
            .case("loud")
            .create()

        try await database.schema("reminders")
            .id()
            .field("owner_user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("title", .string, .required)
            .field("notes", .string, .required, .sql(.default("")))
            .field("due_at", .datetime, .required)
            .field("timezone", .string, .required, .sql(.default("UTC")))
            .field("recurrence_rule", .string)
            .field("reminder_type", reminderType, .required, .sql(.default("standard")))
            .field("is_completed", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .field("deleted_at", .datetime)
            .field("version", .int, .required, .sql(.default(1)))
            .field("pushed_at", .datetime)
            .create()

        if let sql = database as? SQLDatabase {
            try await sql.raw("""
                CREATE INDEX IF NOT EXISTS idx_reminders_owner_updated
                  ON reminders (owner_user_id, updated_at)
            """).run()
            try await sql.raw("""
                CREATE INDEX IF NOT EXISTS idx_reminders_due_pending
                  ON reminders (due_at)
                  WHERE deleted_at IS NULL
                    AND is_completed = false
                    AND pushed_at IS NULL
            """).run()
        }
    }

    func revert(on database: Database) async throws {
        try await database.schema("reminders").delete()
        try await database.enum("reminder_type").delete()
    }
}
