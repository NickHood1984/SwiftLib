import SwiftUI
import WebKit
import Combine
import AppKit
import OSLog
import SwiftLibCore

/// 在线阅读流水线日志：在「控制台」App 中过滤子系统 `SwiftLib`、类别 `OnlineReadable`；用于核对「并未调用浏览器里的 reader.js / Reader.apply」。
private let onlineReadableLog = Logger(subsystem: "SwiftLib", category: "OnlineReadable")

// MARK: - 阅读模式（剪藏 Markdown / 在线 Defuddle + Readability 回退）

enum WebReaderDisplayMode: String, CaseIterable {
    /// 使用条目中的剪藏 Markdown（当前默认行为）
    case clippedMarkdown = "剪藏正文"
    /// 打开解析后的原文 URL（`resolvedWebReaderURLString()`）：优先 Defuddle 抽取并套用 Clipper reader 样式；失败则回退 Readability
    case liveReadable = "在线阅读"
}

struct WebSelectionSnapshot: Equatable {
    var text: String
    var prefixText: String
    var suffixText: String
    /// 选区在网页视口内的矩形（与 `getBoundingClientRect()` 一致，原点在左上）。
    var viewportSelectionRect: CGRect?
}

@MainActor
final class WebReaderViewModel: ObservableObject {
    @Published var annotations: [WebAnnotationRecord] = []
    @Published var currentColorHex: String = "#FFDE59"
    @Published var selectedAnnotationId: Int64?
    @Published var showNoteEditor = false
    @Published var pendingNoteText = ""
    @Published var pendingSelection: WebSelectionSnapshot?
    @Published var selectionToolbarLayout: SelectionToolbarLayout?
    /// When set, shows a note-edit sheet for an existing annotation.
    @Published var editingAnnotationInPlace: WebAnnotationRecord?
    /// When set, shows an annotation action toolbar near the clicked highlight.
    @Published var clickedAnnotationRecord: WebAnnotationRecord?
    @Published var annotationToolbarLayout: SelectionToolbarLayout?
    @Published var renderedHTML = ""
    @Published var isRendering = false
    @Published var fontSize: Double = 18
    @Published var contentWidth: CGFloat = 860
    @Published var displayMode: WebReaderDisplayMode = .clippedMarkdown
    @Published var isLiveReadableBusy = false
    @Published var liveReadableUserMessage: String?
    /// 为 true 时 `WebReaderContentView` 下一次更新会发起对原文 URL 的导航以便抽取正文。
    private(set) var shouldLoadOriginalURLForReadable = false
    /// 递增以触发侧栏滚动到「摘要」卡片（正文内摘要被点击时）。
    @Published var sidebarSummaryScrollToken: UInt64 = 0
    /// 侧栏摘要卡片是否处于「正文摘要已点击」高亮。
    @Published var highlightSidebarSummary: Bool = false
    /// 非 nil 时由顶部原生 WKWebView 加载该 YouTube 观看页 URL（含可选 `t=` 跳转）。
    @Published private(set) var youTubeInlineWatchURL: URL?

    let reference: Reference
    private let db: AppDatabase
    private var cancellables = Set<AnyCancellable>()
    /// 在线阅读整段流程（加载原文 + 注入脚本 + 抽取 + 组 HTML）防挂起超时。
    private var liveReadableSafetyTask: Task<Void, Never>?
    private var transcriptLoadTasks: [Task<Void, Never>] = []
    private var transcriptLoadState: TranscriptLoadState?
    private var transcriptLoadSequence: UInt64 = 0
    private var currentArticleBodyHTML: String?
    private var shouldPersistTranscriptIntoReference = false
    /// Debounce task for appearance changes (font size / content width).
    private var appearanceDebounceTask: Task<Void, Never>?
    private var currentViewportSize: CGSize = .zero
    private var annotationToolbarAnchorRect: CGRect?
    var fetchTranscriptFromOriginalPage: ((String) async -> String?)?

    var jumpToAnnotationInView: ((WebAnnotationRecord) -> Void)?
    var jumpToSummaryInWeb: (() -> Void)?
    /// 停止正在进行的原文加载 / Readability 流程（切回「剪藏正文」时调用）。
    var resetLiveReadableNavigation: (() -> Void)?
    var clearSelectionInView: (() -> Void)?
    var updateAppearanceInView: ((Double, CGFloat) -> Void)?
    var refreshAnnotationsInView: (([WebAnnotationRecord]) -> Void)?

    /// 用户点击缩略图「播放」后加载整页 watch；字幕时间戳通过 `seekYouTubeTo` 更新 URL。
    func activateYouTubeInlinePlayer() {
        guard reference.youTubeVideoId != nil else { return }
        youTubeInlineWatchURL = Self.makeYouTubeWatchURL(for: reference, atSeconds: nil)
    }

    func collapseYouTubeInlinePlayer() {
        youTubeInlineWatchURL = nil
    }

    func seekYouTubeTo(seconds: Int) {
        guard reference.youTubeVideoId != nil else { return }
        youTubeInlineWatchURL = Self.makeYouTubeWatchURL(for: reference, atSeconds: max(0, seconds))
    }

    private static func makeYouTubeWatchURL(for reference: Reference, atSeconds seconds: Int?) -> URL? {
        guard let vid = reference.youTubeVideoId else { return nil }
        var components = URLComponents(string: "https://www.youtube.com/watch")
        var items: [URLQueryItem] = [URLQueryItem(name: "v", value: vid)]
        if let s = seconds, s > 0 {
            items.append(URLQueryItem(name: "t", value: "\(s)s"))
        }
        components?.queryItems = items
        return components?.url
    }

    private enum TranscriptLoadSource: Hashable {
        case network
        case dom
    }

    private struct TranscriptLoadState {
        let sequence: UInt64
        var pendingSources: Set<TranscriptLoadSource>
        var failures: [TranscriptLoadSource: String]
        var resolved: Bool
    }

    init(reference: Reference, db: AppDatabase = .shared) {
        self.reference = reference
        self.db = db
        observeAnnotations()
        let clipEmpty = reference.decodedWebContent == nil
        let urlStr = reference.resolvedWebReaderURLString()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let canLiveRead = reference.referenceType == .webpage && clipEmpty && !urlStr.isEmpty && URL(string: urlStr) != nil
        if canLiveRead {
            displayMode = .liveReadable
            shouldLoadOriginalURLForReadable = true
            isLiveReadableBusy = true
            scheduleLiveReadableSafetyTimeout()
            renderedHTML = Self.emptyDocument(title: reference.title)
        } else {
            renderContent()
        }
    }

    var allowsDisplayModeSwitching: Bool {
        reference.referenceType == .webpage && !reference.isLikelyYouTubeWatchURL
    }

    var hasSelection: Bool {
        !(pendingSelection?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func stageSelection(_ selection: WebSelectionSnapshot?, viewportSize: CGSize) {
        currentViewportSize = viewportSize
        dismissAnnotationToolbar()
        guard let selection else {
            pendingSelection = nil
            selectionToolbarLayout = nil
            return
        }

        let trimmed = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pendingSelection = nil
            selectionToolbarLayout = nil
            return
        }

        pendingSelection = WebSelectionSnapshot(
            text: trimmed,
            prefixText: selection.prefixText,
            suffixText: selection.suffixText,
            viewportSelectionRect: selection.viewportSelectionRect
        )
        selectionToolbarLayout = Self.toolbarLayout(
            viewportSelectionRect: selection.viewportSelectionRect,
            viewportSize: viewportSize,
            fallbackToTop: true
        )
    }

    func updateViewportSize(_ viewportSize: CGSize) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        guard viewportSize != currentViewportSize else { return }

        currentViewportSize = viewportSize

        if let pendingSelection {
            selectionToolbarLayout = Self.toolbarLayout(
                viewportSelectionRect: pendingSelection.viewportSelectionRect,
                viewportSize: viewportSize,
                fallbackToTop: true
            )
        }

        if clickedAnnotationRecord != nil {
            annotationToolbarLayout = Self.toolbarLayout(
                viewportSelectionRect: annotationToolbarAnchorRect,
                viewportSize: viewportSize
            )
        }
    }

    func presentAnnotationToolbar(for annotation: WebAnnotationRecord, anchorRect: CGRect, viewportSize: CGSize) {
        currentViewportSize = viewportSize
        annotationToolbarAnchorRect = anchorRect
        clickedAnnotationRecord = annotation
        annotationToolbarLayout = Self.toolbarLayout(
            viewportSelectionRect: anchorRect,
            viewportSize: viewportSize
        )
    }

    func clearSelection(clearViewSelection: Bool = true) {
        pendingSelection = nil
        selectionToolbarLayout = nil
        dismissAnnotationToolbar()
        if clearViewSelection {
            clearSelectionInView?()
        }
    }

    func applySelectionAction(_ type: AnnotationType) {
        guard let pendingSelection else { return }

        if type == .note {
            pendingNoteText = ""
            showNoteEditor = true
            return
        }

        addAnnotation(type: type, selection: pendingSelection, noteText: nil)
        clearSelection()
    }

    func commitPendingNote() {
        guard let pendingSelection else { return }
        let trimmed = pendingNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        addAnnotation(type: .note, selection: pendingSelection, noteText: trimmed)
        pendingNoteText = ""
        showNoteEditor = false
        clearSelection()
    }

    func cancelPendingNote() {
        pendingNoteText = ""
        showNoteEditor = false
    }

    func deleteAnnotation(_ annotation: WebAnnotationRecord) {
        guard let id = annotation.id else { return }
        try? db.deleteWebAnnotation(id: id)
    }

    func updateAnnotationNote(_ annotation: WebAnnotationRecord, noteText: String) {
        var updated = annotation
        updated.noteText = noteText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        try? db.saveWebAnnotation(&updated)
    }

    func updateAnnotationColor(_ annotation: WebAnnotationRecord, color: String) {
        var updated = annotation
        updated.color = color
        try? db.saveWebAnnotation(&updated)
    }

    func dismissAnnotationToolbar() {
        clickedAnnotationRecord = nil
        annotationToolbarLayout = nil
        annotationToolbarAnchorRect = nil
    }

    func navigateTo(_ annotation: WebAnnotationRecord) {
        selectedAnnotationId = annotation.id
        highlightSidebarSummary = false
        jumpToAnnotationInView?(annotation)
    }

    /// 侧栏摘要卡片点击：滚动正文到摘要块。
    func scrollArticleToSummary() {
        highlightSidebarSummary = false
        jumpToSummaryInWeb?()
    }

    /// 正文内摘要区域被点击：侧栏滚到摘要卡片并高亮。
    func onArticleSummaryTapped() {
        selectedAnnotationId = nil
        highlightSidebarSummary = true
        sidebarSummaryScrollToken &+= 1
    }

    var hasSidebarSummary: Bool {
        let a = reference.abstract?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !a.isEmpty
    }

    func setDisplayMode(_ mode: WebReaderDisplayMode) {
        guard mode != displayMode else { return }
        liveReadableUserMessage = nil
        displayMode = mode
        switch mode {
        case .clippedMarkdown:
            cancelTranscriptLoad()
            cancelLiveReadableSafetyTimeout()
            shouldLoadOriginalURLForReadable = false
            isLiveReadableBusy = false
            resetLiveReadableNavigation?()
            renderContent()
        case .liveReadable:
            let u = reference.resolvedWebReaderURLString() ?? ""
            guard !u.isEmpty, URL(string: u) != nil else {
                liveReadableUserMessage = "没有可用于在线阅读的有效链接。"
                displayMode = .clippedMarkdown
                return
            }
            shouldLoadOriginalURLForReadable = true
            isLiveReadableBusy = true
            scheduleLiveReadableSafetyTimeout()
            let host = URL(string: u)?.host ?? ""
            onlineReadableLog.notice("开始在线阅读 host=\(host, privacy: .public) youtube=\(self.reference.isLikelyYouTubeWatchURL, privacy: .public) — 使用内置 ClipperDefuddle.js，非扩展的 reader-script / Reader.apply")
        }
    }

    private func scheduleLiveReadableSafetyTimeout() {
        liveReadableSafetyTask?.cancel()
        let seconds: UInt64 = 90
        liveReadableSafetyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard displayMode == .liveReadable, isLiveReadableBusy else { return }
            readableExtractionFailed(message: "加载或提取正文超时（约 \(seconds) 秒）。请检查网络、页面是否需登录，或改用「剪藏正文」。")
        }
    }

    private func cancelLiveReadableSafetyTimeout() {
        liveReadableSafetyTask?.cancel()
        liveReadableSafetyTask = nil
    }

    /// 由 Coordinator 在开始加载原文 URL 后调用，避免重复触发导航。
    func acknowledgeOriginalURLLoadStarted() {
        shouldLoadOriginalURLForReadable = false
    }

    func readableExtractionFailed(message: String) {
        cancelTranscriptLoad()
        cancelLiveReadableSafetyTimeout()
        isLiveReadableBusy = false
        liveReadableUserMessage = message
        onlineReadableLog.error("在线阅读失败: \(message, privacy: .public)")
        displayMode = .clippedMarkdown
        renderContent()
    }

    func applyReadableExtractionResult(
        title: String?,
        contentHTML: String,
        excerpt: String?,
        byline: String?,
        includeClipperTypography: Bool,
        eyebrowText: String = "在线阅读"
    ) {
        cancelTranscriptLoad()
        var trimmed = contentHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            readableExtractionFailed(message: "在线阅读失败：提取结果为空。")
            return
        }

        isLiveReadableBusy = true
        let ref = reference
        let fs = fontSize
        let cw = contentWidth

        let isYouTube = ref.youTubeVideoId != nil
        // 对 YouTube 条目，清掉抽取结果里的旧播放器/封面/摘要块，只保留正文与字幕。
        if isYouTube {
            trimmed = Self.cleanedYouTubeArticleBodyHTML(trimmed)
        }

        let finalBody = trimmed

        Task.detached(priority: .userInitiated) {
            let html = Self.buildHTMLDocument(
                reference: ref,
                articleBodyHTML: finalBody,
                fontSize: fs,
                contentWidth: cw,
                eyebrowText: eyebrowText,
                headerTitle: title,
                // YouTube：header 不用条目 abstract（正文已有描述），见 omitReferenceAbstract
                summaryText: isYouTube ? nil : excerpt,
                authorOverride: byline,
                includeClipperTypography: includeClipperTypography,
                omitReferenceAbstract: isYouTube,
                omitArticleHeader: isYouTube
            )
            await MainActor.run {
                self.currentArticleBodyHTML = finalBody
                self.shouldPersistTranscriptIntoReference = ref.decodedWebContent?.format == .html
                self.renderedHTML = html
                self.isLiveReadableBusy = false
                self.cancelLiveReadableSafetyTimeout()
                if let vid = ref.youTubeVideoId {
                    self.scheduleYouTubeTranscriptMerge(videoId: vid)
                }
            }
        }
    }

    /// 异步拉取 YouTube 字幕并插入到已渲染的 HTML 中。
    private func scheduleYouTubeTranscriptMerge(videoId: String) {
        cancelTranscriptLoad()
        if Self.htmlContainsRenderedTranscriptBlock(renderedHTML) {
            onlineReadableLog.notice("YouTube 字幕已存在于页内 fallback，跳过网络抓取 vid=\(videoId)")
            return
        }
        // 先插入"正在加载字幕"占位符
        if let placeholder = Self.htmlInsertingYouTubeTranscriptPlaceholder(renderedHTML) {
            renderedHTML = placeholder
        }

        transcriptLoadSequence &+= 1
        let sequence = transcriptLoadSequence
        var pendingSources: Set<TranscriptLoadSource> = [.network]
        if canAttemptTranscriptDOMFallback {
            pendingSources.insert(.dom)
        }
        transcriptLoadState = TranscriptLoadState(
            sequence: sequence,
            pendingSources: pendingSources,
            failures: [:],
            resolved: false
        )

        let networkTask = Task(priority: .utility) { [weak self] in
            let result = await YouTubeTranscriptFetcher.fetchPlainText(videoId: videoId)
            guard let self else { return }
            self.handleNetworkTranscriptResult(result, videoId: videoId, sequence: sequence)
        }
        transcriptLoadTasks.append(networkTask)

        if canAttemptTranscriptDOMFallback {
            let domTask = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                let transcript = await self.fetchTranscriptDOMFallbackText(videoId: videoId)
                self.handleDOMTranscriptResult(transcript, videoId: videoId, sequence: sequence)
            }
            transcriptLoadTasks.append(domTask)
        }

        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.transcriptLoadTimeoutNanoseconds)
            self?.handleTranscriptLoadTimeout(videoId: videoId, sequence: sequence)
        }
        transcriptLoadTasks.append(timeoutTask)
    }

    private var canAttemptTranscriptDOMFallback: Bool {
        reference.isLikelyYouTubeWatchURL
            && reference.resolvedWebReaderURLString() != nil
            && fetchTranscriptFromOriginalPage != nil
    }

    private func fetchTranscriptDOMFallbackText(videoId: String) async -> String? {
        guard reference.isLikelyYouTubeWatchURL,
              let urlString = reference.resolvedWebReaderURLString(),
              let fetcher = fetchTranscriptFromOriginalPage else {
            return nil
        }

        onlineReadableLog.notice("并行启动隐藏 WKWebView transcript DOM fallback vid=\(videoId, privacy: .public)")
        guard let transcript = await fetcher(urlString) else {
            return nil
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func handleNetworkTranscriptResult(
        _ result: Result<String, Error>,
        videoId: String,
        sequence: UInt64
    ) {
        guard let state = transcriptLoadState,
              state.sequence == sequence,
              !state.resolved else {
            return
        }

        switch result {
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                onlineReadableLog.notice("YouTube 网络字幕为空 vid=\(videoId, privacy: .public)")
                recordTranscriptFailure(
                    source: .network,
                    message: "该视频字幕内容为空。",
                    sequence: sequence
                )
                return
            }
            onlineReadableLog.notice("YouTube 网络字幕成功 vid=\(videoId, privacy: .public) length=\(trimmed.count, privacy: .public)")
            completeTranscriptLoad(with: trimmed, source: .network, videoId: videoId, sequence: sequence)
        case .failure(let error):
            let msg = (error as? YouTubeTranscriptFetcher.FetchError)?.errorDescription ?? error.localizedDescription
            onlineReadableLog.error("YouTube 网络字幕失败 vid=\(videoId, privacy: .public) error=\(msg, privacy: .public)")
            recordTranscriptFailure(source: .network, message: msg, sequence: sequence)
        }
    }

    private func handleDOMTranscriptResult(_ transcript: String?, videoId: String, sequence: UInt64) {
        guard let state = transcriptLoadState,
              state.sequence == sequence,
              !state.resolved else {
            return
        }

        guard let transcript else {
            onlineReadableLog.notice("YouTube transcript DOM fallback 未返回内容 vid=\(videoId, privacy: .public)")
            recordTranscriptFailure(
                source: .dom,
                message: "页面 transcript 面板未返回内容。",
                sequence: sequence
            )
            return
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onlineReadableLog.notice("YouTube transcript DOM fallback 返回空字幕 vid=\(videoId, privacy: .public)")
            recordTranscriptFailure(
                source: .dom,
                message: "页面 transcript 面板未返回内容。",
                sequence: sequence
            )
            return
        }

        onlineReadableLog.notice("YouTube transcript DOM fallback 成功 vid=\(videoId, privacy: .public) length=\(trimmed.count, privacy: .public)")
        completeTranscriptLoad(with: trimmed, source: .dom, videoId: videoId, sequence: sequence)
    }

    private func completeTranscriptLoad(
        with transcript: String,
        source: TranscriptLoadSource,
        videoId: String,
        sequence: UInt64
    ) {
        guard var state = transcriptLoadState,
              state.sequence == sequence,
              !state.resolved else {
            return
        }

        state.resolved = true
        state.pendingSources.removeAll()
        transcriptLoadState = state
        cancelTranscriptLoadTasks()

        let lines = transcript.components(separatedBy: "\n")
        var htmlLines: [String] = []
        for line in lines {
            let escaped = line
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            if let range = escaped.range(of: #"^\[(\d{2}):(\d{2})\]"#, options: .regularExpression) {
                let timestamp = String(escaped[range])
                let rest = String(escaped[range.upperBound...])
                let digits = timestamp.filter { $0.isNumber }
                if digits.count == 4 {
                    let mm = Int(digits.prefix(2)) ?? 0
                    let ss = Int(digits.suffix(2)) ?? 0
                    let totalSeconds = mm * 60 + ss
                    let link = "<a href=\"javascript:void(0)\" class=\"swiftlib-yt-ts\" data-time=\"\(totalSeconds)\" onclick=\"window.SwiftLibReader && window.SwiftLibReader.seekYouTube(\(totalSeconds))\">\(timestamp)</a>"
                    htmlLines.append("<span class=\"swiftlib-yt-line\">\(link)\(rest)</span>")
                    continue
                }
            }
            htmlLines.append("<span class=\"swiftlib-yt-line\">\(escaped)</span>")
        }
        let transcriptHTML = htmlLines.joined(separator: "\n")
        let block = "<details class=\"swiftlib-yt-transcript\" open><summary>字幕 / Transcript</summary><div class=\"swiftlib-yt-transcript-body\">\(transcriptHTML)</div></details>"
        replaceTranscriptPlaceholder(with: block, isHTML: true)
        if let bodyHTML = currentArticleBodyHTML,
           !Self.htmlContainsRenderedTranscriptBlock(bodyHTML) {
            let mergedBodyHTML = Self.htmlByAppendingHTMLBlockToArticle(bodyHTML, blockHTML: block)
            currentArticleBodyHTML = mergedBodyHTML
            persistTranscriptIntoStoredReferenceIfNeeded(mergedBodyHTML)
        }
        onlineReadableLog.notice("YouTube 字幕完成 source=\(String(describing: source), privacy: .public) vid=\(videoId, privacy: .public)")
    }

    private func recordTranscriptFailure(
        source: TranscriptLoadSource,
        message: String,
        sequence: UInt64
    ) {
        guard var state = transcriptLoadState,
              state.sequence == sequence,
              !state.resolved else {
            return
        }

        state.pendingSources.remove(source)
        state.failures[source] = message

        if state.pendingSources.isEmpty {
            state.resolved = true
            transcriptLoadState = state
            cancelTranscriptLoadTasks()
            replaceTranscriptPlaceholder(with: Self.transcriptFailureMessage(failures: state.failures))
            return
        }

        transcriptLoadState = state
    }

    private func handleTranscriptLoadTimeout(videoId: String, sequence: UInt64) {
        guard var state = transcriptLoadState,
              state.sequence == sequence,
              !state.resolved else {
            return
        }

        state.resolved = true
        transcriptLoadState = state
        cancelTranscriptLoadTasks()
        let message = Self.transcriptTimeoutMessage(failures: state.failures)
        onlineReadableLog.error("YouTube 字幕加载超时 vid=\(videoId, privacy: .public) message=\(message, privacy: .public)")
        replaceTranscriptPlaceholder(with: message)
    }

    private func cancelTranscriptLoad() {
        cancelTranscriptLoadTasks()
        transcriptLoadState = nil
    }

    private func cancelTranscriptLoadTasks() {
        transcriptLoadTasks.forEach { $0.cancel() }
        transcriptLoadTasks.removeAll()
    }

    nonisolated private static let transcriptPlaceholderId = "swiftlib-yt-transcript-loading"
    nonisolated private static let transcriptLoadTimeoutNanoseconds: UInt64 = 15_000_000_000

    nonisolated static func htmlContainsRenderedTranscriptBlock(_ html: String) -> Bool {
        html.contains("<details class=\"swiftlib-yt-transcript\"")
            || html.contains("<div id=\"\(transcriptPlaceholderId)\"")
    }

    private func persistTranscriptIntoStoredReferenceIfNeeded(_ articleBodyHTML: String) {
        guard shouldPersistTranscriptIntoReference,
              reference.youTubeVideoId != nil,
              let referenceID = reference.id,
              let encoded = Reference.encodeWebContent(articleBodyHTML, format: .html) else {
            return
        }

        let db = self.db
        Task.detached(priority: .utility) {
            do {
                try db.updateReferenceWebContent(id: referenceID, webContent: encoded)
            } catch {
                onlineReadableLog.error("缓存 YouTube 正文失败 refId=\(referenceID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func htmlInsertingYouTubeTranscriptPlaceholder(_ html: String) -> String? {
        let block = "<div id=\"\(transcriptPlaceholderId)\" class=\"swiftlib-yt-transcript\"><summary style=\"list-style:none;padding:10px 14px;font-size:14px;color:#6b7280;\">正在加载字幕…</summary></div>"
        guard let range = html.range(of: "</article>", options: .backwards) else { return nil }
        return String(html[..<range.lowerBound]) + block + String(html[range.lowerBound...])
    }

    private static func htmlByAppendingHTMLBlockToArticle(_ html: String, blockHTML: String) -> String {
        if let range = html.range(of: "</article>", options: .backwards) {
            return String(html[..<range.lowerBound]) + blockHTML + String(html[range.lowerBound...])
        }
        return html + blockHTML
    }

    nonisolated private static func transcriptFailureMessage(failures: [TranscriptLoadSource: String]) -> String {
        if let network = failures[.network]?.trimmingCharacters(in: .whitespacesAndNewlines), !network.isEmpty {
            return network
        }
        if let dom = failures[.dom]?.trimmingCharacters(in: .whitespacesAndNewlines), !dom.isEmpty {
            return dom
        }
        return "字幕不可用。"
    }

    nonisolated private static func transcriptTimeoutMessage(failures: [TranscriptLoadSource: String]) -> String {
        let base = "字幕加载超时，请稍后重试。"
        if let network = failures[.network]?.trimmingCharacters(in: .whitespacesAndNewlines), !network.isEmpty {
            return "\(base) 当前结果：\(network)"
        }
        return base
    }

    private func replaceTranscriptPlaceholder(with content: String, isHTML: Bool = false) {
        let placeholderId = Self.transcriptPlaceholderId
        guard let startRange = renderedHTML.range(of: "<div id=\"\(placeholderId)\"") else {
            // 占位符不在，直接在 </article> 前插入
            if isHTML {
                if let range = renderedHTML.range(of: "</article>", options: .backwards) {
                    renderedHTML = String(renderedHTML[..<range.lowerBound]) + content + String(renderedHTML[range.lowerBound...])
                }
            }
            return
        }
        // 找到占位符的结束 </div>
        let afterStart = renderedHTML[startRange.lowerBound...]
        guard let endRange = afterStart.range(of: "</div>") else { return }
        let fullRange = startRange.lowerBound..<endRange.upperBound

        if isHTML {
            renderedHTML.replaceSubrange(fullRange, with: content)
        } else {
            let escaped = content
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
            let errorBlock = "<div class=\"swiftlib-yt-transcript\"><summary style=\"list-style:none;padding:10px 14px;font-size:14px;color:#6b7280;\">字幕不可用：\(escaped)</summary></div>"
            renderedHTML.replaceSubrange(fullRange, with: errorBlock)
        }
    }

    func increaseFontSize() {
        fontSize = min(fontSize + 1, 26)
        notifyAppearanceChanged()
    }

    func decreaseFontSize() {
        fontSize = max(fontSize - 1, 13)
        notifyAppearanceChanged()
    }

    func narrowContent() {
        contentWidth = max(contentWidth - 60, 620)
        notifyAppearanceChanged()
    }

    func widenContent() {
        contentWidth = min(contentWidth + 60, 1200)
        notifyAppearanceChanged()
    }

    /// 与 PDF 选区工具栏相同的尺寸与上下优先策略（坐标为 SwiftUI 自上而下、视口与 WKWebView 对齐）。
    static func toolbarLayout(
        viewportSelectionRect: CGRect?,
        viewportSize: CGSize,
        fallbackToTop: Bool = false
    ) -> SelectionToolbarLayout? {
        let metrics = ReaderActionBarMetrics.resolve(for: .web, viewportWidth: viewportSize.width)
        return SelectionToolbarLayout.anchored(
            to: viewportSelectionRect,
            overlaySize: viewportSize,
            metrics: metrics,
            horizontalAnchor: .center,
            fallbackToTop: fallbackToTop
        )
    }

    private func observeAnnotations() {
        guard let refId = reference.id else { return }

        db.observeWebAnnotations(referenceId: refId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        onlineReadableLog.error("Web annotation observation failed: \(error.localizedDescription, privacy: .public)")
                    }
                },
                receiveValue: { [weak self] annotations in
                    guard let self else { return }
                    self.annotations = annotations
                    self.refreshAnnotationsInView?(annotations)
                }
            )
            .store(in: &cancellables)
    }

    func addAnnotation(type: AnnotationType, selection: WebSelectionSnapshot, noteText: String?) {
        guard let refId = reference.id else { return }
        var annotation = WebAnnotationRecord(
            referenceId: refId,
            type: type,
            selectedText: selection.text,
            noteText: noteText,
            color: currentColorHex,
            anchorText: selection.text,
            prefixText: selection.prefixText.nilIfBlank,
            suffixText: selection.suffixText.nilIfBlank
        )
        try? db.saveWebAnnotation(&annotation)
    }

    private func notifyAppearanceChanged() {
        // Debounce: wait 80 ms so rapid button taps are coalesced into one JS call.
        appearanceDebounceTask?.cancel()
        let fs = fontSize
        let cw = contentWidth
        appearanceDebounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 80_000_000) // 80 ms
            guard !Task.isCancelled else { return }
            self.updateAppearanceInView?(fs, cw)
        }
    }

    private func renderContent() {
        cancelTranscriptLoad()
        guard let storedContent = reference.decodedWebContent else {
            renderedHTML = Self.emptyDocument(title: reference.title)
            return
        }

        isRendering = true
        let reference = self.reference
        let fontSize = self.fontSize
        let contentWidth = self.contentWidth

        Task.detached(priority: .userInitiated) {
            let isYouTube = reference.youTubeVideoId != nil
            let includeClipperTypography = storedContent.format == .html
            let rawBodyHTML: String
            switch storedContent.format {
            case .markdown:
                rawBodyHTML = Self.renderedMarkdownHTML(
                    from: storedContent.body,
                    baseURL: reference.resolvedWebReaderURLString().flatMap(URL.init(string:))
                )
            case .html:
                rawBodyHTML = storedContent.body
            }

            let finalBodyHTML: String
            if reference.youTubeVideoId != nil {
                finalBodyHTML = Self.cleanedYouTubeArticleBodyHTML(rawBodyHTML)
            } else {
                finalBodyHTML = rawBodyHTML
            }

            let html = Self.buildHTMLDocument(
                reference: reference,
                articleBodyHTML: finalBodyHTML,
                fontSize: fontSize,
                contentWidth: contentWidth,
                eyebrowText: isYouTube ? "YouTube 剪藏" : "剪藏正文",
                includeClipperTypography: includeClipperTypography,
                omitReferenceAbstract: isYouTube,
                omitArticleHeader: isYouTube
            )
            await MainActor.run {
                self.currentArticleBodyHTML = finalBodyHTML
                self.shouldPersistTranscriptIntoReference = storedContent.format == .html
                self.renderedHTML = html
                self.isRendering = false
                if let vid = reference.youTubeVideoId {
                    self.scheduleYouTubeTranscriptMerge(videoId: vid)
                }
            }
        }
    }

    /// 合并 Obsidian Web Clipper 的 `reader.css` 与 `highlighter.css`（打包于 Resources）。
    nonisolated private static func bundledClipperReaderStyleBlock() -> String? {
        guard let urlR = Bundle.module.url(forResource: "ClipperReader", withExtension: "css"),
              let urlH = Bundle.module.url(forResource: "ClipperHighlighter", withExtension: "css"),
              let r = try? String(contentsOf: urlR, encoding: .utf8),
              let h = try? String(contentsOf: urlH, encoding: .utf8) else {
            return nil
        }
        return r + "\n" + h
    }

    /// - Parameters:
    ///   - articleBodyHTML: 已生成的 HTML 片段（Markdown 渲染结果或 Readability 的 `content`），不做 HTML 转义。
    ///   - headerTitle/summaryText/authorOverride: 在线阅读时可用抽取结果覆盖条目元数据展示。
    ///   - omitReferenceAbstract: 为 true 时头部摘要仅使用 `summaryText`（可为空），不回退到 `reference.abstract`（YouTube 正文已含描述）。
    ///   - includeClipperTypography: 为 true 时注入 Obsidian Clipper 的 `reader.css` / `highlighter.css` 及主题 class（与 Defuddle 在线阅读配套）。
    nonisolated private static func buildHTMLDocument(
        reference: Reference,
        articleBodyHTML: String,
        fontSize: Double,
        contentWidth: CGFloat,
        eyebrowText: String = "Web Article",
        headerTitle: String? = nil,
        summaryText: String? = nil,
        authorOverride: String? = nil,
        includeClipperTypography: Bool = false,
        omitReferenceAbstract: Bool = false,
        omitArticleHeader: Bool = false
    ) -> String {
        let rawHeaderTitle = (headerTitle ?? reference.title).trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = rawHeaderTitle.isEmpty ? reference.title : rawHeaderTitle
        let title = htmlEscape(displayTitle)

        let rawAuthor = authorOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = htmlEscape(rawAuthor.isEmpty ? reference.authors.displayString : rawAuthor)

        let rawSummary: String
        if omitReferenceAbstract {
            rawSummary = (summaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            rawSummary = (summaryText ?? reference.abstract ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let summary = htmlEscape(rawSummary)

        let siteRaw = (reference.siteName ?? reference.journal ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let urlRaw = (reference.resolvedWebReaderURLString() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let site = htmlEscape(siteRaw)
        let url = htmlEscape(urlRaw)
        let showURLInMeta = !urlRaw.isEmpty && !metaSiteAndURLAreRedundant(site: siteRaw, url: urlRaw)
        let eyebrow = htmlEscape(eyebrowText)
        let bodyHTML = articleBodyHTML
        let articleHeaderHTML = omitArticleHeader ? "" : """
              <header class="article-header">
                <div class="eyebrow">\(eyebrow)</div>
                <h1>\(title)</h1>
                <div class="meta">
                  \(author.isEmpty ? "" : "<span>\(author)</span>")
                  \(site.isEmpty ? "" : "<span>\(site)</span>")
                  \(showURLInMeta ? "<span>\(url)</span>" : "")
                </div>
                \(summary.isEmpty ? "" : "<div id=\"swiftlib-article-summary\" class=\"summary\" title=\"在侧栏查看摘要\">\(summary)</div>")
              </header>
"""

        let htmlOpeningTag = includeClipperTypography ? #"<html class="obsidian-reader-active theme-light">"# : "<html>"
        let clipperHeadInjection: String = {
            guard includeClipperTypography else { return "" }
            let vars = """
          <style>
            html.obsidian-reader-active {
              --obsidian-reader-font-size: \(fontSize)px;
              --obsidian-reader-line-height: 1.65;
              --obsidian-reader-line-width: \(Int(contentWidth))px;
            }
          </style>
"""
            guard let bundled = bundledClipperReaderStyleBlock() else { return vars }
            return vars + "\n          <style>\(bundled)</style>\n"
        }()
        let bodyLeadScript = includeClipperTypography
            ? """
          <script>(function(){try{var m=window.matchMedia&&window.matchMedia("(prefers-color-scheme: dark)");if(m&&m.matches){document.documentElement.classList.remove("theme-light");document.documentElement.classList.add("theme-dark");}}catch(_){}})();</script>

"""
            : ""

        return """
        <!doctype html>
        \(htmlOpeningTag)
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: light dark;
              --reader-font-size: \(fontSize)px;
              --reader-max-width: \(Int(contentWidth))px;
              --reader-line-height: 1.8;
            }

            html, body {
              margin: 0;
              padding: 0;
            }

            body {
              background: #ffffff;
              color: #1b1d21;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            }

            #reader-root {
              padding: 28px 32px 48px;
            }

            .article {
              max-width: var(--reader-max-width);
              margin: 0 auto;
              background: transparent;
              padding: 6px 0 46px;
            }

            .article-header {
              margin-bottom: 28px;
              border-bottom: 1px solid rgba(15, 23, 42, 0.08);
              padding-bottom: 22px;
            }

            .eyebrow {
              display: inline-flex;
              align-items: center;
              gap: 8px;
              font-size: 12px;
              font-weight: 600;
              color: #4b5563;
              background: rgba(99, 102, 241, 0.08);
              border-radius: 999px;
              padding: 5px 10px;
            }

            .article-header h1 {
              margin: 14px 0 10px;
              font-size: 34px;
              line-height: 1.22;
              letter-spacing: -0.02em;
            }

            .meta {
              display: flex;
              flex-wrap: wrap;
              gap: 10px 16px;
              color: #6b7280;
              font-size: 14px;
            }

            .summary {
              margin-top: 14px;
              color: #4b5563;
              font-size: 15px;
              line-height: 1.7;
            }

            #swiftlib-article-summary {
              cursor: pointer;
              border-radius: 8px;
              margin-left: -6px;
              margin-right: -6px;
              padding: 6px 8px;
              transition: background-color 0.15s ease;
            }

            #swiftlib-article-summary:hover {
              background: rgba(15, 23, 42, 0.04);
            }

            @keyframes swiftlibSummaryPulse {
              0%, 100% { background-color: transparent; }
              50% { background-color: rgba(99, 102, 241, 0.14); }
            }

            #swiftlib-article-summary.swiftlib-summary-flash {
              animation: swiftlibSummaryPulse 0.55s ease 0s 2;
            }

            html {
              scrollbar-width: thin;
              scrollbar-color: rgba(100, 116, 139, 0.24) transparent;
            }

            html::-webkit-scrollbar,
            body::-webkit-scrollbar {
              width: 9px;
              height: 9px;
            }

            html::-webkit-scrollbar-track,
            body::-webkit-scrollbar-track {
              background: transparent;
            }

            html::-webkit-scrollbar-thumb,
            body::-webkit-scrollbar-thumb {
              background-color: rgba(100, 116, 139, 0.22);
              border-radius: 999px;
              border: 2px solid transparent;
              background-clip: padding-box;
            }

            html::-webkit-scrollbar-thumb:hover,
            body::-webkit-scrollbar-thumb:hover {
              background-color: rgba(100, 116, 139, 0.34);
            }

            html::-webkit-scrollbar-corner,
            body::-webkit-scrollbar-corner {
              background: transparent;
            }

            #article-content {
              font-size: var(--reader-font-size);
              line-height: var(--reader-line-height);
              word-break: break-word;
            }

            #article-content h1,
            #article-content h2,
            #article-content h3,
            #article-content h4 {
              line-height: 1.3;
              margin-top: 1.55em;
              margin-bottom: 0.7em;
              letter-spacing: -0.015em;
            }

            #article-content p,
            #article-content ul,
            #article-content ol,
            #article-content blockquote,
            #article-content pre,
            #article-content table,
            #article-content hr,
            #article-content figure,
            #article-content .swiftlib-md-media-block {
              margin-top: 0;
              margin-bottom: 1em;
            }

            #article-content ul,
            #article-content ol {
              padding-left: 1.5em;
            }

            #article-content li + li {
              margin-top: 0.35em;
            }

            #article-content img {
              max-width: 100%;
              height: auto;
              border-radius: 12px;
            }

            #article-content hr {
              border: 0;
              border-top: 1px solid rgba(15, 23, 42, 0.12);
            }

            #article-content pre {
              background: rgba(15, 23, 42, 0.06);
              border-radius: 12px;
              padding: 14px 16px;
              overflow-x: auto;
            }

            #article-content code {
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: 0.92em;
            }

            #article-content blockquote {
              border-left: 4px solid rgba(59, 130, 246, 0.35);
              padding-left: 14px;
              color: #4b5563;
            }

            #article-content a {
              color: #2563eb;
              text-decoration: none;
            }

            #article-content a:hover {
              text-decoration: underline;
            }

            .swiftlib-annotation {
              border-radius: 5px;
              cursor: pointer;
              transition: box-shadow 0.15s ease, background-color 0.15s ease;
            }

            .swiftlib-annotation.active {
              box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.35);
            }

            /* YouTube transcript (播放器在 SwiftUI 内联 WKWebView) */
            .swiftlib-yt-desc {
              color: #4b5563;
              font-size: 15px;
              line-height: 1.7;
            }
            .swiftlib-yt-transcript {
              margin-top: 1.5em;
              border: none;
              border-radius: 0;
              overflow: visible;
            }
            .swiftlib-yt-transcript summary {
              cursor: pointer;
              padding: 8px 0;
              font-weight: 600;
              font-size: 13px;
              color: #9ca3af;
              letter-spacing: 0.02em;
              text-transform: uppercase;
              background: none;
              user-select: none;
              border-top: 1px solid rgba(15, 23, 42, 0.06);
            }
            .swiftlib-yt-transcript-body {
              font-size: 0.88em;
              line-height: 1.75;
              padding: 8px 0;
              margin: 0;
              max-height: none;
              overflow-y: visible;
            }
            .swiftlib-yt-line {
              display: block;
            }
            .swiftlib-yt-ts {
              display: inline-block;
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: 0.92em;
              color: #6366f1;
              text-decoration: none;
              cursor: pointer;
              margin-right: 0.4em;
              padding: 1px 4px;
              border-radius: 4px;
              transition: background 0.15s;
            }
            .swiftlib-yt-ts:hover {
              background: rgba(99, 102, 241, 0.12);
              text-decoration: none;
            }

            @media (prefers-color-scheme: dark) {
              html {
                scrollbar-color: rgba(148, 163, 184, 0.28) transparent;
              }

              html::-webkit-scrollbar-thumb,
              body::-webkit-scrollbar-thumb {
                background-color: rgba(148, 163, 184, 0.24);
              }

              html::-webkit-scrollbar-thumb:hover,
              body::-webkit-scrollbar-thumb:hover {
                background-color: rgba(148, 163, 184, 0.36);
              }

              body {
                background: #1e1e1e;
                color: #eceef2;
              }

              #swiftlib-article-summary:hover {
                background: rgba(255, 255, 255, 0.06);
              }

              @keyframes swiftlibSummaryPulseDark {
                0%, 100% { background-color: transparent; }
                50% { background-color: rgba(99, 102, 241, 0.22); }
              }

              #swiftlib-article-summary.swiftlib-summary-flash {
                animation: swiftlibSummaryPulseDark 0.55s ease 0s 2;
              }

              .article {
                background: transparent;
              }

              .article-header {
                border-bottom-color: rgba(255, 255, 255, 0.08);
              }

              .eyebrow {
                color: #d1d5db;
                background: rgba(99, 102, 241, 0.16);
              }

              .meta,
              .summary,
              #article-content blockquote {
                color: #aeb6c2;
              }

              #article-content pre {
                background: rgba(255, 255, 255, 0.06);
              }

              #article-content hr {
                border-top-color: rgba(255, 255, 255, 0.12);
              }

              #article-content a {
                color: #7fb3ff;
              }

              .swiftlib-yt-desc {
                color: #aeb6c2;
              }
              .swiftlib-yt-transcript {
                border-color: transparent;
              }
              .swiftlib-yt-transcript summary {
                color: #6b7280;
                background: none;
                border-top-color: rgba(255, 255, 255, 0.08);
              }
            }
          </style>
        \(clipperHeadInjection)
        </head>
        <body>
        \(bodyLeadScript)<main id="reader-root">
            <article class="article">
              \(articleHeaderHTML)
              <div id="article-content">\(bodyHTML)</div>
            </article>
          </main>
          <script>
            (function () {
              const article = document.getElementById('article-content');
              let activeId = null;

              function send(name, payload) {
                try {
                  window.webkit.messageHandlers[name].postMessage(payload);
                } catch (_) {}
              }

              function hexToRgba(hex, alpha) {
                const normalized = (hex || '#FFDE59').replace('#', '');
                const safe = normalized.length === 6 ? normalized : 'FFDE59';
                const r = parseInt(safe.slice(0, 2), 16);
                const g = parseInt(safe.slice(2, 4), 16);
                const b = parseInt(safe.slice(4, 6), 16);
                return `rgba(${r}, ${g}, ${b}, ${alpha})`;
              }

              function unwrapAnnotations() {
                const nodes = Array.from(document.querySelectorAll('span[data-annotation-id]'));
                nodes.forEach((span) => {
                  const parent = span.parentNode;
                  if (!parent) return;
                  while (span.firstChild) {
                    parent.insertBefore(span.firstChild, span);
                  }
                  parent.removeChild(span);
                  parent.normalize();
                });
              }

              function collectTextNodes(root) {
                const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
                  acceptNode(node) {
                    if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
                    if (node.parentElement && node.parentElement.closest('[data-annotation-id]')) return NodeFilter.FILTER_REJECT;
                    return NodeFilter.FILTER_ACCEPT;
                  }
                });

                const result = [];
                while (walker.nextNode()) {
                  result.push(walker.currentNode);
                }
                return result;
              }

              function buildIndex(root) {
                const nodes = collectTextNodes(root);
                const map = [];
                let text = '';

                nodes.forEach((node) => {
                  const start = text.length;
                  const value = node.nodeValue || '';
                  text += value;
                  map.push({ node, start, end: text.length });
                });

                return { text, map };
              }

              function resolvePoint(map, target) {
                for (const entry of map) {
                  if (target >= entry.start && target <= entry.end) {
                    return { node: entry.node, offset: target - entry.start };
                  }
                }
                return null;
              }

              function scoreMatch(fullText, index, annotation) {
                let score = 0;
                if (annotation.prefixText) {
                  const actualPrefix = fullText.slice(Math.max(0, index - annotation.prefixText.length), index);
                  if (actualPrefix.endsWith(annotation.prefixText)) score += annotation.prefixText.length * 2;
                }
                if (annotation.suffixText) {
                  const actualSuffix = fullText.slice(
                    index + annotation.anchorText.length,
                    index + annotation.anchorText.length + annotation.suffixText.length
                  );
                  if (actualSuffix.startsWith(annotation.suffixText)) score += annotation.suffixText.length * 2;
                }
                return score;
              }

              function locateRange(annotation) {
                if (!annotation.anchorText) return null;
                const indexed = buildIndex(article);
                const fullText = indexed.text;
                if (!fullText) return null;

                let bestIndex = -1;
                let bestScore = -1;
                let searchFrom = 0;
                while (searchFrom <= fullText.length) {
                  const idx = fullText.indexOf(annotation.anchorText, searchFrom);
                  if (idx === -1) break;
                  const score = scoreMatch(fullText, idx, annotation);
                  if (score > bestScore) {
                    bestScore = score;
                    bestIndex = idx;
                  }
                  searchFrom = idx + Math.max(annotation.anchorText.length, 1);
                }

                if (bestIndex === -1) return null;
                const start = resolvePoint(indexed.map, bestIndex);
                const end = resolvePoint(indexed.map, bestIndex + annotation.anchorText.length);
                if (!start || !end) return null;

                const range = document.createRange();
                range.setStart(start.node, start.offset);
                range.setEnd(end.node, end.offset);
                return range;
              }

              function applyAnnotationStyle(span, annotation) {
                const color = annotation.color || '#FFDE59';
                const highlightColor = hexToRgba(color, annotation.type === 'underline' ? 0 : 0.3);
                span.className = `swiftlib-annotation ${annotation.type}`;
                span.dataset.annotationId = String(annotation.id || '');
                span.style.backgroundColor = annotation.type === 'underline' ? 'transparent' : highlightColor;
                span.style.borderBottom = annotation.type === 'underline' ? `3px solid ${color}` : 'none';
                span.style.paddingBottom = annotation.type === 'underline' ? '1px' : '0';
                if (annotation.noteText) {
                  span.title = annotation.noteText;
                }
              }

              function wrapRange(range, annotation) {
                const span = document.createElement('span');
                applyAnnotationStyle(span, annotation);

                try {
                  range.surroundContents(span);
                } catch (_) {
                  const fragment = range.extractContents();
                  span.appendChild(fragment);
                  range.insertNode(span);
                }
              }

              function setActive(id) {
                activeId = id;
                document.querySelectorAll('[data-annotation-id]').forEach((node) => {
                  const matches = Number(node.dataset.annotationId) === Number(id);
                  node.classList.toggle('active', matches);
                });
              }

              function setAnnotations(annotations) {
                unwrapAnnotations();
                (annotations || []).forEach((annotation) => {
                  const range = locateRange(annotation);
                  if (range) {
                    wrapRange(range, annotation);
                  }
                });
                if (activeId !== null) {
                  setActive(activeId);
                }
              }

              function currentSelectionPayload() {
                const selection = window.getSelection();
                if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return null;
                const range = selection.getRangeAt(0);
                if (!article.contains(range.commonAncestorContainer)) return null;

                const text = selection.toString().trim();
                if (!text) return null;

                const prefixRange = range.cloneRange();
                prefixRange.selectNodeContents(article);
                prefixRange.setEnd(range.startContainer, range.startOffset);

                const suffixRange = range.cloneRange();
                suffixRange.selectNodeContents(article);
                suffixRange.setStart(range.endContainer, range.endOffset);

                const domRect = range.getBoundingClientRect();
                const rect =
                  domRect.width >= 1 && domRect.height >= 1
                    ? { left: domRect.left, top: domRect.top, width: domRect.width, height: domRect.height }
                    : null;

                return {
                  text,
                  prefixText: prefixRange.toString().slice(-48),
                  suffixText: suffixRange.toString().slice(0, 48),
                  rect
                };
              }

              function emitSelectionState() {
                const payload = currentSelectionPayload();
                if (payload) {
                  send('selectionChanged', payload);
                } else {
                  send('selectionCleared', null);
                }
              }

              let selectionScrollScheduled = false;
              function scheduleSelectionEmitOnScroll() {
                if (selectionScrollScheduled) return;
                selectionScrollScheduled = true;
                requestAnimationFrame(() => {
                  selectionScrollScheduled = false;
                  if (currentSelectionPayload()) {
                    emitSelectionState();
                  }
                });
              }

              document.addEventListener('mouseup', () => setTimeout(emitSelectionState, 0));
              document.addEventListener('keyup', () => setTimeout(emitSelectionState, 0));
              window.addEventListener('scroll', scheduleSelectionEmitOnScroll, true);
              window.addEventListener('resize', scheduleSelectionEmitOnScroll);

              article.addEventListener('click', (event) => {
                const target = event.target;
                if (!(target instanceof Element)) return;
                const marker = target.closest('[data-annotation-id]');
                if (!marker) return;
                const id = Number(marker.dataset.annotationId);
                setActive(id);
                const rect = marker.getBoundingClientRect();
                send('annotationActivated', {
                  id,
                  rectX: rect.x,
                  rectY: rect.y,
                  rectW: rect.width,
                  rectH: rect.height
                });
              });

              const summaryBlock = document.getElementById('swiftlib-article-summary');
              if (summaryBlock) {
                summaryBlock.addEventListener('click', (event) => {
                  event.preventDefault();
                  send('summarySectionClicked', {});
                });
              }

              window.SwiftLibReader = {
                setAnnotations,
                seekYouTube(seconds) {
                  const n = Number(seconds);
                  if (!Number.isFinite(n) || n < 0) return;
                  send('youtubeSeek', { seconds: Math.floor(n) });
                },
                clearSelection() {
                  const selection = window.getSelection();
                  if (selection) selection.removeAllRanges();
                  emitSelectionState();
                },
                scrollToAnnotation(id) {
                  const target = document.querySelector(`[data-annotation-id="${id}"]`);
                  if (!target) return;
                  setActive(id);
                  target.scrollIntoView({ behavior: 'smooth', block: 'center' });
                },
                scrollToSummary() {
                  const el = document.getElementById('swiftlib-article-summary');
                  if (!el) return;
                  el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                  el.classList.remove('swiftlib-summary-flash');
                  void el.offsetWidth;
                  el.classList.add('swiftlib-summary-flash');
                  window.setTimeout(() => el.classList.remove('swiftlib-summary-flash'), 1300);
                },
                updateAppearance(fontSize, maxWidth) {
                  document.documentElement.style.setProperty('--reader-font-size', `${fontSize}px`);
                  document.documentElement.style.setProperty('--reader-max-width', `${maxWidth}px`);
                  requestAnimationFrame(() => emitSelectionState());
                }
              };
            })();
          </script>
        </body>
        </html>
        """
    }

    nonisolated static func renderedMarkdownHTML(from markdown: String, baseURL: URL? = nil) -> String {
        MarkdownHTMLRenderer.render(markdown: markdown, baseURL: baseURL)
    }

    nonisolated private static func emptyDocument(title: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; padding: 40px; background: #ffffff; color: #1f2937; }
            .empty { max-width: 720px; margin: 40px auto; padding: 32px; text-align: center; }
          </style>
        </head>
        <body>
          <div class="empty">
            <h2>\(htmlEscape(title))</h2>
            <p>这个网页条目还没有抓取到正文内容。</p>
          </div>
        </body>
        </html>
        """
    }

    /// 去掉正文中的 YouTube 内嵌播放器（Readability 会保留 video iframe；WKWebView 会报 152-4）。
    nonisolated private static func htmlByStrippingYouTubePlayerEmbeds(_ html: String) -> String {
        var result = html
        // 使用普通字符串，避免 raw string 内 \" 与字符类 [\"'] 冲突。
        let patterns: [(String, NSRegularExpression.Options)] = [
            (
                "<iframe\\b[^>]*\\bsrc\\s*=\\s*[\"'][^\"']*(?:youtube\\.com|youtu\\.be|youtube-nocookie)[^\"']*[\"'][^>]*>[\\s\\S]*?</iframe>",
                [.caseInsensitive, .dotMatchesLineSeparators]
            ),
            (
                "<iframe\\b[^>]*\\bsrc\\s*=\\s*[^\\s>]*(?:youtube\\.com|youtu\\.be|youtube-nocookie)[^>]*>[\\s\\S]*?</iframe>",
                [.caseInsensitive, .dotMatchesLineSeparators]
            ),
            (
                "<embed\\b[^>]*(?:youtube\\.com|youtu\\.be|youtube-nocookie)[^>]*\\/?>",
                [.caseInsensitive]
            ),
            (
                "<object\\b[^>]*(?:youtube\\.com|youtu\\.be|youtube-nocookie)[^>]*>[\\s\\S]*?</object>",
                [.caseInsensitive, .dotMatchesLineSeparators]
            )
        ]
        for (pattern, opts) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }
            for _ in 0 ..< 48 {
                let range = NSRange(result.startIndex..., in: result)
                guard let m = re.firstMatch(in: result, options: [], range: range),
                      let r = Range(m.range, in: result) else { break }
                result.replaceSubrange(r, with: "")
            }
        }
        return result
    }

    nonisolated static func cleanedYouTubeArticleBodyHTML(_ html: String) -> String {
        var result = htmlByStrippingYouTubePlayerEmbeds(html)
        result = htmlByRemovingLegacyYouTubeFallbackChrome(result)
        result = htmlByRemovingLeadingYouTubeCoverMedia(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 兼容清理旧版 YouTube fallback 存量 HTML，避免正文里重复出现封面卡、外链按钮和摘要。
    nonisolated static func htmlByRemovingLegacyYouTubeFallbackChrome(_ html: String) -> String {
        var result = html
        result = htmlByRemovingElement(tagName: "div", containingClass: "swiftlib-yt-player-shell", from: result)
        result = htmlByRemovingElement(tagName: "div", containingClass: "swiftlib-yt-player-actions", from: result)
        result = htmlByRemovingElement(tagName: "p", containingClass: "swiftlib-yt-desc", from: result)

        let patterns: [(String, NSRegularExpression.Options)] = [
            (#"<p>\s*<a\b[^>]*class\s*=\s*["'][^"']*swiftlib-yt-open-link[^"']*["'][^>]*>[\s\S]*?</a>\s*</p>\s*"#, [.caseInsensitive, .dotMatchesLineSeparators]),
            (#"^\s*<p>\s*<a\b[^>]*href\s*=\s*["']https?://(?:www\.)?youtube\.com/watch[^"']*["'][^>]*>\s*(?:在浏览器中打开|Open(?:\s+in)?\s+browser)\s*</a>\s*</p>\s*"#, [.caseInsensitive, .dotMatchesLineSeparators]),
        ]
        for (pattern, opts) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }
            for _ in 0 ..< 12 {
                let range = NSRange(result.startIndex..., in: result)
                guard let match = re.firstMatch(in: result, options: [], range: range),
                      let swiftRange = Range(match.range, in: result) else { break }
                result.removeSubrange(swiftRange)
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func htmlByRemovingElement(
        tagName: String,
        containingClass className: String,
        from html: String
    ) -> String {
        let escapedClass = NSRegularExpression.escapedPattern(for: className)
        let pattern = "<\(tagName)\\b[^>]*class\\s*=\\s*[\"'][^\"']*\\b\(escapedClass)\\b[^\"']*[\"'][^>]*>"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return html
        }

        var result = html
        for _ in 0 ..< 12 {
            let range = NSRange(result.startIndex..., in: result)
            guard let match = re.firstMatch(in: result, options: [], range: range),
                  let openingTagRange = Range(match.range, in: result),
                  let elementRange = htmlElementRange(in: result, tagName: tagName, openingTagRange: openingTagRange) else {
                break
            }
            result.removeSubrange(elementRange)
        }

        return result
    }

    nonisolated private static func htmlElementRange(
        in html: String,
        tagName: String,
        openingTagRange: Range<String.Index>
    ) -> Range<String.Index>? {
        var searchStart = openingTagRange.upperBound
        var depth = 1
        let openPattern = "<\(tagName)\\b"
        let closePattern = "</\(tagName)>"

        while searchStart < html.endIndex {
            let searchRange = searchStart..<html.endIndex
            let nextOpen = html.range(of: openPattern, options: [.regularExpression, .caseInsensitive], range: searchRange)
            let nextClose = html.range(of: closePattern, options: [.caseInsensitive], range: searchRange)
            guard let closeRange = nextClose else { return nil }

            if let openRange = nextOpen, openRange.lowerBound < closeRange.lowerBound {
                depth += 1
                searchStart = openRange.upperBound
            } else {
                depth -= 1
                searchStart = closeRange.upperBound
                if depth == 0 {
                    return openingTagRange.lowerBound..<closeRange.upperBound
                }
            }
        }

        return nil
    }

    /// YouTube 剪藏正文常会把封面图再保存一份，和顶部视频卡重复；仅移除首屏独立媒体块，保留正文其它图片。
    nonisolated static func htmlByRemovingLeadingYouTubeCoverMedia(_ html: String) -> String {
        var result = html
        let patterns: [(String, NSRegularExpression.Options)] = [
            (#"^\s*<div\b[^>]*class\s*=\s*["'][^"']*swiftlib-md-media-block[^"']*["'][^>]*>\s*[\s\S]*?</div>\s*"#, [.caseInsensitive, .dotMatchesLineSeparators]),
            (#"^\s*<p>\s*(?:<a\b[^>]*>\s*)?<img\b[^>]*>(?:\s*</a>)?\s*</p>\s*"#, [.caseInsensitive, .dotMatchesLineSeparators]),
            (#"^\s*<figure\b[^>]*>\s*[\s\S]*?</figure>\s*"#, [.caseInsensitive, .dotMatchesLineSeparators]),
            (#"^\s*(?:<a\b[^>]*>\s*)?<img\b[^>]*>(?:\s*</a>)?\s*"#, [.caseInsensitive, .dotMatchesLineSeparators]),
        ]

        for (pattern, opts) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            guard let match = re.firstMatch(in: result, options: [], range: range),
                  let swiftRange = Range(match.range, in: result) else { continue }
            result.removeSubrange(swiftRange)
            break
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `site` 与 `url` 是否指向同一 http(s) 资源，避免元信息区重复展示同一链接。
    nonisolated private static func metaSiteAndURLAreRedundant(site: String, url: String) -> Bool {
        let s = site.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !u.isEmpty else { return false }
        if s.caseInsensitiveCompare(u) == .orderedSame { return true }
        return httpURLsAreEquivalent(s, u)
    }

    nonisolated private static func httpURLsAreEquivalent(_ a: String, _ b: String) -> Bool {
        guard let ua = URL(string: a), let ub = URL(string: b) else { return false }
        let sa = (ua.scheme ?? "").lowercased()
        let sb = (ub.scheme ?? "").lowercased()
        guard ["http", "https"].contains(sa), ["http", "https"].contains(sb) else { return false }
        func normHost(_ h: String?) -> String {
            let x = h?.lowercased() ?? ""
            if x.hasPrefix("www.") { return String(x.dropFirst(4)) }
            return x
        }
        guard normHost(ua.host) == normHost(ub.host) else { return false }
        return ua.path == ub.path && (ua.query ?? "") == (ub.query ?? "")
    }

    nonisolated private static func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}

struct WebReaderView: View {
    @StateObject private var viewModel: WebReaderViewModel
    @StateObject private var transcriptPageFetcher = YouTubeTranscriptPageFetcher()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAnnotationSidebar = true
    private let onClose: (() -> Void)?

    init(reference: Reference, onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: WebReaderViewModel(reference: reference))
    }

    var body: some View {
        HSplitView {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if usesPinnedYouTubeHeader {
                        pinnedYouTubeHeader
                    }
                    youTubeInlineHeader
                    GeometryReader { proxy in
                        WebReaderContentView(viewModel: viewModel)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .overlay {
                                webSelectionToolbarOverlay
                            }
                            .overlay {
                                webAnnotationToolbarOverlay
                            }
                            .onAppear {
                                viewModel.updateViewportSize(proxy.size)
                            }
                            .onChange(of: proxy.size) { _, newSize in
                                viewModel.updateViewportSize(newSize)
                            }
                    }
                }

                if viewModel.isRendering || viewModel.isLiveReadableBusy {
                    ProgressView(viewModel.isLiveReadableBusy ? "正在加载并提取正文…" : "正在渲染 Markdown…")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 14)
                }
            }
            .frame(minWidth: 540)

            if showAnnotationSidebar {
                WebAnnotationSidebarView(viewModel: viewModel)
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 400)
                    .overlay(alignment: .leading) {
                        LinearGradient(
                            colors: [Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 6)
                        .allowsHitTesting(false)
                    }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .onDisappear {
            viewModel.collapseYouTubeInlinePlayer()
        }
        .background {
            if viewModel.reference.isLikelyYouTubeWatchURL {
                HiddenWKWebViewHost(
                    onCreate: { webView in
                        transcriptPageFetcher.registerWebView(webView)
                    }
                )
                .frame(width: 4, height: 4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .animation(
            .spring(response: 0.3, dampingFraction: 0.82),
            value: viewModel.hasSelection && viewModel.selectionToolbarLayout?.visible == true
        )
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if viewModel.allowsDisplayModeSwitching {
                    Picker("阅读模式", selection: Binding(
                        get: { viewModel.displayMode },
                        set: { viewModel.setDisplayMode($0) }
                    )) {
                        ForEach(WebReaderDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }

                if !usesPinnedYouTubeHeader {
                    fontControls
                    widthControls
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation { showAnnotationSidebar.toggle() }
                } label: {
                    Label("侧边栏", systemImage: "sidebar.right")
                }
            }
        }
        .onAppear {
            NoteEditorPool.shared.warmUp()
        }
        .onChange(of: viewModel.sidebarSummaryScrollToken) { _, new in
            if new > 0, viewModel.hasSidebarSummary {
                showAnnotationSidebar = true
            }
        }
        .task {
            viewModel.fetchTranscriptFromOriginalPage = { [transcriptPageFetcher] urlString in
                await transcriptPageFetcher.fetchTranscript(urlString: urlString)
            }
        }
        .navigationTitle(viewModel.reference.title)
        .alert("在线阅读", isPresented: Binding(
            get: { viewModel.liveReadableUserMessage != nil },
            set: { if !$0 { viewModel.liveReadableUserMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.liveReadableUserMessage ?? "")
        }
    }

    private var usesPinnedYouTubeHeader: Bool {
        viewModel.reference.youTubeVideoId != nil
    }

    private var pinnedYouTubeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Label("YouTube", systemImage: "play.rectangle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)

                Spacer()

                if let urlString = viewModel.reference.resolvedWebReaderURLString(),
                   let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("原视频", systemImage: "arrow.up.right")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
            }

            Text(viewModel.reference.title)
                .font(.system(size: 24, weight: .bold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let site = viewModel.reference.siteName ?? viewModel.reference.journal,
               !site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(site)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    @ViewBuilder
    private var youTubeInlineHeader: some View {
        if let vid = viewModel.reference.youTubeVideoId {
            let externalURL = viewModel.reference.resolvedWebReaderURLString().flatMap { URL(string: $0) }
                ?? URL(string: "https://www.youtube.com/watch?v=\(vid)")
            Group {
                if viewModel.youTubeInlineWatchURL != nil {
                    ZStack(alignment: .topTrailing) {
                        YouTubeWatchInlineWebView(viewModel: viewModel)
                        Button {
                            viewModel.collapseYouTubeInlinePlayer()
                        } label: {
                            Label("收起视频", systemImage: "xmark")
                                .labelStyle(.iconOnly)
                                .padding(9)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                    }
                } else {
                    YouTubeWatchPlayPlaceholder(videoId: vid, externalWatchURL: externalURL) {
                        viewModel.activateYouTubeInlinePlayer()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipped()
        }
    }

    @ViewBuilder
    private var webSelectionToolbarOverlay: some View {
        let shouldShow = viewModel.hasSelection
            && viewModel.selectionToolbarLayout?.visible == true
        if shouldShow, let layout = viewModel.selectionToolbarLayout {
            WebSelectionActionBar(viewModel: viewModel, metrics: layout.metrics)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: layout.origin.x, y: layout.origin.y)
                .allowsHitTesting(true)
                .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                .animation(.spring(response: 0.25, dampingFraction: 0.82), value: layout.origin)
        }
    }

    @ViewBuilder
    private var webAnnotationToolbarOverlay: some View {
        if viewModel.clickedAnnotationRecord != nil,
           let layout = viewModel.annotationToolbarLayout, layout.visible {
            WebAnnotationActionBar(viewModel: viewModel, metrics: layout.metrics)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: layout.origin.x, y: layout.origin.y)
                .allowsHitTesting(true)
                .transition(.opacity)
        }
    }

    private var fontControls: some View {
        HStack(spacing: 3) {
            Button { viewModel.decreaseFontSize() } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)

            Button { viewModel.increaseFontSize() } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private var widthControls: some View {
        HStack(spacing: 3) {
            Button { viewModel.narrowContent() } label: {
                Image(systemName: "arrow.left.and.line.vertical.and.arrow.right")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)

            Button { viewModel.widenContent() } label: {
                Image(systemName: "arrow.left.and.line.vertical.and.arrow.right.circle")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct YouTubeWatchInlineWebView: NSViewRepresentable {
    @ObservedObject var viewModel: WebReaderViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = ReaderExtractionManager.safariLikeUserAgent
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let url = viewModel.youTubeInlineWatchURL else { return }
        if context.coordinator.lastLoadedURL != url {
            context.coordinator.lastLoadedURL = url
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator {
        var lastLoadedURL: URL?
    }
}

private struct YouTubeWatchPlayPlaceholder: View {
    let videoId: String
    let externalWatchURL: URL?
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)

            AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    .black.opacity(0.08),
                                    .black.opacity(0.18),
                                    .black.opacity(0.52)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                case .failure:
                    LinearGradient(
                        colors: [Color.black.opacity(0.86), Color.gray.opacity(0.56)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                case .empty:
                    ZStack {
                        LinearGradient(
                            colors: [Color.black.opacity(0.86), Color.gray.opacity(0.56)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        ProgressView()
                            .controlSize(.regular)
                    }
                @unknown default:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("点击播放在线视频")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("默认保留封面，避免阅读区和网页播放器同时展开。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(18)

            VStack {
                Button(action: onPlay) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("播放在线视频")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.58), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放 YouTube 视频")
            }
        }

    }
}

private struct WebSelectionActionBar: View {
    @ObservedObject var viewModel: WebReaderViewModel
    let metrics: ReaderActionBarMetrics
    @State private var noteMarkdown = ""
    @State private var editorContentHeight: CGFloat = 36
    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.22, alpha: 1))
            : Color(nsColor: NSColor(white: 0.13, alpha: 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: metrics.topRowSpacing) {
                toolbarButton(icon: "highlighter", label: "高亮") {
                    viewModel.applySelectionAction(.highlight)
                }

                toolbarButton(icon: "doc.on.doc", label: "复制") {
                    if let text = viewModel.pendingSelection?.text, !text.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }

                separator

                ForEach(AnnotationColor.palette) { color in
                    let isSelected = viewModel.currentColorHex == color.id
                    Button {
                        viewModel.currentColorHex = color.id
                        viewModel.applySelectionAction(.highlight)
                    } label: {
                        Circle()
                            .fill(Color(nsColor: color.nsColor.withAlphaComponent(1.0)))
                            .frame(width: metrics.colorDotSize, height: metrics.colorDotSize)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        isSelected ? Color.white : Color.white.opacity(0.2),
                                        lineWidth: isSelected ? 2 : 0.5
                                    )
                            )
                            .scaleEffect(isSelected ? 1.12 : 1.0)
                                    .frame(width: metrics.colorButtonWidth, height: metrics.buttonHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(color.name)
                    .animation(.easeOut(duration: 0.12), value: isSelected)
                }

                separator

                toolbarButton(icon: "trash", label: "取消选择") {
                    viewModel.clearSelection()
                }
            }
            .padding(.horizontal, metrics.topRowHorizontalPadding)
            .padding(.vertical, metrics.topRowVerticalPadding)

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
                .padding(.horizontal, metrics.dividerHorizontalPadding)

            // Note section: always-visible inline editor
            VStack(spacing: 0) {
                RichNoteEditorView(
                    markdown: $noteMarkdown,
                    placeholder: "添加笔记…",
                    autoFocus: false,
                    onContentHeightChanged: { height in
                        editorContentHeight = height
                    }
                )
                .frame(height: min(max(editorContentHeight, 36), metrics.selectionEditorMaxHeight))
                .clipShape(RoundedRectangle(cornerRadius: metrics.editorCornerRadius))
                .padding(.horizontal, metrics.editorHorizontalPadding)
                .padding(.top, metrics.editorTopPadding)

                HStack(spacing: metrics.actionRowSpacing) {
                    Spacer()
                    Button("取消") {
                        noteMarkdown = ""
                        viewModel.clearSelection()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
                    .font(.system(size: metrics.secondaryFontSize))

                    Button("保存") {
                        let md = noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !md.isEmpty, let selection = viewModel.pendingSelection else { return }
                        viewModel.addAnnotation(type: .note, selection: selection, noteText: md)
                        noteMarkdown = ""
                        viewModel.clearSelection()
                    }
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, metrics.saveButtonHorizontalPadding)
                    .padding(.vertical, metrics.saveButtonVerticalPadding)
                    .background(
                        Capsule(style: .continuous)
                            .fill(noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  ? Color.accentColor.opacity(0.35)
                                  : Color.accentColor)
                    )
                    .buttonStyle(.plain)
                    .disabled(noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, metrics.actionRowHorizontalPadding)
                .padding(.vertical, metrics.actionRowVerticalPadding)
            }
        }
        .frame(width: metrics.toolbarWidth)
        .background(bgColor, in: RoundedRectangle(cornerRadius: metrics.toolbarCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.toolbarCornerRadius, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : Color.black.opacity(0.08),
                    lineWidth: 0.5
                )
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.28 : 0.12),
            radius: colorScheme == .dark ? 16 : 10,
            y: colorScheme == .dark ? 6 : 3
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.12 : 0.06),
            radius: 3,
            y: 1
        )
    }

    private var separator: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12))
            .frame(width: 1, height: metrics.separatorHeight)
            .padding(.horizontal, metrics.separatorHorizontalPadding)
    }

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: metrics.buttonIconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: metrics.buttonWidth, height: metrics.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(WebNotionToolbarButtonStyle(cornerRadius: metrics.buttonCornerRadius))
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct WebNotionToolbarButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed
                          ? Color.white.opacity(0.18)
                          : (isHovered ? Color.white.opacity(0.10) : Color.clear))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Web Annotation Action Bar (for clicked existing highlights)

private struct WebAnnotationActionBar: View {
    @ObservedObject var viewModel: WebReaderViewModel
    let metrics: ReaderActionBarMetrics
    @State private var isEditingNote = false
    @State private var editingMarkdown = ""
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var editorContentHeight: CGFloat = 36
    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.22, alpha: 1))
            : Color(nsColor: NSColor(white: 0.13, alpha: 1))
    }

    var body: some View {
        if let annotation = viewModel.clickedAnnotationRecord {
            VStack(spacing: 0) {
                HStack(spacing: metrics.topRowSpacing) {
                    ForEach(AnnotationColor.palette) { color in
                        let isSelected = annotation.color == color.id
                        Button {
                            viewModel.updateAnnotationColor(annotation, color: color.id)
                            if let updated = viewModel.annotations.first(where: { $0.id == annotation.id }) {
                                viewModel.clickedAnnotationRecord = updated
                            }
                        } label: {
                            Circle()
                                .fill(Color(nsColor: color.nsColor.withAlphaComponent(1.0)))
                                .frame(width: metrics.colorDotSize, height: metrics.colorDotSize)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            isSelected ? Color.white : Color.white.opacity(0.2),
                                            lineWidth: isSelected ? 2 : 0.5
                                        )
                                )
                                .scaleEffect(isSelected ? 1.12 : 1.0)
                                    .frame(width: metrics.colorButtonWidth, height: metrics.buttonHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(color.name)
                        .animation(.easeOut(duration: 0.12), value: isSelected)
                    }

                    separator

                    Button {
                        viewModel.deleteAnnotation(annotation)
                        viewModel.dismissAnnotationToolbar()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: metrics.buttonIconSize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: metrics.buttonWidth, height: metrics.buttonHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(WebNotionToolbarButtonStyle(cornerRadius: metrics.buttonCornerRadius))
                    .help("删除标注")
                }
                .padding(.horizontal, metrics.topRowHorizontalPadding)
                .padding(.vertical, metrics.topRowVerticalPadding)

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)
                    .padding(.horizontal, metrics.dividerHorizontalPadding)

                // Note section: editor / placeholder
                if isEditingNote {
                    // WYSIWYG inline editor — auto-saves
                    RichNoteEditorView(
                        markdown: $editingMarkdown,
                        placeholder: "添加笔记…",
                        autoFocus: true,
                        onContentHeightChanged: { height in
                            editorContentHeight = height
                        }
                    )
                    .frame(height: min(max(editorContentHeight, 36), metrics.annotationEditorMaxHeight))
                    .clipShape(RoundedRectangle(cornerRadius: metrics.editorCornerRadius))
                    .padding(.horizontal, metrics.editorHorizontalPadding)
                    .padding(.vertical, metrics.editorVerticalPadding)
                } else {
                    // No note — placeholder to add
                    Button {
                        editingMarkdown = ""
                        isEditingNote = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text")
                                .font(.system(size: metrics.placeholderIconSize))
                            Text("添加笔记…")
                                .font(.system(size: metrics.placeholderFontSize))
                        }
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, metrics.editorHorizontalPadding)
                        .padding(.vertical, metrics.editorVerticalPadding)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: metrics.toolbarWidth)
            .background(bgColor, in: RoundedRectangle(cornerRadius: metrics.toolbarCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.toolbarCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            .onAppear {
                let noteText = annotation.noteText ?? ""
                editingMarkdown = noteText
                isEditingNote = !noteText.isEmpty
            }
            .onChange(of: annotation.id) { _, _ in
                let noteText = annotation.noteText ?? ""
                editingMarkdown = noteText
                isEditingNote = !noteText.isEmpty
            }
            .onChange(of: editingMarkdown) { _, newValue in
                autoSaveTask?.cancel()
                autoSaveTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    if let ann = viewModel.clickedAnnotationRecord {
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        viewModel.updateAnnotationNote(ann, noteText: trimmed)
                    }
                }
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: metrics.separatorHeight)
            .padding(.horizontal, metrics.separatorHorizontalPadding)
    }
}

private struct WebReaderContentView: NSViewRepresentable {
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
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                scrollView.hasVerticalScroller = true
                scrollView.applySwiftLibElegantScrollers()
            }
            applyElegantScrollers(to: subview)
        }
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
