import SwiftUI
import PDFKit
import Combine
import SwiftLibCore

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

