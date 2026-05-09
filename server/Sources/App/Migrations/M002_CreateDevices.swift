import Fluent

struct M002_CreateDevices: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("devices")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("apns_token", .string, .required)
            .field("locale", .string, .required, .sql(.default("en")))
            .field("timezone", .string, .required, .sql(.default("UTC")))
            .field("app_version", .string, .required, .sql(.default("1.0")))
            .field("critical_alerts_opt_in", .bool, .required, .sql(.default(false)))
            .field("last_seen", .datetime)
            .field("created_at", .datetime)
            .unique(on: "apns_token")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("devices").delete()
    }
}
