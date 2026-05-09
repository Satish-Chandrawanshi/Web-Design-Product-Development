import Foundation

/// Async URLSession-based client. Three reliability features baked in:
///
/// 1. Per-request `X-Request-ID` propagation so server logs can be joined to
///    client breadcrumbs.
/// 2. Bounded retry on 5xx responses and transient `URLError`s with
///    exponential backoff (250ms, 500ms, 1s, with up to 25% jitter).
/// 3. One-shot 401 recovery: on the first 401, call the registered token
///    refresher and retry the original request once.
actor APIClient {
    struct ServerError: Error {
        let status: Int
        let body: String
    }

    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var refreshHandler: (@Sendable () async throws -> Void)?

    init(baseURL: URL = FeatureFlags.backendBaseURL,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func setRefreshHandler(_ handler: @escaping @Sendable () async throws -> Void) {
        self.refreshHandler = handler
    }

    func send<Response: Decodable>(
        _ method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Encodable? = nil,
        idempotencyKey: String? = nil,
        accessToken: String? = nil,
        as: Response.Type = Response.self
    ) async throws -> Response {
        let request = try buildRequest(
            method: method,
            path: path,
            query: query,
            body: body,
            idempotencyKey: idempotencyKey,
            accessToken: accessToken
        )

        let data = try await execute(request, allowAuthRetry: true)
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func buildRequest(method: String,
                              path: String,
                              query: [URLQueryItem],
                              body: Encodable?,
                              idempotencyKey: String?,
                              accessToken: String?) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        if let key = idempotencyKey {
            req.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }
        return req
    }

    private func execute(_ request: URLRequest, allowAuthRetry: Bool) async throws -> Data {
        let backoffs: [TimeInterval] = [0.25, 0.5, 1.0]

        for attempt in 0...backoffs.count {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if http.statusCode == 401, allowAuthRetry, let refresher = refreshHandler {
                    try await refresher()
                    return try await execute(updateAuth(of: request), allowAuthRetry: false)
                }

                if (200..<300).contains(http.statusCode) {
                    return data
                }

                if (500..<600).contains(http.statusCode), attempt < backoffs.count {
                    try await Task.sleep(nanoseconds: jitter(backoffs[attempt]))
                    continue
                }

                let body = String(data: data, encoding: .utf8) ?? ""
                throw ServerError(status: http.statusCode, body: body)
            } catch let urlError as URLError where urlError.code.isTransient && attempt < backoffs.count {
                try await Task.sleep(nanoseconds: jitter(backoffs[attempt]))
                continue
            }
        }
        throw URLError(.timedOut)
    }

    private func updateAuth(of request: URLRequest) -> URLRequest {
        guard let token = Keychain.get("access_token") else { return request }
        var req = request
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func jitter(_ seconds: TimeInterval) -> UInt64 {
        let withJitter = seconds * Double.random(in: 1.0...1.25)
        return UInt64(withJitter * 1_000_000_000)
    }
}

struct EmptyResponse: Codable {}

private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

private extension URLError.Code {
    var isTransient: Bool {
        switch self {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .dnsLookupFailed, .cannotConnectToHost, .cannotFindHost:
            return true
        default:
            return false
        }
    }
}
