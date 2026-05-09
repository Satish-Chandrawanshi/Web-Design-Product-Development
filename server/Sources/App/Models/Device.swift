import Fluent
import Vapor

final class Device: Model, Content, @unchecked Sendable {
    static let schema = "devices"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "apns_token") var apnsToken: String
    @Field(key: "locale") var locale: String
    @Field(key: "timezone") var timezone: String
    @Field(key: "app_version") var appVersion: String
    @Field(key: "critical_alerts_opt_in") var criticalAlertsOptIn: Bool
    @Timestamp(key: "last_seen", on: .update) var lastSeen: Date?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil,
         userID: UUID,
         apnsToken: String,
         locale: String = "en",
         timezone: String = "UTC",
         appVersion: String = "1.0",
         criticalAlertsOptIn: Bool = false) {
        self.id = id
        self.$user.id = userID
        self.apnsToken = apnsToken
        self.locale = locale
        self.timezone = timezone
        self.appVersion = appVersion
        self.criticalAlertsOptIn = criticalAlertsOptIn
    }
}
