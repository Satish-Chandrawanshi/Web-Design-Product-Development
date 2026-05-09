import Fluent
import Vapor

struct DevicesController: RouteCollection {
    struct RegisterRequest: Content {
        var apnsToken: String
        var locale: String?
        var timezone: String?
        var appVersion: String?
        var criticalAlertsOptIn: Bool?
    }

    func boot(routes: RoutesBuilder) throws {
        let g = routes.grouped("devices")
        g.post(use: register)
        g.delete(":token", use: deregister)
    }

    func register(_ req: Request) async throws -> Device {
        let user = try req.requireUser()
        let body = try req.content.decode(RegisterRequest.self)
        if let existing = try await Device.query(on: req.db)
            .filter(\.$apnsToken == body.apnsToken)
            .first()
        {
            existing.$user.id = user.id
            existing.locale = body.locale ?? existing.locale
            existing.timezone = body.timezone ?? existing.timezone
            existing.appVersion = body.appVersion ?? existing.appVersion
            if let opt = body.criticalAlertsOptIn { existing.criticalAlertsOptIn = opt }
            try await existing.save(on: req.db)
            return existing
        } else {
            let device = Device(
                userID: user.id,
                apnsToken: body.apnsToken,
                locale: body.locale ?? "en",
                timezone: body.timezone ?? "UTC",
                appVersion: body.appVersion ?? "1.0",
                criticalAlertsOptIn: body.criticalAlertsOptIn ?? false
            )
            try await device.save(on: req.db)
            return device
        }
    }

    func deregister(_ req: Request) async throws -> HTTPStatus {
        let user = try req.requireUser()
        guard let token = req.parameters.get("token") else { throw Abort(.badRequest) }
        try await Device.query(on: req.db)
            .filter(\.$apnsToken == token)
            .filter(\.$user.$id == user.id)
            .delete()
        return .noContent
    }
}
