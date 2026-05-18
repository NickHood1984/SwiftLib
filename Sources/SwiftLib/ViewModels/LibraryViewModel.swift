import SwiftUI
import Combine
import SwiftLibCore

private let titleKeywordStopWords: Set<String> = [
    "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
    "have", "has", "had", "having", "do", "does", "did", "doing",
    "and", "or", "but", "not", "no", "nor",
    "in", "on", "at", "to", "for", "of", "with", "by", "from", "as", "into",
    "through", "during", "before", "after", "above", "below", "between",
    "under", "over", "than", "then",
    "it", "its", "that", "this", "these", "those",
    "can", "could", "will", "would", "shall", "should", "may", "might",
    "based", "using", "new", "study", "research", "analysis",
    "的", "了", "在", "是", "与", "和", "或", "不", "及",
    "中", "对", "等", "为", "从", "将", "以", "其",
    "研究", "基于", "一种", "方法", "分析", "应用", "影响", "及其",
    "个", "都", "着", "之", "而", "地", "得",
    "进行", "通过", "不同", "提出", "相关", "使用", "用于",
]

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var references: [ReferenceListRow] = []
    @Published var totalReferenceCount: Int = 0
    @Published var pendingMetadataIntakes: [MetadataIntake] = []
    @Published var workspaces: [Workspace] = []
    @Published var collections: [Collection] = []
    @Published var tags: [Tag] = []
    @Published var selectedWorkspaceID: Int64? {
        didSet {
            guard oldValue != selectedWorkspaceID else { return }
            rebuildReferenceObserver()
            if let selectedWorkspaceID {
                do {
                    try db.touchWorkspaceOpened(id: selectedWorkspaceID)
                } catch {
                    errorMessage = "Workspace update failed: \(error.localizedDescription)"
                }
            }
        }
    }
    @Published var selectedSidebar: SidebarItem = .allReferences {
        didSet { rebuildReferenceObserver() }
    }
    @Published var searchText = "" {
        didSet { scheduleSearchDebounce() }
    }
    @Published var isImporting = false
    @Published var importProgress: String?
    @Published var errorMessage: String?
    @Published private(set) var allReferenceTitles: [String] = []
    @Published private(set) var titleKeywords: [(word: String, count: Int)] = []

    private(set) var allLoaded = false

    let db: AppDatabase
    private var cancellables = Set<AnyCancellable>()
    private var referenceObserverCancellable: AnyCancellable?
    private var countObserverCancellable: AnyCancellable?
    private var searchDebounceTask: Task<Void, Never>?
    private var titleKeywordTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var activeFilter = ReferenceFilter()
    private let pageSize = 200
    private var isLoadingMore = false
    private var currentQueryToken = UUID()

    init(db: AppDatabase = .shared, initialWorkspaceID: Int64? = nil) {
        self.db = db
        self.selectedWorkspaceID = initialWorkspaceID
        setupObservation()
    }

    private func setupObservation() {
        do {
            let systemWorkspace = try db.ensureSystemWorkspace()
            if selectedWorkspaceID == nil {
                selectedWorkspaceID = systemWorkspace.id
            }
        } catch {
            errorMessage = "Workspace setup failed: \(error.localizedDescription)"
        }

        db.observeWorkspaces()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Workspaces refresh failed: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] workspaces in
                    guard let self else { return }
                    self.workspaces = workspaces

                    if let selectedWorkspaceID = self.selectedWorkspaceID,
                       workspaces.contains(where: { $0.id == selectedWorkspaceID }) {
                        return
                    }

                    self.selectedWorkspaceID = workspaces.first(where: { $0.kind == .all })?.id
                        ?? workspaces.first?.id
                }
            )
            .store(in: &cancellables)

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

        db.observeReferenceTitles()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] titles in
                    self?.allReferenceTitles = titles
                    self?.scheduleTitleKeywordRebuild(for: titles)
                }
            )
            .store(in: &cancellables)

        rebuildReferenceObserver()
    }

    private func rebuildReferenceObserver() {
        referenceObserverCancellable?.cancel()
        countObserverCancellable?.cancel()
        loadMoreTask?.cancel()
        loadMoreTask = nil
        allLoaded = false
        isLoadingMore = false
        currentQueryToken = UUID()

        let scope = currentReferenceScope
        var filter = activeFilter
        filter.workspaceId = selectedWorkspaceID

        if case .titleKeyword(let word) = selectedSidebar {
            filter.keyword = word
            filter.titleOnly = true
        }

        referenceObserverCancellable = db
            .observeReferenceListRows(scope: scope, filter: filter, limit: pageSize)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "References refresh failed: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] rows in
                    guard let self else { return }
                    let oldIds = self.references.map(\.id)
                    let newIds = rows.map(\.id)
                    if oldIds == newIds {
                        for (index, newRow) in rows.enumerated()
                        where self.references[index] != newRow {
                            self.references[index] = newRow
                        }
                    } else {
                        self.references = rows
                    }
                    self.allLoaded = rows.count < self.pageSize
                }
            )

        countObserverCancellable = db
            .observeReferenceCount(scope: scope, filter: filter)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] count in
                    self?.totalReferenceCount = count
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

    private func scheduleSearchDebounce() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
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

    var filteredReferences: [ReferenceListRow] { references }

    func loadMoreIfNeeded(currentItem: ReferenceListRow) {
        guard !allLoaded, !isLoadingMore else { return }
        let thresholdIndex = references.index(references.endIndex, offsetBy: -5, limitedBy: references.startIndex) ?? references.startIndex
        guard let currentIndex = references.firstIndex(where: { $0.id == currentItem.id }),
              currentIndex >= thresholdIndex else { return }

        let scope = currentReferenceScope
        var filter = activeFilter
        filter.workspaceId = selectedWorkspaceID
        if case .titleKeyword(let word) = selectedSidebar {
            filter.keyword = word
            filter.titleOnly = true
        }

        let expectedOffset = references.count
        let queryToken = currentQueryToken
        let db = self.db
        let pageSize = self.pageSize
        isLoadingMore = true

        loadMoreTask = Task {
            do {
                let nextPage = try await Task.detached(priority: .utility) {
                    try db.fetchReferenceListRows(
                        scope: scope,
                        filter: filter,
                        limit: pageSize,
                        offset: expectedOffset
                    )
                }.value

                guard !Task.isCancelled,
                      queryToken == currentQueryToken,
                      references.count == expectedOffset else { return }

                if nextPage.isEmpty {
                    allLoaded = true
                } else {
                    references.append(contentsOf: nextPage)
                    if nextPage.count < pageSize { allLoaded = true }
                }
            } catch is CancellationError {
            } catch {
                guard queryToken == currentQueryToken else { return }
                errorMessage = "Load more failed: \(error.localizedDescription)"
            }

            if queryToken == currentQueryToken {
                isLoadingMore = false
                loadMoreTask = nil
            }
        }
    }

    private func scheduleTitleKeywordRebuild(for titles: [String]) {
        titleKeywordTask?.cancel()

        if titles.isEmpty {
            titleKeywords = []
            return
        }

        titleKeywordTask = Task { [titles] in
            let keywords = await Task.detached(priority: .utility) {
                Self.computeTitleKeywords(from: titles)
            }.value

            guard !Task.isCancelled else { return }
            titleKeywords = keywords
        }
    }

    nonisolated static func computeTitleKeywords(from titles: [String]) -> [(word: String, count: Int)] {
        var freq: [String: Int] = [:]

        for title in titles {
            let words = title
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 && !titleKeywordStopWords.contains($0) }

            for word in Set(words) {
                freq[word, default: 0] += 1
            }
        }

        return freq
            .filter { $0.value >= 2 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(15)
            .map { (word: $0.key, count: $0.value) }
    }

    deinit {
        searchDebounceTask?.cancel()
        titleKeywordTask?.cancel()
        loadMoreTask?.cancel()
    }

}
