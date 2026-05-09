import Vapor

struct RequestIDMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let incoming = request.headers.first(name: "X-Request-ID")
        let requestID = incoming ?? UUID().uuidString
        request.headers.replaceOrAdd(name: "X-Request-ID", value: requestID)
        request.logger[metadataKey: "request_id"] = .string(requestID)
        let response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: "X-Request-ID", value: requestID)
        return response
    }
}
