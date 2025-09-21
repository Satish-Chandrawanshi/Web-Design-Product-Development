import SwiftUI

struct TaskListView: View {
    let tasks: [Task]
    let onToggleCompletion: (Task) -> Void
    let onDelete: (Task) -> Void
    let onUpdate: (Task) -> Void

    @State private var editingTask: Task?

    private var upcomingTasks: [Task] {
        tasks.filter { !$0.isCompleted }
    }

    private var completedTasks: [Task] {
        tasks.filter { $0.isCompleted }
    }

    var body: some View {
        List {
            taskSection(title: "Upcoming", tasks: upcomingTasks)
            taskSection(title: "Completed", tasks: completedTasks)
        }
        .listStyle(.insetGrouped)
        .sheet(item: $editingTask) { task in
            NavigationStack {
                TaskDetailView(task: task, isNewTask: false) { updatedTask in
                    onUpdate(updatedTask)
                    editingTask = nil
                }
            }
        }
    }

    private func taskSection(title: String, tasks: [Task]) -> some View {
        Group {
            if !tasks.isEmpty {
                Section(title) {
                    ForEach(tasks) { task in
                        TaskRowView(task: task,
                                    onToggleCompletion: {
                                        onToggleCompletion(task)
                                    },
                                    onEdit: {
                                        editingTask = task
                                    })
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onDelete(task)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TaskListView(tasks: Task.mock,
                     onToggleCompletion: { _ in },
                     onDelete: { _ in },
                     onUpdate: { _ in })
    }
}
