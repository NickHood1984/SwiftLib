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

private struct AIChatResponseScriptPayload: Encodable {
    let responseSel: String
    let contentSel: String
    let streamingSel: String
    let beforeCount: Int
}

private struct AIChatResponseSnapshot: Decodable, Equatable {
    let status: String
    let text: String
    let responseCount: Int
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
            let beforeCount = try await countResponses(wv, selector: sel.responseSelector)
            try await injectText(text, into: wv, inputSelector: sel.inputSelector)
            try await waitForInjectedText(wv, selectors: sel)
            try await triggerSend(on: wv, selectors: sel)
            let response = try await pollForResponse(wv, selectors: sel, beforeCount: beforeCount)
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

    private func countResponses(_ wv: WKWebView, selector: String) async throws -> Int {
        let payload = try jsonLiteral(for: ["selector": selector])
        let result = try await evaluateJavaScript(
            "(() => { const args = \(payload); return document.querySelectorAll(args.selector).length; })();",
            on: wv
        )
        return intValue(from: result) ?? 0
    }

    private func injectText(_ text: String, into wv: WKWebView, inputSelector: String) async throws {
        let payload = try jsonLiteral(for: AIChatInjectScriptPayload(inputSel: inputSelector, text: text))
        let result = try await evaluateJavaScript(
            """
            (() => {
                const args = \(payload);
                const el = document.querySelector(args.inputSel);
                if (!el) return { ok: false, reason: 'no_input' };

                if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
                    const setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')?.set
                        || Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
                    if (setter) setter.call(el, args.text);
                    else el.value = args.text;
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                    el.dispatchEvent(new Event('change', { bubbles: true }));
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

                el.focus();
                return { ok: true };
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
                const el = document.querySelector(args.inputSel);
                if (!el) return { ok: false, reason: 'no_input' };

                if (!args.sendSel || args.sendSel === 'Enter') {
                    ['keydown', 'keypress', 'keyup'].forEach(type => {
                        el.dispatchEvent(new KeyboardEvent(type, {
                            key: 'Enter',
                            code: 'Enter',
                            keyCode: 13,
                            which: 13,
                            bubbles: true
                        }));
                    });
                    return { ok: true };
                }

                const button = document.querySelector(args.sendSel);
                if (!button) return { ok: false, reason: 'no_send' };
                if (button.disabled || button.getAttribute('aria-disabled') === 'true') {
                    return { ok: false, reason: 'send_disabled' };
                }

                button.click();
                return { ok: true };
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

    private func pollForResponse(_ wv: WKWebView, selectors: AIDOMServiceConfig, beforeCount: Int) async throws -> String {
        var lastText = ""
        var stableCount = 0
        var responseStarted = false
        let responseStartDeadline = Date().addingTimeInterval(15)
        let completionDeadline = Date().addingTimeInterval(90)

        while Date() < completionDeadline {
            try Task.checkCancellation()
            if case .failed(let detail) = pageLoadState {
                throw AIChatError.pageLoadFailed(detail)
            }

            try await Task.sleep(nanoseconds: 700_000_000)

            let response = try await captureResponseSnapshot(on: wv, selectors: selectors, beforeCount: beforeCount)
            let status = response.status
            let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if response.responseCount > beforeCount {
                responseStarted = true
            }

            if status == "done" {
                if text.isEmpty { throw AIChatError.emptyResponse }
                return text
            }

            if responseStarted && !text.isEmpty {
                if text == lastText && !text.isEmpty {
                    stableCount += 1
                    if stableCount >= 4 { return text }
                } else {
                    lastText = text
                    stableCount = 0
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

        if responseStarted, !lastText.isEmpty {
            return lastText
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

                const input = document.querySelector(args.inputSel);
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
                    inputEnabled: !!input
                        && !input.disabled
                        && input.getAttribute('aria-disabled') !== 'true'
                        && !input.readOnly,
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

    private func captureResponseSnapshot(on wv: WKWebView, selectors: AIDOMServiceConfig, beforeCount: Int) async throws -> AIChatResponseSnapshot {
        let payload = try jsonLiteral(for: AIChatResponseScriptPayload(
            responseSel: selectors.responseSelector,
            contentSel: selectors.contentSelector,
            streamingSel: selectors.streamingSelector,
            beforeCount: beforeCount
        ))

        let result = try await evaluateJavaScript(
            """
            (() => {
                const args = \(payload);
                const responses = document.querySelectorAll(args.responseSel);
                if (responses.length <= args.beforeCount) {
                    return { status: 'waiting', text: '', responseCount: responses.length };
                }

                const last = responses[responses.length - 1];
                const content = args.contentSel ? (last.querySelector(args.contentSel) || last) : last;
                const text = (content?.innerText || '').trim();

                if (args.streamingSel) {
                    const streaming = document.querySelector(args.streamingSel);
                    return {
                        status: streaming ? 'streaming' : 'done',
                        text,
                        responseCount: responses.length
                    };
                }

                return { status: 'check', text, responseCount: responses.length };
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
