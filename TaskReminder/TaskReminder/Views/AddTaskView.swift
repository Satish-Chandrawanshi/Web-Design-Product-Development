import SwiftUI

struct AddTaskView: View {
    @EnvironmentObject private var viewModel: TaskViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var dueDate: Date = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
    @State private var reminderEnabled: Bool = true

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task details") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(false)

                    DatePicker("Remind me", selection: $dueDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])

                    Toggle("Enable reminder", isOn: $reminderEnabled)

                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if notes.isEmpty {
                                Text("Notes")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .accessibilityLabel("Notes")
                }
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.addTask(title: title,
                                          notes: notes,
                                          dueDate: dueDate,
                                          reminderEnabled: reminderEnabled)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview {
    AddTaskView()
        .environmentObject(TaskViewModel.preview)
}
