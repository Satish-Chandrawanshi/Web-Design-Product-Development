import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

/// Sign in with Apple → backend exchange. Stores tokens in Keychain. Publishes
/// a coarse `AuthState` for the UI to gate `ContentView` behind `AuthView`.
@MainActor
final class AuthService: NSObject, ObservableObject {
    enum AuthState: Equatable {
        case signedOut
        case signedIn(userID: UUID)
        case error(String)
    }

    @Published private(set) var state: AuthState = .signedOut
    private var currentNonce: String?
    private var continuation: CheckedContinuation<UUID, Error>?
    private let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
        super.init()
        if let userIDString = Keychain.get("user_id"), let id = UUID(uuidString: userIDString) {
            state = .signedIn(userID: id)
        }
        Task { await api.setRefreshHandler { [weak self] in
            try await self?.refreshTokens()
        } }
    }

    var accessToken: String? { Keychain.get("access_token") }

    func signOut() {
        Keychain.delete("access_token")
        Keychain.delete("refresh_token")
        Keychain.delete("user_id")
        state = .signedOut
    }

    func signInWithApple() async {
        let nonce = randomNonceString()
        currentNonce = nonce
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        do {
            let userID = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UUID, Error>) in
                self.continuation = cont
                controller.performRequests()
            }
            state = .signedIn(userID: userID)
        } catch {
            state = .error("Sign in failed: \(error.localizedDescription)")
        }
    }

    private func refreshTokens() async throws {
        guard let refresh = Keychain.get("refresh_token") else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "no refresh token"])
        }
        struct Body: Encodable { let refreshToken: String }
        struct Response: Decodable {
            let accessToken: String
            let refreshToken: String
        }
        let resp: Response = try await api.send(
            "POST",
            path: "/auth/refresh",
            body: Body(refreshToken: refresh),
            accessToken: nil
        )
        Keychain.set(resp.accessToken, for: "access_token")
        Keychain.set(resp.refreshToken, for: "refresh_token")
    }

    fileprivate func exchangeAppleCredential(_ credential: ASAuthorizationAppleIDCredential, nonce: String) async throws -> UUID {
        guard let token = credential.identityToken,
              let identity = String(data: token, encoding: .utf8) else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "missing identity token"])
        }
        struct Body: Encodable { let identityToken: String; let nonce: String }
        struct Response: Decodable {
            let accessToken: String
            let refreshToken: String
            let user: UserDTO
            struct UserDTO: Decodable { let id: UUID; let appleSub: String; let email: String? }
        }
        let resp: Response = try await api.send(
            "POST",
            path: "/auth/apple",
            body: Body(identityToken: identity, nonce: sha256(nonce)),
            accessToken: nil
        )
        Keychain.set(resp.accessToken, for: "access_token")
        Keychain.set(resp.refreshToken, for: "refresh_token")
        Keychain.set(resp.user.id.uuidString, for: "user_id")
        return resp.user.id
    }

    private func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in UInt8.random(in: 0...255) }
            for r in randoms where remaining > 0 {
                if r < charset.count {
                    result.append(charset[Int(r) % charset.count])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce else {
                continuation?.resume(throwing: NSError(domain: "Auth", code: -2))
                continuation = nil
                return
            }
            do {
                let id = try await exchangeAppleCredential(credential, nonce: nonce)
                continuation?.resume(returning: id)
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Best-effort window lookup; SwiftUI scenes don't expose this directly.
        ASPresentationAnchor()
    }
}
