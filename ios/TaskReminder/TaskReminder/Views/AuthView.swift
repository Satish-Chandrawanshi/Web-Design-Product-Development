import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "alarm.waves.left.and.right")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Task Reminder")
                    .font(.largeTitle.weight(.semibold))
                Text("Sign in to sync reminders across your devices and to receive backup pushes for your alarms.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { _ in
                Task { await auth.signInWithApple() }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .padding(.horizontal, 32)

            if case .error(let message) = auth.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
    }
}

#Preview {
    AuthView().environmentObject(AuthService())
}
