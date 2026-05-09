import Vapor
import JWT

struct AuthenticatedUser: Authenticatable {
    let id: UUID
    let appleSub: String
}

struct AccessTokenPayload: JWTPayload {
    var sub: SubjectClaim
    var exp: ExpirationClaim
    var iat: IssuedAtClaim
    var appleSub: String

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try self.exp.verifyNotExpired()
    }
}

struct AuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let bearer = request.headers.bearerAuthorization else {
            throw Abort(.unauthorized, reason: "missing bearer token")
        }
        let payload: AccessTokenPayload
        do {
            payload = try await request.jwt.verify(bearer.token, as: AccessTokenPayload.self)
        } catch {
            throw Abort(.unauthorized, reason: "invalid token")
        }
        guard let userID = UUID(uuidString: payload.sub.value) else {
            throw Abort(.unauthorized, reason: "invalid sub")
        }
        request.auth.login(AuthenticatedUser(id: userID, appleSub: payload.appleSub))
        return try await next.respond(to: request)
    }
}

extension Request {
    func requireUser() throws -> AuthenticatedUser {
        try self.auth.require(AuthenticatedUser.self)
    }
}
