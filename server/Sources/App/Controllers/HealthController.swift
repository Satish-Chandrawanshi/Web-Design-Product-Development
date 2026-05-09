import Fluent
import Vapor
import Prometheus

struct HealthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("healthz", use: healthz)
        routes.get("readyz", use: readyz)
        routes.get("metrics", use: metrics)
    }

    func healthz(_ req: Request) -> HTTPStatus { .ok }

    func readyz(_ req: Request) async throws -> HTTPStatus {
        do {
            _ = try await User.query(on: req.db).count()
            return .ok
        } catch {
            throw Abort(.serviceUnavailable, reason: "db not reachable")
        }
    }

    func metrics(_ req: Request) async throws -> Response {
        let registry = PrometheusCollectorRegistry.default
        var buffer = [UInt8]()
        registry.emit(into: &buffer)
        let body = Response.Body(stringLiteral: String(decoding: buffer, as: UTF8.self))
        let resp = Response(status: .ok, body: body)
        resp.headers.replaceOrAdd(name: .contentType, value: "text/plain; version=0.0.4")
        return resp
    }
}
