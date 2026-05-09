import Foundation

@MainActor
final class TaskViewModel: ObservableObject {
    enum SyncState: Equatable { case idle, syncing, error(String) }

    @Published private(set) var tasks: [Task]
    @Published private(set) var filteredTasks: [Task] = []
    @Published private(set) var syncState: SyncState = .idle
    @Published var sortOption: TaskSortOption = .dueDate {
        didSet { applyFilters() }
    }
    @Published var searchQuery: String = "" {
        didSet { applyFilters() }
    }

    private let store: TaskStoring

    init(store: TaskStoring = TaskStore(), initialTasks: [Task] = []) {
        self.store = store
        self.tasks = initialTasks
        if initialTasks.isEmpty {
            loadTasks()
        } else {
            applyFilters()
        }
        NotificationCenter.default.addObserver(
            forName: .syncEnginePulledRemote,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let items = notification.userInfo?["items"] as? [ReminderDTO]
            else { return }
            Swift.Task { @MainActor in self.mergeRemote(items) }
        }
    }

    /// Called once after sign-in to do a full server pull and re-schedule any
    /// future-due reminders. Local notifications survive across sessions because
    /// the OS keeps them, but we re-schedule defensively to handle reinstall.
    func bootstrapAfterLogin(accessToken: String?) async {
        syncState = .syncing
        await SyncEngine.shared.runOnce(accessToken: accessToken)
        for task in tasks where task.dueDate > Date() && task.deletedAt == nil && task.reminderEnabled {
            await NotificationManager.shared.schedule(for: task)
        }
        syncState = .idle
    }

    private func mergeRemote(_ items: [ReminderDTO]) {
        var byID: [UUID: Task] = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        for dto in items {
            let remote = dto.toTask()
            if let local = byID[remote.id] {
                let localStamp = local.serverUpdatedAt ?? .distantPast
                let remoteStamp = remote.serverUpdatedAt ?? .distantPast
                if remoteStamp >= localStamp {
                    byID[remote.id] = remote
                }
            } else {
                byID[remote.id] = remote
            }
        }
        tasks = Array(byID.values).filter { $0.deletedAt == nil }
        applyFilters()
        store.save(tasks)
    }

    func loadTasks() {
        do {
            tasks = try store.loadTasks()
        } catch {
            print("Failed to load tasks: \(error)")
            tasks = []
        }
        applyFilters()
    }

    func addTask(title: String, notes: String, dueDate: Date, reminderEnabled: Bool) {
        let newTask = Task(title: title,
                           notes: notes,
                           dueDate: dueDate,
                           reminderEnabled: reminderEnabled)
        tasks.append(newTask)
        applyFilters()
        persistChanges()

        Task {
            await NotificationManager.shared.schedule(for: newTask)
        }
    }

    func updateTask(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        applyFilters()
        persistChanges()

        Task {
            if task.isCompleted || !task.reminderEnabled {
                await NotificationManager.shared.removeNotification(for: task)
            } else {
                await NotificationManager.shared.schedule(for: task)
            }
        }
    }

    func toggleCompletion(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isCompleted.toggle()
        let updatedTask = tasks[index]
        applyFilters()
        persistChanges()

        Task {
            if updatedTask.isCompleted {
                await NotificationManager.shared.removeNotification(for: updatedTask)
            } else if updatedTask.reminderEnabled {
                await NotificationManager.shared.schedule(for: updatedTask)
            }
        }
    }

    func deleteTask(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let removed = tasks.remove(at: index)
        applyFilters()
        persistChanges()

        Task {
            await NotificationManager.shared.removeNotification(for: removed)
        }
    }

    private func persistChanges() {
        store.save(tasks)
    }

    private func applyFilters() {
        var workingTasks = tasks

        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workingTasks = workingTasks.filter { task in
                task.title.localizedCaseInsensitiveContains(searchQuery) ||
                task.notes.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        workingTasks.sort { lhs, rhs in
            switch sortOption {
            case .dueDate:
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted
                }
                return lhs.dueDate < rhs.dueDate
            case .creationDate:
                return lhs.createdAt < rhs.createdAt
            case .alphabetical:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .completion:
                if lhs.isCompleted == rhs.isCompleted {
                    return lhs.dueDate < rhs.dueDate
                }
                return !lhs.isCompleted
            }
        }

        filteredTasks = workingTasks
    }
}

extension TaskViewModel {
    static var preview: TaskViewModel {
        TaskViewModel(store: InMemoryTaskStore(tasks: Task.mock), initialTasks: Task.mock)
    }
}

enum TaskSortOption: String, CaseIterable, Identifiable {
    case dueDate
    case creationDate
    case alphabetical
    case completion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dueDate:
            return "Due Date"
        case .creationDate:
            return "Date Created"
        case .alphabetical:
            return "Alphabetical"
        case .completion:
            return "Completion"
        }
    }
}

private struct InMemoryTaskStore: TaskStoring {
    var tasks: [Task]

    func loadTasks() throws -> [Task] {
        tasks
    }

    func save(_ tasks: [Task]) {}
}
