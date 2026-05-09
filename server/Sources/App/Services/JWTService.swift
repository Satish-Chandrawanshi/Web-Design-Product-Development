import Foundation
import Vapor
import JWT
import Crypto

/// Issues backend access tokens (15 min) and rotating opaque refresh tokens (30 days).
/// Refresh tokens are stored hashed; the raw value is only ever returned once on creation.
struct JWTService {
    let app: Application
    let accessTTL: TimeInterval = 15 * 60
    let refreshTTL: TimeInterval = 30 * 24 * 60 * 60

    func issueAccess(for user: User) async throws -> String {
        guard let id = user.id else {
            throw Abort(.internalServerError, reason: "user has no id")
        }
        let payload = AccessTokenPayload(
            sub: .init(value: id.uuidString),
            exp: .init(value: Date().addingTimeInterval(accessTTL)),
            iat: .init(value: Date()),
            appleSub: user.appleSub
        )
        return try await app.jwt.keys.sign(payload)
    }

    func issueRefresh(for user: User, db: Database, rotatedFromID: UUID? = nil) async throws -> (raw: String, model: RefreshToken) {
        guard let id = user.id else {
            throw Abort(.internalServerError, reason: "user has no id")
        }
        let raw = randomToken()
        let hash = sha256Hex(raw)
        let model = RefreshToken(
            userID: id,
            tokenHash: hash,
            expiresAt: Date().addingTimeInterval(refreshTTL),
            rotatedFromID: rotatedFromID
        )
        try await model.save(on: db)
        return (raw, model)
    }

    func validateAndRotate(refresh raw: String, db: Database) async throws -> User {
        let hash = sha256Hex(raw)
        guard let token = try await RefreshToken.query(on: db)
            .filter(\.$tokenHash == hash)
            .first()
        else {
            throw Abort(.unauthorized, reason: "invalid refresh token")
        }
        if let revokedAt = token.revokedAt, revokedAt < Date() {
            throw Abort(.unauthorized, reason: "refresh token revoked")
        }
        if token.expiresAt < Date() {
            throw Abort(.unauthorized, reason: "refresh token expired")
        }
        token.revokedAt = Date()
        try await token.save(on: db)
        guard let user = try await User.find(token.$user.id, on: db) else {
            throw Abort(.unauthorized, reason: "user gone")
        }
        return user
    }

    private func randomToken(byteLength: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteLength)
        _ = SystemRandomNumberGenerator().next()
        for i in 0..<byteLength {
            bytes[i] = UInt8.random(in: 0...255)
        }
        return Data(bytes).base64URLEncodedString()
    }

    private func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
