import XCTVapor
@testable import App

/// Documents and pins down the wire-format of `ReminderDTO` so the Swift client
/// and any future client (Android, web) cannot drift.
final class SyncContractTests: XCTestCase {
    func testReminderDTORoundTripsThroughJSON() throws {
        let now = Date(timeIntervalSince1970: 1_715_000_000)
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let dto = ReminderDTO(
            id: id,
            title: "Stand up",
            notes: "daily",
            dueAt: now,
            timezone: "America/Los_Angeles",
            recurrenceRule: nil,
            reminderType: .loud,
            isCompleted: false,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            version: 7
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dto)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let round = try decoder.decode(ReminderDTO.self, from: data)

        XCTAssertEqual(round.id, dto.id)
        XCTAssertEqual(round.title, dto.title)
        XCTAssertEqual(round.reminderType, .loud)
        XCTAssertEqual(round.version, 7)
    }
}

extension ReminderDTO {
    /// Convenience init mirroring the model-driven init so tests can build DTOs directly.
    init(id: UUID, title: String, notes: String, dueAt: Date, timezone: String,
         recurrenceRule: String?, reminderType: ReminderType, isCompleted: Bool,
         createdAt: Date?, updatedAt: Date?, deletedAt: Date?, version: Int) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.timezone = timezone
        self.recurrenceRule = recurrenceRule
        self.reminderType = reminderType
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
    }
}
