import App
import Vapor

var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)
let app = Application(env)
defer { app.shutdown() }

do {
    try await Entrypoint.run(app)
} catch {
    app.logger.report(error: error)
    throw error
}
