import SwiftUI

struct TaskRowView: View {
    let task: Task
    let onToggleCompletion: () -> Void
    let onEdit: () -> Void

    private var statusColor: Color {
        if task.isOverdue {
            return .red
        } else if task.isDueSoon {
            return .orange
        } else {
            return .accentColor
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleCompletion) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Color.green : statusColor)
                    .font(.title3)
                    .accessibilityLabel(task.isCompleted ? "Mark as incomplete" : "Mark as complete")
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted, color: .secondary)

                HStack(spacing: 8) {
                    Label(task.dueDateDescription, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(statusColor)

                    if task.reminderEnabled {
                        Label("Reminder", systemImage: "bell.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(task.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}

#Preview {
    List {
        TaskRowView(task: Task.mock.first!, onToggleCompletion: {}, onEdit: {})
    }
    .listStyle(.insetGrouped)
}
