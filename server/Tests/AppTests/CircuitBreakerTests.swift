import XCTVapor
@testable import App

final class CircuitBreakerTests: XCTestCase {
    func testOpensAfterThresholdAndRecovers() async {
        let breaker = CircuitBreaker(config: .init(failureThreshold: 3, cooldown: 0.1))
        let key = "device-1"

        XCTAssertTrue(await breaker.canPass(key: key))

        for _ in 0..<3 {
            await breaker.recordFailure(key: key)
        }
        XCTAssertFalse(await breaker.canPass(key: key))

        try? await Task.sleep(nanoseconds: 200_000_000)
        // Half-open lets one probe through.
        XCTAssertTrue(await breaker.canPass(key: key))

        await breaker.recordSuccess(key: key)
        XCTAssertTrue(await breaker.canPass(key: key))
    }
}
