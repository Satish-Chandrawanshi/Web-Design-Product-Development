import Vapor
import Metrics

struct MetricsMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let start = DispatchTime.now().uptimeNanoseconds
        let response: Response
        do {
            response = try await next.respond(to: request)
        } catch {
            recordTiming(request: request, status: 500, start: start)
            throw error
        }
        recordTiming(request: request, status: Int(response.status.code), start: start)
        return response
    }

    private func recordTiming(request: Request, status: Int, start: UInt64) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        let route = request.route?.path.map { "\($0)" }.joined(separator: "/") ?? request.url.path
        Metrics.Timer(label: "http_request_duration_seconds",
                      dimensions: [("route", route), ("status", "\(status)"), ("method", request.method.string)])
            .recordSeconds(elapsed)
    }
}
