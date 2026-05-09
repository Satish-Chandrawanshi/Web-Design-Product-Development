import Fluent
import Vapor

final class IdempotencyKey: Model, Content, @unchecked Sendable {
    static let schema = "idempotency_keys"

    @ID(custom: "key", generatedBy: .user) var id: String?
    @Parent(key: "user_id") var user: User
    @Field(key: "response_status") var responseStatus: Int
    @Field(key: "response_body") var responseBody: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(key: String, userID: UUID, responseStatus: Int, responseBody: String) {
        self.id = key
        self.$user.id = userID
        self.responseStatus = responseStatus
        self.responseBody = responseBody
    }
}
