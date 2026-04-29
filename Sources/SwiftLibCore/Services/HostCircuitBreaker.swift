import Foundation

/// A simple per-host circuit breaker.
///
/// Purpose: when a specific upstream API (e.g. Semantic Scholar) is having an
/// outage, we don't want every single caller to wait the full network timeout
/// on every request. After `failureThreshold` consecutive transient failures
/// for a host we "open" the breaker for `cooldownSeconds`; during that window
/// requests are short-circuited and return immediately.
///
/// On the first request after cooldown expires the breaker transitions to
/// half-open (we allow exactly one probe through). If the probe succeeds the
/// breaker closes; if it fails we extend the cooldown with a capped
/// exponential backoff.
public actor HostCircuitBreaker {
    public static let shared = HostCircuitBreaker()

    public enum Decision: Sendable {
        case allow
        case reject(retryAfter: TimeInterval)
    }

    private struct State {
        var consecutiveFailures: Int = 0
        var openUntil: Date? = nil
        var extendedCooldownSeconds: TimeInterval = 0
        var probeInFlight: Bool = false
    }

    private var states: [String: State] = [:]

    private let failureThreshold: Int
    private let baseCooldown: TimeInterval
    private let maxCooldown: TimeInterval

    public init(
        failureThreshold: Int = 5,
        baseCooldown: TimeInterval = 30,
        maxCooldown: TimeInterval = 600
    ) {
        self.failureThreshold = failureThreshold
        self.baseCooldown = baseCooldown
        self.maxCooldown = maxCooldown
    }

    /// Check whether a request to `host` should be allowed.
    /// When the breaker is open and no probe is in flight, transitions
    /// to half-open and lets exactly one probe through.
    public func check(host: String) -> Decision {
        let host = host.lowercased()
        let now = Date()
        var state = states[host] ?? State()

        if let openUntil = state.openUntil {
            if openUntil > now {
                // Still open.
                if state.probeInFlight {
                    let retry = openUntil.timeIntervalSince(now)
                    return .reject(retryAfter: retry)
                }
                // Half-open: allow a single probe, but keep the breaker
                // nominally open until the probe either succeeds or fails.
                state.probeInFlight = true
                states[host] = state
                return .allow
            } else {
                // Cooldown expired: enter half-open automatically.
                state.openUntil = nil
                state.probeInFlight = true
                states[host] = state
                return .allow
            }
        }

        return .allow
    }

    public func recordSuccess(host: String) {
        let host = host.lowercased()
        states[host] = State()
    }

    public func recordFailure(host: String) {
        let host = host.lowercased()
        var state = states[host] ?? State()
        state.consecutiveFailures += 1
        state.probeInFlight = false

        if state.consecutiveFailures >= failureThreshold {
            // Exponential backoff up to maxCooldown.
            let next: TimeInterval
            if state.extendedCooldownSeconds == 0 {
                next = baseCooldown
            } else {
                next = min(maxCooldown, state.extendedCooldownSeconds * 2)
            }
            state.extendedCooldownSeconds = next
            state.openUntil = Date().addingTimeInterval(next)
        }
        states[host] = state
    }
}
