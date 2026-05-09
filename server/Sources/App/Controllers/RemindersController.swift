import Fluent
import Vapor

struct RemindersController: RouteCollection {
    struct ListResponse: Content {
        var items: [ReminderDTO]
        var nextCursor: Date?
    }

    struct BatchRequest: Content {
        struct Op: Content {
            var op: String
            var reminder: ReminderDTO?
            var id: UUID?
            var clientUpdatedAt: Date?
        }
        var ops: [Op]
    }

    struct BatchResponse: Content {
        var applied: Int
        var conflicts: [UUID]
    }

    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("reminders").grouped(IdempotencyMiddleware())
        group.get(use: list)
        group.put(":id", use: upsert)
        group.delete(":id", use: delete)
        group.post("batch", use: batch)
    }

    func list(_ req: Request) async throws -> ListResponse {
        let user = try req.requireUser()
        let since: Date? = req.query[String.self, at: "since"].flatMap { ISO8601DateFormatter().date(from: $0) }
        let limit = min(req.query[Int.self, at: "limit"] ?? 200, 500)
        let service = ReminderService(db: req.db)
        let rows = try await service.list(ownerID: user.id, since: since, limit: limit)
        let dtos = rows.map(ReminderDTO.init)
        let nextCursor = dtos.last?.updatedAt
        return ListResponse(items: dtos, nextCursor: nextCursor)
    }

    func upsert(_ req: Request) async throws -> ReminderDTO {
        let user = try req.requireUser()
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        var dto = try req.content.decode(ReminderDTO.self)
        if dto.id != id { dto.id = id }
        let service = ReminderService(db: req.db)
        let saved = try await service.upsert(dto, ownerID: user.id, clientUpdatedAt: dto.updatedAt)
        return ReminderDTO(saved)
    }

    func delete(_ req: Request) async throws -> HTTPStatus {
        let user = try req.requireUser()
        guard let id = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest) }
        try await ReminderService(db: req.db).delete(id: id, ownerID: user.id)
        return .noContent
    }

    func batch(_ req: Request) async throws -> BatchResponse {
        let user = try req.requireUser()
        let body = try req.content.decode(BatchRequest.self)
        let service = ReminderService(db: req.db)
        var applied = 0
        var conflicts: [UUID] = []

        for op in body.ops {
            switch op.op {
            case "upsert":
                guard let dto = op.reminder else { continue }
                do {
                    _ = try await service.upsert(dto, ownerID: user.id, clientUpdatedAt: op.clientUpdatedAt)
                    applied += 1
                } catch let abort as AbortError where abort.status == .conflict {
                    conflicts.append(dto.id)
                }
            case "delete":
                guard let id = op.id else { continue }
                try await service.delete(id: id, ownerID: user.id)
                applied += 1
            default:
                req.logger.warning("unknown batch op: \(op.op)")
            }
        }
        return BatchResponse(applied: applied, conflicts: conflicts)
    }
}
