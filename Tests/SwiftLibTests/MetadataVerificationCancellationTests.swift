import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

/// The metadata refresh pipeline races its work against a timeout via
/// `withTaskGroup`; the group cannot exit until every child finishes. These
/// tests pin the contract that the user-verification waits (CNKI / Baidu
/// Scholar) resume promptly when their task is cancelled — without this the
/// timeout is ineffective and the "正在刷新元数据…" toast spins forever.
final class MetadataVerificationCancellationTests: XCTestCase {

    @MainActor
    func testCNKIRequestVerificationUnblocksOnTaskCancellation() async {
        let provider = CNKIMetadataProvider()

        let task = Task { @MainActor () -> Error? in
            do {
                try await provider.requestVerification(
                    at: URL(string: "https://kns.cnki.net/")!,
                    title: "测试",
                    message: "测试",
                    continueLabel: "继续"
                )
                return nil
            } catch {
                return error
            }
        }

        // Let the verification wait actually suspend before cancelling.
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let raced = await raceAgainstTimeout(seconds: 5) { await task.value }
        guard case .finished(let error) = raced else {
            XCTFail("requestVerification 在任务取消后仍然挂起")
            return
        }
        XCTAssertNotNil(error, "取消后应当以错误结束，而不是正常返回")
        XCTAssertNil(provider.verificationSession, "取消后验证会话应被清除，关闭验证面板")
    }

    @MainActor
    func testCNKIRequestVerificationFailsFastWhenAlreadyCancelled() async {
        let provider = CNKIMetadataProvider()

        let task = Task { @MainActor () -> Error? in
            // Cancel before the continuation is installed.
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await provider.requestVerification(
                    at: URL(string: "https://kns.cnki.net/")!,
                    title: "测试",
                    message: "测试",
                    continueLabel: "继续"
                )
                return nil
            } catch {
                return error
            }
        }

        let raced = await raceAgainstTimeout(seconds: 5) { await task.value }
        guard case .finished(let error) = raced else {
            XCTFail("requestVerification 在预先取消的任务中仍然挂起")
            return
        }
        XCTAssertNotNil(error)
        XCTAssertNil(provider.verificationSession)
    }

    // MARK: - Helpers

    private enum RaceResult<T: Sendable>: Sendable {
        case finished(T)
        case timedOut
    }

    private func raceAgainstTimeout<T: Sendable>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async -> T
    ) async -> RaceResult<T> {
        await withTaskGroup(of: RaceResult<T>.self) { group in
            group.addTask { .finished(await operation()) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }
}
