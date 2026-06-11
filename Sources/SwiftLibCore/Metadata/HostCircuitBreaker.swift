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
        var probeStartedAt: Date? = nil
    }

    private var states: [String: State] = [:]

    private let failureThreshold: Int
    private let baseCooldown: TimeInterval
    private let maxCooldown: TimeInterval
    /// If a half-open probe never reports back (e.g. its task was cancelled
    /// before reaching recordSuccess/recordFailure), allow a replacement probe
    /// after this long so the breaker can't get stuck rejecting forever.
    private let probeTimeout: TimeInterval

    public init(
        failureThreshold: Int = 5,
        baseCooldown: TimeInterval = 30,
        maxCooldown: TimeInterval = 600,
        probeTimeout: TimeInterval = 60
    ) {
        self.failureThreshold = failureThreshold
        self.baseCooldown = baseCooldown
        self.maxCooldown = maxCooldown
        self.probeTimeout = probeTimeout
    }

    /// Check whether a request to `host` should be allowed.
    ///
    /// State machine:
    /// - Closed (no `openUntil`): allow.
    /// - Open (`openUntil` in the future): reject immediately — this is the
    ///   whole point of the breaker; callers must not wait out a network
    ///   timeout against a host that is known to be down.
    /// - Half-open (`openUntil` reached): allow exactly ONE probe; all other
    ///   callers keep getting rejected until the probe reports success
    ///   (breaker closes) or failure (cooldown extends). The `openUntil`
    ///   marker is intentionally kept in place while the probe is in flight
    ///   so concurrent callers cannot slip past through the closed path.
    public func check(host: String) -> Decision {
        let host = host.lowercased()
        let now = Date()
        var state = states[host] ?? State()

        guard let openUntil = state.openUntil else { return .allow }

        if openUntil > now {
            // Still cooling down: short-circuit immediately.
            return .reject(retryAfter: openUntil.timeIntervalSince(now))
        }

        // Cooldown expired → half-open.
        if state.probeInFlight {
            // A probe is already out. Unless it has been silent past the
            // timeout (cancelled task, etc.), keep rejecting.
            if let startedAt = state.probeStartedAt,
               now.timeIntervalSince(startedAt) < probeTimeout {
                return .reject(retryAfter: probeTimeout - now.timeIntervalSince(startedAt))
            }
            // Probe went silent — let this caller take over as the new probe.
        }

        state.probeInFlight = true
        state.probeStartedAt = now
        states[host] = state
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
        state.probeStartedAt = nil

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
