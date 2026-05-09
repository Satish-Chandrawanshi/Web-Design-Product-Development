import Fluent
import Vapor

enum ScheduledPushStatus: String, Codable {
    case pending
    case delivered
    case failed
}

final class ScheduledPush: Model, Content, @unchecked Sendable {
    static let schema = "scheduled_pushes"

    @ID(key: .id) var id: UUID?
    @Parent(key: "reminder_id") var reminder: Reminder
    @Parent(key: "device_id") var device: Device
    @Field(key: "occurrence_at") var occurrenceAt: Date
    @Enum(key: "status") var status: ScheduledPushStatus
    @Field(key: "attempt") var attempt: Int
    @Field(key: "next_attempt_at") var nextAttemptAt: Date
    @OptionalField(key: "last_error") var lastError: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(id: UUID? = nil,
         reminderID: UUID,
         deviceID: UUID,
         occurrenceAt: Date,
         status: ScheduledPushStatus = .pending,
         attempt: Int = 0,
         nextAttemptAt: Date = .now) {
        self.id = id
        self.$reminder.id = reminderID
        self.$device.id = deviceID
        self.occurrenceAt = occurrenceAt
        self.status = status
        self.attempt = attempt
        self.nextAttemptAt = nextAttemptAt
    }
}
