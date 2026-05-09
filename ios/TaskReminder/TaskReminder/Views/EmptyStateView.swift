import SwiftUI

struct EmptyStateView: View {
    var action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.badge")
                .font(.system(size: 60))
                .foregroundStyle(.accent)
                .padding()
                .background(.thinMaterial, in: Circle())

            Text("No reminders yet")
                .font(.title3)
                .bold()

            Text("Tap the plus button to add your first task reminder and stay on top of your day.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button(action: action) {
                Label("Create a reminder", systemImage: "plus")
                    .padding(.horizontal, 24)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

#Preview {
    EmptyStateView(action: {})
}
