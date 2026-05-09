import Fluent
import Vapor

enum OutboxEventKind: String, Codable {
    case reminderUpserted = "reminder_upserted"
    case reminderDeleted = "reminder_deleted"
}

final class OutboxEvent: Model, Content, @unchecked Sendable {
    static let schema = "outbox_events"

    @ID(key: .id) var id: UUID?
    @Enum(key: "kind") var kind: OutboxEventKind
    @Field(key: "payload") var payload: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @OptionalField(key: "dispatched_at") var dispatchedAt: Date?

    init() {}

    init(id: UUID? = nil, kind: OutboxEventKind, payload: String) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.dispatchedAt = nil
    }
}
