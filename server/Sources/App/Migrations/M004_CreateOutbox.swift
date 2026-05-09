import Fluent

struct M004_CreateOutbox: AsyncMigration {
    func prepare(on database: Database) async throws {
        let kind = try await database.enum("outbox_event_kind")
            .case("reminder_upserted")
            .case("reminder_deleted")
            .create()

        try await database.schema("outbox_events")
            .id()
            .field("kind", kind, .required)
            .field("payload", .string, .required)
            .field("created_at", .datetime)
            .field("dispatched_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("outbox_events").delete()
        try await database.enum("outbox_event_kind").delete()
    }
}
