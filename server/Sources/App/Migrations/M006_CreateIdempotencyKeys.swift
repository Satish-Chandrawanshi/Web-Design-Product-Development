import Fluent

struct M006_CreateIdempotencyKeys: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("idempotency_keys")
            .field("key", .string, .identifier(auto: false))
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("response_status", .int, .required)
            .field("response_body", .string, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("idempotency_keys").delete()
    }
}
