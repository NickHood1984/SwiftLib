import Foundation
import CoreGraphics
import Combine
import SwiftLibCore

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
    var shouldLoadOriginalURLForReadable = false
    /// 递增以触发侧栏滚动到「摘要」卡片（正文内摘要被点击时）。
    @Published var sidebarSummaryScrollToken: UInt64 = 0
    /// 侧栏摘要卡片是否处于「正文摘要已点击」高亮。
    @Published var highlightSidebarSummary: Bool = false
    /// 非 nil 时由顶部原生 WKWebView 加载该 YouTube 观看页 URL（含可选 `t=` 跳转）。
    @Published private(set) var youTubeInlineWatchURL: URL?

    let reference: Reference
    let db: AppDatabase
    var cancellables = Set<AnyCancellable>()
    /// 在线阅读整段流程（加载原文 + 注入脚本 + 抽取 + 组 HTML）防挂起超时。
    var liveReadableSafetyTask: Task<Void, Never>?
    var transcriptLoadTasks: [Task<Void, Never>] = []
    var transcriptLoadState: TranscriptLoadState?
    var transcriptLoadSequence: UInt64 = 0
    var currentArticleBodyHTML: String?
    var shouldPersistTranscriptIntoReference = false
    /// Debounce task for appearance changes (font size / content width).
    var appearanceDebounceTask: Task<Void, Never>?
    var currentViewportSize: CGSize = .zero
    var annotationToolbarAnchorRect: CGRect?
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

    enum TranscriptLoadSource: Hashable {
        case network
        case dom
    }

    struct TranscriptLoadState {
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

}
