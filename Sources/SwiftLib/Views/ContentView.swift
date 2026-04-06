import SwiftUI
import Combine
import SwiftLibCore

enum SidebarItem: Hashable {
    case allReferences
    case collection(Int64)
    case tag(Int64)
    case titleKeyword(String)
}

struct SearchQuery {
    var keyword: String = ""
    var author: String = ""
    var yearFrom: Int?
    var yearTo: Int?
    var journal: String = ""
    var type: ReferenceType?

    static func parse(_ text: String) -> SearchQuery {
        var q = SearchQuery()
        var keywords: [String] = []
        for part in text.components(separatedBy: " ") {
            if part.hasPrefix("author:") {
                q.author = String(part.dropFirst("author:".count))
            } else if part.hasPrefix("year:") {
                let val = String(part.dropFirst("year:".count))
                if val.contains("-") {
                    let comps = val.split(separator: "-", maxSplits: 1)
                    if val.hasPrefix("-") {
                        q.yearTo = Int(comps.last ?? "")
                    } else if comps.count == 2 {
                        q.yearFrom = Int(comps[0])
                        q.yearTo = Int(comps[1])
                    } else {
                        q.yearFrom = Int(comps[0])
                    }
                } else {
                    q.yearFrom = Int(val)
                    q.yearTo = q.yearFrom
                }
            } else if part.hasPrefix("journal:") {
                q.journal = String(part.dropFirst("journal:".count))
            } else if part.hasPrefix("type:") {
                let val = String(part.dropFirst("type:".count))
                q.type = ReferenceType.allCases.first { $0.rawValue == val }
            } else if !part.isEmpty {
                keywords.append(part)
            }
        }
        q.keyword = keywords.joined(separator: " ")
        return q
    }
}

@MainActor
final class LibraryViewModel: ObservableObject {
    /// The current page of references returned by the database-level query.
    @Published var references: [Reference] = []
    @Published var pendingMetadataIntakes: [MetadataIntake] = []
    @Published var collections: [Collection] = []
    @Published var tags: [Tag] = []
    @Published var selectedSidebar: SidebarItem = .allReferences {
        didSet { rebuildReferenceObserver() }
    }
    /// Raw search text typed by the user; debounced before hitting the DB.
    @Published var searchText = "" {
        didSet { scheduleSearchDebounce() }
    }
    @Published var isImporting = false
    @Published var importProgress: String?
    @Published var errorMessage: String?
    /// All reference titles for smart keyword extraction (unaffected by filters).
    @Published private(set) var allReferenceTitles: [String] = []

    // MARK: - Private state
    let db: AppDatabase
    private var cancellables = Set<AnyCancellable>()
    /// Cancellable for the active reference ValueObservation subscription.
    private var referenceObserverCancellable: AnyCancellable?
    /// Timer-based debounce task for search input.
    private var searchDebounceTask: Task<Void, Never>?
    /// The filter currently applied to the database query.
    private var activeFilter = ReferenceFilter()

    init(db: AppDatabase = .shared) {
        self.db = db
        setupObservation()
    }

    // MARK: - Observation setup

    private func setupObservation() {
        db.observeCollections()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Collections refresh failed: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] collections in
                    self?.collections = collections
                }
            )
            .store(in: &cancellables)

        db.observeTags()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Tags refresh failed: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] tags in
                    self?.tags = tags
                }
            )
            .store(in: &cancellables)

        db.observePendingMetadataIntakes()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Pending metadata refresh failed: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] items in
                    self?.pendingMetadataIntakes = items
                }
            )
            .store(in: &cancellables)

        // Observe all reference titles for smart keyword extraction.
        db.observeReferences()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] refs in
                    self?.allReferenceTitles = refs.map(\.title)
                }
            )
            .store(in: &cancellables)

        // Start the initial reference observation with no filter.
        rebuildReferenceObserver()
    }

    /// (Re-)subscribe to the database with the current scope + filter.
    /// Called whenever the sidebar selection or the debounced filter changes.
    private func rebuildReferenceObserver() {
        referenceObserverCancellable?.cancel()

        let scope = currentReferenceScope
        var filter = activeFilter

        if case .titleKeyword(let word) = selectedSidebar {
            filter.keyword = word
            filter.titleOnly = true
        }

        referenceObserverCancellable = db
            .observeReferences(scope: scope, filter: filter, limit: 0)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "References refresh failed: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] refs in
                    self?.references = refs
                }
            )
    }

    var currentReferenceScope: ReferenceScope {
        let scope: ReferenceScope
        switch selectedSidebar {
        case .allReferences, .titleKeyword:
            scope = .all
        case .collection(let id):   scope = .collection(id)
        case .tag(let id):          scope = .tag(id)
        }
        return scope
    }


    /// Debounce raw search text by 250 ms before rebuilding the DB observer.
    private func scheduleSearchDebounce() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 250_000_000) // 250 ms
            guard !Task.isCancelled else { return }
            let parsed = SearchQuery.parse(self.searchText)
            var filter = ReferenceFilter()
            filter.keyword      = parsed.keyword
            filter.author       = parsed.author
            filter.yearFrom     = parsed.yearFrom
            filter.yearTo       = parsed.yearTo
            filter.journal      = parsed.journal
            filter.referenceType = parsed.type
            self.activeFilter = filter
            self.rebuildReferenceObserver()
        }
    }

    /// Convenience accessor — references are already filtered by the DB query.
    var filteredReferences: [Reference] { references }

    /// Top title keywords extracted from all reference titles.
    var titleKeywords: [(word: String, count: Int)] {
        let stopWords: Set<String> = [
            // English
            "the", "and", "for", "with", "from", "that", "this", "are", "was",
            "were", "been", "being", "have", "has", "had", "not", "but", "its",
            "can", "may", "will", "should", "could", "would", "into", "than",
            "also", "where", "when", "how", "what", "which", "who", "whom",
            "why", "all", "any", "each", "every", "both", "few", "more",
            "most", "other", "some", "such", "only", "own", "same", "then",
            "too", "very", "just", "about", "above", "after", "again",
            "below", "between", "during", "further", "here", "once", "there",
            "these", "those", "through", "under", "until", "while",
            "over", "out", "off", "down", "before", "our", "your", "his",
            "her", "their", "its", "does", "did", "doing",
            "using", "based", "via", "new", "one", "two", "study", "analysis",
            "case", "approach", "method", "model", "data", "results", "review",
            "research", "paper", "effect", "effects", "use",
            // Chinese
            "的", "了", "在", "是", "我", "有", "和", "就", "不", "人",
            "都", "一", "一个", "上", "也", "很", "到", "说", "要", "去",
            "你", "会", "着", "没有", "看", "好", "自己", "这", "他", "她",
            "对", "中", "与", "及", "或", "等", "基于", "研究", "分析",
        ]

        var freq: [String: Int] = [:]
        for title in allReferenceTitles {
            let lower = title.lowercased()
            let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 && !stopWords.contains($0) }
            for word in Set(words) {
                freq[word, default: 0] += 1
            }
        }

        return freq
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { (word: $0.key, count: $0.value) }
    }

    func moveReferences(_ refs: [Reference], toCollectionId: Int64?) {
        let ids = refs.compactMap(\.id)
        do {
            try db.moveReferences(ids: ids, toCollectionId: toCollectionId)
        } catch {
            errorMessage = "Move failed: \(error.localizedDescription)"
        }
    }

    func deleteReferences(_ refs: [Reference]) {
        let ids = refs.compactMap(\.id)
        do {
            let pdfPaths = try db.deleteReferencesReturningPDFPaths(ids: ids)
            for path in pdfPaths {
                PDFService.deletePDF(at: path)
            }
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func saveReference(_ ref: inout Reference) {
        ref.dateModified = Date()
        do {
            try db.saveReference(&ref)
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func saveManualReference(_ ref: inout Reference, reviewedBy: String = "manual-entry") {
        if ref.id == nil && !ref.verificationStatus.isLibraryReady {
            ref = MetadataVerifier.manuallyVerified(ref, reviewedBy: reviewedBy)
        }
        saveReference(&ref)
    }

    func batchImportReferences(_ refs: [Reference]) {
        do {
            _ = try db.batchImportReferences(refs)
        } catch {
            errorMessage = "Batch import failed: \(error.localizedDescription)"
        }
    }

    func persistMetadataResolution(
        _ result: MetadataResolutionResult,
        options: MetadataPersistenceOptions
    ) -> MetadataPersistenceResult? {
        do {
            return try db.persistMetadataResolution(result, options: options)
        } catch {
            errorMessage = "Metadata persistence failed: \(error.localizedDescription)"
            return nil
        }
    }

    func confirmPendingMetadataIntake(_ intake: MetadataIntake, reviewedBy: String = "manual-queue") -> Reference? {
        do {
            return try db.confirmMetadataIntake(intake, reviewedBy: reviewedBy)
        } catch {
            errorMessage = "Manual verification failed: \(error.localizedDescription)"
            return nil
        }
    }

    func deletePendingMetadataIntake(_ intake: MetadataIntake) {
        guard let id = intake.id else { return }
        do {
            try db.deleteMetadataIntake(id: id)
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func saveCollection(_ col: inout Collection) {
        do {
            try db.saveCollection(&col)
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func deleteCollection(id: Int64) {
        do {
            try db.deleteCollection(id: id)
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
        if case .collection(let cid) = selectedSidebar, cid == id {
            selectedSidebar = .allReferences
        }
    }

    func saveTag(_ tag: inout Tag) {
        do {
            try db.saveTag(&tag)
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func deleteTag(id: Int64) {
        do {
            try db.deleteTag(id: id)
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func importBibTeX(from url: URL) {
        isImporting = true
        importProgress = "正在读取文件…"

        Task.detached { [weak self] in
            guard let self else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                await MainActor.run { self.importProgress = "正在解析 BibTeX…" }

                let refs = BibTeXImporter.parse(content)
                await MainActor.run { self.importProgress = "正在导入 \(refs.count) 条条目…" }

                let count = try self.db.batchImportReferences(refs)
                await MainActor.run {
                    self.importProgress = "已导入 \(count) 条条目"
                    self.isImporting = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.importProgress = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.importProgress = "导入失败：\(error.localizedDescription)"
                    self.isImporting = false
                }
            }
        }
    }

    func importRIS(from url: URL) {
        isImporting = true
        importProgress = "正在读取文件…"

        Task.detached { [weak self] in
            guard let self else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                await MainActor.run { self.importProgress = "正在解析 RIS…" }

                let refs = RISImporter.parse(content)
                await MainActor.run { self.importProgress = "正在导入 \(refs.count) 条条目…" }

                let count = try self.db.batchImportReferences(refs)
                await MainActor.run {
                    self.importProgress = "已导入 \(count) 条条目"
                    self.isImporting = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.importProgress = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.importProgress = "导入失败：\(error.localizedDescription)"
                    self.isImporting = false
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @StateObject private var cnkiMetadataProvider = CNKIMetadataProvider()
    @AppStorage("hasPromptedCLIInstallation") private var hasPromptedCLIInstallation = false
    @State private var showCLIInstallPrompt = false
    @State private var cliInstallResult: CLIInstallResult?
    @State private var showSearch = false
    @State private var showAddReference = false
    @State private var addReferenceInitialType: ReferenceType = .journalArticle
    @State private var showWebImport = false
    @State private var showAddCollection = false
    @State private var showAddByIdentifier = false
    @State private var showBatchImport = false
    @State private var showPendingMetadataQueue = false
    @State private var pendingQueueNotice: PendingQueueNotice?
    @State private var cslImportMessage: String?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var selectedId: Int64?

    private struct PendingQueueNotice: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var metadataResolver: MetadataResolver {
        MetadataResolver(cnkiProvider: cnkiMetadataProvider)
    }

    private var selectedReference: Reference? {
        guard let selectedId else { return nil }
        return viewModel.filteredReferences.first { $0.id == selectedId }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                collections: viewModel.collections,
                tags: viewModel.tags,
                titleKeywords: viewModel.titleKeywords,
                selection: $viewModel.selectedSidebar,
                referenceCount: viewModel.references.count,
                onDeleteCollection: { viewModel.deleteCollection(id: $0) },
                onDeleteTag: { viewModel.deleteTag(id: $0) },
                onAddCollection: { showAddCollection = true }
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } content: {
            ReferenceListView(
                references: viewModel.filteredReferences,
                collections: viewModel.collections,
                selectedId: selectedId,
                onSelect: { selectedId = $0 },
                onDelete: { deleteReferences($0) },
                onMove: { refs, colId in viewModel.moveReferences(refs, toCollectionId: colId) },
                onRefreshMetadata: { refs in refreshMetadata(for: refs) },
                isRefreshingMetadata: viewModel.isImporting,
                onDoubleClick: { refId in
                    openReader(for: refId)
                }
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 350, max: 500)
        } detail: {
            if let ref = selectedReference {
                ReferenceDetailView(
                    reference: ref,
                    collections: viewModel.collections,
                    allTags: viewModel.tags,
                    db: viewModel.db,
                    onSave: { updated in
                        var r = updated
                        viewModel.saveReference(&r)
                    },
                    onDelete: {
                        deleteReferences([ref])
                    },
                    onOpenPDFReader: { r in
                        ReaderWindowManager.shared.openPDFReader(for: r)
                    },
                    onOpenWebReader: { r in
                        ReaderWindowManager.shared.openWebReader(for: r)
                    }
                )
            } else if selectedId != nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("选择一篇文献")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("共 \(viewModel.references.count) 篇文献")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .toolbar(content: {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showSearch = true
                } label: {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .help("搜索文献")
                .keyboardShortcut("f", modifiers: .command)

                ControlGroup {
                    Button(action: {
                        addReferenceInitialType = .journalArticle
                        showAddReference = true
                    }) {
                        Label("手动新建", systemImage: "square.and.pencil")
                    }
                    .help("新建一个空白条目并手动填写信息")

                    Button(action: {
                        showWebImport = true
                    }) {
                        Label("网页剪藏", systemImage: "globe")
                    }
                    .help("输入网页链接，使用内置 Obsidian Clipper 抓取标题、摘要和正文")
                }

                ControlGroup {
                    Button(action: { showPendingMetadataQueue = true }) {
                        HStack(spacing: 6) {
                            Label("待确认队列", systemImage: "clock.badge.exclamationmark")
                            if !viewModel.pendingMetadataIntakes.isEmpty {
                                Text("\(viewModel.pendingMetadataIntakes.count)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .help("打开待确认元数据队列，继续选候选、处理验证码或人工确认")
                    .disabled(viewModel.pendingMetadataIntakes.isEmpty)

                    Button(action: { showAddByIdentifier = true }) {
                        Label("按标识导入", systemImage: "text.magnifyingglass")
                    }
                    .help("输入 DOI、PMID 或 arXiv ID，自动导入条目元数据")

                    Button(action: { importPDFWithMetadata() }) {
                        Label("导入 PDF", systemImage: "doc.badge.plus")
                    }
                    .help("导入 PDF，并尽量自动补全文献信息")

                    Menu {
                        Button("批量按标识导入…") { showBatchImport = true }
                        Divider()
                        Button("导入 BibTeX (.bib)…") { importBibTeX() }
                        Button("导入 RIS (.ris)…") { importRIS() }
                        Divider()
                        Button("导入引文样式 (.csl)…") { importCitationStyles() }
                    } label: {
                        Label("更多导入", systemImage: "tray.and.arrow.down")
                    }
                    .help("打开更多导入方式")
                    .disabled(viewModel.isImporting)
                }
            }

        })
        .sheet(isPresented: $showAddReference) {
            AddReferenceView(
                collections: viewModel.collections,
                allTags: viewModel.tags,
                onSave: { ref in
                    var r = ref
                    viewModel.saveManualReference(&r)
                },
                onCreateTag: { tag in
                    var t = tag
                    viewModel.saveTag(&t)
                },
                initialReferenceType: addReferenceInitialType
            )
        }
        .sheet(isPresented: $showWebImport) {
            WebImportView(
                collections: viewModel.collections,
                onSave: { ref in
                    var r = ref
                    viewModel.saveManualReference(&r, reviewedBy: "web-import")
                }
            )
        }
        .sheet(isPresented: $showBatchImport) {
            BatchImportView(
                resolver: metadataResolver,
                onImport: { refs in
                viewModel.batchImportReferences(refs)
                },
                onQueueResult: { result, input in
                    queueResolutionResult(
                        result,
                        options: MetadataPersistenceOptions(
                            sourceKind: .batchIdentifier,
                            originalInput: input
                        ),
                        successMessage: "已加入待确认队列"
                    )
                }
            )
        }
        .overlay {
            if showSearch {
                SearchOverlay(
                    db: viewModel.db,
                    scope: viewModel.currentReferenceScope,
                    collections: viewModel.collections,
                    isPresented: $showSearch,
                    onSelect: { ref in
                        selectedId = ref.id
                    },
                    onDeleteMultiple: { refs in
                        deleteReferences(refs)
                    }
                )
            }
        }
        .overlay(alignment: .top) {
            if let progress = viewModel.importProgress {
                FloatingProgressToast(
                    message: progress,
                    isSpinning: viewModel.isImporting
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: progress)
            }
        }
        .sheet(isPresented: $showAddByIdentifier) {
            AddByIdentifierView(
                resolver: metadataResolver,
                onSave: { ref in
                    var r = ref
                    viewModel.saveReference(&r)
                },
                onQueueResult: { result, input in
                    queueResolutionResult(
                        result,
                        options: MetadataPersistenceOptions(
                            sourceKind: .manualEntry,
                            originalInput: input
                        ),
                        successMessage: "已加入待确认队列"
                    )
                }
            )
        }
        .sheet(isPresented: $showAddCollection) {
            AddCollectionSheet { col in
                var c = col
                viewModel.saveCollection(&c)
            }
        }
        .sheet(isPresented: $showPendingMetadataQueue) {
            PendingMetadataQueueView(
                intakes: viewModel.pendingMetadataIntakes,
                resolver: metadataResolver,
                onPersistResult: { result, intake in
                    queueResolutionResult(
                        result,
                        options: MetadataPersistenceOptions(
                            sourceKind: intake.sourceKind,
                            originalInput: intake.originalInput,
                            preferredPDFPath: intake.pdfPath,
                            linkedReferenceId: intake.linkedReferenceId,
                            existingIntakeId: intake.id
                        ),
                        successMessage: nil
                    )
                },
                onConfirmManual: { intake in
                    if let reference = viewModel.confirmPendingMetadataIntake(intake) {
                        selectedId = reference.id
                    }
                },
                onDelete: { intake in
                    viewModel.deletePendingMetadataIntake(intake)
                }
            )
        }
        .sheet(item: Binding(
            get: { cnkiMetadataProvider.verificationSession },
            set: { session in
                if session == nil, cnkiMetadataProvider.verificationSession != nil {
                    cnkiMetadataProvider.cancelVerification()
                }
            }
        )) { session in
            CNKIVerificationSheet(
                provider: cnkiMetadataProvider,
                session: session
            )
        }
        .overlay(alignment: .bottom) {
            if let msg = cslImportMessage {
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let notice = pendingQueueNotice {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "tray.full.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notice.title)
                                .font(.headline)
                            Text(notice.message)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button {
                            pendingQueueNotice = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("打开待确认队列") {
                            pendingQueueNotice = nil
                            showPendingMetadataQueue = true
                        }
                        .buttonStyle(SLPrimaryButtonStyle())

                        Button("稍后处理") {
                            pendingQueueNotice = nil
                        }
                        .buttonStyle(SLSecondaryButtonStyle())
                    }
                }
                .padding(14)
                .frame(maxWidth: 360, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cslImportMessage)
        .animation(.easeInOut(duration: 0.2), value: pendingQueueNotice)
        .onChange(of: viewModel.references) { _, newRefs in
            guard let selectedId else { return }
            if !newRefs.contains(where: { $0.id == selectedId }) {
                self.selectedId = nil
            }
        }

        .onReceive(NotificationCenter.default.publisher(for: .swiftLibClipImported)) { note in
            guard let id = note.userInfo?[SwiftLibClipImportedKeys.id] as? Int64 else { return }
            selectedId = id
            columnVisibility = .all
        }
        .alert("操作失败", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("确定") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            if !hasPromptedCLIInstallation && !CLIInstaller.isInstalled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCLIInstallPrompt = true
                }
            }
        }
        .alert("安装命令行工具", isPresented: $showCLIInstallPrompt) {
            Button("安装") {
                hasPromptedCLIInstallation = true
                do {
                    try CLIInstaller.install()
                    cliInstallResult = .success
                } catch {
                    cliInstallResult = .failure(error.localizedDescription)
                }
            }
            Button("暂不安装", role: .cancel) {
                hasPromptedCLIInstallation = true
            }
        } message: {
            Text("SwiftLib 提供配套的命令行工具 swiftlib-cli，可在终端中快速搜索、添加和导出文献。\n\n是否将其安装到 /usr/local/bin？\n（你也可以稍后在菜单栏「CLI 工具」中安装）")
        }
        .alert(
            cliInstallResult?.isSuccess == true ? "安装成功" : "安装失败",
            isPresented: Binding(
                get: { cliInstallResult != nil },
                set: { if !$0 { cliInstallResult = nil } }
            )
        ) {
            Button("好") { cliInstallResult = nil }
        } message: {
            Text(cliInstallResult?.message ?? "")
        }
        .background(cnkiHiddenWebViewIfNeeded)
    }

    @ViewBuilder
    private var cnkiHiddenWebViewIfNeeded: some View {
        if cnkiMetadataProvider.needsWebView {
            HiddenWKWebViewHost(
                configure: cnkiMetadataProvider.configureWebView(_:),
                onCreate: { webView in
                    cnkiMetadataProvider.registerWebView(webView)
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .allowsHitTesting(false)
        }
    }

    private func importBibTeX() {
        guard let url = OpenPanelPicker.pickBibTeXFile() else { return }
        viewModel.importBibTeX(from: url)
    }

    private func importRIS() {
        guard let url = OpenPanelPicker.pickRISFile() else { return }
        viewModel.importRIS(from: url)
    }

    private func importPDFWithMetadata() {
        guard let url = OpenPanelPicker.pickPDFFile() else { return }
        viewModel.isImporting = true
        viewModel.importProgress = "正在导入 PDF…"

        Task { @MainActor in
            do {
                let prepared = try PDFService.prepareImportedPDF(from: url)
                let fallbackReference = prepared.reference
                let seed = MetadataResolutionSeed.fromImportedPDF(url: url, extracted: prepared.extracted)

                if MetadataResolution.shouldPreferCNKIForImportedPDF(seed: seed) {
                    viewModel.importProgress = "正在匹配知网元数据…"
                } else if let doi = prepared.extracted.doi, !doi.isEmpty {
                    viewModel.importProgress = "正在获取元数据：\(doi)…"
                }

                let resolution = await metadataResolver.resolveImportedPDF(url: url, extracted: prepared.extracted)

                switch resolution {
                case .verified(let envelope):
                    var reference = envelope.reference
                    reference.pdfPath = fallbackReference.pdfPath
                    finishPDFImport(with: reference, message: "已导入: \(reference.title)")

                case .candidate, .blocked, .seedOnly, .rejected:
                    let queued = queueResolutionResult(
                        resolution,
                        options: MetadataPersistenceOptions(
                            sourceKind: .importedPDF,
                            preferredPDFPath: fallbackReference.pdfPath
                        ),
                        successMessage: "还不能自动确认，已加入待确认队列"
                    )
                    if queued == nil, let pdfPath = fallbackReference.pdfPath {
                        PDFService.deletePDF(at: pdfPath)
                    }
                }
            } catch {
                viewModel.isImporting = false
                viewModel.importProgress = nil
                viewModel.errorMessage = "PDF 导入失败: \(error.localizedDescription)"
            }
        }
    }

    private func finishPDFImport(with reference: Reference, message: String?) {
        var mutable = reference
        viewModel.saveReference(&mutable)
        selectedId = mutable.id
        viewModel.isImporting = false
        viewModel.importProgress = message

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if !viewModel.isImporting {
                viewModel.importProgress = nil
            }
        }
    }

    private func refreshMetadata(for references: [Reference]) {
        let candidates = references.compactMap { reference -> Reference? in
            guard reference.id != nil else { return nil }
            return reference
        }
        guard !candidates.isEmpty else { return }

        if candidates.count == 1, let reference = candidates.first {
            refreshSingleReferenceMetadata(reference)
        } else {
            refreshBatchMetadata(for: candidates)
        }
    }

    private func refreshSingleReferenceMetadata(_ reference: Reference) {
        viewModel.isImporting = true
        viewModel.importProgress = "正在刷新元数据…"

        Task { @MainActor in
            let result = await metadataResolver.refreshReference(reference, allowCandidateSelection: true)
            switch result {
            case .refreshed(let refreshed):
                saveRefreshedReference(refreshed, message: "已刷新：\(refreshed.title)")

            case .pending(let pendingResult):
                _ = queueResolutionResult(
                    pendingResult,
                    options: MetadataPersistenceOptions(
                        sourceKind: .refresh,
                        originalInput: reference.doi ?? reference.pmid ?? reference.isbn ?? reference.title,
                        linkedReferenceId: reference.id
                    ),
                    successMessage: "已加入待确认队列，等待你继续处理"
                )

            case .skipped(let reason):
                viewModel.isImporting = false
                viewModel.importProgress = reason
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    if !viewModel.isImporting {
                        viewModel.importProgress = nil
                    }
                }

            case .failed(let message):
                viewModel.isImporting = false
                viewModel.importProgress = nil
                viewModel.errorMessage = message
            }
        }
    }

    private func refreshBatchMetadata(for references: [Reference]) {
        viewModel.isImporting = true
        viewModel.importProgress = "准备刷新 \(references.count) 条条目…"

        Task { @MainActor in
            var refreshedCount = 0
            var skippedCount = 0
            var failedMessages: [String] = []
            let total = references.count
            let maxConcurrency = 3

            // Process in concurrent batches to improve performance while
            // limiting parallelism to avoid API rate-limiting.
            for batchStart in stride(from: 0, to: total, by: maxConcurrency) {
                let batchEnd = min(batchStart + maxConcurrency, total)
                let batch = Array(references[batchStart..<batchEnd])

                viewModel.importProgress = "正在刷新 \(batchStart + 1)–\(batchEnd)/\(total)…"

                let batchResults: [(Reference, ReferenceMetadataRefreshResult)] = await withTaskGroup(
                    of: (Reference, ReferenceMetadataRefreshResult).self,
                    returning: [(Reference, ReferenceMetadataRefreshResult)].self
                ) { group in
                    for reference in batch {
                        group.addTask {
                            let result = await metadataResolver.refreshReference(reference, allowCandidateSelection: false)
                            return (reference, result)
                        }
                    }
                    var results: [(Reference, ReferenceMetadataRefreshResult)] = []
                    for await pair in group {
                        results.append(pair)
                    }
                    return results
                }

                for (reference, result) in batchResults {
                    switch result {
                    case .refreshed(let refreshed):
                        saveRefreshedReference(refreshed, message: nil, finishRefreshing: false, clearProgress: false)
                        refreshedCount += 1
                    case .pending(let pendingResult):
                        _ = queueResolutionResult(
                            pendingResult,
                            options: MetadataPersistenceOptions(
                                sourceKind: .refresh,
                                originalInput: reference.doi ?? reference.pmid ?? reference.isbn ?? reference.title,
                                linkedReferenceId: reference.id
                            ),
                            successMessage: nil
                        )
                        skippedCount += 1
                    case .skipped:
                        skippedCount += 1
                    case .failed(let message):
                        failedMessages.append("\(reference.title)：\(message)")
                    }
                }
            }

            viewModel.isImporting = false
            viewModel.importProgress = "批量刷新完成：\(refreshedCount) 条已更新，\(skippedCount) 条跳过，\(failedMessages.count) 条失败"

            if !failedMessages.isEmpty {
                viewModel.errorMessage = failedMessages.prefix(5).joined(separator: "\n")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if !viewModel.isImporting {
                    viewModel.importProgress = nil
                }
            }
        }
    }

    private func saveRefreshedReference(
        _ reference: Reference,
        message: String?,
        finishRefreshing: Bool = true,
        clearProgress: Bool = true
    ) {
        var mutable = reference
        viewModel.saveReference(&mutable)
        viewModel.isImporting = !finishRefreshing ? viewModel.isImporting : false
        viewModel.importProgress = message

        guard clearProgress else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if !viewModel.isImporting {
                viewModel.importProgress = nil
            }
        }
    }

    @discardableResult
    private func queueResolutionResult(
        _ result: MetadataResolutionResult,
        options: MetadataPersistenceOptions,
        successMessage: String?
    ) -> MetadataPersistenceResult? {
        let persisted = viewModel.persistMetadataResolution(result, options: options)
        switch persisted {
        case .verified(let reference):
            selectedId = reference.id
            viewModel.isImporting = false
            viewModel.importProgress = successMessage ?? "已验证：\(reference.title)"
            pendingQueueNotice = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if !viewModel.isImporting {
                    viewModel.importProgress = nil
                }
            }
        case .intake(let intake):
            viewModel.isImporting = false
            viewModel.importProgress = nil
            showPendingQueueNotice(for: intake, message: successMessage)
        case .none:
            viewModel.isImporting = false
            viewModel.importProgress = nil
        }

        return persisted
    }

    private func showPendingQueueNotice(for intake: MetadataIntake, message: String?) {
        let title = "这条元数据还需要你确认"
        let lead = intake.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "该条目" : "“\(intake.title)”"
        let detail = message?.swiftlib_nilIfBlank
            ?? intake.statusMessage?.swiftlib_nilIfBlank
            ?? "已放入待确认队列。"

        let notice = PendingQueueNotice(
            title: title,
            message: "\(lead)\(detail.hasPrefix("已") ? "" : " ")\(detail) 你可以直接打开队列继续处理。"
        )
        pendingQueueNotice = notice

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if pendingQueueNotice?.id == notice.id {
                pendingQueueNotice = nil
            }
        }
    }

    private func importCitationStyles() {
        let urls = OpenPanelPicker.pickCitationStyleFiles()
        guard !urls.isEmpty else { return }

        var imported: [String] = []
        for url in urls {
            if let title = try? CSLManager.shared.importCSL(from: url) {
                imported.append(title)
            }
        }

        guard !imported.isEmpty else { return }

        cslImportMessage = "已导入：\(imported.joined(separator: "、"))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            cslImportMessage = nil
        }
    }

    private func deleteReferences(_ references: [Reference]) {
        let ids = references.compactMap(\.id)
        if let selectedId, ids.contains(selectedId) {
            self.selectedId = nil
        }
        viewModel.deleteReferences(references)
    }

    private func openReader(for referenceID: Int64) {
        guard let reference = try? viewModel.db.fetchReferences(ids: [referenceID]).first else { return }
        if reference.pdfPath != nil {
            ReaderWindowManager.shared.openPDFReader(for: reference)
        } else if reference.canOpenWebReader {
            ReaderWindowManager.shared.openWebReader(for: reference)
        }
    }
}

private struct FloatingProgressToast: View {
    let message: String
    let isSpinning: Bool

    var body: some View {
        HStack(spacing: 7) {
            if isSpinning {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.85)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            }

            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            Capsule(style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        }
        .padding(.top, 10)
        .allowsHitTesting(false)
    }
}

// MARK: - CLI Install Result

private enum CLIInstallResult {
    case success
    case failure(String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .success:
            return "命令行工具已安装到 \(CLIInstaller.installURL.path)\n\n你现在可以在终端中使用 swiftlib-cli 命令了。"
        case .failure(let reason):
            return "安装失败：\(reason)\n\n你可以稍后在菜单栏「CLI 工具」中重试，或手动复制。"
        }
    }
}
