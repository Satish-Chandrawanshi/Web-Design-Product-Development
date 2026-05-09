import Foundation

/// Drains the local `SyncQueue` against the server and pulls remote changes in
/// the same pass.
///
/// Triggered:
/// - on app foreground / sign-in (`runOnce`)
/// - after each local save (best-effort)
/// - from `BGAppRefreshTask` (opportunistic)
///
/// Failed pushes stay in the queue with bumped `attempts`; we never block UI.
actor SyncEngine {
    static let shared = SyncEngine()

    private let api: APIClient
    private let queue: SyncQueue
    private var inFlight = false

    init(api: APIClient = APIClient(), queue: SyncQueue = SyncQueue()) {
        self.api = api
        self.queue = queue
    }

    func runOnce(accessToken: String?) async {
        guard let accessToken else { return }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        await pushPendingOps(accessToken: accessToken)
        await pullRemote(accessToken: accessToken)
    }

    private func pushPendingOps(accessToken: String) async {
        let ops = await queue.snapshot()
        guard !ops.isEmpty else { return }

        struct BatchOp: Encodable {
            let op: String
            let reminder: ReminderDTO?
            let id: UUID?
            let clientUpdatedAt: Date?
        }
        struct Body: Encodable {
            let ops: [BatchOp]
        }
        struct Response: Decodable {
            let applied: Int
            let conflicts: [UUID]
        }

        let payloadOps: [BatchOp] = ops.map { op in
            switch op.kind {
            case .upsert:
                guard let snap = op.snapshot else {
                    return BatchOp(op: "delete", reminder: nil, id: op.taskID, clientUpdatedAt: op.clientUpdatedAt)
                }
                return BatchOp(
                    op: "upsert",
                    reminder: ReminderDTO(from: snap),
                    id: snap.id,
                    clientUpdatedAt: op.clientUpdatedAt
                )
            case .delete:
                return BatchOp(op: "delete", reminder: nil, id: op.taskID, clientUpdatedAt: op.clientUpdatedAt)
            }
        }

        do {
            let resp: Response = try await api.send(
                "POST",
                path: "/reminders/batch",
                body: Body(ops: payloadOps),
                idempotencyKey: UUID().uuidString,
                accessToken: accessToken
            )
            // Conflicts will be reconciled by the next pull. Drop everything we sent.
            await queue.remove(ids: Set(ops.map(\.id)))
            print("Sync push: \(resp.applied) applied, \(resp.conflicts.count) conflicts")
        } catch {
            await queue.bumpAttempts(for: Set(ops.map(\.id)))
            print("Sync push failed: \(error)")
        }
    }

    private func pullRemote(accessToken: String) async {
        struct ListResponse: Decodable {
            let items: [ReminderDTO]
            let nextCursor: Date?
        }

        let cursorString = UserDefaults.standard.string(forKey: "syncCursor")
        let query: [URLQueryItem] = cursorString.map { [URLQueryItem(name: "since", value: $0)] } ?? []

        do {
            let resp: ListResponse = try await api.send(
                "GET",
                path: "/reminders",
                query: query,
                accessToken: accessToken
            )
            // Hand off to the model: SyncEngine is intentionally model-store-agnostic;
            // observers post a notification that TaskViewModel listens for.
            NotificationCenter.default.post(
                name: .syncEnginePulledRemote,
                object: nil,
                userInfo: ["items": resp.items]
            )
            if let cursor = resp.nextCursor {
                UserDefaults.standard.set(ISO8601DateFormatter().string(from: cursor), forKey: "syncCursor")
            }
        } catch {
            print("Sync pull failed: \(error)")
        }
    }
}

extension Notification.Name {
    static let syncEnginePulledRemote = Notification.Name("SyncEnginePulledRemote")
}

/// DTO mirroring the server's wire format. Kept identical so the contract is
/// trivially auditable.
struct ReminderDTO: Codable {
    var id: UUID
    var title: String
    var notes: String
    var dueAt: Date
    var timezone: String
    var recurrenceRule: String?
    var reminderType: ReminderType
    var isCompleted: Bool
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?
    var version: Int

    init(from task: Task) {
        self.id = task.id
        self.title = task.title
        self.notes = task.notes
        self.dueAt = task.dueDate
        self.timezone = TimeZone.current.identifier
        self.recurrenceRule = nil
        self.reminderType = task.reminderType
        self.isCompleted = task.isCompleted
        self.createdAt = task.createdAt
        self.updatedAt = task.serverUpdatedAt
        self.deletedAt = task.deletedAt
        self.version = task.version
    }

    func toTask() -> Task {
        Task(
            id: id,
            title: title,
            notes: notes,
            dueDate: dueAt,
            isCompleted: isCompleted,
            reminderEnabled: deletedAt == nil,
            createdAt: createdAt ?? Date(),
            reminderType: reminderType,
            serverUpdatedAt: updatedAt,
            version: version,
            pendingSync: false,
            deletedAt: deletedAt
        )
    }
}
