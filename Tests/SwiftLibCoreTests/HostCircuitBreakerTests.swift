import XCTest
@testable import SwiftLibCore

final class HostCircuitBreakerTests: XCTestCase {

    private let host = "breaker-test.example.org"

    private func makeBreaker(
        failureThreshold: Int = 2,
        baseCooldown: TimeInterval = 0.2,
        maxCooldown: TimeInterval = 2,
        probeTimeout: TimeInterval = 0.5
    ) -> HostCircuitBreaker {
        HostCircuitBreaker(
            failureThreshold: failureThreshold,
            baseCooldown: baseCooldown,
            maxCooldown: maxCooldown,
            probeTimeout: probeTimeout
        )
    }

    private func isAllow(_ decision: HostCircuitBreaker.Decision) -> Bool {
        if case .allow = decision { return true }
        return false
    }

    func testClosedBreakerAllows() async {
        let breaker = makeBreaker()
        let decision = await breaker.check(host: host)
        XCTAssertTrue(isAllow(decision))
    }

    func testSubThresholdFailuresKeepBreakerClosed() async {
        let breaker = makeBreaker(failureThreshold: 3)
        await breaker.recordFailure(host: host)
        await breaker.recordFailure(host: host)
        let decision = await breaker.check(host: host)
        XCTAssertTrue(isAllow(decision), "未达阈值不应熔断")
    }

    /// Regression: while the breaker is open (cooldown not yet expired) every
    /// request must be rejected immediately. The old implementation let the
    /// first caller through as a "probe" during the cooldown window, so the
    /// breaker never actually short-circuited anything.
    func testOpenBreakerRejectsDuringCooldown() async {
        let breaker = makeBreaker(failureThreshold: 2, baseCooldown: 5)
        await breaker.recordFailure(host: host)
        await breaker.recordFailure(host: host)

        for attempt in 0..<3 {
            let decision = await breaker.check(host: host)
            XCTAssertFalse(isAllow(decision), "冷却期内第 \(attempt) 次请求应被直接拒绝")
        }
    }

    /// Regression: after cooldown expiry exactly ONE probe may pass. The old
    /// implementation cleared `openUntil` when the first probe went out, which
    /// let every concurrent caller through the closed path simultaneously.
    func testHalfOpenAllowsExactlyOneProbe() async throws {
        let breaker = makeBreaker(failureThreshold: 2, baseCooldown: 0.1, probeTimeout: 5)
        await breaker.recordFailure(host: host)
        await breaker.recordFailure(host: host)

        try await Task.sleep(nanoseconds: 150_000_000) // cooldown (100ms) expired

        let first = await breaker.check(host: host)
        XCTAssertTrue(isAllow(first), "冷却结束后应放行一个探针")

        let second = await breaker.check(host: host)
        XCTAssertFalse(isAllow(second), "探针未返回前其余请求必须继续被拒绝")
    }

    func testProbeSuccessClosesBreaker() async throws {
        let breaker = makeBreaker(failureThreshold: 2, baseCooldown: 0.1)
        await breaker.recordFailure(host: host)
        await breaker.recordFailure(host: host)
        try await Task.sleep(nanoseconds: 150_000_000)

        let probe = await breaker.check(host: host)
        XCTAssertTrue(isAllow(probe))
        await breaker.recordSuccess(host: host)

        let after = await breaker.check(host: host)
        XCTAssertTrue(isAllow(after), "探针成功后熔断器应关闭")
    }

    func testProbeFailureReopensWithExtendedCooldown() async throws {
        let breaker = makeBreaker(failureThreshold: 2, baseCooldown: 0.1)
        await breaker.recordFailure(host: host)
        await breaker.recordFailure(host: host)
        try await Task.sleep(nanoseconds: 150_000_000)

        let probe = await breaker.check(host: host)
        XCTAssertTrue(isAllow(probe))
        await breaker.recordFailure(host: host)

        let after = await breaker.check(host: host)
        XCTAssertFalse(isAllow(after), "探针失败后熔断器应重新打开")
    }

    /// A probe whose task was cancelled (never reports back) must not wedge
    /// the breaker permanently — after `probeTimeout` a new probe is allowed.
    func testSilentProbeIsReplacedAfterTimeout() async throws {
        let breaker = makeBreaker(failureThreshold: 2, baseCooldown: 0.1, probeTimeout: 0.2)
        await breaker.recordFailure(host: host)
        await breaker.recordFailure(host: host)
        try await Task.sleep(nanoseconds: 150_000_000)

        let probe = await breaker.check(host: host)
        XCTAssertTrue(isAllow(probe))
        // Probe goes silent (no recordSuccess/recordFailure).

        try await Task.sleep(nanoseconds: 250_000_000) // > probeTimeout

        let replacement = await breaker.check(host: host)
        XCTAssertTrue(isAllow(replacement), "探针超时后应允许新的探针，避免熔断器卡死")
    }
}
