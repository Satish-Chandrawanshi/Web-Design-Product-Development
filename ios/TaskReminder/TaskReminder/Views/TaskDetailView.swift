import SwiftUI

struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draftTask: Task
    let isNewTask: Bool
    let onSave: (Task) -> Void

    init(task: Task, isNewTask: Bool, onSave: @escaping (Task) -> Void) {
        _draftTask = State(initialValue: task)
        self.isNewTask = isNewTask
        self.onSave = onSave
    }

    private var canSave: Bool {
        !draftTask.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Task details") {
                TextField("Title", text: $draftTask.title)
                    .textInputAutocapitalization(.sentences)

                DatePicker("Remind me", selection: $draftTask.dueDate, displayedComponents: [.date, .hourAndMinute])

                Toggle("Enable reminder", isOn: $draftTask.reminderEnabled)
            }

            Section("Notes") {
                TextEditor(text: $draftTask.notes)
                    .frame(minHeight: 140)
            }

            Section("Status") {
                Toggle("Mark as complete", isOn: $draftTask.isCompleted)
            }
        }
        .navigationTitle(isNewTask ? "New Reminder" : "Task Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", role: .cancel) { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(draftTask)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}

#Preview {
    NavigationStack {
        TaskDetailView(task: Task.mock.first!, isNewTask: false, onSave: { _ in })
    }
}
