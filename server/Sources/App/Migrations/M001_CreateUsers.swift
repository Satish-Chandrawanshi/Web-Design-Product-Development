import Fluent

struct M001_CreateUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .id()
            .field("apple_sub", .string, .required)
            .field("email", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "apple_sub")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users").delete()
    }
}
