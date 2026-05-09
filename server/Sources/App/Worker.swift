import Vapor
import NIOCore

public enum Worker {
    public static func run(_ app: Application) async throws {
        let logger = app.logger
        logger.info("Worker started")

        let poller = DueReminderPollerJob(app: app)
        let dispatcher = OutboxDispatcherJob(app: app)
        let retry = RetryPushJob(app: app)

        let promise = app.eventLoopGroup.next().makePromise(of: Void.self)

        @Sendable func tick() async {
            do {
                try await poller.runOnce()
                try await dispatcher.runOnce()
                try await retry.runOnce()
            } catch {
                logger.error("Worker tick failed: \(error)")
            }
        }

        let task = Task {
            while !Task.isCancelled {
                await tick()
                try? await Task.sleep(nanoseconds: UInt64(5_000_000_000))
            }
            promise.succeed(())
        }

        app.lifecycle.use(WorkerShutdown(task: task, promise: promise))

        try await promise.futureResult.get()
    }
}

private struct WorkerShutdown: LifecycleHandler {
    let task: Task<Void, Never>
    let promise: EventLoopPromise<Void>

    func shutdown(_ application: Application) {
        task.cancel()
        application.logger.info("Worker received shutdown signal; cancelling tick loop")
    }
}
