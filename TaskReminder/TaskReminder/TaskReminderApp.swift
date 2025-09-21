import SwiftUI

@main
struct TaskReminderApp: App {
    @StateObject private var viewModel = TaskViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .task {
                    await NotificationManager.shared.requestAuthorization()
                }
        }
    }
}
