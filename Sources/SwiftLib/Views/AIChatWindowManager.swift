import AppKit
import SwiftUI
import WebKit

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

    /// Reference to the active WKWebView for JS evaluation.
    fileprivate(set) var webView: WKWebView?

    private init() {}

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
            _ = self
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
        window?.close()
        window = nil
    }

    // MARK: - Internals

    func changeService(to urlString: String) {
        currentURLString = urlString
        SwiftLibPreferences.aiChatURL = urlString
    }

    // MARK: - Send text and extract response

    /// Inject text into the AI chat input, send it, wait for the response,
    /// Inject text, send it, wait for the AI response, and return the response text.
    func sendText(_ text: String) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        open()
        try await waitForWebView()

        guard let wv = webView else { throw AIChatError.noWebView }
        guard let sel = AIDOMSelectorService.shared.selectors(for: currentURLString) else {
            throw AIChatError.unknownService(currentURLString)
        }

        // Wait until the page has rendered the input element
        try await waitForInputReady(wv, inputSelector: sel.inputSelector)

        let beforeCount = try await countResponses(wv, selector: sel.responseSelector)
        try await injectAndSend(wv, text: text, selectors: sel, shouldSend: true)
        try await Task.sleep(nanoseconds: 2_500_000_000)
        return try await pollForResponse(wv, selectors: sel, beforeCount: beforeCount)
    }

    /// Open the AI window and inject text into the input box — does NOT send.
    /// The user can review and submit manually.
    func injectTextOnly(_ text: String) async throws {
        isLoading = true
        defer { isLoading = false }

        open()
        try await waitForWebView()

        guard let wv = webView else { throw AIChatError.noWebView }
        guard let sel = AIDOMSelectorService.shared.selectors(for: currentURLString) else {
            throw AIChatError.unknownService(currentURLString)
        }

        try await waitForInputReady(wv, inputSelector: sel.inputSelector)
        try await injectAndSend(wv, text: text, selectors: sel, shouldSend: false)
    }

    // MARK: - DOM interaction helpers

    private func waitForWebView() async throws {
        for _ in 0..<30 {
            if webView != nil { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw AIChatError.noWebView
    }

    /// Poll until the input selector exists in the DOM and the page is fully loaded.
    private func waitForInputReady(_ wv: WKWebView, inputSelector: String) async throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let ready = (try? await wv.callAsyncJavaScript(
                """
                var loaded = document.readyState === 'complete' || document.readyState === 'interactive';
                var hasInput = !!document.querySelector(sel);
                return loaded && hasInput;
                """,
                arguments: ["sel": inputSelector],
                contentWorld: .page
            ) as? Bool) ?? false
            if ready { return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw AIChatError.inputNotFound(inputSelector)
    }

    private func countResponses(_ wv: WKWebView, selector: String) async throws -> Int {
        let result = try await wv.callAsyncJavaScript(
            "return document.querySelectorAll(sel).length;",
            arguments: ["sel": selector],
            contentWorld: .page
        )
        return (result as? Int) ?? 0
    }

    private func injectAndSend(_ wv: WKWebView, text: String, selectors: AIDOMServiceConfig, shouldSend: Bool) async throws {
        let result = try await wv.callAsyncJavaScript("""
            var el = document.querySelector(inputSel);
            if (!el) return {error: 'no_input'};

            if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
                var setter = Object.getOwnPropertyDescriptor(
                    window.HTMLTextAreaElement.prototype, 'value')?.set
                    || Object.getOwnPropertyDescriptor(
                    window.HTMLInputElement.prototype, 'value')?.set;
                if (setter) setter.call(el, text);
                else el.value = text;
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
            } else {
                // contenteditable / ProseMirror
                el.focus();
                document.execCommand('selectAll', false, null);
                document.execCommand('insertText', false, text);
            }
            el.focus();

            if (!doSend) return {ok: true};

            // Wait until the framework has actually accepted the text
            // (value/innerText non-empty), then wait a further 600ms for
            // event listeners to settle before sending.
            var waited = 0;
            while (waited < 5000) {
                var content = el.tagName === 'TEXTAREA' || el.tagName === 'INPUT'
                    ? el.value
                    : (el.innerText || el.textContent || '');
                if (content.trim().length > 0) break;
                await new Promise(r => setTimeout(r, 100));
                waited += 100;
            }
            await new Promise(r => setTimeout(r, 600));

            if (sendSel === 'Enter' || sendSel === '') {
                el.dispatchEvent(new KeyboardEvent('keydown', {
                    key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true
                }));
                el.dispatchEvent(new KeyboardEvent('keyup', {
                    key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true
                }));
            } else {
                var btn = document.querySelector(sendSel);
                if (btn) { btn.click(); }
            }
            return {ok: true};
        """, arguments: [
            "inputSel": selectors.inputSelector,
            "sendSel": selectors.sendSelector,
            "text": text,
            "doSend": shouldSend
        ], contentWorld: .page)

        if let dict = result as? [String: Any], dict["error"] != nil {
            throw AIChatError.inputNotFound(selectors.inputSelector)
        }
    }

    private func pollForResponse(_ wv: WKWebView, selectors: AIDOMServiceConfig, beforeCount: Int) async throws -> String {
        let useStreamingIndicator = !selectors.streamingSelector.isEmpty

        let pollJS: String
        if useStreamingIndicator {
            pollJS = """
                var responses = document.querySelectorAll(responseSel);
                if (responses.length <= beforeCount) return {status: 'waiting'};
                var streaming = document.querySelector(streamingSel);
                if (streaming) return {status: 'streaming'};
                var last = responses[responses.length - 1];
                var content = contentSel ? (last.querySelector(contentSel) || last) : last;
                return {status: 'done', text: content.innerText || ''};
            """
        } else {
            // No streaming indicator — use text stability (unchanged for ~2.4s)
            pollJS = """
                var responses = document.querySelectorAll(responseSel);
                if (responses.length <= beforeCount) return {status: 'waiting', text: ''};
                var last = responses[responses.length - 1];
                var content = contentSel ? (last.querySelector(contentSel) || last) : last;
                return {status: 'check', text: content.innerText || ''};
            """
        }

        var lastText = ""
        var stableCount = 0
        let deadline = Date().addingTimeInterval(120)

        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 800_000_000)

            guard let result = try? await wv.callAsyncJavaScript(
                pollJS,
                arguments: [
                    "responseSel": selectors.responseSelector,
                    "contentSel": selectors.contentSelector,
                    "streamingSel": selectors.streamingSelector,
                    "beforeCount": beforeCount
                ],
                contentWorld: .page
            ) as? [String: Any] else { continue }

            let status = result["status"] as? String ?? ""
            let text = (result["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if status == "done" {
                if text.isEmpty { throw AIChatError.emptyResponse }
                return text
            }

            if status == "check" {
                if text == lastText && !text.isEmpty {
                    stableCount += 1
                    if stableCount >= 3 { return text }
                } else {
                    lastText = text
                    stableCount = 0
                }
            }
        }

        throw AIChatError.timeout
    }

    // MARK: - Errors

    enum AIChatError: LocalizedError {
        case noWebView
        case unknownService(String)
        case inputNotFound(String)
        case emptyResponse
        case timeout

        var errorDescription: String? {
            switch self {
            case .noWebView: return "AI 聊天窗口未就绪"
            case .unknownService(let url): return "未识别的 AI 服务：\(url)\n请更新 DOM 选择器配置"
            case .inputNotFound(let sel): return "找不到聊天输入框（\(sel)）\n请更新 DOM 选择器配置"
            case .emptyResponse: return "AI 返回了空回复"
            case .timeout: return "等待 AI 回复超时（120 秒）"
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
                    let current = manager.currentURLString
                    manager.currentURLString = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        manager.currentURLString = current
                    }
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

// MARK: - WKWebView browser wrapper (stores ref in manager)

private struct AIChatBrowserView: NSViewRepresentable {
    var url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        wv.allowsBackForwardNavigationGestures = true
        wv.isInspectable = true  // Enable Safari Web Inspector
        context.coordinator.webView = wv

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

    final class Coordinator {
        weak var webView: WKWebView?
        var currentURL: URL?
        var backObserver: NSObjectProtocol?
        var forwardObserver: NSObjectProtocol?
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let aiChatGoBack = Notification.Name("SwiftLib.aiChatGoBack")
    static let aiChatGoForward = Notification.Name("SwiftLib.aiChatGoForward")
}
