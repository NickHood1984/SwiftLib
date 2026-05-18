import Foundation
import WebKit

extension AIChatWindowManager {
    func waitForInputReady(_ wv: WKWebView, selectors: AIDOMServiceConfig) async throws -> AIChatPageSnapshot {
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

    func injectText(_ text: String, into wv: WKWebView, inputSelector: String) async throws {
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

    func waitForInjectedText(_ wv: WKWebView, selectors: AIDOMServiceConfig) async throws {
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

    func armResponseTracker(on wv: WKWebView, selectors: AIDOMServiceConfig) async throws {
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

    func triggerSend(on wv: WKWebView, selectors: AIDOMServiceConfig) async throws {
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


    func capturePageSnapshot(on wv: WKWebView, selectors: AIDOMServiceConfig) async throws -> AIChatPageSnapshot {
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

    func captureResponseSnapshot(
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

    func evaluateJavaScript(_ script: String, on wv: WKWebView, timeout: TimeInterval = 8) async throws -> Any? {
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

    func jsonLiteral<T: Encodable>(for value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw AIChatError.pageInteractionFailed("无法编码 AI 页面脚本参数")
        }
        return string
    }

    func decodeJSONObject<T: Decodable>(_ raw: Any?, as type: T.Type) throws -> T {
        guard let raw else {
            throw AIChatError.pageInteractionFailed("AI 页面脚本没有返回结果")
        }

        guard JSONSerialization.isValidJSONObject(raw) else {
            throw AIChatError.pageInteractionFailed("AI 页面脚本返回了不可解析的数据")
        }

        let data = try JSONSerialization.data(withJSONObject: raw)
        return try JSONDecoder().decode(type, from: data)
    }

    func intValue(from raw: Any?) -> Int? {
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

}
