import Fluent
import FluentPostgresDriver
import JWT
import Vapor
import VaporAPNS
import APNSCore
import Logging

public func configure(_ app: Application) async throws {
    try configureDatabase(app)
    try configureMigrations(app)
    try await configureJWT(app)
    try configureAPNs(app)
    configureMiddleware(app)
    try routes(app)
}

private func configureDatabase(_ app: Application) throws {
    if let url = Environment.get("DATABASE_URL") {
        try app.databases.use(.postgres(url: url), as: .psql)
    } else {
        app.databases.use(
            .postgres(configuration: .init(
                hostname: Environment.get("DB_HOST") ?? "localhost",
                port: Int(Environment.get("DB_PORT") ?? "5432") ?? 5432,
                username: Environment.get("DB_USER") ?? "postgres",
                password: Environment.get("DB_PASSWORD") ?? "postgres",
                database: Environment.get("DB_NAME") ?? "reminders",
                tls: .disable
            )),
            as: .psql
        )
    }
}

private func configureMigrations(_ app: Application) throws {
    app.migrations.add(M001_CreateUsers())
    app.migrations.add(M002_CreateDevices())
    app.migrations.add(M003_CreateReminders())
    app.migrations.add(M004_CreateOutbox())
    app.migrations.add(M005_CreateScheduledPush())
    app.migrations.add(M006_CreateIdempotencyKeys())
    app.migrations.add(M007_CreateRefreshTokens())

    if Environment.get("AUTO_MIGRATE")?.lowercased() == "true" {
        try app.autoMigrate().wait()
    }
}

private func configureJWT(_ app: Application) async throws {
    guard let signingKey = Environment.get("JWT_SIGNING_KEY") else {
        throw Abort(.internalServerError, reason: "JWT_SIGNING_KEY must be set")
    }
    await app.jwt.keys.add(hmac: .init(stringLiteral: signingKey), digestAlgorithm: .sha256)
}

private func configureAPNs(_ app: Application) throws {
    guard
        let keyP8 = Environment.get("APNS_KEY_P8"),
        let keyId = Environment.get("APNS_KEY_ID"),
        let teamId = Environment.get("APNS_TEAM_ID"),
        let bundleId = Environment.get("APPLE_BUNDLE_ID")
    else {
        app.logger.warning("APNs env vars missing; pushes will be no-ops in this process")
        return
    }
    let environment: APNSEnvironment = (Environment.get("APNS_USE_SANDBOX") == "true") ? .sandbox : .production
    let config = APNSClientConfiguration(
        authenticationMethod: .jwt(privateKey: try .loadFrom(string: keyP8), keyIdentifier: keyId, teamIdentifier: teamId),
        environment: environment
    )
    try app.apns.containers.use(config, eventLoopGroupProvider: .shared(app.eventLoopGroup), responseDecoder: JSONDecoder(), requestEncoder: JSONEncoder(), as: .default)
    app.storage[APNsBundleIDKey.self] = bundleId
}

private func configureMiddleware(_ app: Application) {
    app.middleware = .init()
    app.middleware.use(RequestIDMiddleware())
    app.middleware.use(MetricsMiddleware())
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))
}

struct APNsBundleIDKey: StorageKey {
    typealias Value = String
}

extension Application {
    var apnsBundleID: String {
        storage[APNsBundleIDKey.self] ?? "com.example.TaskReminder"
    }
}
