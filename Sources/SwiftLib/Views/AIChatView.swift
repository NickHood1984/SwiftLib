import SwiftUI
import WebKit

/// A WKWebView wrapper that loads an AI chat web interface (ChatGPT, 豆包, Kimi, etc.).
/// Uses a persistent data store so login sessions survive across show/hide cycles.
struct AIChatView: NSViewRepresentable {
    /// The URL to load. Changes trigger navigation.
    var url: URL
    /// Text to inject into the chat input (best-effort, falls back to clipboard).
    var pendingText: String?
    /// Called after the pending text has been consumed (injected or copied).
    var onPendingTextConsumed: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator

        // Navigate if URL changed
        if coord.currentURL != url {
            coord.currentURL = url
            webView.load(URLRequest(url: url))
        }

        // Inject pending text if available
        if let text = pendingText, !text.isEmpty, text != coord.lastInjectedText {
            coord.lastInjectedText = text
            coord.injectText(text, into: webView)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AIChatView
        weak var webView: WKWebView?
        var currentURL: URL?
        var lastInjectedText: String?

        init(parent: AIChatView) {
            self.parent = parent
        }

        func injectText(_ text: String, into webView: WKWebView) {
            // Always copy to clipboard as a reliable fallback
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)

            // Attempt to inject into common AI chat input elements
            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            let js = """
            (function() {
                var text = `\(escaped)`;
                // Try textarea first
                var el = document.querySelector('textarea, div[contenteditable="true"], div[role="textbox"], [data-testid="chat-input"]');
                if (!el) return false;
                if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
                    var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')?.set
                                    || Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
                    if (nativeSetter) {
                        nativeSetter.call(el, text);
                    } else {
                        el.value = text;
                    }
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                    el.dispatchEvent(new Event('change', { bubbles: true }));
                } else {
                    // contenteditable or div[role=textbox]
                    el.focus();
                    el.textContent = text;
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                }
                el.focus();
                return true;
            })();
            """

            webView.evaluateJavaScript(js) { [weak self] result, _ in
                Task { @MainActor in
                    self?.parent.onPendingTextConsumed?()
                }
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Allow all navigation within the AI chat
            .allow
        }
    }
}

// MARK: - AI Chat Toolbar (top bar with URL + controls)

struct AIChatToolbar: View {
    @Binding var urlString: String
    var onReload: () -> Void
    var onGoBack: () -> Void
    var onGoForward: () -> Void
    var onChangeService: (String) -> Void

    @State private var editingURL = ""
    @State private var isEditing = false

    var body: some View {
        HStack(spacing: 8) {
            // Navigation buttons
            Button(action: onGoBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("后退")

            Button(action: onGoForward) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help("前进")

            Button(action: onReload) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新")

            // Service switcher
            Menu {
                ForEach(SwiftLibPreferences.aiChatPresets, id: \.url) { preset in
                    Button(preset.name) {
                        onChangeService(preset.url)
                    }
                }
                Divider()
                Text("当前：\(urlString)")
            } label: {
                Image(systemName: "globe")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("切换 AI 服务")

            // URL field
            if isEditing {
                TextField("输入 URL…", text: $editingURL, onCommit: {
                    let trimmed = editingURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        var finalURL = trimmed
                        if !finalURL.hasPrefix("http://") && !finalURL.hasPrefix("https://") {
                            finalURL = "https://" + finalURL
                        }
                        onChangeService(finalURL)
                    }
                    isEditing = false
                })
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            } else {
                Text(urlString)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingURL = urlString
                        isEditing = true
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
