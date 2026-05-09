import Fluent
import Vapor

struct AuthController: RouteCollection {
    struct AppleLoginRequest: Content {
        var identityToken: String
        var nonce: String
    }

    struct LoginResponse: Content {
        var accessToken: String
        var refreshToken: String
        var user: UserDTO
    }

    struct RefreshRequest: Content {
        var refreshToken: String
    }

    struct UserDTO: Content {
        var id: UUID
        var appleSub: String
        var email: String?
    }

    func boot(routes: RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("apple", use: apple)
        auth.post("refresh", use: refresh)
    }

    func apple(_ req: Request) async throws -> LoginResponse {
        let body = try req.content.decode(AppleLoginRequest.self)
        let bundleID = req.application.apnsBundleID
        let verifier = AppleTokenVerifier(bundleID: bundleID, client: req.client, logger: req.logger)
        let payload = try await verifier.verify(identityToken: body.identityToken, expectedNonce: body.nonce)

        let appleSub = payload.sub.value
        let email = payload.email

        let user: User
        if let existing = try await User.query(on: req.db).filter(\.$appleSub == appleSub).first() {
            if let email, existing.email != email {
                existing.email = email
                try await existing.save(on: req.db)
            }
            user = existing
        } else {
            let new = User(appleSub: appleSub, email: email)
            try await new.save(on: req.db)
            user = new
        }

        let jwtService = JWTService(app: req.application)
        let access = try await jwtService.issueAccess(for: user)
        let refresh = try await jwtService.issueRefresh(for: user, db: req.db)

        return LoginResponse(
            accessToken: access,
            refreshToken: refresh.raw,
            user: UserDTO(id: user.id!, appleSub: user.appleSub, email: user.email)
        )
    }

    func refresh(_ req: Request) async throws -> LoginResponse {
        let body = try req.content.decode(RefreshRequest.self)
        let jwtService = JWTService(app: req.application)
        let user = try await jwtService.validateAndRotate(refresh: body.refreshToken, db: req.db)
        let access = try await jwtService.issueAccess(for: user)
        let refresh = try await jwtService.issueRefresh(for: user, db: req.db)
        return LoginResponse(
            accessToken: access,
            refreshToken: refresh.raw,
            user: UserDTO(id: user.id!, appleSub: user.appleSub, email: user.email)
        )
    }
}
