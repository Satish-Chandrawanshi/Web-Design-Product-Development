import Foundation

protocol TaskStoring {
    func loadTasks() throws -> [Task]
    func save(_ tasks: [Task])
}

final class TaskStore: TaskStoring {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "TaskStoreQueue", qos: .background)

    init(filename: String = "tasks.json") {
        let manager = FileManager.default
        let directory = manager.urls(for: .documentDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
        fileURL = directory.appendingPathComponent(filename)
    }

    func loadTasks() throws -> [Task] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Task].self, from: data)
    }

    func save(_ tasks: [Task]) {
        queue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(tasks)
                try data.write(to: self.fileURL, options: [.atomic])
            } catch {
                assertionFailure("Failed to persist tasks: \(error)")
            }
        }
    }
}
