import Foundation

enum ReminderType: String, Codable, CaseIterable, Identifiable {
    case standard
    case loud

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .loud: return "Loud Alarm"
        }
    }
}

struct Task: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var notes: String
    var dueDate: Date
    var isCompleted: Bool
    var reminderEnabled: Bool
    var createdAt: Date

    // Sync + alarm fields. All optional / defaulted so older on-device JSON
    // continues to decode without migration.
    var reminderType: ReminderType
    var serverUpdatedAt: Date?
    var version: Int
    var pendingSync: Bool
    var deletedAt: Date?

    init(id: UUID = UUID(),
         title: String,
         notes: String = "",
         dueDate: Date = .now,
         isCompleted: Bool = false,
         reminderEnabled: Bool = true,
         createdAt: Date = .now,
         reminderType: ReminderType = .standard,
         serverUpdatedAt: Date? = nil,
         version: Int = 1,
         pendingSync: Bool = true,
         deletedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.reminderEnabled = reminderEnabled
        self.createdAt = createdAt
        self.reminderType = reminderType
        self.serverUpdatedAt = serverUpdatedAt
        self.version = version
        self.pendingSync = pendingSync
        self.deletedAt = deletedAt
    }

    // Backward-compatible decoding: any field absent in older JSON gets a default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.dueDate = try c.decode(Date.self, forKey: .dueDate)
        self.isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        self.reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? true
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        self.reminderType = try c.decodeIfPresent(ReminderType.self, forKey: .reminderType) ?? .standard
        self.serverUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .serverUpdatedAt)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.pendingSync = try c.decodeIfPresent(Bool.self, forKey: .pendingSync) ?? true
        self.deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    var isOverdue: Bool {
        !isCompleted && dueDate < Date()
    }

    var isDueSoon: Bool {
        let calendar = Calendar.current
        guard let threshold = calendar.date(byAdding: .hour, value: 2, to: Date()) else {
            return false
        }
        return dueDate <= threshold && dueDate >= Date()
    }

    var dueDateDescription: String {
        let formatter = DateFormatter.taskDueDateFormatter
        return formatter.string(from: dueDate)
    }
}

extension Task {
    static let mock: [Task] = [
        Task(title: "Stand-up meeting",
             notes: "Daily sync with the product team",
             dueDate: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now),
        Task(title: "Take medication",
             notes: "Allergy pill",
             dueDate: Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: .now) ?? .now,
             reminderEnabled: true,
             reminderType: .loud),
        Task(title: "Plan tomorrow",
             notes: "Review tomorrow's priorities",
             dueDate: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now,
             reminderEnabled: false)
    ]
}

private extension DateFormatter {
    static let taskDueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
