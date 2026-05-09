import Foundation
import Vapor
import JWT

/// Verifies Apple ID identity tokens against Apple's JWKS endpoint.
///
/// Caches keys for 24h with stale-while-revalidate semantics so a single brief
/// outage at appleid.apple.com cannot block sign-in.
actor AppleTokenVerifier {
    struct ApplePayload: JWTPayload {
        var iss: IssuerClaim
        var aud: AudienceClaim
        var exp: ExpirationClaim
        var iat: IssuedAtClaim
        var sub: SubjectClaim
        var nonce: String?
        var email: String?
        var emailVerified: BoolOrString?

        func verify(using algorithm: some JWTAlgorithm) async throws {
            try self.exp.verifyNotExpired()
            guard self.iss.value == "https://appleid.apple.com" else {
                throw JWTError.claimVerificationFailure(
                    failedClaim: self.iss,
                    reason: "wrong issuer"
                )
            }
        }
    }

    enum BoolOrString: Codable {
        case bool(Bool), string(String)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let b = try? c.decode(Bool.self) { self = .bool(b); return }
            if let s = try? c.decode(String.self) { self = .string(s); return }
            self = .bool(false)
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .bool(let b): try c.encode(b)
            case .string(let s): try c.encode(s)
            }
        }
    }

    private let bundleID: String
    private let client: Client
    private let logger: Logger
    private var cachedKeys: JWTKeyCollection?
    private var cachedAt: Date?
    private let ttl: TimeInterval = 24 * 60 * 60

    init(bundleID: String, client: Client, logger: Logger) {
        self.bundleID = bundleID
        self.client = client
        self.logger = logger
    }

    /// Verifies an Apple identity token and returns the verified payload.
    /// - Parameters:
    ///   - identityToken: the JWT received from `ASAuthorizationAppleIDCredential`.
    ///   - expectedNonce: SHA256 hex of the nonce the client used; the token's
    ///                    `nonce` claim must match.
    func verify(identityToken: String, expectedNonce: String) async throws -> ApplePayload {
        let keys = try await loadKeys()
        let payload = try await keys.verify(identityToken, as: ApplePayload.self)

        guard payload.aud.value.contains(bundleID) else {
            throw Abort(.unauthorized, reason: "wrong audience")
        }
        guard payload.nonce == expectedNonce else {
            throw Abort(.unauthorized, reason: "nonce mismatch")
        }
        return payload
    }

    private func loadKeys() async throws -> JWTKeyCollection {
        if let cached = cachedKeys, let at = cachedAt, Date().timeIntervalSince(at) < ttl {
            return cached
        }
        do {
            let response = try await client.get("https://appleid.apple.com/auth/keys")
            guard let body = response.body else { throw Abort(.internalServerError, reason: "no JWKS body") }
            let data = Data(buffer: body)
            let keys = JWTKeyCollection()
            try await keys.add(jwks: try JSONDecoder().decode(JWKS.self, from: data))
            self.cachedKeys = keys
            self.cachedAt = Date()
            return keys
        } catch {
            // Stale-while-revalidate: if we have an old key set, prefer it over hard failure.
            if let cached = cachedKeys {
                logger.warning("JWKS fetch failed, falling back to stale cache: \(error)")
                return cached
            }
            throw error
        }
    }
}
