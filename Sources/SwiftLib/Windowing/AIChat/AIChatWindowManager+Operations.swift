import Foundation
import WebKit

extension AIChatWindowManager {
    // MARK: - Send text and extract response

    /// Inject text into the AI chat input, send it, wait for the response,
    /// Inject text, send it, wait for the AI response, and return the response text.
    func sendText(_ text: String) async throws -> String {
        lastOperationErrorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let (wv, sel) = try await prepareChatOperation()

            _ = try await waitForInputReady(wv, selectors: sel)
            let beforeResponse = try await captureResponseSnapshot(
                on: wv,
                selectors: sel,
                beforeCount: -1,
                beforeText: ""
            )
            try await injectText(text, into: wv, inputSelector: sel.inputSelector)
            try await waitForInjectedText(wv, selectors: sel)
            try await armResponseTracker(on: wv, selectors: sel)
            try await triggerSend(on: wv, selectors: sel)
            let response = try await pollForResponse(
                wv,
                selectors: sel,
                beforeCount: beforeResponse.responseCount,
                beforeText: beforeResponse.text
            )
            lastOperationErrorMessage = nil
            return response
        } catch {
            let resolved = normalizeError(error)
            lastOperationErrorMessage = resolved.localizedDescription
            throw resolved
        }
    }

    /// Open the AI window and inject text into the input box — does NOT send.
    /// The user can review and submit manually.
    func injectTextOnly(_ text: String) async throws {
        lastOperationErrorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let (wv, sel) = try await prepareChatOperation()
            _ = try await waitForInputReady(wv, selectors: sel)
            try await injectText(text, into: wv, inputSelector: sel.inputSelector)
            try await waitForInjectedText(wv, selectors: sel)
            lastOperationErrorMessage = nil
        } catch {
            let resolved = normalizeError(error)
            lastOperationErrorMessage = resolved.localizedDescription
            throw resolved
        }
    }


    func prepareChatOperation() async throws -> (WKWebView, AIDOMServiceConfig) {
        open()
        try await waitForWebView()

        guard let wv = webView else { throw AIChatError.noWebView }
        guard let selectors = AIDOMSelectorService.shared.selectors(for: currentURLString) else {
            throw AIChatError.unknownService(currentURLString)
        }

        return (wv, selectors)
    }

    func waitForWebView() async throws {
        for _ in 0..<30 {
            if webView != nil { return }
            if case .failed(let detail) = pageLoadState {
                throw AIChatError.pageLoadFailed(detail)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw AIChatError.noWebView
    }

    /// Poll until the input selector exists in the DOM and the page is fully loaded.

    func pollForResponse(
        _ wv: WKWebView,
        selectors: AIDOMServiceConfig,
        beforeCount: Int,
        beforeText: String
    ) async throws -> String {
        var responseStarted = false
        let normalizedBeforeText = beforeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let responseStartDeadline = Date().addingTimeInterval(15)
        let completionDeadline = Date().addingTimeInterval(90)
        var stabilityTracker = AIChatResponseStabilityTracker()

        while Date() < completionDeadline {
            try Task.checkCancellation()
            if case .failed(let detail) = pageLoadState {
                throw AIChatError.pageLoadFailed(detail)
            }

            try await Task.sleep(nanoseconds: 700_000_000)

            let response = try await captureResponseSnapshot(
                on: wv,
                selectors: selectors,
                beforeCount: beforeCount,
                beforeText: normalizedBeforeText
            )
            let status = response.status
            let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)

            let textChanged = !text.isEmpty && text != normalizedBeforeText
            if response.responseCount > beforeCount || textChanged {
                responseStarted = true
            }

            if responseStarted && !text.isEmpty {
                stabilityTracker.ingest(text)
                let stableText = stabilityTracker.lastText.isEmpty ? text : stabilityTracker.lastText
                let structuredState = StructuredJSONCandidateExtractor.candidateState(
                    in: stableText,
                    requireStructuredPrefix: true
                )

                if case .incomplete = structuredState {
                    continue
                }

                if response.hasTrackedNetworkCompletion {
                    return stableText
                }
                if stabilityTracker.hasSettled(for: status) {
                    return stableText
                }
            }

            if !responseStarted && Date() >= responseStartDeadline {
                let snapshot = try await capturePageSnapshot(on: wv, selectors: selectors)
                if let diagnostic = diagnoseAIChatPage(
                    snapshot,
                    serviceName: selectors.name,
                    stage: .waitingForResponseStart,
                    requiresClickableSendButton: selectors.requiresClickableSendButton
                ) {
                    throw error(for: diagnostic, fallbackSelector: selectors.inputSelector)
                }

                throw AIChatError.responseDidNotStart("\(selectors.name) 没有开始回复，请先确认已经登录且页面完成加载。")
            }
        }

        if responseStarted, !stabilityTracker.lastText.isEmpty {
            return stabilityTracker.lastText
        }

        throw AIChatError.timeout
    }

}
