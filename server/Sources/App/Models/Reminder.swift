import Fluent
import Vapor

enum ReminderType: String, Codable {
    case standard
    case loud
}

final class Reminder: Model, Content, @unchecked Sendable {
    static let schema = "reminders"

    @ID(key: .id) var id: UUID?
    @Parent(key: "owner_user_id") var owner: User
    @Field(key: "title") var title: String
    @Field(key: "notes") var notes: String
    @Field(key: "due_at") var dueAt: Date
    @Field(key: "timezone") var timezone: String
    @OptionalField(key: "recurrence_rule") var recurrenceRule: String?
    @Enum(key: "reminder_type") var reminderType: ReminderType
    @Field(key: "is_completed") var isCompleted: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
    @Field(key: "version") var version: Int
    @OptionalField(key: "pushed_at") var pushedAt: Date?

    init() {}

    init(id: UUID? = nil,
         ownerID: UUID,
         title: String,
         notes: String = "",
         dueAt: Date,
         timezone: String = "UTC",
         recurrenceRule: String? = nil,
         reminderType: ReminderType = .standard,
         isCompleted: Bool = false,
         version: Int = 1) {
        self.id = id
        self.$owner.id = ownerID
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.timezone = timezone
        self.recurrenceRule = recurrenceRule
        self.reminderType = reminderType
        self.isCompleted = isCompleted
        self.version = version
        self.pushedAt = nil
    }
}

struct ReminderDTO: Content {
    var id: UUID
    var title: String
    var notes: String
    var dueAt: Date
    var timezone: String
    var recurrenceRule: String?
    var reminderType: ReminderType
    var isCompleted: Bool
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?
    var version: Int

    init(_ reminder: Reminder) {
        self.id = reminder.id ?? UUID()
        self.title = reminder.title
        self.notes = reminder.notes
        self.dueAt = reminder.dueAt
        self.timezone = reminder.timezone
        self.recurrenceRule = reminder.recurrenceRule
        self.reminderType = reminder.reminderType
        self.isCompleted = reminder.isCompleted
        self.createdAt = reminder.createdAt
        self.updatedAt = reminder.updatedAt
        self.deletedAt = reminder.deletedAt
        self.version = reminder.version
    }
}
