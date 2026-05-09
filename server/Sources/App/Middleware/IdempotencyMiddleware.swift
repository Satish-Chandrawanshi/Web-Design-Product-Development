import Fluent
import Vapor

/// Replays cached responses for repeated `(userID, Idempotency-Key)` pairs within 24h.
/// Applied at the controller level for `PUT` and `POST` endpoints that mutate state.
struct IdempotencyMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let key = request.headers.first(name: "Idempotency-Key"),
              let user = request.auth.get(AuthenticatedUser.self)
        else {
            return try await next.respond(to: request)
        }

        if let existing = try await IdempotencyKey.query(on: request.db)
            .filter(\.$id == key)
            .filter(\.$user.$id == user.id)
            .first() {
            let status = HTTPResponseStatus(statusCode: existing.responseStatus)
            let body = Response.Body(string: existing.responseBody)
            let response = Response(status: status, body: body)
            response.headers.replaceOrAdd(name: .contentType, value: "application/json")
            response.headers.replaceOrAdd(name: "X-Idempotent-Replay", value: "true")
            return response
        }

        let response = try await next.respond(to: request)

        if (200..<300).contains(Int(response.status.code)) {
            let bodyString = response.body.string ?? ""
            let row = IdempotencyKey(
                key: key,
                userID: user.id,
                responseStatus: Int(response.status.code),
                responseBody: bodyString
            )
            try await row.save(on: request.db)
        }

        return response
    }
}
