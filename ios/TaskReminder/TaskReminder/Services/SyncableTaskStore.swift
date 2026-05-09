import Foundation

/// Decorator over the existing `TaskStoring`. Persists to the inner store
/// exactly as before so the offline experience is unchanged, and additionally
/// records a `SyncOp` per change for `SyncEngine` to drain against the server.
///
/// Note: the existing `TaskStore.save([Task])` is bulk; we don't have access
/// to per-row diffs at the call site, so we diff against the previous
/// snapshot we cached.
final class SyncableTaskStore: TaskStoring {
    private let inner: TaskStoring
    private let queue: SyncQueue
    private var lastSnapshot: [UUID: Task] = [:]
    private let snapshotLock = NSLock()

    init(inner: TaskStoring = TaskStore(), queue: SyncQueue) {
        self.inner = inner
        self.queue = queue
        if let loaded = try? inner.loadTasks() {
            for task in loaded { lastSnapshot[task.id] = task }
        }
    }

    func loadTasks() throws -> [Task] {
        let tasks = try inner.loadTasks()
        snapshotLock.lock()
        for t in tasks { lastSnapshot[t.id] = t }
        snapshotLock.unlock()
        return tasks
    }

    func save(_ tasks: [Task]) {
        let newByID: [UUID: Task] = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        snapshotLock.lock()
        let previous = lastSnapshot
        lastSnapshot = newByID
        snapshotLock.unlock()

        // Compute diff.
        let upserts: [Task] = tasks.compactMap { task in
            guard let old = previous[task.id] else { return task } // new
            return (old != task) ? task : nil
        }
        let deletedIDs = Set(previous.keys).subtracting(newByID.keys)

        inner.save(tasks)

        Task { [queue] in
            for t in upserts {
                await queue.append(SyncOp(kind: .upsert, task: t))
            }
            for id in deletedIDs {
                let stub = Task(id: id, title: "", deletedAt: Date())
                await queue.append(SyncOp(kind: .delete, task: stub))
            }
        }
    }
}
