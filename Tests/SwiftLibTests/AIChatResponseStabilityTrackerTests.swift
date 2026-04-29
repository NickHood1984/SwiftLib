import XCTest
@testable import SwiftLib

final class AIChatResponseStabilityTrackerTests: XCTestCase {
    func testStructuredJSONStateDetectsIncompletePayload() {
        let state = StructuredJSONCandidateExtractor.candidateState(
            in: #"{"translations":[{"id":"block_1","translation":"第一段"}"#,
            requireStructuredPrefix: true
        )

        XCTAssertEqual(state, .incomplete)
    }

    func testStructuredJSONStateAcceptsCompletePayloadWithTrailingText() {
        let state = StructuredJSONCandidateExtractor.candidateState(
            in: """
            {"translations":[{"id":"block_1","translation":"第一段"}]}

            下面是额外说明
            """,
            requireStructuredPrefix: true
        )

        guard case .complete(let candidate) = state else {
            return XCTFail("Expected a complete structured payload")
        }

        XCTAssertEqual(candidate, #"{"translations":[{"id":"block_1","translation":"第一段"}]}"#)
    }

    func testStructuredJSONExtractorCollectsMultipleCompletePayloads() {
        let candidates = StructuredJSONCandidateExtractor.completeCandidates(
            in: """
            例子：
            {"translations":[{"id":"block_1","translation":"示例"}]}

            真正回复：
            {"translations":[{"id":"block_1","translation":"第一段"},{"id":"block_2","translation":"第二段"}]}
            """
        )

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.last, #"{"translations":[{"id":"block_1","translation":"第一段"},{"id":"block_2","translation":"第二段"}]}"#)
    }

    func testDoneStatusWaitsForRepeatedStablePolls() {
        var tracker = AIChatResponseStabilityTracker()

        tracker.ingest("第一段")
        XCTAssertFalse(tracker.hasSettled(for: "done"))

        tracker.ingest("第一段")
        XCTAssertFalse(tracker.hasSettled(for: "done"))

        tracker.ingest("第一段")
        XCTAssertTrue(tracker.hasSettled(for: "done"))
    }

    func testStreamingStatusNeedsLongerStabilityWindow() {
        var tracker = AIChatResponseStabilityTracker()

        tracker.ingest("正在回复")
        tracker.ingest("正在回复")
        tracker.ingest("正在回复")
        tracker.ingest("正在回复")
        XCTAssertFalse(tracker.hasSettled(for: "streaming"))

        tracker.ingest("正在回复")
        XCTAssertTrue(tracker.hasSettled(for: "streaming"))
    }

    func testTextChangeResetsStabilityCounter() {
        var tracker = AIChatResponseStabilityTracker()

        tracker.ingest("第一版")
        tracker.ingest("第一版")
        XCTAssertFalse(tracker.hasSettled(for: "done"))

        tracker.ingest("第二版")
        XCTAssertFalse(tracker.hasSettled(for: "done"))

        tracker.ingest("第二版")
        XCTAssertFalse(tracker.hasSettled(for: "done"))

        tracker.ingest("第二版")
        XCTAssertTrue(tracker.hasSettled(for: "done"))
    }
}
