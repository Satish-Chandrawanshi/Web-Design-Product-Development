import Foundation
import UserNotifications

/// Schedules user-facing notifications. Two paths:
///
/// - `scheduleNotification(for:)` — single time-sensitive notification with the
///   default sound. Used for `reminderType == .standard`.
/// - `scheduleLoudAlarm(for:)` — three chained notifications spaced ~32s apart,
///   each playing the longest sound the OS will allow (~30s). This is the
///   closest we can get to an alarm-clock experience without the Critical
///   Alerts entitlement; the entitlement, when granted, is enabled by flipping
///   `FeatureFlags.criticalAlertsEnabled`.
///
/// Push de-duplication: when an APNs payload arrives with `dedupeKey`, we
/// remember the key for 60s; the UN delegate suppresses the foreground
/// presentation if the local notification with the same key is already scheduled.
actor NotificationManager {
    static let shared = NotificationManager()

    private var dedupeKeysSeen: [String: Date] = [:]
    private let dedupeWindow: TimeInterval = 60

    private init() {}

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        var options: UNAuthorizationOptions = [.alert, .sound, .badge, .timeSensitive]
        if FeatureFlags.criticalAlertsEnabled {
            options.insert(.criticalAlert)
        }
        do {
            _ = try await center.requestAuthorization(options: options)
        } catch {
            print("Notification auth failed: \(error)")
        }
    }

    // MARK: - Standard

    func scheduleNotification(for task: Task) async {
        await removeNotification(for: task)
        guard task.reminderEnabled, task.dueDate > Date(), task.deletedAt == nil else { return }

        let content = baseContent(for: task)
        content.sound = .default

        let trigger = makeTrigger(at: task.dueDate)
        let request = UNNotificationRequest(
            identifier: task.id.uuidString,
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Loud alarm

    private static let chainCount = 3
    private static let chainSpacing: TimeInterval = 32

    func scheduleLoudAlarm(for task: Task) async {
        await removeNotification(for: task)
        guard task.reminderEnabled, task.dueDate > Date(), task.deletedAt == nil else { return }

        let sound: UNNotificationSound
        if FeatureFlags.criticalAlertsEnabled {
            sound = .defaultCriticalSound(withAudioVolume: 1.0)
        } else if Bundle.main.url(forResource: "alarm_long", withExtension: "caf") != nil {
            sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "alarm_long.caf"))
        } else {
            print("alarm_long.caf not bundled — see docs/sounds/README.md. Falling back to .default.")
            sound = .default
        }

        for index in 0..<Self.chainCount {
            let fireDate = task.dueDate.addingTimeInterval(Double(index) * Self.chainSpacing)
            let content = baseContent(for: task)
            content.sound = sound
            content.threadIdentifier = "alarm-\(task.id.uuidString)"
            content.userInfo["chainIndex"] = index

            let request = UNNotificationRequest(
                identifier: "\(task.id.uuidString)-\(index)",
                content: content,
                trigger: makeTrigger(at: fireDate)
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    func cancelLoudAlarm(for id: UUID) async {
        let identifiers = (0..<Self.chainCount).map { "\(id.uuidString)-\($0)" }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // MARK: - Generic

    func removeNotification(for task: Task) async {
        let center = UNUserNotificationCenter.current()
        let chainIDs = (0..<Self.chainCount).map { "\(task.id.uuidString)-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: [task.id.uuidString] + chainIDs)
        center.removeDeliveredNotifications(withIdentifiers: [task.id.uuidString] + chainIDs)
    }

    /// Schedules whichever variant matches `task.reminderType`.
    func schedule(for task: Task) async {
        switch task.reminderType {
        case .standard: await scheduleNotification(for: task)
        case .loud: await scheduleLoudAlarm(for: task)
        }
    }

    // MARK: - Push dedupe

    /// Called from `AppDelegate` when an APNs payload arrives. Returns `true`
    /// if the payload should be presented; `false` if a local notification
    /// with the same dedupeKey is already scheduled within the dedupe window.
    func shouldPresentPush(userInfo: [AnyHashable: Any]) async -> Bool {
        pruneStaleDedupes()
        guard let key = userInfo["dedupeKey"] as? String else { return true }

        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let hasMatchingLocal = pending.contains { req in
            (req.content.userInfo["dedupeKey"] as? String) == key
        }
        if hasMatchingLocal {
            return false
        }
        dedupeKeysSeen[key] = Date()
        return true
    }

    private func pruneStaleDedupes() {
        let cutoff = Date().addingTimeInterval(-dedupeWindow)
        dedupeKeysSeen = dedupeKeysSeen.filter { $0.value > cutoff }
    }

    // MARK: - Helpers

    private func baseContent(for task: Task) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = task.notes.isEmpty ? "It's almost time to complete this task." : task.notes
        content.categoryIdentifier = "TASK_REMINDER"
        content.threadIdentifier = "reminder-\(task.id.uuidString)"
        content.interruptionLevel = .timeSensitive
        let dedupeKey = "\(task.id.uuidString):\(Int(task.dueDate.timeIntervalSince1970))"
        content.userInfo["dedupeKey"] = dedupeKey
        content.userInfo["reminderId"] = task.id.uuidString
        return content
    }

    private func makeTrigger(at date: Date) -> UNCalendarNotificationTrigger {
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }
}
