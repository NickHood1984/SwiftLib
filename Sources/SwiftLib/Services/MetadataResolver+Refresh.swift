import Foundation
import SwiftLibCore

// MARK: - Refresh Logic (v14 — OpenAlex-First Multi-Source Engine)

extension MetadataResolver {

    func refreshReference(_ reference: Reference, allowCandidateSelection: Bool) async -> ReferenceMetadataRefreshResult {
        // Wrap the entire refresh flow in a 90-second timeout to prevent infinite spinning.
        return await withTaskGroup(of: ReferenceMetadataRefreshResult.self) { group in
            group.addTask {
                await self.refreshReferenceCore(reference, allowCandidateSelection: allowCandidateSelection)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 90 * 1_000_000_000)
                return .failed("元数据刷新超时（90 秒），请检查网络连接后重试。")
            }
            let result = await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func refreshReferenceCore(
        _ reference: Reference,
        allowCandidateSelection: Bool
    ) async -> ReferenceMetadataRefreshResult {
        let seed = MetadataResolutionSeed.fromReference(reference)
        let isBookLike = MetadataRoutePlanner.isBookLike(seed)
        let hasTitle = !reference.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasStrongIdentifier = normalizedIdentifier(reference.doi) != nil
            || normalizedIdentifier(reference.pmid) != nil
            || normalizedIdentifier(reference.isbn) != nil
        var deferredPending: MetadataResolutionResult?

        resolverTrace("refreshReference 标题=\"\(reference.title)\" url=\"\(reference.url ?? "(无)")\" source=\(reference.metadataSource?.rawValue ?? "(无)") shouldSearchCNKI=\(seed.shouldSearchCNKI)")

        func consume(_ outcome: ReferenceMetadataRefreshResult) -> ReferenceMetadataRefreshResult? {
            switch outcome {
            case .refreshed, .failed:
                return outcome
            case .skipped:
                return nil
            case .pending(let result):
                deferredPending = preferredPendingRefreshResult(existing: deferredPending, candidate: result)
                if shouldReturnPendingImmediately(result, allowCandidateSelection: allowCandidateSelection) {
                    return .pending(result)
                }
                return nil
            }
        }

        if isBookLike,
           let explicitBookURL = explicitBookMetadataURL(for: reference) {
            resolverTrace("refreshReference -> 显式图书详情页优先: \(explicitBookURL.absoluteString)")
            let webResult = await resolveWebURLMetadata(
                explicitBookURL,
                fallback: reference,
                seed: seed,
                sourceHint: MetadataResolution.metadataSource(for: explicitBookURL.absoluteString, fallback: .webMeta),
                defaultRejectMessage: "图书详情页已提取，但未满足自动验证规则。"
            )
            if let decisive = consume(await refreshOutcome(from: webResult, original: reference)) {
                return decisive
            }
        }

        // ── Layer 1: Chinese non-book — CNKI native browser context ──
        // Chinese BOOKS skip Layer 1 entirely and go straight to Douban (Layer 3a).
        // CNKI is a journal/thesis database; it rarely covers books and produces noise.
        if seed.shouldSearchCNKI && !isBookLike {
            resolverTrace("refreshReference -> 中文非书，首先尝试 CNKI")
            let cnkiResult = await resolveCNKISeed(seed, fallback: reference)
            if let decisive = consume(await refreshOutcome(from: cnkiResult, original: reference)) {
                return decisive
            }
            resolverTrace("refreshReference -> CNKI 无明确更优更新")
        }

        // ── Layer 2: Chinese book — Douban first ──
        if seed.shouldSearchCNKI && isBookLike && hasTitle {
            resolverTrace("refreshReference -> 中文书籍，优先尝试豆瓣")
            if let bookResult = await refreshWithDoubanBookSearch(reference) {
                return bookResult
            }
        }

        // ── Layer 3: Parallel multi-source fetch (CrossRef + OpenAlex + S2) ──
        if hasStrongIdentifier || (!isBookLike && !seed.shouldSearchCNKI) {
            if let result = await refreshWithParallelSources(reference, seed: seed) {
                if let decisive = consume(result) {
                    return decisive
                }
            }
        }

        // ── Layer 4a: Book title search (Open Library / Google Books, non-Chinese) ──
        if !seed.shouldSearchCNKI && isBookLike && hasTitle {
            if let bookResult = await refreshWithBookTitleSearch(reference) {
                if let decisive = consume(bookResult) {
                    return decisive
                }
            }
        }

        // ── Layer 4: 网页元数据提取（如果有 URL）──
        if let urlString = reference.url?.swiftlib_nilIfBlank {
            resolverTrace("refreshReference -> 尝试网页元数据提取 URL: \(urlString)")
            do {
                let extracted = try await scholarlyExtractor.extract(urlString: urlString)
                if extracted.hasCitationMetaTags {
                    let merged = MetadataResolution.mergeRefreshedReference(primary: extracted.reference, existing: reference)
                    if MetadataResolution.hasMeaningfulRefreshChanges(original: reference, refreshed: merged) {
                        resolverTrace("refreshReference -> 网页元数据刷新成功")
                        return .refreshed(merged)
                    }
                }
            } catch {
                resolverTrace("refreshReference -> 网页元数据提取失败: \(error.localizedDescription)")
            }
        }

        if let deferredPending {
            resolverTrace("refreshReference -> 返回延迟 pending 结果: \(debugLabel(for: deferredPending))")
            return .pending(deferredPending)
        }

        resolverTrace("refreshReference 跳过：所有搜索策略均未找到匹配结果")
        return .skipped("未在已知数据库中找到匹配条目。如有标准标识符（ISBN、DOI 等），可填写后重试。")
    }

    // MARK: - Parallel Multi-Source Refresh (v14 core)

    /// Unified parallel refresh: queries CrossRef + OpenAlex + S2 concurrently,
    /// then merges results with FieldLevelMerger.
    nonisolated private func refreshWithParallelSources(_ reference: Reference, seed: MetadataResolutionSeed) async -> ReferenceMetadataRefreshResult? {
        let fetcher = ParallelSourceFetcher.shared

        let fetchResult: ParallelSourceFetcher.FetchResult

        // forceRefresh: true bypasses every two-tier cache. The user clicked
        // "Refresh Metadata" expecting a fresh scrape, not a replay of a
        // stale cache entry from a bad earlier parse.
        let forceRefresh = true

        // Determine fetch strategy based on available identifiers
        if let doi = normalizedIdentifier(reference.doi) {
            resolverTrace("refreshWithParallelSources -> DOI 并行抓取: \(doi)")
            fetchResult = await fetcher.fetchByDOI(doi, forceRefresh: forceRefresh)
        } else if let pmid = normalizedIdentifier(reference.pmid) {
            resolverTrace("refreshWithParallelSources -> PMID 标识符抓取: \(pmid)")
            fetchResult = await fetcher.fetchByIdentifier(.pmid(pmid), forceRefresh: forceRefresh)
        } else if let isbn = normalizedIdentifier(reference.isbn) {
            resolverTrace("refreshWithParallelSources -> ISBN 标识符抓取: \(isbn)")
            fetchResult = await fetcher.fetchByIdentifier(.isbn(isbn), forceRefresh: forceRefresh)
        } else {
            let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            resolverTrace("refreshWithParallelSources -> 标题并行搜索: \(title)")
            fetchResult = await fetcher.fetchByTitle(title, forceRefresh: forceRefresh)
        }

        guard !fetchResult.sources.isEmpty else {
            resolverTrace("refreshWithParallelSources -> 所有源均无结果")
            return nil
        }

        resolverTrace("refreshWithParallelSources -> 获取到 \(fetchResult.sources.count) 个源: \(fetchResult.sources.map { $0.source.rawValue }.joined(separator: ", "))")

        // FieldLevelMerger: merge all source results with confidence-based priority
        let (merged, enrichment) = FieldLevelMerger.merge(sources: fetchResult.sources, existing: reference)

        // Preserve local state fields from the original reference
        var refreshed = MetadataResolution.mergeRefreshedReference(primary: merged, existing: reference)

        // Apply OpenAlex enrichment (keywords, topics, OA, funding, citations)
        refreshed = MetadataResolution.applyEnrichment(enrichment, to: refreshed)

        // easyScholar journal-rank enrichment
        let secretKey = SwiftLibPreferences.easyScholarSecretKey
        if !secretKey.isEmpty, let journal = refreshed.journal, !journal.isEmpty {
            let rankResponse = await MetadataFetcher.enrichWithEasyScholar(journal: journal, secretKey: secretKey)
            refreshed = MetadataResolution.applyEasyScholarEnrichment(rankResponse, to: refreshed)
        }

        // Carry over confidence score from merger
        if let score = merged.confidenceScore {
            refreshed.confidenceScore = score
        }

        if MetadataResolution.hasMeaningfulRefreshChanges(original: reference, refreshed: refreshed) {
            resolverTrace("refreshWithParallelSources -> 有有效更新 (confidence=\(refreshed.confidenceScore ?? 0))")
            return .refreshed(refreshed)
        }
        return .skipped("元数据没有变化。")
    }

    // MARK: - CNKI Outcome Processing

    nonisolated func refreshOutcome(from result: MetadataResolutionResult, original: Reference) async -> ReferenceMetadataRefreshResult {
        switch result {
        case .verified(let envelope):
            var refreshed = MetadataResolution.mergeRefreshedReference(primary: envelope.reference, existing: original)

            // For CNKI-sourced results, still try to add enrichment from OpenAlex/S2
            let doiValue = refreshed.doi
            let titleValue = refreshed.title

            // Abstract fallback for Chinese articles that may lack abstracts
            if (refreshed.abstract ?? "").isEmpty {
                if let doi = refreshed.doi, !doi.isEmpty {
                    if let newAbstract = try? await MetadataFetcher.fetchAbstractFromSemanticScholar(doi: doi) {
                        resolverTrace("refreshOutcome -> 通过 SemanticScholar(DOI) 获取到摘要")
                        refreshed.abstract = newAbstract
                    } else if let newAbstract = try? await MetadataFetcher.fetchAbstractFromOpenAlex(doi: doi) {
                        resolverTrace("refreshOutcome -> 通过 OpenAlex(DOI) 获取到摘要")
                        refreshed.abstract = newAbstract
                    }
                } else if !refreshed.title.isEmpty, let newAbstract = try? await MetadataFetcher.fetchAbstractFromOpenAlex(title: refreshed.title) {
                    resolverTrace("refreshOutcome -> 通过 OpenAlex(Title) 获取到摘要")
                    refreshed.abstract = newAbstract
                }
            }

            // Enrichment: sequential (avoids async let cancellation crash on swift_task_dealloc)
            let enrichment: MetadataFetcher.OpenAlexEnrichment?
            if let doi = doiValue, !doi.isEmpty {
                enrichment = await MetadataFetcher.enrichWithOpenAlex(doi: doi)
            } else if !titleValue.isEmpty {
                enrichment = await MetadataFetcher.enrichWithOpenAlex(title: titleValue)
            } else {
                enrichment = nil
            }
            refreshed = MetadataResolution.applyEnrichment(enrichment, to: refreshed)

            // easyScholar journal-rank enrichment
            let secretKey = SwiftLibPreferences.easyScholarSecretKey
            if !secretKey.isEmpty, let journal = refreshed.journal, !journal.isEmpty {
                let rankResponse = await MetadataFetcher.enrichWithEasyScholar(journal: journal, secretKey: secretKey)
                refreshed = MetadataResolution.applyEasyScholarEnrichment(rankResponse, to: refreshed)
            }

            if MetadataResolution.hasMeaningfulRefreshChanges(original: original, refreshed: refreshed) {
                return .refreshed(refreshed)
            }
            return .skipped("元数据没有变化。")
        case .candidate, .blocked, .seedOnly, .rejected:
            return .pending(result)
        }
    }

    nonisolated private func explicitBookMetadataURL(for reference: Reference) -> URL? {
        [reference.url, reference.verificationSourceURL]
            .compactMap(normalizedHTTPURL(from:))
            .first(where: MetadataRoutePlanner.isExplicitBookMetadataURL)
    }

    nonisolated private func shouldReturnPendingImmediately(
        _ result: MetadataResolutionResult,
        allowCandidateSelection: Bool
    ) -> Bool {
        guard allowCandidateSelection else { return false }
        switch result {
        case .candidate, .blocked:
            return true
        case .seedOnly, .rejected, .verified:
            return false
        }
    }

    nonisolated private func preferredPendingRefreshResult(
        existing: MetadataResolutionResult?,
        candidate: MetadataResolutionResult
    ) -> MetadataResolutionResult {
        guard let existing else { return candidate }

        func rank(_ result: MetadataResolutionResult) -> Int {
            switch result {
            case .candidate:
                return 4
            case .blocked:
                return 3
            case .rejected:
                return 2
            case .seedOnly:
                return 1
            case .verified:
                return 0
            }
        }

        return rank(candidate) >= rank(existing) ? candidate : existing
    }

    // MARK: - Book Title Search

    nonisolated private func refreshWithBookTitleSearch(_ reference: Reference) async -> ReferenceMetadataRefreshResult? {
        let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        resolverTrace("refreshWithBookTitleSearch title=\"\(title)\" (forceRefresh)")
        // forceRefresh: true so "Refresh Metadata" triggers a real re-scrape,
        // not a replay of the previously-cached (possibly wrong) record.
        guard let bookRef = try? await MetadataFetcher.searchBookByTitle(title, forceRefresh: true) else {
            resolverTrace("refreshWithBookTitleSearch -> 无结果")
            return nil
        }
        let titleScore = MetadataResolution.titleSimilarity(title, bookRef.title)
        resolverTrace("refreshWithBookTitleSearch -> titleScore=\(titleScore) fetchedTitle=\"\(bookRef.title)\"")
        guard titleScore >= 0.60 else {
            resolverTrace("refreshWithBookTitleSearch -> 标题相似度不足，丢弃")
            return nil
        }
        let refreshed = MetadataResolution.mergeRefreshedReference(primary: bookRef, existing: reference)
        if MetadataResolution.hasMeaningfulRefreshChanges(original: reference, refreshed: refreshed) {
            resolverTrace("refreshWithBookTitleSearch -> 有有效更新")
            return .refreshed(refreshed)
        }
        return .skipped("书名搜索命中但元数据没有变化。")
    }

    // MARK: - Douban Book Search (Chinese Books)

    nonisolated private func refreshWithDoubanBookSearch(_ reference: Reference) async -> ReferenceMetadataRefreshResult? {
        let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        resolverTrace("refreshWithDoubanBookSearch title=\"\(title)\"")
        guard let doubanRef = try? await MetadataFetcher.searchDoubanBookByTitle(title) else {
            resolverTrace("refreshWithDoubanBookSearch -> 无结果")
            return nil
        }
        let titleScore = MetadataResolution.titleSimilarity(title, doubanRef.title)
        resolverTrace("refreshWithDoubanBookSearch -> titleScore=\(titleScore) fetchedTitle=\"\(doubanRef.title)\"")
        guard titleScore >= 0.55 else {
            resolverTrace("refreshWithDoubanBookSearch -> 标题相似度不足，丢弃")
            return nil
        }
        let refreshed = MetadataResolution.mergeRefreshedReference(primary: doubanRef, existing: reference)
        if MetadataResolution.hasMeaningfulRefreshChanges(original: reference, refreshed: refreshed) {
            resolverTrace("refreshWithDoubanBookSearch -> 有有效更新（豆瓣）")
            return .refreshed(refreshed)
        }
        return .skipped("豆瓣命中但元数据没有变化。")
    }
}
