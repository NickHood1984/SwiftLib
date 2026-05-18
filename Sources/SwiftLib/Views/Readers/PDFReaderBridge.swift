import SwiftUI
import PDFKit
import SwiftLibCore

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

