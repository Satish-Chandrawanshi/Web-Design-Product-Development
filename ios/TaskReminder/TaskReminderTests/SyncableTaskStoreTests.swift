import XCTest
@testable import TaskReminder

final class SyncableTaskStoreTests: XCTestCase {
    final class FakeStore: TaskStoring {
        var saved: [Task] = []
        func loadTasks() throws -> [Task] { saved }
        func save(_ tasks: [Task]) { saved = tasks }
    }

    func testCreatingATaskEnqueuesAnUpsert() async throws {
        let inner = FakeStore()
        let queue = SyncQueue(filename: "test_sync_queue.json")
        let store = SyncableTaskStore(inner: inner, queue: queue)
        let task = Task(title: "Test", dueDate: Date().addingTimeInterval(60))

        store.save([task])

        // Allow the inner Task { } in save() to run.
        try await Task.sleep(nanoseconds: 100_000_000)
        let ops = await queue.snapshot()
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.kind, .upsert)
        XCTAssertEqual(ops.first?.taskID, task.id)
    }

    func testDeletingATaskEnqueuesADelete() async throws {
        let inner = FakeStore()
        let queue = SyncQueue(filename: "test_sync_queue_2.json")
        let task = Task(title: "Will be deleted")
        inner.save([task])
        let store = SyncableTaskStore(inner: inner, queue: queue)

        // Force a load so SyncableTaskStore's snapshot includes the task.
        _ = try store.loadTasks()
        store.save([])

        try await Task.sleep(nanoseconds: 100_000_000)
        let ops = await queue.snapshot()
        XCTAssertTrue(ops.contains { $0.kind == .delete && $0.taskID == task.id })
    }
}
