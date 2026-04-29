import SwiftUI
import WebKit

struct BaiduScholarVerificationSheet: View {
    @ObservedObject var provider: BaiduScholarWebEngine
    let session: BaiduScholarWebEngine.VerificationSession
    @State private var pageState: PageState = .loading
    @State private var autoContinueTask: Task<Void, Never>?
    @State private var hasIssuedContinue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.title)
                    .font(.title3.weight(.semibold))
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(session.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            BaiduScholarVerificationWebView(
                url: session.url,
                onStateChange: handlePageStateChange(_:)
            )
            .frame(minWidth: 720, minHeight: 460)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("取消") {
                    provider.cancelVerification()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(session.continueLabel) {
                    continueVerificationIfNeeded()
                }
                .buttonStyle(SLPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 560)
        .onDisappear {
            autoContinueTask?.cancel()
        }
    }

    private func handlePageStateChange(_ state: PageState) {
        pageState = state
        autoContinueTask?.cancel()
        guard state == .ready, !hasIssuedContinue else { return }
        autoContinueTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            continueVerificationIfNeeded()
        }
    }

    private func continueVerificationIfNeeded() {
        guard !hasIssuedContinue else { return }
        hasIssuedContinue = true
        autoContinueTask?.cancel()
        provider.continueVerification()
    }

    private var statusMessage: String {
        switch pageState {
        case .ready:
            return "已检测到百度学术页面恢复正常，正在自动继续；如果没有自动关闭，也可以手动点“继续检查”。"
        case .blocked:
            return "页面仍处于百度学术安全验证状态。请先在这个窗口中完成验证，并保持当前结果页打开。"
        case .loading:
            return session.message
        }
    }
}

private extension BaiduScholarVerificationSheet {
    enum PageState: Equatable {
        case loading
        case blocked
        case ready
    }
}

private struct BaiduScholarVerificationWebView: NSViewRepresentable {
    let url: URL
    var onStateChange: (BaiduScholarVerificationSheet.PageState) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        HiddenWKWebViewMediaGuard.configure(configuration)
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = ReaderExtractionManager.safariLikeUserAgent
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard nsView.url?.absoluteString != url.absoluteString else { return }
        nsView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onStateChange: onStateChange)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onStateChange: (BaiduScholarVerificationSheet.PageState) -> Void

        init(onStateChange: @escaping (BaiduScholarVerificationSheet.PageState) -> Void) {
            self.onStateChange = onStateChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                let script = #"""
                (() => {
                  const marker = ((document.title || '') + ' ' + (document.body?.innerText || '').slice(0, 1600)).toLowerCase();
                  const href = location.href.toLowerCase();
                  const blocked = /安全验证|captcha|访问异常|异常访问|验证后继续访问/.test(marker)
                    || href.includes('seccaptcha')
                    || href.includes('/verify/')
                    || href.includes('wappass.baidu.com');
                  return JSON.stringify({ blocked });
                })();
                """#

                do {
                    let raw = try await webView.evaluateJavaScript(script)
                    if let json = raw as? String,
                       let data = json.data(using: .utf8),
                       let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let blocked = payload["blocked"] as? Bool {
                        onStateChange(blocked ? .blocked : .ready)
                        return
                    }
                } catch {
                    // Ignore and fall through to loading state.
                }

                onStateChange(.loading)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onStateChange(.loading)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onStateChange(.loading)
        }
    }
}
