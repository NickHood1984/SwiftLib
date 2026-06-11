import XCTest
@testable import SwiftLibCore

final class HostRateLimiterTests: XCTestCase {

    /// Regression test for the actor-reentrancy bug: concurrent `acquire`
    /// calls used to read the same stale `lastDispatchAt`, sleep the same
    /// duration, and then all dispatch simultaneously. The limiter must
    /// instead space concurrent callers at least ~`interval` apart.
    func testConcurrentAcquiresAreSpacedByInterval() async {
        let limiter = HostRateLimiter()
        let host = "rate-limit-test.example.org"
        let requestsPerSecond = 20.0 // 50ms gap — fast enough for CI
        await limiter.setInterval(host: host, requestsPerSecond: requestsPerSecond)

        let callerCount = 5
        let timestamps: [UInt64] = await withTaskGroup(of: UInt64.self) { group in
            for _ in 0..<callerCount {
                group.addTask {
                    await limiter.acquire(host: host)
                    return DispatchTime.now().uptimeNanoseconds
                }
            }
            var collected: [UInt64] = []
            for await stamp in group {
                collected.append(stamp)
            }
            return collected
        }

        let sorted = timestamps.sorted()
        XCTAssertEqual(sorted.count, callerCount)

        let expectedGapNanos = 1_000_000_000.0 / requestsPerSecond
        // Allow generous scheduling tolerance (40%): we are asserting that the
        // limiter queues callers, not exact timer precision.
        let minimumAcceptableGap = UInt64(expectedGapNanos * 0.6)

        for index in 1..<sorted.count {
            let gap = sorted[index] - sorted[index - 1]
            XCTAssertGreaterThanOrEqual(
                gap,
                minimumAcceptableGap,
                "并发 acquire 第 \(index) 与 \(index - 1) 个完成时间差仅 \(gap)ns，限速在并发下失效"
            )
        }

        // Total elapsed must reflect (N-1) queued slots — simultaneous dispatch
        // would finish in roughly one interval.
        let totalElapsed = sorted.last! - sorted.first!
        XCTAssertGreaterThanOrEqual(
            totalElapsed,
            UInt64(expectedGapNanos * Double(callerCount - 1) * 0.6),
            "全部并发请求几乎同时完成，说明没有排队"
        )
    }

    /// Sequential callers separated by more than the interval should not be
    /// delayed at all (no artificial queuing when traffic is already slow).
    func testSlowSequentialAcquiresDoNotSleep() async {
        let limiter = HostRateLimiter()
        let host = "rate-limit-sequential.example.org"
        await limiter.setInterval(host: host, requestsPerSecond: 100.0) // 10ms gap

        await limiter.acquire(host: host)
        try? await Task.sleep(nanoseconds: 30_000_000) // 30ms > 10ms interval

        let before = DispatchTime.now().uptimeNanoseconds
        await limiter.acquire(host: host)
        let elapsed = DispatchTime.now().uptimeNanoseconds - before

        XCTAssertLessThan(elapsed, 8_000_000, "间隔已满足时 acquire 不应再休眠")
    }
}
