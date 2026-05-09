import Foundation

/// Append-only operation log persisted to `sync_queue.json` in the documents
/// directory. Survives app launches; drained by `SyncEngine`.
struct SyncOp: Codable, Identifiable {
    enum Kind: String, Codable { case upsert, delete }
    let id: UUID
    let kind: Kind
    let taskID: UUID
    let snapshot: Task?
    let clientUpdatedAt: Date
    var attempts: Int

    init(kind: Kind, task: Task) {
        self.id = UUID()
        self.kind = kind
        self.taskID = task.id
        self.snapshot = (kind == .upsert) ? task : nil
        self.clientUpdatedAt = task.serverUpdatedAt ?? Date()
        self.attempts = 0
    }
}

actor SyncQueue {
    private let fileURL: URL
    private var ops: [SyncOp]

    init(filename: String = "sync_queue.json") {
        let manager = FileManager.default
        let dir = manager.urls(for: .documentDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
        self.fileURL = dir.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder.iso8601().decode([SyncOp].self, from: data) {
            self.ops = decoded
        } else {
            self.ops = []
        }
    }

    func append(_ op: SyncOp) {
        // Coalesce: if there's an existing pending op for the same taskID, replace it
        // (latest intent wins). This keeps the queue from growing unbounded for rapidly
        // edited reminders.
        ops.removeAll { $0.taskID == op.taskID && $0.kind == op.kind }
        ops.append(op)
        persist()
    }

    func snapshot() -> [SyncOp] { ops }

    func remove(ids: Set<UUID>) {
        ops.removeAll { ids.contains($0.id) }
        persist()
    }

    func bumpAttempts(for ids: Set<UUID>) {
        for index in ops.indices where ids.contains(ops[index].id) {
            ops[index].attempts += 1
        }
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder.iso8601().encode(ops)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("SyncQueue persist failed: \(error)")
        }
    }
}

extension JSONEncoder {
    static func iso8601() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static func iso8601() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
