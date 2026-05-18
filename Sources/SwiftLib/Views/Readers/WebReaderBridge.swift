import SwiftUI
import WebKit
import SwiftLibCore

struct WebReaderContentView: NSViewRepresentable {
    @ObservedObject var viewModel: WebReaderViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "selectionChanged")
        controller.add(context.coordinator, name: "selectionCleared")
        controller.add(context.coordinator, name: "annotationActivated")
        controller.add(context.coordinator, name: "summarySectionClicked")
        controller.add(context.coordinator, name: "youtubeSeek")
        controller.add(context.coordinator, name: "SwiftLibClipperDebug")
        controller.add(context.coordinator.extractionManager, name: ReaderExtractionManager.readerResultHandlerName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = ReaderExtractionManager.safariLikeUserAgent
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false

        DispatchQueue.main.async {
            Self.applyElegantScrollers(to: webView)
        }

        context.coordinator.webView = webView
        context.coordinator.extractionManager.hostWebView = webView
        context.coordinator.bind(to: viewModel)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.bind(to: viewModel)

        if viewModel.shouldLoadOriginalURLForReadable,
           viewModel.displayMode == .liveReadable,
           let urlString = viewModel.reference.resolvedWebReaderURLString(),
           let pageURL = URL(string: urlString) {
            viewModel.acknowledgeOriginalURLLoadStarted()
            context.coordinator.extractionManager.resetForNewNavigation()
            context.coordinator.awaitingReadableExtraction = true
            context.coordinator.lastLoadedHTML = ""
            nsView.stopLoading()
            nsView.load(URLRequest(url: pageURL))
            return
        }

        // 在线阅读抽取进行中，不要用 loadHTMLString 覆盖正在加载原文的 WKWebView
        if viewModel.displayMode == .liveReadable,
           viewModel.isLiveReadableBusy || context.coordinator.awaitingReadableExtraction {
            return
        }

        if context.coordinator.lastLoadedHTML != viewModel.renderedHTML {
            context.coordinator.awaitingReadableExtraction = false
            context.coordinator.lastLoadedHTML = viewModel.renderedHTML
            nsView.loadHTMLString(viewModel.renderedHTML, baseURL: URL(string: referenceBaseURL))
        } else {
            context.coordinator.pushAppearance()
            context.coordinator.pushAnnotations()
        }
    }

    static func applyElegantScrollers(to view: NSView) {
        view.applySwiftLibElegantScrollersRecursively(forceVerticalScroller: true)
    }

    private var referenceBaseURL: String {
        if let url = viewModel.reference.resolvedWebReaderURLString(), !url.isEmpty {
            return url
        }
        return "http://127.0.0.1:23858/"
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebReaderContentView
        weak var webView: WKWebView?
        var lastLoadedHTML = ""
        /// 刚通过 `load(URLRequest)` 打开原文，等待 `didFinish` 后跑 Defuddle / Readability 抽取。
        var awaitingReadableExtraction = false

        let extractionManager = ReaderExtractionManager()

        init(parent: WebReaderContentView) {
            self.parent = parent
        }

        func bind(to viewModel: WebReaderViewModel) {
            extractionManager.isLiveReadableBusyContext = { [weak self] in
                guard let self else { return false }
                let vm = self.parent.viewModel
                return vm.displayMode == .liveReadable && vm.isLiveReadableBusy
            }
            extractionManager.onDefuddleSuccess = { [weak self] title, content, excerpt, byline in
                guard let self else { return }
                let vm = self.parent.viewModel
                Task { @MainActor in
                    vm.applyReadableExtractionResult(
                        title: title,
                        contentHTML: content,
                        excerpt: excerpt,
                        byline: byline,
                        includeClipperTypography: true,
                        eyebrowText: "在线阅读 · Defuddle"
                    )
                }
            }
            extractionManager.onReadabilitySuccess = { [weak self] title, content, excerpt, byline in
                guard let self else { return }
                let vm = self.parent.viewModel
                Task { @MainActor in
                    vm.applyReadableExtractionResult(
                        title: title,
                        contentHTML: content,
                        excerpt: excerpt,
                        byline: byline,
                        includeClipperTypography: false,
                        eyebrowText: "在线阅读"
                    )
                }
            }
            extractionManager.onYouTubeFallbackSuccess = { [weak self] title, content, excerpt, byline in
                guard let self else { return }
                let vm = self.parent.viewModel
                Task { @MainActor in
                    vm.applyReadableExtractionResult(
                        title: title,
                        contentHTML: content,
                        excerpt: excerpt,
                        byline: byline,
                        includeClipperTypography: false,
                        eyebrowText: "在线阅读 · YouTube"
                    )
                }
            }
            extractionManager.onTerminalFailure = { [weak self] message in
                guard let self else { return }
                let vm = self.parent.viewModel
                Task { @MainActor in
                    vm.readableExtractionFailed(message: message)
                }
            }

            viewModel.resetLiveReadableNavigation = { [weak self] in
                self?.awaitingReadableExtraction = false
                self?.webView?.stopLoading()
            }
            viewModel.jumpToSummaryInWeb = { [weak self] in
                self?.evaluate("window.SwiftLibReader && window.SwiftLibReader.scrollToSummary();")
            }
            viewModel.clearSelectionInView = { [weak self] in
                self?.evaluate("window.SwiftLibReader && window.SwiftLibReader.clearSelection();")
            }
            viewModel.jumpToAnnotationInView = { [weak self] annotation in
                guard let id = annotation.id else { return }
                self?.evaluate("window.SwiftLibReader && window.SwiftLibReader.scrollToAnnotation(\(id));")
            }
            viewModel.updateAppearanceInView = { [weak self] fontSize, contentWidth in
                self?.pushAppearance(fontSize: fontSize, contentWidth: contentWidth)
            }
            viewModel.refreshAnnotationsInView = { [weak self] annotations in
                self?.pushAnnotations(annotations: annotations)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if awaitingReadableExtraction {
                awaitingReadableExtraction = false
                let vm = parent.viewModel
                let pageURL = webView.url?.absoluteString ?? "(nil)"
                onlineReadableLog.notice("WK didFinish url=\(pageURL, privacy: .public) — 即将注入 Defuddle 抽取（非 reader.ts Reader.apply）")
                let urlForYouTubeCheck = webView.url?.absoluteString ?? vm.reference.resolvedWebReaderURLString() ?? ""
                if Reference.isLikelyYouTubeWatchURL(urlString: urlForYouTubeCheck) {
                    // YouTube 为 SPA：`didFinish` 时常早于标题/说明注入 DOM，立刻抽取易失败。
                    onlineReadableLog.notice("YouTube：延迟 2.5s 再抽取（reader.ts 里的 embed/Referer 逻辑依赖扩展，此处不会执行）")
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        guard let self else { return }
                        guard self.parent.viewModel.displayMode == .liveReadable,
                              self.parent.viewModel.isLiveReadableBusy else { return }
                        self.extractionManager.isYouTubeExtractionContext = true
                        self.extractionManager.runOnlineArticleExtraction(from: webView)
                    }
                } else {
                    extractionManager.isYouTubeExtractionContext = false
                    extractionManager.runOnlineArticleExtraction(from: webView)
                }
                return
            }
            pushAppearance()
            pushAnnotations()
            WebReaderContentView.applyElegantScrollers(to: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finishLiveReadableWithFailureIfNeeded(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finishLiveReadableWithFailureIfNeeded(error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Task { @MainActor in
                let vm = parent.viewModel
                guard vm.displayMode == .liveReadable, vm.isLiveReadableBusy else { return }
                awaitingReadableExtraction = false
                vm.readableExtractionFailed(message: "网页进程已终止，请重试或改用「剪藏正文」。")
            }
        }

        private func finishLiveReadableWithFailureIfNeeded(_ message: String) {
            awaitingReadableExtraction = false
            Task { @MainActor in
                let vm = self.parent.viewModel
                guard vm.displayMode == .liveReadable, vm.isLiveReadableBusy else { return }
                vm.readableExtractionFailed(message: "页面加载失败：\(message)")
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "selectionChanged":
                guard let body = message.body as? [String: Any] else { return }
                let rect = Self.parseViewportRect(from: body["rect"])
                let selection = WebSelectionSnapshot(
                    text: body["text"] as? String ?? "",
                    prefixText: body["prefixText"] as? String ?? "",
                    suffixText: body["suffixText"] as? String ?? "",
                    viewportSelectionRect: rect
                )
                let viewportSize = webView?.bounds.size ?? .zero
                Task { @MainActor in
                    parent.viewModel.stageSelection(selection, viewportSize: viewportSize)
                }
            case "selectionCleared":
                Task { @MainActor in
                    parent.viewModel.clearSelection(clearViewSelection: false)
                }
            case "annotationActivated":
                guard let body = message.body as? [String: Any],
                      let id = body["id"] as? Int64 ?? (body["id"] as? NSNumber)?.int64Value,
                      let annotation = parent.viewModel.annotations.first(where: { $0.id == id }) else { return }
                // Extract the click rect sent from JS
                func cgFloat(_ key: String, fallback: CGFloat) -> CGFloat {
                    if let v = body[key] as? Double { return CGFloat(v) }
                    if let v = body[key] as? NSNumber { return CGFloat(v.doubleValue) }
                    return fallback
                }
                let clickRect = CGRect(
                    x: cgFloat("rectX", fallback: 0),
                    y: cgFloat("rectY", fallback: 0),
                    width: cgFloat("rectW", fallback: 100),
                    height: cgFloat("rectH", fallback: 20)
                )
                let viewportSize = message.webView?.bounds.size ?? CGSize(width: 800, height: 600)
                Task { @MainActor in
                    parent.viewModel.highlightSidebarSummary = false
                    parent.viewModel.selectedAnnotationId = annotation.id
                    parent.viewModel.clearSelection(clearViewSelection: false)
                    parent.viewModel.presentAnnotationToolbar(
                        for: annotation,
                        anchorRect: clickRect,
                        viewportSize: viewportSize
                    )
                }
            case "summarySectionClicked":
                Task { @MainActor in
                    parent.viewModel.onArticleSummaryTapped()
                }
            case "youtubeSeek":
                let body = message.body as? [String: Any]
                let sec: Int = {
                    if let i = body?["seconds"] as? Int { return i }
                    if let n = body?["seconds"] as? NSNumber { return n.intValue }
                    return 0
                }()
                Task { @MainActor in
                    parent.viewModel.seekYouTubeTo(seconds: max(0, sec))
                }
            case "SwiftLibClipperDebug":
                if let dict = message.body as? [String: Any] {
                    let phase = dict["phase"] as? String ?? "?"
                    let url = dict["url"] as? String ?? ""
                    let detail = dict["detail"] as? String ?? String(describing: dict["extra"] ?? "")
                    onlineReadableLog.notice("[JS] \(phase, privacy: .public) url=\(url, privacy: .public) \(detail, privacy: .public)")
                } else {
                    onlineReadableLog.notice("[JS] \(String(describing: message.body), privacy: .public)")
                }
            default:
                break
            }
        }

        func pushAppearance() {
            pushAppearance(fontSize: parent.viewModel.fontSize, contentWidth: parent.viewModel.contentWidth)
        }

        func pushAppearance(fontSize: Double, contentWidth: CGFloat) {
            evaluate("window.SwiftLibReader && window.SwiftLibReader.updateAppearance(\(fontSize), \(Int(contentWidth)));")
        }

        func pushAnnotations() {
            pushAnnotations(annotations: parent.viewModel.annotations)
        }

        func pushAnnotations(annotations: [WebAnnotationRecord]) {
            guard let data = try? JSONEncoder().encode(annotations),
                  let json = String(data: data, encoding: .utf8) else { return }
            evaluate("window.SwiftLibReader && window.SwiftLibReader.setAnnotations(\(json));")
        }

        private func evaluate(_ script: String) {
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        /// 解析内嵌脚本 `rect: { left, top, width, height }`（`WKScriptMessage` 中数字多为 `NSNumber`）。
        private static func parseViewportRect(from value: Any?) -> CGRect? {
            guard let dict = value as? [String: Any] else { return nil }
            let left = CGFloat((dict["left"] as? NSNumber)?.doubleValue ?? 0)
            let top = CGFloat((dict["top"] as? NSNumber)?.doubleValue ?? 0)
            let width = CGFloat((dict["width"] as? NSNumber)?.doubleValue ?? 0)
            let height = CGFloat((dict["height"] as? NSNumber)?.doubleValue ?? 0)
            guard width >= 1, height >= 1 else { return nil }
            return CGRect(x: left, y: top, width: width, height: height)
        }
    }
}

