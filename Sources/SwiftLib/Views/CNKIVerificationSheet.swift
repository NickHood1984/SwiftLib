import SwiftUI
import WebKit

struct CNKIVerificationSheet: View {
    @ObservedObject var provider: CNKIMetadataProvider
    let session: CNKIMetadataProvider.VerificationSession
    @State private var pageState: CNKIMetadataProvider.PageResolutionState = .loadingOrUnknown
    @State private var autoContinueTask: Task<Void, Never>?
    @State private var hasIssuedContinue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.title)
                    .font(.title3.bold())
                Text(statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                Text(session.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            CNKIVerificationWebView(
                url: session.url,
                configure: provider.configureWebView(_:),
                prepareResultIfPossible: { webView in
                    await provider.prepareVerificationResultIfPossible(from: webView)
                },
                pageState: { webView in
                    await provider.pageResolutionState(in: webView)
                },
                onPreparedResult: continueVerificationIfNeeded,
                onPageStateChange: handlePageStateChange(_:)
            )
            .frame(minWidth: 900, minHeight: 620)
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
        .frame(minWidth: 960, minHeight: 760)
        .onDisappear {
            autoContinueTask?.cancel()
        }
    }

    private func handlePageStateChange(_ state: CNKIMetadataProvider.PageResolutionState) {
        pageState = state
        autoContinueTask?.cancel()
        guard state.isReady, !hasIssuedContinue else { return }
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
        case .resolvedSearch, .resolvedDetail:
            return "已检测到知网页面恢复正常，正在自动继续；如果没有自动关闭，也可以手动点“继续检查”。"
        case .blocked:
            return "页面仍处于知网验证或登录拦截状态。请先在这个窗口中完成验证，并保持当前搜索结果页或目标详情页打开。"
        case .loadingOrUnknown:
            return session.message
        }
    }
}

private struct CNKIVerificationWebView: NSViewRepresentable {
    let url: URL
    var configure: (WKWebViewConfiguration) -> Void
    var prepareResultIfPossible: @MainActor (WKWebView) async -> Bool
    var pageState: @MainActor (WKWebView) async -> CNKIMetadataProvider.PageResolutionState
    var onPreparedResult: @MainActor () -> Void
    var onPageStateChange: (CNKIMetadataProvider.PageResolutionState) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        HiddenWKWebViewMediaGuard.configure(configuration)
        configure(configuration)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = ReaderExtractionManager.safariLikeUserAgent
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard nsView.url?.absoluteString != url.absoluteString else { return }
        nsView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            prepareResultIfPossible: prepareResultIfPossible,
            pageState: pageState,
            onPreparedResult: onPreparedResult,
            onPageStateChange: onPageStateChange
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let prepareResultIfPossible: @MainActor (WKWebView) async -> Bool
        private let pageState: @MainActor (WKWebView) async -> CNKIMetadataProvider.PageResolutionState
        private let onPreparedResult: @MainActor () -> Void
        private let onPageStateChange: (CNKIMetadataProvider.PageResolutionState) -> Void
        weak var webView: WKWebView?

        init(
            prepareResultIfPossible: @escaping @MainActor (WKWebView) async -> Bool,
            pageState: @escaping @MainActor (WKWebView) async -> CNKIMetadataProvider.PageResolutionState,
            onPreparedResult: @escaping @MainActor () -> Void,
            onPageStateChange: @escaping (CNKIMetadataProvider.PageResolutionState) -> Void
        ) {
            self.prepareResultIfPossible = prepareResultIfPossible
            self.pageState = pageState
            self.onPreparedResult = onPreparedResult
            self.onPageStateChange = onPageStateChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                let prepared = await prepareResultIfPossible(webView)
                if prepared {
                    onPageStateChange(.resolvedDetail)
                    onPreparedResult()
                    return
                }
                onPageStateChange(await pageState(webView))
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onPageStateChange(.loadingOrUnknown)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onPageStateChange(.loadingOrUnknown)
        }
    }
}
