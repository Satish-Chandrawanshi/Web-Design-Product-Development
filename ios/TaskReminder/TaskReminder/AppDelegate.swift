import UIKit
import UserNotifications
import BackgroundTasks

/// Wired into SwiftUI via `@UIApplicationDelegateAdaptor` in `TaskReminderApp`.
/// Handles APNs registration, incoming pushes, push-vs-local de-duplication,
/// and background sync.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let backgroundSyncTaskID = "com.taskreminder.sync"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundSyncTaskID,
            using: nil
        ) { task in
            self.handleBackgroundSync(task: task as! BGAppRefreshTask)
        }
        scheduleNextBackgroundSync()

        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task {
            guard let access = Keychain.get("access_token") else { return }
            await DeviceRegistrar.shared.register(deviceToken: deviceToken, accessToken: access)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error)")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let shouldPresent = await NotificationManager.shared.shouldPresentPush(userInfo: userInfo)
        if !shouldPresent {
            // Local notification will fire / has fired; suppress this push.
            return .noData
        }
        // Otherwise let the system display it as usual; also kick off a sync to
        // pick up any state we might have missed.
        Task {
            if let access = Keychain.get("access_token") {
                await SyncEngine.shared.runOnce(accessToken: access)
            }
        }
        return .newData
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // We always want banner + sound; the dedupe path filters duplicates BEFORE
        // delivery, so by the time we reach this delegate we are showing it.
        return [.banner, .sound, .list]
    }

    // MARK: - Background sync

    private func handleBackgroundSync(task: BGAppRefreshTask) {
        scheduleNextBackgroundSync()
        let workItem = Task {
            if let access = Keychain.get("access_token") {
                await SyncEngine.shared.runOnce(accessToken: access)
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            workItem.cancel()
        }
    }

    private func scheduleNextBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundSyncTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
