import SwiftUI

@main
struct TaskReminderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthService()
    @StateObject private var viewModel: TaskViewModel = {
        let queue = SyncQueue()
        let store = SyncableTaskStore(queue: queue)
        return TaskViewModel(store: store)
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                switch auth.state {
                case .signedIn:
                    ContentView()
                        .environmentObject(viewModel)
                        .task {
                            await NotificationManager.shared.requestAuthorization()
                            await viewModel.bootstrapAfterLogin(accessToken: auth.accessToken)
                        }
                case .signedOut, .error:
                    AuthView()
                }
            }
            .environmentObject(auth)
        }
    }
}
