import Vapor

func routes(_ app: Application) throws {
    let health = HealthController()
    try app.register(collection: health)

    let auth = AuthController()
    try app.register(collection: auth)

    let protected = app.grouped(AuthMiddleware())

    let reminders = RemindersController()
    try protected.register(collection: reminders)

    let devices = DevicesController()
    try protected.register(collection: devices)
}
