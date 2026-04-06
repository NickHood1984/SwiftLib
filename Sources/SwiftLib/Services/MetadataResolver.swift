import Foundation
import OSLog
import SwiftLibCore

private let resolverLog = Logger(subsystem: "SwiftLib", category: "MetadataResolver")

private func resolverTrace(_ message: String) {
    guard SwiftLibDebugLogging.metadataVerbose else { return }
    resolverLog.notice("\(message, privacy: .public)")
    if let data = "[MetadataResolver] \(message)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

enum ReferenceMetadataRefreshResult {
    case refreshed(Reference)
    case pending(MetadataResolutionResult)
    case skipped(String)
    case failed(String)
}

struct ManualCandidateImportAssessment {
    let reference: Reference
    let canImportDirectly: Bool
    let presentFields: [String]
    let missingFields: [String]
}

@MainActor
final class MetadataResolver {
    private let cnkiProvider: CNKIMetadataProvider
    private let backendClient = TranslationBackendClient()

    init(
        cnkiProvider: CNKIMetadataProvider
    ) {
        self.cnkiProvider = cnkiProvider
    }

    func resolveImportedPDF(url: URL, extracted: PDFService.ExtractedMetadata) async -> MetadataResolutionResult {
        let seed = MetadataResolutionSeed.fromImportedPDF(url: url, extracted: extracted)
        let fallback = MetadataResolution.fallbackReference(from: extracted, url: url)
        let prefersCNKI = MetadataResolution.shouldPreferCNKIForImportedPDF(seed: seed)

        if prefersCNKI {
            let cnkiResult = await resolveCNKISeed(seed, fallback: fallback)
            switch cnkiResult {
            case .candidate, .blocked, .verified:
                return cnkiResult
            case .seedOnly, .rejected:
                break
            }
        }

        if let doi = seed.doi?.swiftlib_nilIfBlank {
            let identifierResult = await resolveIdentifierValue(
                doi,
                as: .doi(doi),
                seed: seed,
                fallback: fallback,
                existingReference: nil
            )
            switch identifierResult {
            case .verified, .candidate, .blocked:
                return identifierResult
            case .rejected, .seedOnly:
                break
            }
        }

        if let isbn = seed.isbn?.swiftlib_nilIfBlank {
            resolverTrace("resolveImportedPDF → ISBN 分支: \(isbn)")
            let identifierResult = await resolveIdentifierValue(
                isbn,
                as: .isbn(isbn),
                seed: seed,
                fallback: fallback,
                existingReference: nil
            )
            switch identifierResult {
            case .verified, .candidate, .blocked:
                return identifierResult
            case .rejected, .seedOnly:
                break
            }
        }

        if seed.shouldSearchCNKI {
            let cnkiResult = await resolveCNKISeed(seed, fallback: fallback)
            switch cnkiResult {
            case .verified, .candidate, .blocked:
                return cnkiResult
            case .seedOnly, .rejected:
                break
            }
        }

        // 书名搜索：书籍类型 + 无 ISBN + 非中文 → Open Library / Google Books 按书名查询
        if seed.workKindHint == .book,
           seed.isbn == nil,
           let title = seed.title?.swiftlib_nilIfBlank,
           !MetadataResolution.containsHanCharacters(title) {
            resolverTrace("resolveImportedPDF → book workKind, no ISBN, trying title search: \"\(title)\"")
            if let bookRef = try? await MetadataFetcher.searchBookByTitle(title) {
                let evidence = buildGenericEvidence(
                    for: bookRef,
                    source: .translationServer,
                    fetchMode: .identifier,
                    origin: .identifierAPI,
                    recordKey: bookRef.isbn?.swiftlib_nilIfBlank,
                    exactIdentifierMatch: false
                )
                let titleResult = verifyFetchedRecord(
                    AuthoritativeMetadataRecord(reference: bookRef, evidence: evidence),
                    seed: seed,
                    fallback: fallback,
                    defaultRejectMessage: "书名搜索命中，但仍未满足自动验证规则。"
                )
                switch titleResult {
                case .verified, .candidate, .blocked:
                    return titleResult
                case .rejected, .seedOnly:
                    break
                }
            }
        }

        return .seedOnly(
            IntakeEnvelope(
                seed: seed,
                fallbackReference: fallback,
                message: "未获得 authoritative metadata；仅保留本地附件与 seed。"
            )
        )
    }

    func resolveManualEntry(_ text: String) async -> MetadataResolutionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .rejected(
                RejectedEnvelope(
                    seed: nil,
                    fallbackReference: nil,
                    reason: .unsupportedRoute,
                    message: "请输入 DOI、ISBN、PMID、arXiv、中文题名，或 CNKI 链接。"
                )
            )
        }

        if let url = normalizedHTTPURL(from: trimmed) {
            if isCNKIURL(url) {
                return await resolveCNKIURL(url, fallback: nil, seed: nil)
            }
            resolverTrace("resolveManualEntry → 尝试 Translation Backend 解析 URL")
            let backendResult = await backendClient.resolve(
                TranslationBackendInput(inputType: .url, value: url.absoluteString)
            )
            let mapped = mapBackendResult(backendResult, seed: nil, fallback: nil)
            switch mapped {
            case .verified, .candidate, .blocked:
                return mapped
            case .seedOnly, .rejected:
                resolverTrace("resolveManualEntry → Translation Backend 未能解析此 URL")
                return .rejected(
                    RejectedEnvelope(
                        seed: nil,
                        fallbackReference: nil,
                        currentReference: nil,
                        reason: .unsupportedRoute,
                        message: "无法从此 URL 提取元数据，请改用 DOI、PMID、ISBN、arXiv、中文题名，或 CNKI 链接。"
                    )
                )
            }
        }

        if let identifier = MetadataFetcher.extractIdentifier(from: trimmed) {
            return await resolveIdentifierValue(
                identifierString(identifier),
                as: identifier,
                seed: nil,
                fallback: nil,
                existingReference: nil
            )
        }

        let seed = MetadataResolutionSeed(
            fileName: trimmed,
            title: trimmed,
            languageHint: MetadataResolution.containsHanCharacters(trimmed) ? .chinese : .unknown,
            workKindHint: .unknown
        )
        return await resolveCNKISeed(seed, fallback: nil)
    }

    func resolveSeed(_ seed: MetadataResolutionSeed, fallback: Reference?) async -> MetadataResolutionResult {
        if let sourceURL = normalizedHTTPURL(from: seed.sourceURL), isCNKIURL(sourceURL) {
            return await resolveCNKIURL(sourceURL, fallback: fallback, seed: seed)
        }
        if let doi = seed.doi?.swiftlib_nilIfBlank {
            let result = await resolveIdentifierValue(
                doi,
                as: .doi(doi),
                seed: seed,
                fallback: fallback,
                existingReference: nil
            )
            switch result {
            case .verified, .candidate, .blocked:
                return result
            case .seedOnly, .rejected:
                break
            }
        }
        return await resolveCNKISeed(seed, fallback: fallback)
    }

    func resolveCandidate(
        _ candidate: MetadataCandidate,
        fallback: Reference? = nil,
        seed: MetadataResolutionSeed? = nil,
        treatingManualSelectionAsConfirmation: Bool = false,
        reviewedBy: String = "candidate-selection"
    ) async -> MetadataResolutionResult {
        // When the user manually confirmed this candidate, try to enrich it via
        // the authoritative record but always fall back to the candidate's own
        // metadata — which the user already verified visually.
        if treatingManualSelectionAsConfirmation {
            let assessment = Self.assessManuallyConfirmedCandidate(candidate, fallback: fallback)
            let candidateReference = assessment.reference
            if assessment.canImportDirectly {
                resolverTrace(
                    "resolveCandidate 手动确认快路径：直接导入候选 title=\"\(candidate.title)\" abstractLen=\(candidateReference.abstract?.count ?? 0)"
                )
                let manual = MetadataVerifier.manuallyVerified(candidateReference, reviewedBy: reviewedBy)
                let evidence = buildGenericEvidence(
                    for: manual,
                    source: candidate.source,
                    fetchMode: .manual,
                    origin: .manual,
                    recordKey: Self.recordKey(for: candidate),
                    exactIdentifierMatch: false
                )
                return .verified(VerifiedEnvelope(reference: manual, evidence: evidence))
            }

            do {
                var record = try await cnkiProvider.fetchAuthoritativeRecord(candidate: candidate)
                record.evidence.verificationHints.competingCandidateCount = 1
                // Verify the fetched title actually matches the candidate the user picked.
                let fetchedTitle = record.reference.title
                let similarity = MetadataResolution.titleSimilarity(candidate.title, fetchedTitle)
                if similarity >= 0.50 {
                    let resolved = verifyFetchedRecord(
                        record,
                        seed: seed,
                        fallback: fallback,
                        defaultRejectMessage: "所选中文候选未达到自动验证标准。"
                    )
                    return Self.promoteManualCandidateSelectionResult(resolved, reviewedBy: reviewedBy)
                }
            } catch {
                // Fetch failed — fall through to use the candidate data directly.
            }
            let manual = MetadataVerifier.manuallyVerified(candidateReference, reviewedBy: reviewedBy)
            let evidence = buildGenericEvidence(
                for: manual,
                source: candidate.source,
                fetchMode: .manual,
                origin: .manual,
                recordKey: Self.recordKey(for: candidate),
                exactIdentifierMatch: false
            )
            return .verified(VerifiedEnvelope(reference: manual, evidence: evidence))
        }

        do {
            var record = try await cnkiProvider.fetchAuthoritativeRecord(candidate: candidate)
            record.evidence.verificationHints.competingCandidateCount = 1
            let resolved = verifyFetchedRecord(
                record,
                seed: seed,
                fallback: fallback,
                defaultRejectMessage: "所选中文候选未达到自动验证标准。"
            )
            return resolved
        } catch let error as CNKIMetadataProvider.CNKIError {
            return blockedOrRejectedResult(
                error: error,
                seed: seed,
                fallback: fallback,
                message: error.localizedDescription
            )
        } catch {
            return .rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .insufficientEvidence,
                    message: error.localizedDescription
                )
            )
        }
    }

    nonisolated private static func referenceFromCandidate(
        _ candidate: MetadataCandidate,
        fallback: Reference?
    ) -> Reference {
        let candidateAbstract = candidate.snippet?.swiftlib_nilIfBlank
        let fallbackAbstract = fallback?.abstract?.swiftlib_nilIfBlank
        let resolvedAbstract: String? = {
            switch (candidateAbstract, fallbackAbstract) {
            case let (candidateAbstract?, fallbackAbstract?):
                return candidateAbstract.count >= fallbackAbstract.count ? candidateAbstract : fallbackAbstract
            case let (candidateAbstract?, nil):
                return candidateAbstract
            case let (nil, fallbackAbstract?):
                return fallbackAbstract
            case (nil, nil):
                return nil
            }
        }()

        var ref = Reference(
            title: candidate.title,
            authors: candidate.authors,
            year: candidate.year,
            journal: candidate.journal,
            doi: fallback?.doi,
            url: candidate.detailURL.isEmpty ? fallback?.url : candidate.detailURL,
            abstract: resolvedAbstract,
            referenceType: candidate.referenceType ?? candidate.workKind.referenceType,
            metadataSource: candidate.source,
            publisher: candidate.publisher,
            isbn: candidate.isbn ?? fallback?.isbn,
            issn: candidate.issn ?? fallback?.issn
        )
        if let fallback {
            ref.volume = ref.volume ?? fallback.volume
            ref.issue = ref.issue ?? fallback.issue
            ref.pages = ref.pages ?? fallback.pages
            ref.pdfPath = fallback.pdfPath
        }
        return ref
    }

    nonisolated static func assessManuallyConfirmedCandidate(
        _ candidate: MetadataCandidate,
        fallback: Reference?
    ) -> ManualCandidateImportAssessment {
        let reference = referenceFromCandidate(candidate, fallback: fallback)
        let titleReady = !reference.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let authorReady = !reference.authors.isEmpty
        let publicationReady = reference.year != nil
            || reference.journal?.swiftlib_nilIfBlank != nil
            || reference.publisher?.swiftlib_nilIfBlank != nil
        let abstractReady = reference.abstract?.swiftlib_nilIfBlank != nil
        let identifierReady = reference.doi?.swiftlib_nilIfBlank != nil
            || reference.isbn?.swiftlib_nilIfBlank != nil
            || reference.issn?.swiftlib_nilIfBlank != nil

        let canImportDirectly = titleReady && (
            (authorReady && publicationReady)
            || (authorReady && abstractReady)
            || (publicationReady && abstractReady)
            || identifierReady
        )

        let presentFields = [
            titleReady ? "题名" : nil,
            authorReady ? "作者" : nil,
            publicationReady ? "年份/刊名/出版者" : nil,
            abstractReady ? "摘要" : nil,
            identifierReady ? "标识符" : nil,
        ].compactMap { $0 }

        let missingFields = [
            titleReady ? nil : "题名",
            authorReady ? nil : "作者",
            publicationReady ? nil : "年份/刊名/出版者",
            abstractReady ? nil : "摘要",
            identifierReady ? nil : "标识符",
        ].compactMap { $0 }

        return ManualCandidateImportAssessment(
            reference: reference,
            canImportDirectly: canImportDirectly,
            presentFields: presentFields,
            missingFields: missingFields
        )
    }

    nonisolated private static func recordKey(for candidate: MetadataCandidate) -> String? {
        if let sourceRecordID = candidate.sourceRecordID?.swiftlib_nilIfBlank {
            return sourceRecordID
        }
        if let exportID = candidate.cnkiExport?.exportID?.swiftlib_nilIfBlank {
            return exportID
        }
        if let dbname = candidate.cnkiExport?.dbname?.swiftlib_nilIfBlank,
           let filename = candidate.cnkiExport?.filename?.swiftlib_nilIfBlank {
            return "\(dbname):\(filename)"
        }
        return nil
    }

    nonisolated static func promoteManualCandidateSelectionResult(
        _ result: MetadataResolutionResult,
        reviewedBy: String
    ) -> MetadataResolutionResult {
        switch result {
        case .verified:
            return result

        case .candidate(let envelope):
            guard let evidence = envelope.evidence,
                  let reference = envelope.currentReference ?? envelope.fallbackReference else {
                return result
            }
            let manual = MetadataVerifier.manuallyVerified(reference, evidence: evidence, reviewedBy: reviewedBy)
            return .verified(VerifiedEnvelope(reference: manual, evidence: evidence))

        case .rejected(let envelope):
            guard let evidence = envelope.evidence,
                  let reference = envelope.currentReference ?? envelope.fallbackReference else {
                return result
            }
            let manual = MetadataVerifier.manuallyVerified(reference, evidence: evidence, reviewedBy: reviewedBy)
            return .verified(VerifiedEnvelope(reference: manual, evidence: evidence))

        case .seedOnly(let envelope):
            guard let evidence = envelope.evidence,
                  let reference = envelope.currentReference ?? envelope.fallbackReference else {
                return result
            }
            let manual = MetadataVerifier.manuallyVerified(reference, evidence: evidence, reviewedBy: reviewedBy)
            return .verified(VerifiedEnvelope(reference: manual, evidence: evidence))

        case .blocked:
            return result
        }
    }

    func retryIntake(_ intake: MetadataIntake) async -> MetadataResolutionResult {
        if let originalInput = intake.originalInput?.swiftlib_nilIfBlank {
            if let url = normalizedHTTPURL(from: originalInput), !isCNKIURL(url) {
                resolverTrace("retryIntake 忽略旧的普通 URL originalInput，改走 seed/fallback")
            } else {
                return await resolveManualEntry(originalInput)
            }
        }
        if let seed = intake.decodedSeed {
            return await resolveSeed(seed, fallback: intake.decodedFallbackReference ?? intake.decodedCurrentReference)
        }
        return .rejected(
            RejectedEnvelope(
                seed: nil,
                fallbackReference: intake.decodedFallbackReference,
                currentReference: intake.decodedCurrentReference,
                reason: .unsupportedRoute,
                message: "当前待验证条目缺少可重试的输入。"
            )
        )
    }

    func refreshReference(_ reference: Reference, allowCandidateSelection _: Bool) async -> ReferenceMetadataRefreshResult {
        // Wrap the entire refresh flow in a 90-second timeout to prevent infinite spinning.
        return await withTaskGroup(of: ReferenceMetadataRefreshResult.self) { group in
            group.addTask {
                await self.refreshReferenceCore(reference)
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

    private func refreshReferenceCore(_ reference: Reference) async -> ReferenceMetadataRefreshResult {
        let seed = MetadataResolutionSeed.fromReference(reference)
        let hasIdentifier = normalizedIdentifier(reference.doi) != nil
            || normalizedIdentifier(reference.isbn) != nil
            || normalizedIdentifier(reference.pmid) != nil
        
        let hasTitle = !reference.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        resolverTrace("refreshReference 标题=\"\(reference.title)\" url=\"\(reference.url ?? "(无)")\" source=\(reference.metadataSource?.rawValue ?? "(无)") shouldSearchCNKI=\(seed.shouldSearchCNKI)")

        // 1. Chinese first — CNKI native browser context
        if seed.shouldSearchCNKI {
            resolverTrace("refreshReference -> 中文特征，首先尝试 CNKI")
            let cnkiResult = await resolveCNKISeed(seed, fallback: reference)
            let outcome = await refreshOutcome(from: cnkiResult, original: reference)
            if case .refreshed = outcome {
                return outcome
            }
            resolverTrace("refreshReference -> CNKI 无明确更优更新")
        }

        // 2. Non-Chinese references with standard identifiers: try native API
        // (CrossRef/PubMed/arXiv/ISBN) — direct calls to academic APIs
        if hasIdentifier && !seed.shouldSearchCNKI {
            resolverTrace("refreshReference -> 非中文+有标识符，本地 API 抓取")
            if let localResult = await refreshWithDirectIdentifierAPIs(reference, seed: seed) {
                resolverTrace("refreshReference 本地 API 结果: \(debugLabel(for: localResult))")
                return localResult
            }
            resolverTrace("refreshReference -> 本地 API 未获取到有效结果")
        }

        // 3. Non-Chinese book without any identifier: Open Library/Google Books title search
        if !hasIdentifier && !seed.shouldSearchCNKI && seed.workKindHint == .book && hasTitle {
            resolverTrace("refreshReference -> 非中文书籍无标识符，直接书名搜索")
            if let bookResult = await refreshWithBookTitleSearch(reference, seed: seed) {
                resolverTrace("refreshReference 书名搜索结果: \(debugLabel(for: bookResult))")
                return bookResult
            }
        }

        // 4. OpenAlex title search as general fallback for non-Chinese items
        if !seed.shouldSearchCNKI && hasTitle {
            resolverTrace("refreshReference -> 尝试 OpenAlex 标题搜索")
            if let titleResult = await refreshWithOpenAlexTitleSearch(reference, seed: seed) {
                return titleResult
            }
        }

        // 5. Translation Backend as last-resort fallback
        resolverTrace("refreshReference -> 尝试 Translation Backend 刷新")
        let backendResult = await backendClient.refresh(reference: reference)
        switch backendResult {
        case .resolved(let refreshedRef):
            let merged = MetadataResolution.mergeRefreshedReference(primary: refreshedRef, existing: reference)
            if MetadataResolution.hasMeaningfulRefreshChanges(original: reference, refreshed: merged) {
                resolverTrace("refreshReference -> Translation Backend 刷新成功")
                return .refreshed(merged)
            }
        case .candidates, .unresolved, .unavailable:
            break
        }

        resolverTrace("refreshReference 跳过：所有搜索策略均未找到匹配结果")
        return .skipped("未在已知数据库中找到匹配条目。如有标准标识符（ISBN、DOI 等），可填写后重试。")
    }

    private func refreshOutcome(from result: MetadataResolutionResult, original: Reference) async -> ReferenceMetadataRefreshResult {
        switch result {
        case .verified(let envelope):
            var refreshed = MetadataResolution.mergeRefreshedReference(primary: envelope.reference, existing: original)
            
            // Extract abstract fallback for English Articles
            if (refreshed.abstract ?? "").isEmpty {
                if let doi = refreshed.doi, !doi.isEmpty {
                    // Try S2 first, then OpenAlex by DOI
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
            
            if MetadataResolution.hasMeaningfulRefreshChanges(original: original, refreshed: refreshed) {
                return .refreshed(refreshed)
            }
            return .skipped("元数据没有变化。")
        case .candidate, .blocked, .seedOnly, .rejected:
            return .pending(result)
        }
    }

    private func resolveCNKISeed(
        _ seed: MetadataResolutionSeed,
        fallback: Reference?,
        forceSearch: Bool = false
    ) async -> MetadataResolutionResult {
        guard forceSearch || seed.shouldSearchCNKI else {
            resolverTrace("resolveCNKISeed 跳过：缺少中文搜索种子")
            return .seedOnly(
                IntakeEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    message: "缺少可用于中文源搜索的种子。"
                )
            )
        }

        // ─────────────────────────────────────────────────────────────────────────────
        // CNKI 主路径：原生 CNKIMetadataProvider（浏览器上下文）
        // 依赖同一套 WKWebView 会话来完成搜索、详情页提取和人工验证后的继续。
        // ─────────────────────────────────────────────────────────────────────────────
        resolverTrace("resolveCNKISeed 标题=\"\(seed.title ?? "(无)")\" 作者=\"\(seed.firstAuthor ?? "(无)")\" → 走原生 CNKIMetadataProvider（浏览器上下文）")
        do {
            let candidates = try await cnkiProvider.search(seed: seed)
                .sorted { $0.score > $1.score }

            resolverTrace("resolveCNKISeed 原生 CNKI 候选数=\(candidates.count)")

            guard !candidates.isEmpty else {
                // CNKI 未返回结果，尝试百度学术 fallback
                resolverTrace("resolveCNKISeed 原生 CNKI 无结果 → 尝试百度学术 fallback")
                let baiduResult = await backendClient.searchCN(
                    title: seed.title ?? "",
                    author: seed.firstAuthor
                )
                let mapped = mapBackendResult(baiduResult, seed: seed, fallback: fallback)
                switch mapped {
                case .verified, .candidate, .blocked:
                    return mapped
                case .seedOnly, .rejected:
                    break
                }
                return .rejected(
                    RejectedEnvelope(
                        seed: seed,
                        fallbackReference: fallback,
                        currentReference: fallback,
                        reason: .insufficientEvidence,
                        message: "未找到可信的知网候选结果。"
                    )
                )
            }

            let topCandidates = Array(candidates.prefix(5))

            if let top = topCandidates.first,
               shouldAutoResolveCNKICandidate(top, second: topCandidates.dropFirst().first, seed: seed) {
                resolverTrace("resolveCNKISeed 原生 CNKI 首候选满足自动解析，继续抓取 authoritative record")
                let autoResult = await resolveCandidate(top, fallback: fallback, seed: seed)
                resolverTrace("resolveCNKISeed 原生 CNKI 首候选解析结果: \(debugLabel(for: autoResult))")
                switch autoResult {
                case .verified, .blocked:
                    return autoResult
                default:
                    break
                }
            }

            return .candidate(
                CandidateEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    candidates: topCandidates,
                    message: "已找到候选结果，需进一步抓取 authoritative record。"
                )
            )
        } catch let error as CNKIMetadataProvider.CNKIError {
            // 对于验证阻塞和超时，不走 fallback，直接返回
            switch error {
            case .blockedByVerification, .verificationCancelled, .timedOut:
                return blockedOrRejectedResult(
                    error: error,
                    seed: seed,
                    fallback: fallback,
                    message: error.localizedDescription
                )
            default:
                break
            }
            // 其他 CNKI 错误：尝试百度学术 fallback
            resolverTrace("resolveCNKISeed CNKI 错误 → 尝试百度学术 fallback: \(error.localizedDescription)")
            let baiduResult = await backendClient.searchCN(
                title: seed.title ?? "",
                author: seed.firstAuthor
            )
            let mapped = mapBackendResult(baiduResult, seed: seed, fallback: fallback)
            switch mapped {
            case .verified, .candidate, .blocked:
                return mapped
            case .seedOnly, .rejected:
                break
            }
            return blockedOrRejectedResult(
                error: error,
                seed: seed,
                fallback: fallback,
                message: error.localizedDescription
            )
        } catch {
            // 通用错误：尝试百度学术 fallback
            resolverTrace("resolveCNKISeed 通用错误 → 尝试百度学术 fallback: \(error.localizedDescription)")
            let baiduResult = await backendClient.searchCN(
                title: seed.title ?? "",
                author: seed.firstAuthor
            )
            let mapped = mapBackendResult(baiduResult, seed: seed, fallback: fallback)
            switch mapped {
            case .verified, .candidate, .blocked:
                return mapped
            case .seedOnly, .rejected:
                break
            }
            return .rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .insufficientEvidence,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func shouldAutoResolveCNKICandidate(
        _ top: MetadataCandidate,
        second: MetadataCandidate?,
        seed: MetadataResolutionSeed
    ) -> Bool {
        let titleScore = MetadataResolution.titleSimilarity(seed.title ?? "", top.title)
        guard titleScore >= 0.90 else { return false }
        let secondScore = second?.score ?? 0
        let margin = top.score - secondScore
        let hasClearLead = top.score >= 0.85 || margin >= 0.08 || second == nil
        guard hasClearLead else { return false }
        let seedAuthor = seed.firstAuthor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !seedAuthor.isEmpty {
            let topAuthor = top.authors.first?.displayName ?? ""
            let authorMatch = MetadataResolution.normalizedComparableText(seedAuthor)
                == MetadataResolution.normalizedComparableText(topAuthor)
            if !authorMatch { return false }
        }
        return true
    }

    private func refreshWithDirectIdentifierAPIs(_ reference: Reference, seed: MetadataResolutionSeed) async -> ReferenceMetadataRefreshResult? {
        let identifier: MetadataFetcher.Identifier?
        if let doi = normalizedIdentifier(reference.doi) {
            identifier = .doi(doi)
        } else if let pmid = normalizedIdentifier(reference.pmid) {
            identifier = .pmid(pmid)
        } else if let isbn = normalizedIdentifier(reference.isbn) {
            identifier = .isbn(isbn)
        } else {
            identifier = nil
        }
        guard let identifier else { return nil }

        let localResult = await resolveIdentifierLocally(identifier, seed: seed, fallback: reference)
        let outcome = await refreshOutcome(from: localResult, original: reference)
        switch outcome {
        case .refreshed:
            return outcome
        case .skipped:
            return outcome
        default:
            return nil
        }
    }

    private func refreshWithOpenAlexTitleSearch(_ reference: Reference, seed: MetadataResolutionSeed) async -> ReferenceMetadataRefreshResult? {
        let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        resolverTrace("refreshWithOpenAlexTitleSearch title=\"\(title)\"")

        do {
            guard let fetched = try await MetadataFetcher.fetchFromOpenAlexByTitle(title) else {
                resolverTrace("refreshWithOpenAlexTitleSearch -> OpenAlex 无结果")
                return nil
            }

            let titleScore = MetadataResolution.titleSimilarity(title, fetched.title)
            resolverTrace("refreshWithOpenAlexTitleSearch -> titleScore=\(titleScore) fetchedTitle=\"\(fetched.title)\"")
            guard titleScore >= 0.80 else {
                resolverTrace("refreshWithOpenAlexTitleSearch -> 标题相似度不足，丢弃")
                return nil
            }

            var refreshed = MetadataResolution.mergeRefreshedReference(primary: fetched, existing: reference)

            // Also try to fetch abstract via Semantic Scholar if we got a DOI
            if (refreshed.abstract ?? "").isEmpty, let doi = refreshed.doi, !doi.isEmpty {
                if let abstract = try? await MetadataFetcher.fetchAbstractFromSemanticScholar(doi: doi) {
                    refreshed.abstract = abstract
                }
            }

            if MetadataResolution.hasMeaningfulRefreshChanges(original: reference, refreshed: refreshed) {
                resolverTrace("refreshWithOpenAlexTitleSearch -> 有有效更新")
                return .refreshed(refreshed)
            }
            return .skipped("元数据没有变化。")
        } catch {
            resolverTrace("refreshWithOpenAlexTitleSearch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func refreshWithBookTitleSearch(_ reference: Reference, seed: MetadataResolutionSeed) async -> ReferenceMetadataRefreshResult? {
        let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        resolverTrace("refreshWithBookTitleSearch title=\"\(title)\"")
        guard let bookRef = try? await MetadataFetcher.searchBookByTitle(title) else {
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

    private func resolveCNKIURL(_ url: URL, fallback: Reference?, seed: MetadataResolutionSeed?) async -> MetadataResolutionResult {
        resolverTrace("resolveCNKIURL url=\"\(url.absoluteString)\"")
        do {
            let record = try await cnkiProvider.fetchAuthoritativeRecord(detailURL: url)
            let result = verifyFetchedRecord(
                record,
                seed: seed,
                fallback: fallback,
                defaultRejectMessage: "知网页面未满足自动验证规则。"
            )
            resolverTrace("resolveCNKIURL 结果: \(debugLabel(for: result))")
            return result
        } catch let error as CNKIMetadataProvider.CNKIError {
            let result = blockedOrRejectedResult(
                error: error,
                seed: seed,
                fallback: fallback,
                message: error.localizedDescription
            )
            resolverTrace("resolveCNKIURL CNKIError: \(debugLabel(for: result))")
            return result
        } catch {
            let result = MetadataResolutionResult.rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .insufficientEvidence,
                    message: error.localizedDescription
                )
            )
            resolverTrace("resolveCNKIURL failed error=\"\(error.localizedDescription)\"")
            return result
        }
    }

    private func resolveChineseCorrectionIfNeeded(
        baseReference: Reference,
        seed: MetadataResolutionSeed?,
        fallback: Reference?,
        inputURL: URL?,
        existingReference: Reference?
    ) async -> MetadataResolutionResult? {
        guard ChineseMetadataMergePolicy.shouldAttemptChineseCorrection(
            seed: seed,
            inputURL: inputURL,
            reference: baseReference,
            existingReference: existingReference
        ) else {
            return nil
        }

        let correctionSeed = Self.correctionSeed(for: baseReference, preferredSeed: seed, inputURL: inputURL)
        let correction = await resolveCNKISeed(correctionSeed, fallback: fallback, forceSearch: true)
        switch correction {
        case .candidate, .blocked:
            return correction
        case .verified:
            return correction
        case .seedOnly, .rejected:
            return nil
        }
    }

    private func verifyFetchedRecord(
        _ record: AuthoritativeMetadataRecord,
        seed: MetadataResolutionSeed?,
        fallback: Reference?,
        defaultRejectMessage: String
    ) -> MetadataResolutionResult {
        let decision = MetadataVerifier.verify(reference: record.reference, seed: seed, evidence: record.evidence)
        switch decision {
        case .verified(let envelope):
            let mergedReference = fallback.map { MetadataResolution.mergeReference(primary: envelope.reference, fallback: $0) } ?? envelope.reference
            return .verified(VerifiedEnvelope(reference: mergedReference, evidence: envelope.evidence))

        case .candidate(let envelope):
            let current = fallback.map { MetadataResolution.mergeReference(primary: envelope.currentReference ?? record.reference, fallback: $0) }
                ?? envelope.currentReference
                ?? record.reference
            return .candidate(
                CandidateEnvelope(
                    seed: seed ?? envelope.seed,
                    fallbackReference: fallback ?? envelope.fallbackReference,
                    currentReference: current,
                    candidates: envelope.candidates,
                    message: envelope.message,
                    evidence: envelope.evidence ?? record.evidence
                )
            )

        case .blocked(let envelope):
            return .blocked(
                BlockedEnvelope(
                    seed: seed ?? envelope.seed,
                    fallbackReference: fallback ?? envelope.fallbackReference,
                    currentReference: envelope.currentReference ?? record.reference,
                    candidates: envelope.candidates,
                    reason: envelope.reason,
                    message: envelope.message,
                    evidence: envelope.evidence ?? record.evidence
                )
            )

        case .rejected(let envelope):
            let mergedCurrent = fallback.map { MetadataResolution.mergeReference(primary: envelope.currentReference ?? record.reference, fallback: $0) }
                ?? envelope.currentReference
                ?? record.reference
            return .rejected(
                RejectedEnvelope(
                    seed: seed ?? envelope.seed,
                    fallbackReference: fallback ?? envelope.fallbackReference,
                    currentReference: mergedCurrent,
                    reason: envelope.reason,
                    message: envelope.message.isEmpty ? defaultRejectMessage : envelope.message,
                    evidence: envelope.evidence ?? record.evidence
                )
            )
        }
    }

    private func blockedOrRejectedResult(
        error: CNKIMetadataProvider.CNKIError,
        seed: MetadataResolutionSeed?,
        fallback: Reference?,
        message: String
    ) -> MetadataResolutionResult {
        switch error {
        case .blockedByVerification:
            return .blocked(
                BlockedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .verificationRequired,
                    message: message
                )
            )
        case .verificationCancelled:
            return .blocked(
                BlockedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .verificationRequired,
                    message: message
                )
            )
        case .timedOut:
            return .blocked(
                BlockedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .timedOut,
                    message: message
                )
            )
        default:
            return .rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .insufficientEvidence,
                    message: message
                )
            )
        }
    }

    private func resolveIdentifierValue(
        _ rawIdentifier: String,
        as identifier: MetadataFetcher.Identifier,
        seed: MetadataResolutionSeed?,
        fallback: Reference?,
        existingReference: Reference?
    ) async -> MetadataResolutionResult {
        resolverTrace("resolveIdentifierValue 标识符=\"\(rawIdentifier)\" -> 本地标识符解析")
        return await resolveIdentifierLocally(identifier, seed: seed, fallback: fallback)
    }

    private func resolveIdentifierLocally(
        _ identifier: MetadataFetcher.Identifier,
        seed: MetadataResolutionSeed?,
        fallback: Reference?
    ) async -> MetadataResolutionResult {
        resolverTrace("resolveIdentifierLocally -> \(String(describing: identifier))")
        do {
            let reference: Reference
            switch identifier {
            case .doi(let value):
                reference = try await MetadataFetcher.fetchFromDOI(value)
            case .pmid(let value):
                reference = try await MetadataFetcher.fetchFromPMID(value)
            case .arxiv(let value):
                reference = try await MetadataFetcher.fetchFromArXiv(value)
            case .isbn(let value):
                reference = try await MetadataFetcher.fetchFromISBN(value)
            }

            let evidence = buildGenericEvidence(
                for: reference,
                source: reference.metadataSource ?? .translationServer,
                fetchMode: .identifier,
                origin: .identifierAPI,
                recordKey: normalizedIdentifier(reference.doi) ?? normalizedIdentifier(reference.pmid) ?? normalizedIdentifier(reference.isbn),
                exactIdentifierMatch: true
            )
            return verifyFetchedRecord(
                AuthoritativeMetadataRecord(reference: reference, evidence: evidence),
                seed: seed,
                fallback: fallback,
                defaultRejectMessage: "标识符命中，但仍未满足自动验证规则。"
            )
        } catch {
            resolverTrace("resolveIdentifierLocally failed error=\"\(error.localizedDescription)\"")
            return .rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .insufficientEvidence,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func debugLabel(for result: MetadataResolutionResult) -> String {
        switch result {
        case .verified(let envelope):
            return "verified(title=\"\(envelope.reference.title)\")"
        case .candidate(let envelope):
            let count = envelope.candidates.count
            let title = envelope.currentReference?.title ?? envelope.candidates.first?.title ?? "(无)"
            return "candidate(count=\(count), title=\"\(title)\")"
        case .blocked(let envelope):
            return "blocked(reason=\(envelope.reason.rawValue), message=\"\(envelope.message)\")"
        case .seedOnly(let envelope):
            return "seedOnly(message=\"\(envelope.message)\")"
        case .rejected(let envelope):
            return "rejected(reason=\(envelope.reason.rawValue), message=\"\(envelope.message)\")"
        }
    }

    private func debugLabel(for result: ReferenceMetadataRefreshResult) -> String {
        switch result {
        case .refreshed(let reference):
            return "refreshed(title=\"\(reference.title)\")"
        case .pending(let resolution):
            return "pending(\(debugLabel(for: resolution)))"
        case .skipped(let message):
            return "skipped(message=\"\(message)\")"
        case .failed(let message):
            return "failed(message=\"\(message)\")"
        }
    }

    private func buildGenericEvidence(
        for reference: Reference,
        source: MetadataSource,
        fetchMode: FetchMode,
        origin: EvidenceOrigin,
        recordKey: String?,
        exactIdentifierMatch: Bool
    ) -> EvidenceBundle {
        var fields: [FieldEvidence] = [FieldEvidence(field: "title", value: reference.title, origin: origin)]
        if !reference.authors.isEmpty {
            fields.append(FieldEvidence(field: "authors", value: reference.authors.displayString, origin: origin))
        }
        if let year = reference.year {
            fields.append(FieldEvidence(field: "year", value: String(year), origin: origin))
        }
        if let journal = reference.journal?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "journal", value: journal, origin: origin))
        }
        if let pages = reference.pages?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "pages", value: pages, origin: origin))
        }
        if let doi = reference.doi?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "doi", value: doi, origin: origin))
        }
        if let isbn = reference.isbn?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "isbn", value: isbn, origin: origin))
        }
        if let institution = reference.institution?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "institution", value: institution, origin: origin))
        }
        if let thesisType = reference.genre?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "thesisType", value: thesisType, origin: origin))
        }

        return EvidenceBundle(
            source: source,
            recordKey: recordKey,
            sourceURL: reference.url,
            fetchMode: fetchMode,
            fieldEvidence: fields,
            verificationHints: VerificationHints(
                hasStructuredTitle: !reference.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                hasStructuredAuthors: !reference.authors.isEmpty,
                hasStructuredJournal: reference.journal?.swiftlib_nilIfBlank != nil,
                hasStructuredInstitution: reference.institution?.swiftlib_nilIfBlank != nil,
                hasStructuredPages: reference.pages?.swiftlib_nilIfBlank != nil,
                hasStructuredThesisType: reference.genre?.swiftlib_nilIfBlank != nil,
                hasStableRecordKey: recordKey?.swiftlib_nilIfBlank != nil,
                usedIdentifierFetch: fetchMode == .identifier,
                exactIdentifierMatch: exactIdentifierMatch
            )
        )
    }

    nonisolated static func correctionSeed(
        for reference: Reference,
        preferredSeed: MetadataResolutionSeed?,
        inputURL: URL?
    ) -> MetadataResolutionSeed {
        var seed = preferredSeed ?? MetadataResolutionSeed.fromReference(reference)
        if seed.sourceURL == nil {
            seed.sourceURL = inputURL?.absoluteString ?? reference.url
        }
        if seed.doi == nil {
            seed.doi = reference.doi?.swiftlib_nilIfBlank
        }
        if seed.title == nil || !MetadataResolution.containsHanCharacters(seed.title) {
            let chineseTitle = reference.title.swiftlib_nilIfBlank
            if MetadataResolution.containsHanCharacters(chineseTitle) {
                seed.title = chineseTitle
            }
        }
        if seed.journal == nil || !MetadataResolution.containsHanCharacters(seed.journal) {
            let chineseJournal = reference.journal.swiftlib_nilIfBlank
            if MetadataResolution.containsHanCharacters(chineseJournal) {
                seed.journal = chineseJournal
            }
        }

        if !MetadataResolution.containsHanCharacters(seed.title),
           let doi = seed.doi?.swiftlib_nilIfBlank {
            seed.title = nil
            seed.fileName = doi
        }

        let preferredAuthor = reference.authors.first?.displayName.swiftlib_nilIfBlank
        if MetadataResolution.containsHanCharacters(seed.firstAuthor) == false {
            seed.firstAuthor = MetadataResolution.containsHanCharacters(preferredAuthor) ? preferredAuthor : nil
        }

        seed.languageHint = .chinese
        return seed
    }

    private func identifierString(_ identifier: MetadataFetcher.Identifier) -> String {
        switch identifier {
        case .doi(let value), .pmid(let value), .arxiv(let value), .isbn(let value):
            return value
        }
    }

    private func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedHTTPURL(from value: String?) -> URL? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }

    private func isCNKIURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return MetadataResolution.metadataSource(for: url.absoluteString, fallback: .translationServer) == .cnki
    }

    // MARK: - Translation Backend Mapping

    private func mapBackendResult(
        _ result: TranslationBackendResult,
        seed: MetadataResolutionSeed?,
        fallback: Reference?
    ) -> MetadataResolutionResult {
        switch result {
        case .resolved(let ref):
            let evidence = buildGenericEvidence(
                for: ref,
                source: .translationServer,
                fetchMode: .identifier,
                origin: .identifierAPI,
                recordKey: ref.doi?.swiftlib_nilIfBlank ?? ref.url?.swiftlib_nilIfBlank,
                exactIdentifierMatch: false
            )
            return verifyFetchedRecord(
                AuthoritativeMetadataRecord(reference: ref, evidence: evidence),
                seed: seed,
                fallback: fallback,
                defaultRejectMessage: "Translation backend 命中，但未满足自动验证规则。"
            )
        case .candidates(let candidates):
            return .candidate(
                CandidateEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    candidates: candidates,
                    message: "Translation backend 返回了多个候选结果，请选择。"
                )
            )
        case .unresolved(let msg):
            resolverTrace("mapBackendResult -> unresolved: \(msg)")
            return .rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .insufficientEvidence,
                    message: msg
                )
            )
        case .unavailable(let msg):
            resolverTrace("mapBackendResult -> unavailable: \(msg)")
            return .rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .insufficientEvidence,
                    message: msg
                )
            )
        }
    }
}
