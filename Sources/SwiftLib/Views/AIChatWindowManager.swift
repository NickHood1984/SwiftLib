import AppKit
import SwiftUI
import WebKit

enum AIChatPageLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

enum AIChatStatusTone {
    case info
    case warning
    case error
}

struct AIChatStatusBanner {
    let message: String
    let systemImage: String
    let tone: AIChatStatusTone
    let showsProgress: Bool
}

private struct AIChatPageSnapshotScriptPayload: Encodable {
    let inputSel: String
    let sendSel: String
}

private struct AIChatInjectScriptPayload: Encodable {
    let inputSel: String
    let text: String
}

private struct AIChatSendScriptPayload: Encodable {
    let inputSel: String
    let sendSel: String
}

private struct AIChatResponseTrackerScriptPayload: Encodable {
    let selectors: [String]
}

private struct AIChatResponseScriptPayload: Encodable {
    let responseSel: String
    let contentSel: String
    let streamingSel: String
    let beforeCount: Int
    let beforeText: String
}

private struct AIChatResponseSnapshot: Decodable, Equatable {
    let status: String
    let text: String
    let responseCount: Int
    let pendingRequests: Int
    let requestsStartedSinceMark: Int
    let responseIdleMs: Int
    let networkIdleMs: Int
}

private extension AIChatResponseSnapshot {
    var hasTrackedNetworkCompletion: Bool {
        requestsStartedSinceMark > 0
            && pendingRequests == 0
            && responseIdleMs >= 900
            && networkIdleMs >= 300
    }
}

struct AIChatResponseStabilityTracker {
    private(set) var lastText = ""
    private(set) var stablePollCount = 0

    mutating func ingest(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed == lastText {
            stablePollCount += 1
        } else {
            lastText = trimmed
            stablePollCount = 0
        }
    }

    func hasSettled(for status: String) -> Bool {
        let requiredStablePolls = status == "done" ? 2 : 4
        return !lastText.isEmpty && stablePollCount >= requiredStablePolls
    }
}

private extension AIDOMServiceConfig {
    var requiresClickableSendButton: Bool {
        let trimmed = sendSelector.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.caseInsensitiveCompare("Enter") != .orderedSame
    }
}

/// Manages a single, shared AI chat browser window backed by WKWebView.
///
/// Provides DOM-based text injection and response extraction using configurable
/// selectors loaded from `AIDOMSelectorService`.
@MainActor
final class AIChatWindowManager: ObservableObject {
    static let shared = AIChatWindowManager()

    private var window: NSPanel?
    private var closeObserver: NSObjectProtocol?

    @Published var currentURLString: String = SwiftLibPreferences.aiChatURL
    @Published var isLoading = false
    @Published private(set) var pageLoadState: AIChatPageLoadState = .idle
    @Published private(set) var lastOperationErrorMessage: String?

    /// Reference to the active WKWebView for JS evaluation.
    fileprivate(set) var webView: WKWebView?

    private init() {}

    var statusBanner: AIChatStatusBanner? {
        if let message = lastOperationErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            return AIChatStatusBanner(
                message: message,
                systemImage: "exclamationmark.triangle.fill",
                tone: .error,
                showsProgress: false
            )
        }

        switch pageLoadState {
        case .loading:
            return AIChatStatusBanner(
                message: "AI 页面加载中，页面未就绪时不会自动发送。",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .info,
                showsProgress: true
            )
        case .failed(let detail):
            return AIChatStatusBanner(
                message: "AI 页面加载失败：\(detail)",
                systemImage: "wifi.exclamationmark",
                tone: .warning,
                showsProgress: false
            )
        case .idle, .ready:
            return nil
        }
    }

    // MARK: - Public API

    /// Show the AI chat browser window.
    func open() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            existing.deminiaturize(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = makeWindow()
        let hostView = AIChatHostView(manager: self)
        win.contentViewController = NSHostingController(rootView: hostView)
        window = win

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pageLoadState = .idle
                self?.lastOperationErrorMessage = nil
            }
        }

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Release the WKWebView and free memory.
    func destroyWindow() {
        if let obs = closeObserver {
            NotificationCenter.default.removeObserver(obs)
            closeObserver = nil
        }
        webView = nil
        pageLoadState = .idle
        lastOperationErrorMessage = nil
        window?.close()
        window = nil
    }

    // MARK: - Internals

    func changeService(to urlString: String) {
        lastOperationErrorMessage = nil
        pageLoadState = .loading
        currentURLString = urlString
        SwiftLibPreferences.aiChatURL = urlString
    }

    func reloadCurrentPage() {
        lastOperationErrorMessage = nil
        pageLoadState = .loading
        if let webView {
            webView.reload()
            return
        }

        let current = currentURLString
        currentURLString = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.currentURLString = current
        }
    }

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

    // MARK: - DOM interaction helpers

    fileprivate func handleNavigationStarted() {
        pageLoadState = .loading
        if !isLoading {
            lastOperationErrorMessage = nil
        }
    }

    fileprivate func handleNavigationFinished() {
        pageLoadState = .ready
    }

    fileprivate func handleNavigationFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == URLError.cancelled.rawValue {
            return
        }
        pageLoadState = .failed(error.localizedDescription)
    }

    private func prepareChatOperation() async throws -> (WKWebView, AIDOMServiceConfig) {
        open()
        try await waitForWebView()

        guard let wv = webView else { throw AIChatError.noWebView }
        guard let selectors = AIDOMSelectorService.shared.selectors(for: currentURLString) else {
            throw AIChatError.unknownService(currentURLString)
        }

        return (wv, selectors)
    }

    private func waitForWebView() async throws {
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
    private func waitForInputReady(_ wv: WKWebView, selectors: AIDOMServiceConfig) async throws -> AIChatPageSnapshot {
        let deadline = Date().addingTimeInterval(20)
        var lastSnapshot: AIChatPageSnapshot?

        while Date() < deadline {
            if case .failed(let detail) = pageLoadState {
                throw AIChatError.pageLoadFailed(detail)
            }

            let snapshot = try await capturePageSnapshot(on: wv, selectors: selectors)
            lastSnapshot = snapshot

            if snapshot.hasUsableInput {
                return snapshot
            }

            if let diagnostic = diagnoseAIChatPage(
                snapshot,
                serviceName: selectors.name,
                stage: .waitingForInput,
                requiresClickableSendButton: selectors.requiresClickableSendButton
            ), diagnostic.issue == .authRequired {
                throw error(for: diagnostic, fallbackSelector: selectors.inputSelector)
            }

            try await Task.sleep(nanoseconds: 350_000_000)
        }

        if let lastSnapshot,
           let diagnostic = diagnoseAIChatPage(
               lastSnapshot,
               serviceName: selectors.name,
               stage: .waitingForInput,
               requiresClickableSendButton: selectors.requiresClickableSendButton
           ) {
            throw error(for: diagnostic, fallbackSelector: selectors.inputSelector)
        }

        if case .loading = pageLoadState {
            throw AIChatError.pageStillLoading("\(selectors.name) 页面仍在加载或跳转，请等页面稳定后再试。")
        }

        throw AIChatError.inputNotFound(selectors.inputSelector)
    }

    private func injectText(_ text: String, into wv: WKWebView, inputSelector: String) async throws {
        let payload = try jsonLiteral(for: AIChatInjectScriptPayload(inputSel: inputSelector, text: text))
        let result = try await evaluateJavaScript(
            """
            (() => {
                const args = \(payload);
                function isVisible(el) {
                    if (!el) return false;
                    const style = window.getComputedStyle(el);
                    if (!style || style.display === 'none' || style.visibility === 'hidden') return false;
                    const rect = el.getBoundingClientRect();
                    return rect.width > 0 && rect.height > 0;
                }

                function isEnabled(el) {
                    return !!el
                        && !el.disabled
                        && el.getAttribute('aria-disabled') !== 'true'
                        && !el.readOnly;
                }

                const inputs = Array.from(document.querySelectorAll(args.inputSel));
                const el = inputs.find(input => isVisible(input) && isEnabled(input))
                    || inputs.find(input => isEnabled(input))
                    || inputs[0];
                if (!el) return { ok: false, reason: 'no_input' };

                if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
                    const prototype = el.tagName === 'TEXTAREA'
                        ? window.HTMLTextAreaElement.prototype
                        : window.HTMLInputElement.prototype;
                    const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;

                    const fireInput = (inputType, data) => {
                        try {
                            el.dispatchEvent(new InputEvent('input', {
                                bubbles: true,
                                cancelable: false,
                                inputType,
                                data
                            }));
                        } catch (_) {
                            el.dispatchEvent(new Event('input', { bubbles: true }));
                        }
                    };

                    el.focus();
                    if (typeof el.select === 'function') {
                        el.select();
                    }
                    if (typeof el.setSelectionRange === 'function') {
                        try { el.setSelectionRange(0, (el.value || '').length); } catch (_) {}
                    }

                    let insertedByCommand = false;
                    if (document.execCommand) {
                        try {
                            insertedByCommand = document.execCommand('insertText', false, args.text);
                        } catch (_) {
                            insertedByCommand = false;
                        }
                    }

                    if (!insertedByCommand || (el.value || '').trim() !== args.text.trim()) {
                        if (setter) setter.call(el, args.text);
                        else el.value = args.text;
                        fireInput('insertText', args.text);
                    }

                } else {
                    el.focus();
                    if (document.execCommand) {
                        document.execCommand('selectAll', false, null);
                        document.execCommand('insertText', false, args.text);
                    } else {
                        el.textContent = args.text;
                    }
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                }

                el.dispatchEvent(new Event('change', { bubbles: true }));
                el.focus();
                const value = el.value || el.innerText || el.textContent || '';
                return { ok: value.trim().length > 0, valueLength: value.trim().length };
            })();
            """,
            on: wv
        )

        guard let dict = result as? [String: Any], let ok = dict["ok"] as? Bool else {
            throw AIChatError.pageInteractionFailed("AI 输入注入返回了无效结果")
        }

        if !ok {
            throw AIChatError.inputNotFound(inputSelector)
        }
    }

    private func waitForInjectedText(_ wv: WKWebView, selectors: AIDOMServiceConfig) async throws {
        let deadline = Date().addingTimeInterval(6)
        var lastSnapshot: AIChatPageSnapshot?

        while Date() < deadline {
            let snapshot = try await capturePageSnapshot(on: wv, selectors: selectors)
            lastSnapshot = snapshot
            if snapshot.inputValueLength > 0 {
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        if let lastSnapshot,
           let diagnostic = diagnoseAIChatPage(
               lastSnapshot,
               serviceName: selectors.name,
               stage: .waitingForInput,
               requiresClickableSendButton: selectors.requiresClickableSendButton
           ) {
            throw error(for: diagnostic, fallbackSelector: selectors.inputSelector)
        }

        throw AIChatError.inputUnavailable("\(selectors.name) 的输入框没有接受文本，请确认页面已经准备好。")
    }

    private func armResponseTracker(on wv: WKWebView, selectors: AIDOMServiceConfig) async throws {
        let selectorList = [
            selectors.responseSelector,
            selectors.contentSelector,
            "[data-testid*='assistant']",
            "[data-testid*='message']",
            "div[class*='assistant']",
            "div[class*='message']",
            "div[class*='markdown']",
            "div[class*='rich-text']",
            "article",
            "main"
        ]
        .flatMap { raw in
            raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        .filter { !$0.isEmpty }

        let payload = try jsonLiteral(for: AIChatResponseTrackerScriptPayload(selectors: selectorList))
        _ = try await evaluateJavaScript(
            """
            (() => {
                const args = \(payload);
                const responseSelectors = Array.from(new Set(args.selectors || []));
                const tracker = window.__swiftlibAIChatTracker || (window.__swiftlibAIChatTracker = {
                    installed: false,
                    activeRequests: new Set(),
                    totalRequestCount: 0,
                    pendingRequests: 0,
                    requestsAtMark: 0,
                    lastNetworkActivityAt: Date.now(),
                    lastResponseMutationAt: Date.now(),
                    responseMutationCount: 0,
                    armed: false
                });

                tracker.responseSelectors = responseSelectors;

                function matchesResponseRegion(node) {
                    const element = node?.nodeType === Node.ELEMENT_NODE
                        ? node
                        : node?.parentElement;
                    if (!element) return false;

                    return responseSelectors.some(selector => {
                        try {
                            return element.matches(selector) || !!element.closest(selector);
                        } catch (_) {
                            return false;
                        }
                    });
                }

                function markResponseMutation() {
                    tracker.lastResponseMutationAt = Date.now();
                    tracker.responseMutationCount += 1;
                }

                function finalizeRequest(requestID) {
                    if (!tracker.activeRequests.has(requestID)) return;
                    tracker.activeRequests.delete(requestID);
                    tracker.pendingRequests = tracker.activeRequests.size;
                    tracker.lastNetworkActivityAt = Date.now();
                }

                function installFetchTracking() {
                    if (tracker.fetchTrackingInstalled || typeof window.fetch !== 'function') return;
                    tracker.fetchTrackingInstalled = true;
                    const originalFetch = window.fetch.bind(window);

                    window.fetch = (...fetchArgs) => {
                        const requestID = ++tracker.totalRequestCount;
                        tracker.activeRequests.add(requestID);
                        tracker.pendingRequests = tracker.activeRequests.size;
                        tracker.lastNetworkActivityAt = Date.now();

                        return originalFetch(...fetchArgs).then(response => {
                            try {
                                const cloned = response.clone();
                                const body = cloned.body;
                                if (!body || typeof body.getReader !== 'function') {
                                    finalizeRequest(requestID);
                                    return response;
                                }

                                const reader = body.getReader();
                                const pump = () => reader.read().then(({ done, value }) => {
                                    tracker.lastNetworkActivityAt = Date.now();
                                    if (value && value.byteLength) {
                                        tracker.lastNetworkActivityAt = Date.now();
                                    }
                                    if (done) {
                                        finalizeRequest(requestID);
                                        return;
                                    }
                                    return pump();
                                }).catch(() => {
                                    finalizeRequest(requestID);
                                });
                                pump();
                            } catch (_) {
                                finalizeRequest(requestID);
                            }

                            return response;
                        }).catch(error => {
                            finalizeRequest(requestID);
                            throw error;
                        });
                    };
                }

                function installXHRTracking() {
                    if (tracker.xhrTrackingInstalled || !window.XMLHttpRequest) return;
                    tracker.xhrTrackingInstalled = true;

                    const originalOpen = window.XMLHttpRequest.prototype.open;
                    const originalSend = window.XMLHttpRequest.prototype.send;

                    window.XMLHttpRequest.prototype.open = function(...openArgs) {
                        this.__swiftlibTrackerRequestID = null;
                        return originalOpen.apply(this, openArgs);
                    };

                    window.XMLHttpRequest.prototype.send = function(...sendArgs) {
                        const requestID = ++tracker.totalRequestCount;
                        this.__swiftlibTrackerRequestID = requestID;
                        tracker.activeRequests.add(requestID);
                        tracker.pendingRequests = tracker.activeRequests.size;
                        tracker.lastNetworkActivityAt = Date.now();

                        this.addEventListener('progress', () => {
                            tracker.lastNetworkActivityAt = Date.now();
                        });

                        this.addEventListener('loadend', () => {
                            finalizeRequest(requestID);
                        }, { once: true });

                        return originalSend.apply(this, sendArgs);
                    };
                }

                function installMutationTracking() {
                    if (tracker.mutationTrackingInstalled || !document.body) return;
                    tracker.mutationTrackingInstalled = true;
                    const observer = new MutationObserver(mutations => {
                        if (!tracker.armed) return;
                        const touchedResponse = mutations.some(mutation => {
                            if (matchesResponseRegion(mutation.target)) return true;
                            return Array.from(mutation.addedNodes || []).some(matchesResponseRegion)
                                || Array.from(mutation.removedNodes || []).some(matchesResponseRegion);
                        });

                        if (touchedResponse) {
                            markResponseMutation();
                        }
                    });

                    observer.observe(document.body, {
                        subtree: true,
                        childList: true,
                        characterData: true
                    });
                }

                if (!tracker.installed) {
                    tracker.installed = true;
                    installFetchTracking();
                    installXHRTracking();
                    installMutationTracking();
                }

                tracker.armed = true;
                tracker.requestsAtMark = tracker.totalRequestCount;
                tracker.lastNetworkActivityAt = Date.now();
                tracker.lastResponseMutationAt = Date.now();
                return { ok: true };
            })();
            """,
            on: wv
        )
    }

    private func triggerSend(on wv: WKWebView, selectors: AIDOMServiceConfig) async throws {
        let snapshot = try await capturePageSnapshot(on: wv, selectors: selectors)
        if let diagnostic = diagnoseAIChatPage(
            snapshot,
            serviceName: selectors.name,
            stage: .waitingForResponseStart,
            requiresClickableSendButton: selectors.requiresClickableSendButton
        ), diagnostic.issue == .authRequired || diagnostic.issue == .sendUnavailable {
            throw error(for: diagnostic, fallbackSelector: selectors.inputSelector)
        }

        let payload = try jsonLiteral(for: AIChatSendScriptPayload(inputSel: selectors.inputSelector, sendSel: selectors.sendSelector))
        let result = try await evaluateJavaScript(
            """
            (() => {
                const args = \(payload);

                function isVisible(el) {
                    if (!el) return false;
                    const style = window.getComputedStyle(el);
                    if (!style || style.display === 'none' || style.visibility === 'hidden') return false;
                    const rect = el.getBoundingClientRect();
                    return rect.width > 0 && rect.height > 0;
                }

                function isEnabled(el) {
                    return !!el
                        && !el.disabled
                        && el.getAttribute('aria-disabled') !== 'true'
                        && !el.readOnly;
                }

                const inputs = Array.from(document.querySelectorAll(args.inputSel));
                const el = inputs.find(input => isVisible(input) && isEnabled(input))
                    || inputs.find(input => isEnabled(input))
                    || inputs[0];
                if (!el) return { ok: false, reason: 'no_input' };

                const dispatchEnter = () => {
                    el.focus();
                    ['keydown', 'keypress', 'keyup'].forEach(type => {
                        el.dispatchEvent(new KeyboardEvent(type, {
                            key: 'Enter',
                            code: 'Enter',
                            keyCode: 13,
                            which: 13,
                            bubbles: true,
                            cancelable: true
                        }));
                    });
                    const form = el.closest('form');
                    if (form && typeof form.requestSubmit === 'function') {
                        try { form.requestSubmit(); } catch (_) {}
                    }
                    return true;
                };

                const clickSendButton = button => {
                    if (!button) return false;
                    button.focus?.();
                    ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(type => {
                        button.dispatchEvent(new MouseEvent(type, {
                            bubbles: true,
                            cancelable: true,
                            view: window
                        }));
                    });
                    if (typeof button.click === 'function') {
                        button.click();
                    }
                    return true;
                };

                if (!args.sendSel || args.sendSel === 'Enter') {
                    return { ok: dispatchEnter(), method: 'enter' };
                }

                const button = document.querySelector(args.sendSel);
                if (button && !button.disabled && button.getAttribute('aria-disabled') !== 'true') {
                    return { ok: clickSendButton(button), method: 'button' };
                }

                return {
                    ok: dispatchEnter(),
                    reason: button ? 'send_disabled_fallback' : 'no_send_fallback',
                    method: 'enter_fallback'
                };
            })();
            """,
            on: wv
        )

        guard let dict = result as? [String: Any], let ok = dict["ok"] as? Bool else {
            throw AIChatError.pageInteractionFailed("AI 发送动作返回了无效结果")
        }

        if ok {
            return
        }

        let reason = dict["reason"] as? String ?? "unknown"
        switch reason {
        case "no_input":
            throw AIChatError.inputNotFound(selectors.inputSelector)
        case "no_send", "send_disabled":
            throw AIChatError.sendUnavailable("\(selectors.name) 的发送按钮当前不可用，可能页面还没准备好，或者页面没有接管输入。")
        default:
            throw AIChatError.pageInteractionFailed("AI 发送动作失败：\(reason)")
        }
    }

    private func pollForResponse(
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

    private func capturePageSnapshot(on wv: WKWebView, selectors: AIDOMServiceConfig) async throws -> AIChatPageSnapshot {
        let payload = try jsonLiteral(for: AIChatPageSnapshotScriptPayload(inputSel: selectors.inputSelector, sendSel: selectors.sendSelector))
        let result = try await evaluateJavaScript(
            """
            (() => {
                const args = \(payload);

                function isVisible(el) {
                    if (!el) return false;
                    const style = window.getComputedStyle(el);
                    if (!style || style.display === 'none' || style.visibility === 'hidden') return false;
                    const rect = el.getBoundingClientRect();
                    return rect.width > 0 && rect.height > 0;
                }

                function isEnabled(el) {
                    return !!el
                        && !el.disabled
                        && el.getAttribute('aria-disabled') !== 'true'
                        && !el.readOnly;
                }

                const inputs = Array.from(document.querySelectorAll(args.inputSel));
                const input = inputs.find(candidate => isVisible(candidate) && isEnabled(candidate))
                    || inputs.find(candidate => isEnabled(candidate))
                    || inputs[0];
                const sendButton = args.sendSel && args.sendSel !== 'Enter'
                    ? document.querySelector(args.sendSel)
                    : null;

                const authSelectors = [
                    'input[type="password"]',
                    'a[href*="login"]',
                    'a[href*="signin"]',
                    'button[class*="login"]',
                    'button[id*="login"]',
                    '[data-testid*="login"]',
                    '[aria-label*="login" i]',
                    '[aria-label*="sign in" i]',
                    '[href*="auth"]'
                ];

                const authHintVisible = authSelectors.some(selector =>
                    Array.from(document.querySelectorAll(selector)).some(isVisible)
                );

                const inputValue = input
                    ? (input.value || input.innerText || input.textContent || '')
                    : '';

                return {
                    href: window.location.href || '',
                    title: document.title || '',
                    readyState: document.readyState || '',
                    hasInput: !!input,
                    inputVisible: isVisible(input),
                    inputEnabled: isEnabled(input),
                    inputValueLength: inputValue.trim().length,
                    hasSendButton: !!sendButton || !args.sendSel || args.sendSel === 'Enter',
                    sendButtonVisible: !args.sendSel || args.sendSel === 'Enter' ? true : isVisible(sendButton),
                    sendButtonEnabled: !args.sendSel || args.sendSel === 'Enter'
                        ? true
                        : !!sendButton
                            && !sendButton.disabled
                            && sendButton.getAttribute('aria-disabled') !== 'true',
                    authHintVisible,
                    hasPasswordField: !!document.querySelector('input[type="password"]'),
                    bodyTextSample: (document.body?.innerText || '').replace(/\\s+/g, ' ').trim().slice(0, 2000)
                };
            })();
            """,
            on: wv
        )

        return try decodeJSONObject(result, as: AIChatPageSnapshot.self)
    }

    private func captureResponseSnapshot(
        on wv: WKWebView,
        selectors: AIDOMServiceConfig,
        beforeCount: Int,
        beforeText: String
    ) async throws -> AIChatResponseSnapshot {
        let payload = try jsonLiteral(for: AIChatResponseScriptPayload(
            responseSel: selectors.responseSelector,
            contentSel: selectors.contentSelector,
            streamingSel: selectors.streamingSelector,
            beforeCount: beforeCount,
            beforeText: beforeText
        ))

        let result = try await evaluateJavaScript(
            """
            (() => {
                const args = \(payload);

                function isVisible(el) {
                    if (!el) return false;
                    const style = window.getComputedStyle(el);
                    if (!style || style.display === 'none' || style.visibility === 'hidden') return false;
                    const rect = el.getBoundingClientRect();
                    return rect.width > 0 && rect.height > 0;
                }

                function collectResponses() {
                    const selectorCandidates = [
                        args.contentSel,
                        args.responseSel,
                        '[data-testid*="assistant"] [data-testid*="message"]',
                        '[data-testid*="message-content"]',
                        'div[class*="assistant"] div[class*="markdown"]',
                        'div[class*="message-content"]',
                        'div[class*="rich-text"]',
                        'div[class*="markdown"]',
                        'article'
                    ].filter(Boolean);

                    function isSuggestionNode(node) {
                        const element = node?.nodeType === Node.ELEMENT_NODE
                            ? node
                            : node?.parentElement;
                        if (!element) return false;

                        const suggestionHost = element.closest('[class*="suggest"], [data-testid*="suggest"]');
                        if (!suggestionHost) return false;

                        const className = String(suggestionHost.className || '').toLowerCase();
                        const testID = String(suggestionHost.getAttribute?.('data-testid') || '').toLowerCase();
                        return className.includes('suggest') || testID.includes('suggest');
                    }

                    for (const selector of selectorCandidates) {
                        const nodes = Array.from(document.querySelectorAll(selector))
                            .filter(node =>
                                isVisible(node)
                                && !isSuggestionNode(node)
                                && (node.innerText || '').trim().length > 0
                            );
                        if (nodes.length > 0) {
                            return nodes;
                        }
                    }

                    return [];
                }

                const responses = collectResponses();
                const last = responses[responses.length - 1] || null;
                const content = args.contentSel && last ? (last.querySelector(args.contentSel) || last) : last;
                const text = (content?.innerText || '').trim();
                const textChanged = !!text && text !== (args.beforeText || '');

                if (args.beforeCount < 0) {
                    return {
                        status: 'baseline',
                        text,
                        responseCount: responses.length,
                        pendingRequests: 0,
                        requestsStartedSinceMark: 0,
                        responseIdleMs: 0,
                        networkIdleMs: 0
                    };
                }

                const tracker = window.__swiftlibAIChatTracker || null;
                const pendingRequests = tracker ? (tracker.pendingRequests || 0) : 0;
                const requestsStartedSinceMark = tracker
                    ? Math.max(0, (tracker.totalRequestCount || 0) - (tracker.requestsAtMark || 0))
                    : 0;
                const responseIdleMs = tracker
                    ? Math.max(0, Date.now() - (tracker.lastResponseMutationAt || Date.now()))
                    : 0;
                const networkIdleMs = tracker
                    ? Math.max(0, Date.now() - (tracker.lastNetworkActivityAt || Date.now()))
                    : 0;

                if (responses.length <= args.beforeCount && !textChanged) {
                    return {
                        status: 'waiting',
                        text,
                        responseCount: responses.length,
                        pendingRequests,
                        requestsStartedSinceMark,
                        responseIdleMs,
                        networkIdleMs
                    };
                }

                if (args.streamingSel) {
                    const streamingSelectors = args.streamingSel
                        .split(',')
                        .map(item => item.trim())
                        .filter(Boolean);
                    const streaming = streamingSelectors.some(selector => document.querySelector(selector));
                    return {
                        status: streaming ? 'streaming' : 'done',
                        text,
                        responseCount: responses.length,
                        pendingRequests,
                        requestsStartedSinceMark,
                        responseIdleMs,
                        networkIdleMs
                    };
                }

                return {
                    status: responses.length > args.beforeCount || textChanged ? 'check' : 'waiting',
                    text,
                    responseCount: responses.length,
                    pendingRequests,
                    requestsStartedSinceMark,
                    responseIdleMs,
                    networkIdleMs
                };
            })();
            """,
            on: wv
        )

        return try decodeJSONObject(result, as: AIChatResponseSnapshot.self)
    }

    private func evaluateJavaScript(_ script: String, on wv: WKWebView, timeout: TimeInterval = 8) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            var finished = false
            let timeoutWorkItem = DispatchWorkItem {
                guard !finished else { return }
                finished = true
                continuation.resume(throwing: AIChatError.javaScriptTimedOut)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            wv.evaluateJavaScript(script) { result, error in
                DispatchQueue.main.async {
                    guard !finished else { return }
                    finished = true
                    timeoutWorkItem.cancel()

                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: result)
                    }
                }
            }
        }
    }

    private func jsonLiteral<T: Encodable>(for value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw AIChatError.pageInteractionFailed("无法编码 AI 页面脚本参数")
        }
        return string
    }

    private func decodeJSONObject<T: Decodable>(_ raw: Any?, as type: T.Type) throws -> T {
        guard let raw else {
            throw AIChatError.pageInteractionFailed("AI 页面脚本没有返回结果")
        }

        guard JSONSerialization.isValidJSONObject(raw) else {
            throw AIChatError.pageInteractionFailed("AI 页面脚本返回了不可解析的数据")
        }

        let data = try JSONSerialization.data(withJSONObject: raw)
        return try JSONDecoder().decode(type, from: data)
    }

    private func intValue(from raw: Any?) -> Int? {
        if let int = raw as? Int {
            return int
        }
        if let number = raw as? NSNumber {
            return number.intValue
        }
        if let double = raw as? Double {
            return Int(double)
        }
        return nil
    }

    private func error(for diagnostic: AIChatPageDiagnostic, fallbackSelector: String) -> AIChatError {
        switch diagnostic.issue {
        case .authRequired:
            return .authRequired(diagnostic.message)
        case .pageStillLoading:
            return .pageStillLoading(diagnostic.message)
        case .inputUnavailable:
            return .inputUnavailable(diagnostic.message)
        case .sendUnavailable:
            return .sendUnavailable(diagnostic.message)
        case .responseDidNotStart:
            return .responseDidNotStart(diagnostic.message)
        }
    }

    private func normalizeError(_ error: Error) -> AIChatError {
        if let aiError = error as? AIChatError {
            return aiError
        }

        return AIChatError.pageInteractionFailed(error.localizedDescription)
    }

    // MARK: - Errors

    enum AIChatError: LocalizedError {
        case noWebView
        case unknownService(String)
        case inputNotFound(String)
        case inputUnavailable(String)
        case authRequired(String)
        case pageStillLoading(String)
        case pageLoadFailed(String)
        case sendUnavailable(String)
        case responseDidNotStart(String)
        case emptyResponse
        case timeout
        case javaScriptTimedOut
        case pageInteractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .noWebView: return "AI 聊天窗口未就绪"
            case .unknownService(let url): return "未识别的 AI 服务：\(url)\n请更新 DOM 选择器配置"
            case .inputNotFound(let sel): return "找不到聊天输入框（\(sel)）。当前页可能尚未登录或仍在加载，请先确认 AI 页面已准备好。"
            case .inputUnavailable(let message): return message
            case .authRequired(let message): return message
            case .pageStillLoading(let message): return message
            case .pageLoadFailed(let detail): return "AI 页面加载失败：\(detail)"
            case .sendUnavailable(let message): return message
            case .responseDidNotStart(let message): return message
            case .emptyResponse: return "AI 返回了空回复"
            case .timeout: return "等待 AI 回复超时，请稍后再试。"
            case .javaScriptTimedOut: return "AI 页面脚本执行超时，页面可能仍在加载或卡住了。"
            case .pageInteractionFailed(let message): return "AI 页面交互失败：\(message)"
            }
        }
    }

    // MARK: - Window factory

    private func makeWindow() -> NSPanel {
        let size = preferredSize()
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "AI 助手"
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 480, height: 520)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.auxiliary, .moveToActiveSpace]
        panel.setFrameAutosaveName("SwiftLibAIChat-v1")
        if !panel.setFrameUsingName("SwiftLibAIChat-v1") {
            positionNearMainWindow(panel)
        }
        return panel
    }

    private func positionNearMainWindow(_ panel: NSPanel) {
        guard let mainWindow = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }),
              let screen = mainWindow.screen ?? NSScreen.main else {
            panel.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height

        let rightX = mainWindow.frame.maxX + 8
        if rightX + panelWidth <= visibleFrame.maxX {
            let y = max(visibleFrame.minY, min(mainWindow.frame.midY - panelHeight / 2, visibleFrame.maxY - panelHeight))
            panel.setFrameOrigin(NSPoint(x: rightX, y: y))
        } else {
            panel.center()
        }
    }

    private func preferredSize() -> NSSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 960)
        let width = min(max(560, visibleFrame.width * 0.36), visibleFrame.width - 80)
        let height = min(max(640, visibleFrame.height * 0.72), visibleFrame.height - 80)
        return NSSize(width: width, height: height)
    }
}

// MARK: - SwiftUI host view

private struct AIChatHostView: View {
    @ObservedObject var manager: AIChatWindowManager
    @ObservedObject var selectorService = AIDOMSelectorService.shared

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let banner = manager.statusBanner {
                Divider()
                AIChatStatusBannerView(banner: banner)
            }
            Divider()
            chatWebView
        }
        .task {
            await AIDOMSelectorService.shared.autoUpdateIfNeeded()
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 0) {
            AIChatToolbar(
                urlString: $manager.currentURLString,
                onReload: {
                    manager.reloadCurrentPage()
                },
                onGoBack: {
                    NotificationCenter.default.post(name: .aiChatGoBack, object: nil)
                },
                onGoForward: {
                    NotificationCenter.default.post(name: .aiChatGoForward, object: nil)
                },
                onChangeService: { newURL in
                    manager.changeService(to: newURL)
                }
            )

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            Button {
                Task { await AIDOMSelectorService.shared.updateFromRemote() }
            } label: {
                if selectorService.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.borderless)
            .disabled(selectorService.isUpdating)
            .help("更新 DOM 选择器配置（v\(selectorService.config.version)）")
            .padding(.trailing, 8)
        }
    }

    @ViewBuilder
    private var chatWebView: some View {
        if let url = URL(string: manager.currentURLString), !manager.currentURLString.isEmpty {
            AIChatBrowserView(url: url)
        } else {
            VStack {
                Spacer()
                Text("请在设置中配置 AI 服务 URL")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

private struct AIChatStatusBannerView: View {
    let banner: AIChatStatusBanner

    var body: some View {
        HStack(spacing: 8) {
            if banner.showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: banner.systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }

            Text(banner.message)
                .font(.caption)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
    }

    private var foregroundColor: Color {
        switch banner.tone {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch banner.tone {
        case .info:
            return Color.secondary.opacity(0.08)
        case .warning:
            return Color.orange.opacity(0.10)
        case .error:
            return Color.red.opacity(0.10)
        }
    }
}

// MARK: - WKWebView browser wrapper (stores ref in manager)

private struct AIChatBrowserView: NSViewRepresentable {
    var url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        wv.allowsBackForwardNavigationGestures = true
        wv.isInspectable = true  // Enable Safari Web Inspector
        context.coordinator.webView = wv
        context.coordinator.currentURL = url

        // Store reference for JS evaluation
        AIChatWindowManager.shared.webView = wv

        context.coordinator.backObserver = NotificationCenter.default.addObserver(
            forName: .aiChatGoBack, object: nil, queue: .main
        ) { _ in wv.goBack() }
        context.coordinator.forwardObserver = NotificationCenter.default.addObserver(
            forName: .aiChatGoForward, object: nil, queue: .main
        ) { _ in wv.goForward() }

        wv.load(URLRequest(url: url))
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        if context.coordinator.currentURL != url {
            context.coordinator.currentURL = url
            wv.load(URLRequest(url: url))
        }
    }

    static func dismantleNSView(_ wv: WKWebView, coordinator: Coordinator) {
        if let obs = coordinator.backObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = coordinator.forwardObserver { NotificationCenter.default.removeObserver(obs) }
        AIChatWindowManager.shared.webView = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var currentURL: URL?
        var backObserver: NSObjectProtocol?
        var forwardObserver: NSObjectProtocol?

        /// 拦截非 http/https 的 URL scheme，避免页面里触发 `bitbrowser://` / `weixin://`
        /// 这类自定义协议时 macOS 弹出「未设定应用程序」的系统提示。
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased()
            switch scheme {
            case "http", "https", "about", "data", "blob", "file", nil:
                decisionHandler(.allow)
            default:
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                AIChatWindowManager.shared.handleNavigationStarted()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                AIChatWindowManager.shared.handleNavigationFinished()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                AIChatWindowManager.shared.handleNavigationFailure(error)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                AIChatWindowManager.shared.handleNavigationFailure(error)
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Task { @MainActor in
                AIChatWindowManager.shared.handleNavigationFailure(AIChatWindowManager.AIChatError.pageInteractionFailed("Web 内容进程已终止，请刷新页面后重试。"))
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let aiChatGoBack = Notification.Name("SwiftLib.aiChatGoBack")
    static let aiChatGoForward = Notification.Name("SwiftLib.aiChatGoForward")
}
