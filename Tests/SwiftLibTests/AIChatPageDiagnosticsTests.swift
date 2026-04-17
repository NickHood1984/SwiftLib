import XCTest
@testable import SwiftLib

final class AIChatPageDiagnosticsTests: XCTestCase {
    func testDetectsAuthRequiredWhenLoginSignalsAreVisible() throws {
        let snapshot = AIChatPageSnapshot(
            href: "https://chatgpt.com/auth/login",
            title: "Log in",
            readyState: "complete",
            hasInput: false,
            inputVisible: false,
            inputEnabled: false,
            inputValueLength: 0,
            hasSendButton: false,
            sendButtonVisible: false,
            sendButtonEnabled: false,
            authHintVisible: true,
            hasPasswordField: true,
            bodyTextSample: "Log in to continue"
        )

        let diagnostic = try XCTUnwrap(
            diagnoseAIChatPage(
                snapshot,
                serviceName: "ChatGPT",
                stage: .waitingForInput,
                requiresClickableSendButton: true
            )
        )

        XCTAssertEqual(diagnostic.issue, .authRequired)
    }

    func testDetectsPageStillLoadingWhenInputIsNotReady() throws {
        let snapshot = AIChatPageSnapshot(
            href: "https://chat.deepseek.com/",
            title: "Loading",
            readyState: "loading",
            hasInput: false,
            inputVisible: false,
            inputEnabled: false,
            inputValueLength: 0,
            hasSendButton: false,
            sendButtonVisible: false,
            sendButtonEnabled: false,
            authHintVisible: false,
            hasPasswordField: false,
            bodyTextSample: "Loading your workspace"
        )

        let diagnostic = try XCTUnwrap(
            diagnoseAIChatPage(
                snapshot,
                serviceName: "DeepSeek",
                stage: .waitingForInput,
                requiresClickableSendButton: false
            )
        )

        XCTAssertEqual(diagnostic.issue, .pageStillLoading)
    }

    func testDetectsDisabledSendButtonBeforeWaitingForReply() throws {
        let snapshot = AIChatPageSnapshot(
            href: "https://www.doubao.com/chat",
            title: "Doubao",
            readyState: "complete",
            hasInput: true,
            inputVisible: true,
            inputEnabled: true,
            inputValueLength: 24,
            hasSendButton: true,
            sendButtonVisible: true,
            sendButtonEnabled: false,
            authHintVisible: false,
            hasPasswordField: false,
            bodyTextSample: "Ready"
        )

        let diagnostic = try XCTUnwrap(
            diagnoseAIChatPage(
                snapshot,
                serviceName: "豆包",
                stage: .waitingForResponseStart,
                requiresClickableSendButton: true
            )
        )

        XCTAssertEqual(diagnostic.issue, .sendUnavailable)
    }

    func testDetectsReplyDidNotStartOnApparentlyReadyPage() throws {
        let snapshot = AIChatPageSnapshot(
            href: "https://kimi.com/",
            title: "Kimi",
            readyState: "complete",
            hasInput: true,
            inputVisible: true,
            inputEnabled: true,
            inputValueLength: 18,
            hasSendButton: true,
            sendButtonVisible: true,
            sendButtonEnabled: true,
            authHintVisible: false,
            hasPasswordField: false,
            bodyTextSample: "Ready"
        )

        let diagnostic = try XCTUnwrap(
            diagnoseAIChatPage(
                snapshot,
                serviceName: "Kimi",
                stage: .waitingForResponseStart,
                requiresClickableSendButton: false
            )
        )

        XCTAssertEqual(diagnostic.issue, .responseDidNotStart)
    }
}