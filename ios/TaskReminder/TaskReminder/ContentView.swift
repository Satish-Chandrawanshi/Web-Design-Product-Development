import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: TaskViewModel
    @State private var isPresentingAddTask = false
    @State private var isPresentingSortOptions = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.tasks.isEmpty {
                    EmptyStateView(action: {
                        isPresentingAddTask = true
                    })
                } else {
                    TaskListView(tasks: viewModel.filteredTasks,
                                 onToggleCompletion: viewModel.toggleCompletion,
                                 onDelete: viewModel.deleteTask,
                                 onUpdate: viewModel.updateTask)
                }
            }
            .animation(.default, value: viewModel.tasks)
            .navigationTitle("Daily Reminders")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isPresentingSortOptions = true
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("sortButton")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresentingAddTask = true
                    } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addTaskButton")
                }
            }
            .sheet(isPresented: $isPresentingAddTask) {
                AddTaskView()
                    .environmentObject(viewModel)
            }
            .confirmationDialog("Sort Tasks", isPresented: $isPresentingSortOptions, titleVisibility: .visible) {
                ForEach(TaskSortOption.allCases) { option in
                    Button(option.title) {
                        viewModel.sortOption = option
                    }
                }
            }
            .onAppear {
                viewModel.loadTasks()
            }
        }
        .searchable(text: $viewModel.searchQuery, prompt: "Search tasks")
    }
}

#Preview {
    ContentView()
        .environmentObject(TaskViewModel.preview)
}
