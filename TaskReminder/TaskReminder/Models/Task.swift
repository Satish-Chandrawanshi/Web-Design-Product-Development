import Foundation

struct Task: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var notes: String
    var dueDate: Date
    var isCompleted: Bool
    var reminderEnabled: Bool
    var createdAt: Date

    init(id: UUID = UUID(),
         title: String,
         notes: String = "",
         dueDate: Date = .now,
         isCompleted: Bool = false,
         reminderEnabled: Bool = true,
         createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.reminderEnabled = reminderEnabled
        self.createdAt = createdAt
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
        Task(title: "Submit status report",
             notes: "Send weekly update to management",
             dueDate: Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: .now) ?? .now,
             reminderEnabled: true),
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
