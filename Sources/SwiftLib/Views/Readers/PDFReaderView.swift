import SwiftUI
import PDFKit
import SwiftLibCore

// MARK: - Main Reader

struct PDFReaderView: View {
    @StateObject private var viewModel: PDFReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAnnotationSidebar = true
    @State private var sidebarWidth: CGFloat = 360
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

