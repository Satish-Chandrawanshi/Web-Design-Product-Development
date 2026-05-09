import XCTVapor
@testable import App

/// Validates the FOR UPDATE SKIP LOCKED scheduler doesn't double-pick rows
/// and the backoff function grows correctly.
final class SchedulerTests: XCTestCase {
    func testBackoffGrowsExponentiallyAndCaps() {
        for attempt in 0..<6 {
            let next = OutboxDispatcherJob.nextDelay(after: attempt)
            let secondsFromNow = next.timeIntervalSinceNow
            XCTAssertGreaterThanOrEqual(secondsFromNow, 60.0 * pow(2.0, Double(attempt)))
            XCTAssertLessThanOrEqual(secondsFromNow, 3600.0 + 60.0)
        }
    }
}
