import SwiftUI
import PDFKit
import Combine
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
                    AnnotatablePDFView(viewModel: viewModel)
                        .padding(6)
                        .overlay {
                            selectionActionBarOverlay
                        }
                        .overlay {
                            annotationActionBarOverlay
                        }

                    floatingReaderTab
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                }
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
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

                    AnnotationSidebarView(viewModel: viewModel)
                        .frame(width: min(max(sidebarWidth - dragOffset, 260), 500))
                        .transition(.move(edge: .trailing))
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
                ? NSColor(calibratedWhite: 0.15, alpha: 1.0)
                : NSColor(calibratedWhite: 0.90, alpha: 1.0)
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
                    viewModel.clearStagedSelection()
                }
            }
            .padding(.horizontal, metrics.topRowHorizontalPadding)
            .padding(.vertical, metrics.topRowVerticalPadding)

            // Divider
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
                        viewModel.clearStagedSelection()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
                    .font(.system(size: metrics.secondaryFontSize))

                    Button("保存") {
                        let md = noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !md.isEmpty else { return }
                        viewModel.addAnnotations(
                            type: .note,
                            selectedText: viewModel.stagedSelectionText,
                            noteText: md,
                            pageRects: viewModel.stagedSelectionPageRects
                        )
                        noteMarkdown = ""
                        viewModel.clearStagedSelection()
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

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = CommitAwarePDFView()
        let canvasBackgroundColor = NSColor(name: nil) { trait in
            trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.18, alpha: 1.0)
                : NSColor(calibratedWhite: 0.94, alpha: 1.0)
        }
        pdfView.autoScales = true
        pdfView.displaysPageBreaks = true
        pdfView.pageBreakMargins = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.pageShadowsEnabled = false
        pdfView.backgroundColor = canvasBackgroundColor
        pdfView.applyElegantScrollers()

        // Remove NSScrollView bezel border and keep the inner PDF canvas subtly gray.
        DispatchQueue.main.async { [weak pdfView] in
            guard let sv = pdfView?.internalScrollView else { return }
            sv.borderType = .noBorder
            sv.backgroundColor = canvasBackgroundColor
            sv.drawsBackground = true
            sv.contentView.backgroundColor = canvasBackgroundColor
            if let documentView = pdfView?.documentView {
                documentView.wantsLayer = true
                documentView.layer?.backgroundColor = canvasBackgroundColor.cgColor
            }
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

        let existingKeys = Set(coordinator.trackedAnnotations.keys)
        let recordKeys = Set(records.compactMap { $0.id })

        let removedKeys = existingKeys.subtracting(recordKeys)
        for key in removedKeys {
            if let tracked = coordinator.trackedAnnotations[key],
               let page = document.page(at: tracked.pageIndex) {
                page.removeAnnotation(tracked.annotation)
            }
            coordinator.trackedAnnotations.removeValue(forKey: key)
        }

        for record in records {
            guard let recordId = record.id else { continue }
            let recordHash = record.renderHash

            if let tracked = coordinator.trackedAnnotations[recordId],
               tracked.renderHash == recordHash {
                continue
            }

            if let tracked = coordinator.trackedAnnotations[recordId],
               let existingPage = document.page(at: tracked.pageIndex) {
                existingPage.removeAnnotation(tracked.annotation)
            }

            if record.pageIndex < document.pageCount,
               let page = document.page(at: record.pageIndex) {
                let annotation = createPDFAnnotation(from: record)
                page.addAnnotation(annotation)
                coordinator.trackedAnnotations[recordId] = TrackedAnnotation(
                    annotation: annotation,
                    pageIndex: record.pageIndex,
                    renderHash: recordHash
                )
            }
        }
    }

    private func createPDFAnnotation(from record: PDFAnnotationRecord) -> PDFAnnotation {
        let bounds = record.unionBounds
        let color = AnnotationColor.nsColor(for: record.color)
        let rects = record.rects

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

        if !rects.isEmpty {
            annotation.quadrilateralPoints = buildQuadrilateralPoints(from: rects, relativeTo: bounds)
        }

        if let noteText = record.noteText, !noteText.isEmpty {
            annotation.contents = noteText
        }

        return annotation
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            flashAnnotation(in: pdfView, page: page, bounds: bounds)
        }
    }

    private func flashAnnotation(in pdfView: PDFView, page: PDFPage, bounds: CGRect) {
        let flashBounds = bounds.insetBy(dx: -1.5, dy: -1.5)
        let flashAnnotation = PDFAnnotation(bounds: flashBounds, forType: .highlight, withProperties: nil)
        flashAnnotation.color = NSColor.systemBlue.withAlphaComponent(0.22)
        page.addAnnotation(flashAnnotation)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            page.removeAnnotation(flashAnnotation)
        }
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
            pdfView.document = document
            let canvasBackgroundColor = NSColor(name: nil) { trait in
                trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(calibratedWhite: 0.18, alpha: 1.0)
                    : NSColor(calibratedWhite: 0.94, alpha: 1.0)
            }
            if let scrollView = pdfView.internalScrollView {
                scrollView.backgroundColor = canvasBackgroundColor
                scrollView.contentView.backgroundColor = canvasBackgroundColor
            }
            if let documentView = pdfView.documentView {
                documentView.wantsLayer = true
                documentView.layer?.backgroundColor = canvasBackgroundColor.cgColor
            }
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
