import Foundation

/// Per-key three-state circuit breaker (closed → open → half-open).
///
/// - `closed`: requests pass; failures increment a counter.
/// - `open`: requests rejected for `cooldown` seconds.
/// - `halfOpen`: a single probe is allowed; success closes the circuit, failure re-opens.
actor CircuitBreaker {
    enum State { case closed, open(until: Date), halfOpen }

    struct Config {
        var failureThreshold: Int = 5
        var cooldown: TimeInterval = 60
    }

    private var states: [String: State] = [:]
    private var failureCounts: [String: Int] = [:]
    private let config: Config

    init(config: Config = Config()) {
        self.config = config
    }

    func canPass(key: String) -> Bool {
        switch states[key] ?? .closed {
        case .closed, .halfOpen:
            return true
        case .open(let until):
            if Date() >= until {
                states[key] = .halfOpen
                return true
            }
            return false
        }
    }

    func recordSuccess(key: String) {
        states[key] = .closed
        failureCounts[key] = 0
    }

    func recordFailure(key: String) {
        let current = (failureCounts[key] ?? 0) + 1
        failureCounts[key] = current
        if current >= config.failureThreshold {
            states[key] = .open(until: Date().addingTimeInterval(config.cooldown))
        }
    }
}
