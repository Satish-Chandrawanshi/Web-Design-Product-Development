import XCTest
@testable import TaskReminder

final class TaskCodableTests: XCTestCase {
    /// Older builds did not write `reminderType`, `version`, etc. We must keep
    /// loading their JSON without throwing.
    func testDecodesLegacyJSONWithoutOptionalFields() throws {
        let legacy = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "title": "Legacy",
          "notes": "from v1",
          "dueDate": "2025-01-01T09:00:00Z",
          "isCompleted": false,
          "reminderEnabled": true,
          "createdAt": "2025-01-01T08:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let task = try decoder.decode(Task.self, from: legacy)

        XCTAssertEqual(task.title, "Legacy")
        XCTAssertEqual(task.reminderType, .standard)
        XCTAssertEqual(task.version, 1)
        XCTAssertNil(task.serverUpdatedAt)
        XCTAssertNil(task.deletedAt)
        XCTAssertTrue(task.pendingSync)
    }

    func testRoundTripsLoudReminder() throws {
        let task = Task(title: "Wake up", dueDate: .distantFuture, reminderType: .loud)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(task)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Task.self, from: data)

        XCTAssertEqual(decoded.reminderType, .loud)
        XCTAssertEqual(decoded.id, task.id)
    }
}
