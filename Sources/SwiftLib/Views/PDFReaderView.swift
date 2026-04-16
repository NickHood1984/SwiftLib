import SwiftUI
import PDFKit
import Combine
import WebKit
import SwiftLibCore

// MARK: - Annotation Tool

enum PDFSidebarTab: String, CaseIterable {
    case outline = "目录"
    case annotations = "标注"
    case info = "信息"
}

enum AnnotationTool: String, CaseIterable {
    case cursor = "cursor"
    case highlight = "highlight"
    case underline = "underline"
    case note = "note"

    var icon: String {
        switch self {
        case .cursor: return "cursorarrow"
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .note: return "note.text"
        }
    }

    var label: String {
        switch self {
        case .cursor: return "选择"
        case .highlight: return "高亮"
        case .underline: return "下划线"
        case .note: return "笔记"
        }
    }
}

struct AnnotationColor: Identifiable {
    let id: String
    let name: String
    let nsColor: NSColor

    static let palette: [AnnotationColor] = [
        .init(id: "#FFDE59", name: "黄色", nsColor: NSColor(red: 1.0, green: 0.87, blue: 0.35, alpha: 0.4)),
        .init(id: "#7ED957", name: "绿色", nsColor: NSColor(red: 0.49, green: 0.85, blue: 0.34, alpha: 0.4)),
        .init(id: "#5CE1E6", name: "蓝色", nsColor: NSColor(red: 0.36, green: 0.88, blue: 0.9, alpha: 0.4)),
        .init(id: "#FF66C4", name: "粉色", nsColor: NSColor(red: 1.0, green: 0.4, blue: 0.77, alpha: 0.4)),
        .init(id: "#FF914D", name: "橙色", nsColor: NSColor(red: 1.0, green: 0.57, blue: 0.3, alpha: 0.4)),
        .init(id: "#CB6CE6", name: "紫色", nsColor: NSColor(red: 0.80, green: 0.42, blue: 0.9, alpha: 0.4)),
    ]

    static func nsColor(for hex: String) -> NSColor {
        palette.first { $0.id == hex }?.nsColor ?? palette[0].nsColor
    }
}

// MARK: - Selection toolbar (PDF anchor + layout)

struct StagedSelectionPDFAnchor: Equatable {
    var pageIndex: Int
    var lastLineBounds: CGRect
}

// MARK: - PDFReader ViewModel

@MainActor
final class PDFReaderViewModel: ObservableObject {
    @Published var annotations: [PDFAnnotationRecord] = []
    @Published var currentColorHex: String = "#FFDE59"
    @Published var selectedAnnotationId: Int64?
    @Published var showNoteEditor = false
    @Published var pendingNoteText = ""
    @Published var pendingNoteSelection: PDFSelection?
    @Published var pendingNotePageIndex: Int = 0
    @Published var pendingNoteRects: [CGRect] = []
    @Published var stagedSelectionText = ""
    @Published var stagedSelectionPDFAnchor: StagedSelectionPDFAnchor?
    @Published var selectionToolbarLayout: SelectionToolbarLayout?
    @Published var currentPageIndex: Int = 0
    @Published var totalPages: Int = 0
    @Published var scaleFactor: CGFloat = 1.0
    /// When set, shows a note-edit popover for an existing annotation (e.g. after clicking a highlight).
    @Published var editingAnnotationInPlace: PDFAnnotationRecord?
    /// When set, shows an annotation action toolbar near the clicked highlight.
    @Published var clickedAnnotationRecord: PDFAnnotationRecord?
    @Published var annotationToolbarLayout: SelectionToolbarLayout?

    // MARK: - OCR Recognition
    @Published var ocrMarkdown: String?
    @Published var isOCRLoading = false
    @Published var ocrError: String?
    @Published var showOCRResult = false
    private var ocrTask: Task<Void, Never>?

    let reference: Reference
    let pdfURL: URL
    private let db: AppDatabase
    private var cancellables = Set<AnyCancellable>()
    private var stagedSelection: PDFSelection?
    private(set) var stagedSelectionPageRects: [Int: [CGRect]] = [:]

    var jumpToAnnotation: ((PDFAnnotationRecord) -> Void)?
    var clearSelectionInView: (() -> Void)?
    var onPageChanged: ((Int, Int) -> Void)?

    init(reference: Reference, db: AppDatabase = .shared) {
        self.reference = reference
        self.pdfURL = PDFService.pdfURL(for: reference.pdfPath ?? "")
        self.db = db

        guard let refId = reference.id else { return }

        db.observeAnnotations(referenceId: refId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("[PDFReaderViewModel] Annotation observation failed: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] annotations in
                    self?.annotations = annotations
                }
            )
            .store(in: &cancellables)
    }

    func addAnnotation(
        type: AnnotationType,
        selectedText: String?,
        noteText: String? = nil,
        pageIndex: Int,
        rects: [CGRect]
    ) {
        guard let refId = reference.id else { return }
        var record = PDFAnnotationRecord(
            referenceId: refId,
            type: type,
            selectedText: selectedText,
            noteText: noteText,
            color: currentColorHex,
            pageIndex: pageIndex,
            rects: rects
        )
        try? db.saveAnnotation(&record)
    }

    func addAnnotations(
        type: AnnotationType,
        selectedText: String?,
        noteText: String? = nil,
        pageRects: [Int: [CGRect]]
    ) {
        guard let refId = reference.id else { return }
        var records: [PDFAnnotationRecord] = []
        for pageIndex in pageRects.keys.sorted() {
            guard let rects = pageRects[pageIndex], !rects.isEmpty else { continue }
            records.append(
                PDFAnnotationRecord(
                    referenceId: refId,
                    type: type,
                    selectedText: selectedText,
                    noteText: noteText,
                    color: currentColorHex,
                    pageIndex: pageIndex,
                    rects: rects
                )
            )
        }
        try? db.saveAnnotations(&records)
    }

    func deleteAnnotation(_ annotation: PDFAnnotationRecord) {
        guard let id = annotation.id else { return }
        try? db.deleteAnnotation(id: id)
    }

    func updateAnnotationNote(_ annotation: PDFAnnotationRecord, noteText: String) {
        var updated = annotation
        updated.noteText = noteText.isEmpty ? nil : noteText
        try? db.saveAnnotation(&updated)
    }

    func updateAnnotationColor(_ annotation: PDFAnnotationRecord, color: String) {
        var updated = annotation
        updated.color = color
        try? db.saveAnnotation(&updated)
    }

    func dismissAnnotationToolbar() {
        clickedAnnotationRecord = nil
        annotationToolbarLayout = nil
    }

    func navigateTo(_ annotation: PDFAnnotationRecord) {
        selectedAnnotationId = annotation.id
        jumpToAnnotation?(annotation)
    }

    var annotationsByPage: [Int: [PDFAnnotationRecord]] {
        Dictionary(grouping: annotations, by: \.pageIndex)
    }

    var hasStagedSelection: Bool {
        !stagedSelectionText.isEmpty && !stagedSelectionPageRects.isEmpty
    }

    func stageSelection(_ selection: PDFSelection, pageRects: [Int: [CGRect]], pdfAnchor: StagedSelectionPDFAnchor?) {
        let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, !pageRects.isEmpty else {
            clearStagedSelection(clearViewSelection: false)
            return
        }

        stagedSelection = selection
        stagedSelectionPageRects = pageRects
        stagedSelectionText = text
        stagedSelectionPDFAnchor = pdfAnchor
    }

    func clearStagedSelection(clearViewSelection: Bool = true) {
        stagedSelection = nil
        stagedSelectionPageRects = [:]
        stagedSelectionText = ""
        stagedSelectionPDFAnchor = nil
        selectionToolbarLayout = nil
        if clearViewSelection {
            clearSelectionInView?()
        }
    }

    func clearPendingNoteDraft() {
        pendingNoteText = ""
        pendingNoteSelection = nil
        pendingNotePageIndex = 0
        pendingNoteRects = []
    }

    func applySelectionAction(_ tool: AnnotationTool) {
        guard tool != .cursor else { return }
        guard hasStagedSelection else { return }

        if tool == .note {
            pendingNoteSelection = stagedSelection
            pendingNoteText = ""
            pendingNotePageIndex = stagedSelectionPageRects.keys.sorted().first ?? 0
            pendingNoteRects = stagedSelectionPageRects[pendingNotePageIndex] ?? []
            showNoteEditor = true
            clearStagedSelection()
            return
        }

        let annotationType: AnnotationType = tool == .underline ? .underline : .highlight
        addAnnotations(
            type: annotationType,
            selectedText: stagedSelectionText,
            pageRects: stagedSelectionPageRects
        )
        clearStagedSelection()
    }

    // MARK: - OCR

    func startOCR() {
        guard !isOCRLoading else { return }
        ocrTask?.cancel()
        isOCRLoading = true
        ocrError = nil

        ocrTask = Task {
            do {
                let markdown = try await PaddleOCRClient.shared.recognize(fileURL: pdfURL)
                self.ocrMarkdown = markdown
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                    self.showOCRResult = true
                }
            } catch is CancellationError {
                // ignored
            } catch {
                self.ocrError = error.localizedDescription
            }
            self.isOCRLoading = false
        }
    }

    func dismissOCR() {
        showOCRResult = false
    }
}

// MARK: - Main Reader

struct PDFReaderView: View {
    @StateObject private var viewModel: PDFReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAnnotationSidebar = true
    @State private var sidebarWidth: CGFloat = 300
    @GestureState private var dragOffset: CGFloat = 0
    @State private var showOutlineSidebar = true
    @State private var outlineSidebarWidth: CGFloat = 240
    @GestureState private var outlineDragOffset: CGFloat = 0
    @State private var outlineSidebarTab: PDFSidebarTab = .outline
    @State private var isEditingPage = false
    @State private var pageInputText = ""
    private let onClose: (() -> Void)?

    init(reference: Reference, onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: PDFReaderViewModel(reference: reference))
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar: TOC / Info
            if showOutlineSidebar {
                PDFReaderSidebarView(reference: viewModel.reference, selectedTab: $outlineSidebarTab)
                    .frame(width: min(max(outlineSidebarWidth + outlineDragOffset, 200), 400))
                    .transition(.move(edge: .leading))

                Rectangle()
                    .fill(pdfContainerBackground)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .updating($outlineDragOffset) { value, state, _ in
                                state = value.translation.width
                            }
                            .onEnded { value in
                                let newWidth = outlineSidebarWidth + value.translation.width
                                outlineSidebarWidth = min(max(newWidth, 200), 400)
                            }
                    )
            }

            // Elevated plane: center PDF + right annotation sidebar
            HStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    centerContentView

                    floatingReaderTab
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.88), value: viewModel.showOCRResult)
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(readerPanelBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.10), radius: 6, x: 0, y: 2)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(pdfContainerBackground)
                .ignoresSafeArea(.container, edges: .top)

                if showAnnotationSidebar {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(pdfContainerBackground)
                            .frame(width: 4)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.resizeLeftRight.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .updating($dragOffset) { value, state, _ in
                                        state = value.translation.width
                                    }
                                    .onEnded { value in
                                        let newWidth = sidebarWidth - value.translation.width
                                        sidebarWidth = min(max(newWidth, 260), 500)
                                    }
                            )

                        AnnotationSidebarView(
                            annotations: viewModel.annotations,
                            selectedAnnotationId: viewModel.selectedAnnotationId,
                            onNavigate: { annotation in
                                viewModel.navigateTo(annotation)
                            },
                            onDelete: { annotation in
                                viewModel.deleteAnnotation(annotation)
                            },
                            onUpdateNote: { annotation, noteText in
                                viewModel.updateAnnotationNote(annotation, noteText: noteText)
                            }
                        )
                        .equatable()
                            .frame(width: min(max(sidebarWidth - dragOffset, 260), 500))
                            .transition(.move(edge: .trailing))
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(minWidth: 980, minHeight: 720)
        .background {
            pdfContainerBackground
                .ignoresSafeArea(.container, edges: .top)
        }
        .animation(
            .spring(response: 0.3, dampingFraction: 0.82),
            value: showAnnotationSidebar
        )
        .animation(
            .spring(response: 0.3, dampingFraction: 0.82),
            value: showOutlineSidebar
        )
        .animation(
            .spring(response: 0.3, dampingFraction: 0.82),
            value: viewModel.hasStagedSelection && viewModel.selectionToolbarLayout?.visible == true
        )
        .navigationTitle(viewModel.reference.title)
        .toolbarBackground(pdfContainerBackground, for: .windowToolbar)
        .onAppear {
            NoteEditorPool.shared.warmUp()
        }
        .alert("OCR 识别失败", isPresented: Binding(
            get: { viewModel.ocrError != nil },
            set: { if !$0 { viewModel.ocrError = nil } }
        )) {
            Button("确定") { viewModel.ocrError = nil }
        } message: {
            Text(viewModel.ocrError ?? "")
        }
    }

    private static let ocrViewTransition: AnyTransition = .asymmetric(
        insertion: .opacity
            .combined(with: .scale(scale: 0.96, anchor: .center))
            .combined(with: .offset(y: 6)),
        removal: .opacity
            .combined(with: .scale(scale: 0.96, anchor: .center))
            .combined(with: .offset(y: 6))
    )

    @ViewBuilder
    private var centerContentView: some View {
        if viewModel.showOCRResult, let markdown = viewModel.ocrMarkdown {
            OCRMarkdownView(markdown: markdown, onDismiss: {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                    viewModel.dismissOCR()
                }
            })
            .transition(Self.ocrViewTransition)
        } else {
            pdfContentView
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(readerCanvasBackground)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    selectionActionBarOverlay
                }
                .overlay {
                    annotationActionBarOverlay
                }
                .transition(Self.ocrViewTransition)
        }
    }

    /// Apply `.colorInvert()` at the SwiftUI level instead of using CIFilter
    /// contentFilters inside the NSView. SwiftUI composites the inversion on the
    /// GPU without rasterizing the NSView's text rendering pipeline, so text
    /// stays crisp on Retina displays.
    @ViewBuilder
    private var pdfContentView: some View {
        if colorScheme == .dark {
            AnnotatablePDFView(viewModel: viewModel)
                .colorInvert()
        } else {
            AnnotatablePDFView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var selectionActionBarOverlay: some View {
        let shouldShow = viewModel.hasStagedSelection
            && viewModel.selectionToolbarLayout?.visible == true
        if shouldShow, let layout = viewModel.selectionToolbarLayout {
            SelectionActionBar(viewModel: viewModel, metrics: layout.metrics)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: layout.origin.x, y: layout.origin.y)
                .allowsHitTesting(true)
                .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                .animation(.spring(response: 0.25, dampingFraction: 0.82), value: layout.origin)
        }
    }

    @ViewBuilder
    private var annotationActionBarOverlay: some View {
        if viewModel.clickedAnnotationRecord != nil,
           let layout = viewModel.annotationToolbarLayout, layout.visible {
            AnnotationActionBar(viewModel: viewModel, metrics: layout.metrics)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: layout.origin.x, y: layout.origin.y)
                .allowsHitTesting(true)
                .transition(.opacity)
        }
    }

    private var floatingReaderTab: some View {
        HStack(spacing: 4) {
            // Left sidebar toggle (TOC / Info)
            Button {
                withAnimation { showOutlineSidebar.toggle() }
            } label: {
                Image(systemName: showOutlineSidebar ? "sidebar.left" : "sidebar.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(showOutlineSidebar ? .primary : .secondary)
                    .frame(width: 26, height: 20)
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(FloatingGlassCapsuleButtonStyle(isActive: showOutlineSidebar))
            .help("显示/隐藏目录侧边栏")

            HStack(spacing: 1) {
                floatingIconButton(systemName: "minus.magnifyingglass", help: "缩小", action: zoomOut)
                floatingIconButton(systemName: "plus.magnifyingglass", help: "放大", action: zoomIn)
                floatingIconButton(systemName: "arrow.left.and.right", help: "适合宽度", action: fitToWidth)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(floatingInnerFill, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(floatingInnerStroke, lineWidth: 0.45)
            )

            pageIndicator

            // OCR recognition button
            Button {
                viewModel.startOCR()
            } label: {
                if viewModel.isOCRLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 26, height: 20)
                } else {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(viewModel.showOCRResult ? .primary : .secondary)
                        .frame(width: 26, height: 20)
                        .contentShape(Capsule(style: .continuous))
                }
            }
            .buttonStyle(FloatingGlassCapsuleButtonStyle(isActive: viewModel.showOCRResult))
            .disabled(viewModel.isOCRLoading)
            .help("智能识别（OCR）")

            // Right sidebar toggle (Annotations)
            Button {
                withAnimation { showAnnotationSidebar.toggle() }
            } label: {
                Image(systemName: showAnnotationSidebar ? "sidebar.right" : "sidebar.right")
                    .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(showAnnotationSidebar ? .primary : .secondary)
                .frame(width: 26, height: 20)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(FloatingGlassCapsuleButtonStyle(isActive: showAnnotationSidebar))
            .help("显示/隐藏标注侧边栏")
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(floatingOuterStroke, lineWidth: 0.55)
        )
        .shadow(color: floatingShadowPrimary, radius: 10, y: 4)
        .shadow(color: floatingShadowSecondary, radius: 2, y: 1)
    }

    @ViewBuilder
    private var pageIndicator: some View {
        if isEditingPage {
            TextField("", text: $pageInputText)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(width: 40)
                .textFieldStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(floatingInnerFill, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                )
                .onSubmit {
                    if let page = Int(pageInputText), page >= 1, page <= viewModel.totalPages {
                        if let pdfView = findPDFView(),
                           let doc = pdfView.document,
                           let target = doc.page(at: page - 1) {
                            pdfView.go(to: target)
                        }
                    }
                    isEditingPage = false
                }
        } else {
            Text(pageDisplayText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(floatingInnerFill, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(floatingInnerStroke, lineWidth: 0.45)
                )
                .onTapGesture {
                    pageInputText = "\(viewModel.currentPageIndex + 1)"
                    isEditingPage = true
                }
        }
    }

    private func floatingIconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 20)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(FloatingGlassIconButtonStyle())
        .help(help)
    }

    private var pageDisplayText: String {
        guard viewModel.totalPages > 0 else { return "PDF" }
        return "\(viewModel.currentPageIndex + 1)/\(viewModel.totalPages)"
    }

    private var floatingInnerFill: Color {
        Color.white.opacity(colorScheme == .dark ? 0.07 : 0.24)
    }

    private var floatingInnerStroke: Color {
        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18)
    }

    private var floatingOuterStroke: Color {
        Color.white.opacity(colorScheme == .dark ? 0.12 : 0.28)
    }

    private var floatingShadowPrimary: Color {
        Color.black.opacity(colorScheme == .dark ? 0.22 : 0.07)
    }

    private var floatingShadowSecondary: Color {
        Color.black.opacity(colorScheme == .dark ? 0.12 : 0.03)
    }





    private var pdfContainerBackground: Color {
        Color(nsColor: NSColor(name: nil) { trait in
            trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.12, alpha: 1.0)
                : NSColor(calibratedWhite: 0.90, alpha: 1.0)
        })
    }

    private var readerPanelBackground: Color {
        Color(nsColor: NSColor(name: nil) { trait in
            trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.12, alpha: 1.0)
                : .white
        })
    }

    private var readerCanvasBackground: Color {
        Color(nsColor: NSColor(name: nil) { trait in
            trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.02, alpha: 1.0)
                : NSColor(calibratedWhite: 0.94, alpha: 1.0)
        })
    }

    private var panelEdgeShadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.22 : 0.09)
    }

    private func zoomIn() {
        guard let pdfView = findPDFView() else { return }
        let newScale = min(pdfView.scaleFactor * 1.2, 5.0)
        pdfView.scaleFactor = newScale
        viewModel.scaleFactor = newScale
    }

    private func zoomOut() {
        guard let pdfView = findPDFView() else { return }
        let newScale = max(pdfView.scaleFactor * 0.8, 0.5)
        pdfView.scaleFactor = newScale
        viewModel.scaleFactor = newScale
    }

    private func fitToWidth() {
        guard let pdfView = findPDFView() else { return }
        pdfView.autoScales = false
        pdfView.scaleFactor = 1.0
        viewModel.scaleFactor = 1.0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pdfView.autoScales = true
        }
    }

    private func findPDFView() -> PDFView? {
        guard let window = NSApp.keyWindow,
              let contentView = window.contentView else { return nil }
        return findPDFViewInView(contentView)
    }

    private func findPDFViewInView(_ view: NSView) -> PDFView? {
        if let pdfView = view as? PDFView {
            return pdfView
        }
        for subview in view.subviews {
            if let found = findPDFViewInView(subview) {
                return found
            }
        }
        return nil
    }
}

private struct FloatingGlassIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule(style: .continuous)
                    .fill(
                        Color.white.opacity(
                            configuration.isPressed
                                ? (colorScheme == .dark ? 0.13 : 0.34)
                                : (colorScheme == .dark ? 0.04 : 0.12)
                        )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct FloatingGlassCapsuleButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule(style: .continuous)
                    .fill(
                        Color.white.opacity(
                            configuration.isPressed
                                ? (colorScheme == .dark ? 0.14 : 0.36)
                                : (isActive
                                    ? (colorScheme == .dark ? 0.08 : 0.20)
                                    : (colorScheme == .dark ? 0.04 : 0.10))
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(
                            isActive
                                ? (colorScheme == .dark ? 0.08 : 0.16)
                                : 0
                        ),
                        lineWidth: 0.45
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SelectionActionBar: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    let metrics: ReaderActionBarMetrics
    @ObservedObject private var aiChat = AIChatWindowManager.shared
    @State private var noteMarkdown = ""
    @State private var editorContentHeight: CGFloat = 36
    @State private var capturedSelectionText = ""
    @State private var capturedPageRects: [Int: [CGRect]] = [:]
    @Environment(\.colorScheme) private var colorScheme

    private func saveNoteIfNeeded() {
        let md = noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !md.isEmpty, !capturedSelectionText.isEmpty else { return }
        viewModel.addAnnotations(
            type: .note,
            selectedText: capturedSelectionText,
            noteText: md,
            pageRects: capturedPageRects
        )
        noteMarkdown = ""
    }

    private var bgColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.22, alpha: 1))
            : Color(nsColor: NSColor(white: 0.13, alpha: 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top row: actions + color dots
            HStack(spacing: metrics.topRowSpacing) {
                toolbarButton(icon: "highlighter", label: "高亮") {
                    viewModel.applySelectionAction(.highlight)
                }

                toolbarButton(icon: "doc.on.doc", label: "复制") {
                    if !viewModel.stagedSelectionText.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.stagedSelectionText, forType: .string)
                    }
                }

                AISparklesHoverButton(
                    metrics: metrics,
                    isLoading: aiChat.isLoading,
                    onTranslate: {
                        guard !viewModel.stagedSelectionText.isEmpty else { return }
                        let text = viewModel.stagedSelectionText
                        Task {
                            do {
                                let prompt = "请将以下内容翻译成中文，只返回翻译结果，不要添加任何解释：\n\n\(text)"
                                let response = try await AIChatWindowManager.shared.sendText(prompt)
                                let sep = noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
                                noteMarkdown += sep + response
                            } catch {
                                let sep = noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
                                noteMarkdown += sep + "⚠️ \(error.localizedDescription)"
                            }
                        }
                    },
                    onQA: {
                        guard !viewModel.stagedSelectionText.isEmpty else { return }
                        let text = viewModel.stagedSelectionText
                        Task {
                            do {
                                try await AIChatWindowManager.shared.injectTextOnly(text)
                            } catch {
                                let sep = noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
                                noteMarkdown += sep + "⚠️ \(error.localizedDescription)"
                            }
                        }
                    }
                )

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

                Spacer(minLength: 4)

                separator

                toolbarButton(icon: "trash", label: "关闭") {
                    saveNoteIfNeeded()
                    viewModel.clearStagedSelection()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, metrics.topRowHorizontalPadding)
            .padding(.vertical, metrics.topRowVerticalPadding)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
                .padding(.horizontal, metrics.dividerHorizontalPadding)

            // Note section: inline editor (auto-saves on dismiss / trash click)
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
            .padding(.bottom, metrics.actionRowVerticalPadding)
        }
        .frame(width: metrics.toolbarWidth)
        .onAppear {
            capturedSelectionText = viewModel.stagedSelectionText
            capturedPageRects = viewModel.stagedSelectionPageRects
        }
        .onChange(of: viewModel.stagedSelectionText) { _, newValue in
            if !newValue.isEmpty {
                capturedSelectionText = newValue
                capturedPageRects = viewModel.stagedSelectionPageRects
            }
        }
        .onDisappear {
            saveNoteIfNeeded()
        }
        .background(bgColor, in: RoundedRectangle(cornerRadius: metrics.toolbarCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.toolbarCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
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
        .buttonStyle(NotionToolbarButtonStyle(cornerRadius: metrics.buttonCornerRadius))
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct NotionToolbarButtonStyle: ButtonStyle {
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

// MARK: - Annotation Action Bar (for clicked existing highlights)

/// Toolbar shown when user clicks an existing highlight.
/// Provides: change color, edit note, delete.
private struct AnnotationActionBar: View {
    @ObservedObject var viewModel: PDFReaderViewModel
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
                // Top row: color dots + actions
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

                    Spacer(minLength: 4)

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
                    .buttonStyle(NotionToolbarButtonStyle(cornerRadius: metrics.buttonCornerRadius))
                    .help("删除标注")
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, metrics.topRowHorizontalPadding)
                .padding(.vertical, metrics.topRowVerticalPadding)

                // Divider
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
                            // Animate so the height change doesn't trigger a synchronous
                            // layout pass that makes the PDF view jitter.
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                                editorContentHeight = height
                            }
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
                // Pre-estimate height from line count to reduce the initial jump
                // when WKWebView reports its actual height.
                if !noteText.isEmpty {
                    let lines = noteText.components(separatedBy: "\n").count
                    let estimated = CGFloat(lines) * 22 + 24
                    editorContentHeight = min(max(estimated, 36), metrics.annotationEditorMaxHeight)
                }
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

// MARK: - PDFKit Bridge

final class CommitAwarePDFView: PDFView {
    var onSelectionCommitted: ((PDFSelection) -> Void)?
    var onSelectionCleared: (() -> Void)?
    var onAnnotationClicked: ((PDFAnnotation) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
            _ = NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: self)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)

        if let selection = currentSelection,
           let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            commitSelectionIfNeeded()
            return
        }

        if let ann = annotationAtClick(event) {
            onAnnotationClicked?(ann)
            return
        }

        onSelectionCleared?()
    }

    override func keyUp(with event: NSEvent) {
        super.keyUp(with: event)
        if currentSelection != nil {
            commitSelectionIfNeeded()
        }
    }

    private func annotationAtClick(_ event: NSEvent) -> PDFAnnotation? {
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(for: point, nearest: true) else { return nil }
        let pagePoint = convert(point, to: page)
        return page.annotation(at: pagePoint)
    }

    private func commitSelectionIfNeeded() {
        guard let selection = currentSelection,
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            onSelectionCleared?()
            return
        }

        if let copiedSelection = selection.copy() as? PDFSelection {
            onSelectionCommitted?(copiedSelection)
        } else {
            onSelectionCommitted?(selection)
        }
    }
}

struct AnnotatablePDFView: NSViewRepresentable {
    @ObservedObject var viewModel: PDFReaderViewModel
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = CommitAwarePDFView()
        pdfView.autoScales = true
        pdfView.displaysPageBreaks = true
        pdfView.pageBreakMargins = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.pageShadowsEnabled = false
        pdfView.applyElegantScrollers()
        context.coordinator.isDarkMode = colorScheme == .dark
        Self.applyReaderAppearance(to: pdfView, isDarkMode: context.coordinator.isDarkMode)

        // Remove NSScrollView bezel border and re-apply dark canvas after subviews settle.
        let isDark = context.coordinator.isDarkMode
        DispatchQueue.main.async { [weak pdfView] in
            guard let pdfView, let sv = pdfView.internalScrollView else { return }
            sv.borderType = .noBorder
            sv.drawsBackground = true
            Self.applyReaderAppearance(to: pdfView, isDarkMode: isDark)
        }

        context.coordinator.pdfView = pdfView
        context.coordinator.loadDocument(from: viewModel.pdfURL, into: pdfView)
        pdfView.onSelectionCommitted = { [weak coordinator = context.coordinator] selection in
            coordinator?.handleCommittedSelection(selection)
        }
        pdfView.onAnnotationClicked = { [weak coordinator = context.coordinator] ann in
            coordinator?.handleAnnotationClicked(ann)
        }
        pdfView.onSelectionCleared = { [weak coordinator = context.coordinator] in
            coordinator?.handleClearedSelection()
        }

        DispatchQueue.main.async { [weak coordinator = context.coordinator, weak pdfView] in
            guard let coordinator, let pdfView else { return }
            coordinator.ensureObservers(for: pdfView)
        }

        viewModel.clearSelectionInView = { [weak pdfView] in
            pdfView?.clearSelection()
        }

        viewModel.jumpToAnnotation = { [weak pdfView] annotation in
            guard let pdfView = pdfView,
                  let document = pdfView.document,
                  annotation.pageIndex < document.pageCount,
                  let page = document.page(at: annotation.pageIndex) else { return }
            navigateToAnnotation(in: pdfView, page: page, bounds: annotation.unionBounds)
        }

        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.isDarkMode = colorScheme == .dark

        guard let pdfView = pdfView as? CommitAwarePDFView else { return }

        pdfView.onSelectionCommitted = { [weak coordinator = context.coordinator] selection in
            coordinator?.handleCommittedSelection(selection)
        }
        pdfView.onAnnotationClicked = { [weak coordinator = context.coordinator] ann in
            coordinator?.handleAnnotationClicked(ann)
        }
        pdfView.onSelectionCleared = { [weak coordinator = context.coordinator] in
            coordinator?.handleClearedSelection()
        }

        context.coordinator.ensureObservers(for: pdfView)
        viewModel.clearSelectionInView = { [weak pdfView] in
            pdfView?.clearSelection()
        }

        context.coordinator.loadDocument(from: viewModel.pdfURL, into: pdfView)

        pdfView.applyElegantScrollers()
        Self.applyReaderAppearance(to: pdfView, isDarkMode: context.coordinator.isDarkMode)

        // Skip syncAnnotations if annotations haven't changed (hash check)
        let currentHash = viewModel.annotations.hashValue
        if currentHash != context.coordinator.lastAnnotationsHash {
            context.coordinator.lastAnnotationsHash = currentHash
            syncAnnotations(pdfView: pdfView, records: viewModel.annotations, coordinator: context.coordinator)
        }
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: Coordinator) {
        coordinator.teardownObservers()
        coordinator.cancelDocumentLoad()
        pdfView.document = nil
    }

    private func syncAnnotations(pdfView: PDFView, records: [PDFAnnotationRecord], coordinator: Coordinator) {
        guard let document = pdfView.document else { return }
        coordinator.applyAnnotationRecords(records, to: document)
    }

    private func createPDFAnnotation(from record: PDFAnnotationRecord) -> PDFAnnotation {
        let bounds = sanitizedAnnotationBounds(for: record)
        let color = AnnotationColor.nsColor(for: record.color)
        let rects = sanitizedAnnotationRects(for: record)

        let annotation: PDFAnnotation
        switch record.type {
        case .highlight:
            annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = color
        case .underline:
            annotation = PDFAnnotation(bounds: bounds, forType: .underline, withProperties: nil)
            annotation.color = color.withAlphaComponent(0.8)
        case .note:
            annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = color
        }

        if record.type != .note, !rects.isEmpty {
            annotation.quadrilateralPoints = buildQuadrilateralPoints(from: rects, relativeTo: bounds)
        }

        return annotation
    }

    private func sanitizedAnnotationBounds(for record: PDFAnnotationRecord) -> CGRect {
        let bounds = record.unionBounds.standardized
        if bounds.width.isFinite,
           bounds.height.isFinite,
           bounds.minX.isFinite,
           bounds.minY.isFinite,
           bounds.width > 0,
           bounds.height > 0 {
            return bounds
        }

        if let fallback = sanitizedAnnotationRects(for: record).first {
            return fallback.standardized
        }

        return CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    private func sanitizedAnnotationRects(for record: PDFAnnotationRecord) -> [CGRect] {
        record.rects
            .map { $0.standardized }
            .filter {
                $0.minX.isFinite && $0.minY.isFinite
                    && $0.width.isFinite && $0.height.isFinite
                    && $0.width > 0 && $0.height > 0
            }
    }

    private func buildQuadrilateralPoints(from rects: [CGRect], relativeTo union: CGRect) -> [NSValue] {
        rects.flatMap { rect -> [NSValue] in
            let relativeRect = rect.offsetBy(dx: -union.minX, dy: -union.minY)
            let topLeft = CGPoint(x: relativeRect.minX, y: relativeRect.maxY)
            let topRight = CGPoint(x: relativeRect.maxX, y: relativeRect.maxY)
            let bottomLeft = CGPoint(x: relativeRect.minX, y: relativeRect.minY)
            let bottomRight = CGPoint(x: relativeRect.maxX, y: relativeRect.minY)
            return [topLeft, topRight, bottomLeft, bottomRight].map(NSValue.init(point:))
        }
    }

    private func navigateToAnnotation(in pdfView: PDFView, page: PDFPage, bounds: CGRect) {
        let focusRect = bounds.insetBy(dx: -120, dy: -200)
        pdfView.go(to: focusRect, on: page)
    }

    private static func applyReaderAppearance(to pdfView: PDFView, isDarkMode: Bool) {
        // When dark mode is on, SwiftUI applies .colorInvert() on the entire
        // view. So internally we use pure white (inverts to pure black).
        let canvasBackgroundColor = isDarkMode ? .white : canvasBackgroundColor(isDarkMode: false)
        let documentBackgroundColor = isDarkMode ? .white : documentViewBackgroundColor(isDarkMode: false)
        pdfView.displaysPageBreaks = !isDarkMode
        pdfView.pageBreakMargins = isDarkMode
            ? NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            : NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        pdfView.backgroundColor = canvasBackgroundColor
        pdfView.wantsLayer = true
        pdfView.layer?.backgroundColor = canvasBackgroundColor.cgColor
        pdfView.layer?.cornerRadius = 10
        pdfView.layer?.masksToBounds = true

        if let scrollView = pdfView.internalScrollView {
            scrollView.backgroundColor = canvasBackgroundColor
            scrollView.drawsBackground = false
            scrollView.contentView.backgroundColor = canvasBackgroundColor
            scrollView.contentView.wantsLayer = true
            scrollView.contentView.layer?.backgroundColor = canvasBackgroundColor.cgColor
            normalizeScrollViewBackgroundHierarchy(in: scrollView, backgroundColor: canvasBackgroundColor)
        }

        guard let documentView = pdfView.documentView else { return }
        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = documentBackgroundColor.cgColor
        documentView.contentFilters = []
        normalizeDocumentHierarchy(in: documentView, backgroundColor: documentBackgroundColor)
    }

    private static func normalizeScrollViewBackgroundHierarchy(in scrollView: NSScrollView, backgroundColor: NSColor) {
        for subview in scrollView.subviews {
            let className = NSStringFromClass(type(of: subview))

            if subview === scrollView.contentView || className.contains("PDFClipView") {
                subview.wantsLayer = true
                subview.layer?.backgroundColor = backgroundColor.cgColor
                continue
            }

            if subview is NSVisualEffectView || className.contains("ContentBackground") {
                subview.wantsLayer = true
                subview.layer?.backgroundColor = NSColor.clear.cgColor
                subview.isHidden = true
                continue
            }
        }
    }

    private static func normalizeDocumentHierarchy(in rootView: NSView, backgroundColor: NSColor) {
        for subview in rootView.subviews {
            let className = NSStringFromClass(type(of: subview))
            if className.contains("PDFPageView") {
                continue
            }

            subview.wantsLayer = true
            subview.layer?.backgroundColor = backgroundColor.cgColor
            normalizeDocumentHierarchy(in: subview, backgroundColor: backgroundColor)
        }
    }

    private static func canvasBackgroundColor(isDarkMode: Bool) -> NSColor {
        isDarkMode
            ? NSColor(calibratedWhite: 0.02, alpha: 1.0)
            : NSColor(calibratedWhite: 0.94, alpha: 1.0)
    }

    private static func documentViewBackgroundColor(isDarkMode: Bool) -> NSColor {
        canvasBackgroundColor(isDarkMode: isDarkMode)
    }

    struct TrackedAnnotation {
        let annotation: PDFAnnotation
        let pageIndex: Int
        let renderHash: Int
    }

    class Coordinator: NSObject {
        var viewModel: PDFReaderViewModel
        weak var pdfView: PDFView?
        var trackedAnnotations: [Int64: TrackedAnnotation] = [:]
        var lastAnnotationsHash: Int = 0
        var isDarkMode = false

        private var scrollObserver: NSObjectProtocol?
        private var scaleObserver: NSObjectProtocol?
        private var pageChangedObserver: NSObjectProtocol?
        private weak var observedClipView: NSClipView?
        private weak var scaleObservedPDFView: PDFView?
        private weak var pageObservedPDFView: PDFView?
        private var loadedPDFURL: URL?
        private var documentLoadTask: Task<Void, Never>?
        private var toolbarDebounceTask: Task<Void, Never>?

        init(viewModel: PDFReaderViewModel) {
            self.viewModel = viewModel
        }

        deinit {
            teardownObservers()
            cancelDocumentLoad()
            toolbarDebounceTask?.cancel()
        }

        // MARK: - Annotation sync
        //
        // NEVER call page.removeAnnotation() after the document is set on PDFView.
        // PDFKit's tile pool renders pages on a private background queue and reads
        // the per-page annotations NSMutableArray concurrently. Mutating that array
        // from the main thread while the renderer reads it causes memory corruption
        // (a slot ends up pointing to an arbitrary address – observed as
        // __NSCFConstantString – and PDFKit crashes calling akAnnotationAdaptor on it).
        //
        // Safe strategy:
        //   • Pre-load ALL annotations into pages before assigning the document to
        //     PDFView (no renderer running yet → no race).
        //   • For subsequent changes, update annotation properties in-place (color,
        //     shouldDisplay) and only ever ADD, never remove from the array.
        //   • "Deleted" annotations become invisible via shouldDisplay = false.

        /// Pre-load – called BEFORE pdfView.document is set.
        func preloadAnnotations(into document: PDFDocument, records: [PDFAnnotationRecord]) {
            trackedAnnotations.removeAll()
            for record in records {
                guard let recordId = record.id,
                      record.pageIndex < document.pageCount,
                      let page = document.page(at: record.pageIndex) else { continue }
                let annotation = Self.makePDFAnnotation(from: record)
                page.addAnnotation(annotation)
                trackedAnnotations[recordId] = TrackedAnnotation(
                    annotation: annotation,
                    pageIndex: record.pageIndex,
                    renderHash: record.renderHash
                )
            }
        }

        /// Incremental sync – called from updateNSView after document is live.
        /// Only adds new annotations; never removes from the page array.
        func applyAnnotationRecords(_ records: [PDFAnnotationRecord], to document: PDFDocument) {
            let recordIds = Set(records.compactMap { $0.id })

            // Hide annotations whose records were deleted.
            for (key, tracked) in trackedAnnotations where !recordIds.contains(key) {
                tracked.annotation.shouldDisplay = false
            }

            for record in records {
                guard let recordId = record.id else { continue }
                let recordHash = record.renderHash

                if let tracked = trackedAnnotations[recordId],
                   tracked.renderHash == recordHash {
                    // Unchanged — make sure it's visible (may have been hidden).
                    if !tracked.annotation.shouldDisplay { tracked.annotation.shouldDisplay = true }
                    continue
                }

                if let tracked = trackedAnnotations[recordId] {
                    // Exists but properties changed (e.g. color) — update in-place.
                    // Avoid remove/add so the NSMutableArray is never mutated.
                    Self.applyProperties(of: record, to: tracked.annotation)
                    trackedAnnotations[recordId] = TrackedAnnotation(
                        annotation: tracked.annotation,
                        pageIndex: tracked.pageIndex,
                        renderHash: recordHash
                    )
                } else {
                    // New annotation — add once.
                    guard record.pageIndex < document.pageCount,
                          let page = document.page(at: record.pageIndex) else { continue }
                    let annotation = Self.makePDFAnnotation(from: record)
                    page.addAnnotation(annotation)
                    trackedAnnotations[recordId] = TrackedAnnotation(
                        annotation: annotation,
                        pageIndex: record.pageIndex,
                        renderHash: recordHash
                    )
                }
            }
        }

        // MARK: - Annotation factory (static — no instance state)

        static func makePDFAnnotation(from record: PDFAnnotationRecord) -> PDFAnnotation {
            let bounds = safeBounds(for: record)
            let color  = AnnotationColor.nsColor(for: record.color)
            let rects  = safeRects(for: record)

            let annotation: PDFAnnotation
            switch record.type {
            case .highlight:
                annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color
            case .underline:
                annotation = PDFAnnotation(bounds: bounds, forType: .underline, withProperties: nil)
                annotation.color = color.withAlphaComponent(0.8)
            case .note:
                annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color
            }
            if record.type != .note, !rects.isEmpty {
                annotation.quadrilateralPoints = buildQuads(from: rects, relativeTo: bounds)
            }
            return annotation
        }

        static func applyProperties(of record: PDFAnnotationRecord, to annotation: PDFAnnotation) {
            let color = AnnotationColor.nsColor(for: record.color)
            switch record.type {
            case .highlight, .note:
                annotation.color = color
            case .underline:
                annotation.color = color.withAlphaComponent(0.8)
            }
            annotation.shouldDisplay = true
        }

        private static func safeBounds(for record: PDFAnnotationRecord) -> CGRect {
            let b = record.unionBounds.standardized
            if b.width > 0, b.height > 0,
               b.minX.isFinite, b.minY.isFinite,
               b.width.isFinite, b.height.isFinite { return b }
            return safeRects(for: record).first?.standardized ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        private static func safeRects(for record: PDFAnnotationRecord) -> [CGRect] {
            record.rects.map { $0.standardized }.filter {
                $0.minX.isFinite && $0.minY.isFinite &&
                $0.width.isFinite && $0.height.isFinite &&
                $0.width > 0 && $0.height > 0
            }
        }

        private static func buildQuads(from rects: [CGRect], relativeTo union: CGRect) -> [NSValue] {
            rects.flatMap { rect -> [NSValue] in
                let r = rect.offsetBy(dx: -union.minX, dy: -union.minY)
                return [
                    CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
                    CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                ].map(NSValue.init(point:))
            }
        }

        func ensureObservers(for pdfView: PDFView) {
            if let clip = pdfView.internalScrollView?.contentView, observedClipView !== clip {
                removeScrollObserver()
                observedClipView = clip
                clip.postsBoundsChangedNotifications = true
                scrollObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clip,
                    queue: .main
                ) { [weak self] _ in
                    self?.requestToolbarLayoutUpdate()
                }
            }

            if scaleObservedPDFView !== pdfView {
                removeScaleObserver()
                scaleObservedPDFView = pdfView
                scaleObserver = NotificationCenter.default.addObserver(
                    forName: .PDFViewScaleChanged,
                    object: pdfView,
                    queue: .main
                ) { [weak self] _ in
                    self?.requestToolbarLayoutUpdate()
                }
            }

            if pageObservedPDFView !== pdfView {
                removePageChangedObserver()
                pageObservedPDFView = pdfView
                pageChangedObserver = NotificationCenter.default.addObserver(
                    forName: .PDFViewPageChanged,
                    object: pdfView,
                    queue: .main
                ) { [weak self, weak pdfView] _ in
                    guard let self, let pdfView,
                          let document = pdfView.document,
                          let firstPage = document.page(at: 0) else { return }
                    let currentPage = document.index(for: pdfView.currentPage ?? firstPage)
                    self.updatePageInfo(current: currentPage, total: document.pageCount)
                    self.requestToolbarLayoutUpdate()
                }
            }
        }

        func loadDocument(from url: URL, into pdfView: PDFView) {
            guard loadedPDFURL != url || pdfView.document == nil else { return }

            cancelDocumentLoad()
            loadedPDFURL = url
            self.pdfView = pdfView

            documentLoadTask = Task.detached(priority: .userInitiated) { [weak self] in
                let document = PDFDocument(url: url)
                guard !Task.isCancelled else { return }
                await self?.finishLoadingDocument(document, for: url)
            }
        }

        @MainActor
        private func finishLoadingDocument(_ document: PDFDocument?, for url: URL) {
            guard loadedPDFURL == url, let pdfView else { return }
            // Pre-load annotations into the PDFDocument pages BEFORE handing the
            // document to PDFView. At this point PDFKit's tile renderer hasn't
            // started yet, so there is zero race with the background render queue.
            if let document {
                preloadAnnotations(into: document, records: viewModel.annotations)
                lastAnnotationsHash = viewModel.annotations.hashValue
            }
            pdfView.document = document
            AnnotatablePDFView.applyReaderAppearance(to: pdfView, isDarkMode: isDarkMode)
            ensureObservers(for: pdfView)
            if let document,
               let firstPage = document.page(at: 0) {
                let currentPage = document.index(for: pdfView.currentPage ?? firstPage)
                updatePageInfo(current: currentPage, total: document.pageCount)
            } else {
                viewModel.currentPageIndex = 0
                viewModel.totalPages = 0
            }
        }

        func cancelDocumentLoad() {
            documentLoadTask?.cancel()
            documentLoadTask = nil
        }

        func teardownObservers() {
            removeScrollObserver()
            removeScaleObserver()
            removePageChangedObserver()
        }

        private func removeScrollObserver() {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            scrollObserver = nil
            observedClipView = nil
        }

        private func removeScaleObserver() {
            if let scaleObserver {
                NotificationCenter.default.removeObserver(scaleObserver)
            }
            scaleObserver = nil
            scaleObservedPDFView = nil
        }

        private func removePageChangedObserver() {
            if let pageChangedObserver {
                NotificationCenter.default.removeObserver(pageChangedObserver)
            }
            pageChangedObserver = nil
            pageObservedPDFView = nil
        }

        private func requestToolbarLayoutUpdate() {
            toolbarDebounceTask?.cancel()
            toolbarDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 16_000_000) // ~1 frame (16ms)
                guard !Task.isCancelled else { return }
                self?.updateToolbarLayouts()
            }
        }

        @MainActor
        func updateToolbarLayouts() {
            if let pdfView {
                AnnotatablePDFView.applyReaderAppearance(to: pdfView, isDarkMode: isDarkMode)
            }

            if viewModel.hasStagedSelection,
               let anchor = viewModel.stagedSelectionPDFAnchor,
               let pdfView {
                let newLayout = selectionToolbarLayout(for: anchor, in: pdfView)
                if viewModel.selectionToolbarLayout != newLayout {
                    viewModel.selectionToolbarLayout = newLayout
                }
            } else if viewModel.selectionToolbarLayout != nil {
                viewModel.selectionToolbarLayout = nil
            }

            if let annotation = viewModel.clickedAnnotationRecord,
               let pdfView {
                let newLayout = annotationToolbarLayout(for: annotation, in: pdfView)
                if viewModel.annotationToolbarLayout != newLayout {
                    viewModel.annotationToolbarLayout = newLayout
                }
            } else if viewModel.annotationToolbarLayout != nil {
                viewModel.annotationToolbarLayout = nil
            }
        }

        func handleCommittedSelection(_ selection: PDFSelection) {
            let pageRects = rectsByPage(for: selection)
            let pdfAnchor: StagedSelectionPDFAnchor?
            if let doc = pdfView?.document {
                pdfAnchor = Self.lastLinePDFAnchor(for: selection, document: doc)
            } else {
                pdfAnchor = nil
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                viewModel.dismissAnnotationToolbar()
                viewModel.stageSelection(selection, pageRects: pageRects, pdfAnchor: pdfAnchor)
                updateToolbarLayouts()
            }
        }

        func handleAnnotationClicked(_ annotation: PDFAnnotation) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Clear any active text selection toolbar
                viewModel.clearStagedSelection(clearViewSelection: true)
                for (id, tracked) in trackedAnnotations where tracked.annotation === annotation {
                    viewModel.selectedAnnotationId = id
                    if let record = viewModel.annotations.first(where: { $0.id == id }) {
                        viewModel.clickedAnnotationRecord = record
                        updateToolbarLayouts()
                    }
                    return
                }
            }
        }

        static func lastLinePDFAnchor(for selection: PDFSelection, document: PDFDocument) -> StagedSelectionPDFAnchor? {
            let lines = selection.selectionsByLine()
            guard let lastLine = lines.last else { return nil }

            var chosenPage: PDFPage?
            var chosenBounds: CGRect = .null
            for page in lastLine.pages {
                let bounds = lastLine.bounds(for: page).standardized
                guard !bounds.isNull, !bounds.isEmpty, bounds.width > 0, bounds.height > 0 else { continue }
                chosenPage = page
                chosenBounds = bounds
            }
            guard let page = chosenPage, !chosenBounds.isNull else { return nil }
            let idx = document.index(for: page)
            return StagedSelectionPDFAnchor(pageIndex: idx, lastLineBounds: chosenBounds)
        }

        func handleClearedSelection() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                viewModel.clearStagedSelection(clearViewSelection: false)
                viewModel.dismissAnnotationToolbar()
            }
        }

        @MainActor
        private func selectionToolbarLayout(for anchor: StagedSelectionPDFAnchor, in pdfView: PDFView) -> SelectionToolbarLayout? {
            guard let document = pdfView.document,
                  anchor.pageIndex >= 0,
                  anchor.pageIndex < document.pageCount,
                  let page = document.page(at: anchor.pageIndex) else {
                return nil
            }

            let rectInView = pdfView.convert(anchor.lastLineBounds, from: page)
            let overlaySize = pdfView.bounds.size
            let metrics = ReaderActionBarMetrics.resolve(for: .pdf, viewportWidth: overlaySize.width)

            guard !rectInView.isNull, !rectInView.isEmpty else {
                return SelectionToolbarLayout(origin: .zero, visible: false, metrics: metrics)
            }
            guard rectInView.intersects(pdfView.bounds) else {
                return SelectionToolbarLayout(origin: .zero, visible: false, metrics: metrics)
            }

            let overlayRect = Self.overlayRect(fromPDFViewRect: rectInView, overlayHeight: overlaySize.height)
            return SelectionToolbarLayout.anchored(
                to: overlayRect,
                overlaySize: overlaySize,
                metrics: metrics,
                horizontalAnchor: .trailing
            )
        }

        @MainActor
        private func annotationToolbarLayout(for annotation: PDFAnnotationRecord, in pdfView: PDFView) -> SelectionToolbarLayout? {
            guard let document = pdfView.document,
                  annotation.pageIndex >= 0,
                  annotation.pageIndex < document.pageCount,
                  let page = document.page(at: annotation.pageIndex) else {
                return nil
            }

            let rectInView = pdfView.convert(annotation.unionBounds, from: page)
            let overlaySize = pdfView.bounds.size
            let metrics = ReaderActionBarMetrics.resolve(for: .pdf, viewportWidth: overlaySize.width)

            guard !rectInView.isNull, !rectInView.isEmpty else {
                return SelectionToolbarLayout(origin: .zero, visible: false, metrics: metrics)
            }
            guard rectInView.intersects(pdfView.bounds) else {
                return SelectionToolbarLayout(origin: .zero, visible: false, metrics: metrics)
            }

            let overlayRect = Self.overlayRect(fromPDFViewRect: rectInView, overlayHeight: overlaySize.height)
            return SelectionToolbarLayout.anchored(
                to: overlayRect,
                overlaySize: overlaySize,
                metrics: metrics,
                horizontalAnchor: .center
            )
        }

        private static func overlayRect(fromPDFViewRect rectInView: CGRect, overlayHeight: CGFloat) -> CGRect {
            CGRect(
                x: rectInView.minX,
                y: overlayHeight - rectInView.maxY,
                width: rectInView.width,
                height: rectInView.height
            )
        }

        func updatePageInfo(current: Int, total: Int) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                viewModel.currentPageIndex = current
                viewModel.totalPages = total
                viewModel.scaleFactor = pdfView?.scaleFactor ?? viewModel.scaleFactor
                viewModel.onPageChanged?(current, total)
            }
        }

        private func rectsByPage(for selection: PDFSelection) -> [Int: [CGRect]] {
            guard let document = pdfView?.document else { return [:] }

            var pageRects: [Int: [CGRect]] = [:]
            for lineSelection in selection.selectionsByLine() {
                for page in lineSelection.pages {
                    let bounds = lineSelection.bounds(for: page).standardized
                    guard !bounds.isNull, !bounds.isEmpty, bounds.width > 0, bounds.height > 0 else {
                        continue
                    }
                    let pageIndex = document.index(for: page)
                    pageRects[pageIndex, default: []].append(bounds)
                }
            }

            return pageRects
        }
    }
}

// MARK: - OCR Markdown View

private struct OCRMarkdownView: View {
    let markdown: String
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var renderedHTML: String {
        OCRMarkdownWebView.documentHTML(for: markdown, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("智能识别结果", systemImage: "doc.text.viewfinder")
                    .font(.headline)
                Spacer()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(markdown, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("复制全部 Markdown")

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("返回 PDF")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()

                        OCRMarkdownWebView(html: renderedHTML)
                                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color(nsColor: NSColor(calibratedWhite: 0.08, alpha: 1.0)) : .white)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OCRMarkdownWebView: NSViewRepresentable {
        let html: String

        func makeCoordinator() -> Coordinator {
                Coordinator()
        }

        func makeNSView(context: Context) -> WKWebView {
                let configuration = WKWebViewConfiguration()
                let webView = WKWebView(frame: .zero, configuration: configuration)
                webView.navigationDelegate = context.coordinator
                webView.allowsBackForwardNavigationGestures = false
                webView.setValue(false, forKey: "drawsBackground")
                return webView
        }

        func updateNSView(_ nsView: WKWebView, context: Context) {
                guard context.coordinator.lastLoadedHTML != html else { return }
                context.coordinator.lastLoadedHTML = html
                nsView.loadHTMLString(html, baseURL: nil)
        }

        static func documentHTML(for markdown: String, colorScheme: ColorScheme) -> String {
                let bodyHTML = MarkdownHTMLRenderer.render(markdown: markdown, baseURL: nil)
                let resolvedBodyHTML = bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "<p>识别结果为空。</p>"
                        : bodyHTML

                let palette: (bg: String, text: String, secondary: String, border: String, code: String, link: String) = {
                        switch colorScheme {
                        case .dark:
                                return (
                                        bg: "#111418",
                                        text: "#eef2f7",
                                        secondary: "#b6c0cc",
                                        border: "rgba(255, 255, 255, 0.12)",
                                        code: "rgba(255, 255, 255, 0.08)",
                                        link: "#8ec5ff"
                                )
                        default:
                                return (
                                        bg: "#ffffff",
                                        text: "#1f2937",
                                        secondary: "#4b5563",
                                        border: "rgba(15, 23, 42, 0.12)",
                                        code: "#f3f4f6",
                                        link: "#2563eb"
                                )
                        }
                }()

                let colorSchemeName = colorScheme == .dark ? "dark" : "light"

                return """
                <!doctype html>
                <html>
                <head>
                    <meta charset="utf-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1">
                    <style>
                        :root {
                            color-scheme: \(colorSchemeName);
                            --ocr-bg: \(palette.bg);
                            --ocr-text: \(palette.text);
                            --ocr-secondary: \(palette.secondary);
                            --ocr-border: \(palette.border);
                            --ocr-code-bg: \(palette.code);
                            --ocr-link: \(palette.link);
                        }

                        * {
                            box-sizing: border-box;
                        }

                        html, body {
                            margin: 0;
                            padding: 0;
                            background: transparent;
                            color: var(--ocr-text);
                            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
                            font-size: 15px;
                            line-height: 1.72;
                            -webkit-font-smoothing: antialiased;
                        }

                        body {
                            padding: 24px 28px 32px;
                        }

                        #article-content {
                            max-width: 920px;
                            margin: 0 auto;
                            user-select: text;
                            word-break: break-word;
                        }

                        #article-content h1,
                        #article-content h2,
                        #article-content h3,
                        #article-content h4,
                        #article-content h5,
                        #article-content h6 {
                            line-height: 1.28;
                            margin: 1.35em 0 0.55em;
                        }

                        #article-content p,
                        #article-content ul,
                        #article-content ol,
                        #article-content pre,
                        #article-content table,
                        #article-content blockquote,
                        #article-content hr,
                        #article-content .math-display,
                        #article-content .swiftlib-md-media-block {
                            margin: 1em 0;
                        }

                        #article-content ul,
                        #article-content ol {
                            padding-left: 1.5em;
                        }

                        #article-content li + li {
                            margin-top: 0.28em;
                        }

                        #article-content code,
                        #article-content pre,
                        #article-content .math-display {
                            font-family: ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace;
                        }

                        #article-content code {
                            background: var(--ocr-code-bg);
                            border-radius: 6px;
                            padding: 0.12em 0.4em;
                            font-size: 0.92em;
                        }

                        #article-content pre,
                        #article-content .math-display {
                            background: var(--ocr-code-bg);
                            border: 1px solid var(--ocr-border);
                            border-radius: 12px;
                            padding: 14px 16px;
                            overflow-x: auto;
                            white-space: pre-wrap;
                        }

                        #article-content pre code {
                            background: transparent;
                            border-radius: 0;
                            padding: 0;
                        }

                        #article-content blockquote {
                            color: var(--ocr-secondary);
                            border-left: 3px solid var(--ocr-border);
                            padding-left: 14px;
                        }

                        #article-content table {
                            width: 100%;
                            border-collapse: collapse;
                            display: block;
                            overflow-x: auto;
                        }

                        #article-content th,
                        #article-content td {
                            border: 1px solid var(--ocr-border);
                            padding: 8px 10px;
                            vertical-align: top;
                        }

                        #article-content th {
                            background: var(--ocr-code-bg);
                            font-weight: 600;
                        }

                        #article-content hr {
                            border: none;
                            border-top: 1px solid var(--ocr-border);
                        }

                        #article-content a {
                            color: var(--ocr-link);
                            text-decoration: none;
                        }

                        #article-content a:hover {
                            text-decoration: underline;
                        }

                        #article-content img,
                        #article-content .swiftlib-md-image {
                            display: block;
                            max-width: 100%;
                            height: auto;
                            margin: 18px auto;
                            border-radius: 10px;
                        }
                    </style>
                </head>
                <body>
                    <div id="article-content">\(resolvedBodyHTML)</div>
                </body>
                </html>
                """
        }

        final class Coordinator: NSObject, WKNavigationDelegate {
                var lastLoadedHTML = ""

                func webView(
                        _ webView: WKWebView,
                        decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
                ) {
                        if navigationAction.navigationType == .linkActivated,
                             let url = navigationAction.request.url,
                             let scheme = url.scheme?.lowercased(),
                             scheme != "about",
                             scheme != "data" {
                                NSWorkspace.shared.open(url)
                                decisionHandler(.cancel)
                                return
                        }

                        decisionHandler(.allow)
                }
        }
}
