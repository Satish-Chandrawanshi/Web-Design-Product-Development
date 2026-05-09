import Vapor

public enum RunMode: String {
    case api
    case worker

    static func detect() -> RunMode {
        let raw = Environment.get("RUN_MODE")?.lowercased() ?? "api"
        return RunMode(rawValue: raw) ?? .api
    }
}

public enum Entrypoint {
    public static func run(_ app: Application) async throws {
        try await configure(app)

        switch RunMode.detect() {
        case .api:
            app.logger.info("Booting in API mode")
            try await app.execute()
        case .worker:
            app.logger.info("Booting in worker mode")
            try await Worker.run(app)
        }
    }
}
