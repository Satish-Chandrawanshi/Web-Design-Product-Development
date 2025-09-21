import Foundation
import UserNotifications

actor NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                print("User denied notification permissions")
            }
        } catch {
            print("Failed to request notification permissions: \(error)")
        }
    }

    func scheduleNotification(for task: Task) async {
        guard task.reminderEnabled, task.dueDate > Date() else {
            await removeNotification(for: task)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = task.notes.isEmpty ? "It's almost time to complete this task." : task.notes
        content.sound = .default
        content.categoryIdentifier = "TASK_REMINDER"

        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: task.dueDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(identifier: task.id.uuidString,
                                            content: content,
                                            trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }

    func removeNotification(for task: Task) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
    }
}
