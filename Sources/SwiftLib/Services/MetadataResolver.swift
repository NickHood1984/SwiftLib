import Foundation
import OSLog
import SwiftLibCore

let resolverLog = Logger(subsystem: "SwiftLib", category: "MetadataResolver")

func resolverTrace(_ message: String) {
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
    let cnkiProvider: CNKIMetadataProvider
    let scholarlyExtractor = WebScholarlyMetadataExtractor()

    init(
        cnkiProvider: CNKIMetadataProvider
    ) {
        self.cnkiProvider = cnkiProvider
    }

    // MARK: - Entry Points

    func resolveImportedPDF(url: URL, extracted: PDFService.ExtractedMetadata) async -> MetadataResolutionResult {
        let seed = MetadataResolutionSeed.fromImportedPDF(url: url, extracted: extracted)
        let fallback = MetadataResolution.fallbackReference(from: extracted, url: url)
        let result = await resolveSeed(seed, fallback: fallback)

        if case .seedOnly(var envelope) = result {
            envelope.message = "未获得 authoritative metadata；仅保留本地附件与 seed。"
            return .seedOnly(envelope)
        }

        return result
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
            return await resolveWebURLMetadata(
                url,
                fallback: nil,
                seed: nil,
                sourceHint: MetadataResolution.metadataSource(for: url.absoluteString, fallback: .webMeta),
                defaultRejectMessage: "网页元数据已提取，但未满足自动验证规则。",
                failureReason: .unsupportedRoute,
                failureMessage: "无法从此 URL 提取元数据，请改用 DOI、PMID、ISBN、arXiv、中文题名，或 CNKI 链接。"
            )
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
            workKindHint: MetadataRoutePlanner.inferWorkKind(fromFreeTextTitle: trimmed)
        )
        return await resolveSeed(seed, fallback: nil)
    }

    func resolveSeed(_ seed: MetadataResolutionSeed, fallback: Reference?) async -> MetadataResolutionResult {
        if let sourceURL = normalizedHTTPURL(from: seed.sourceURL) {
            if isCNKIURL(sourceURL) {
                return await resolveCNKIURL(sourceURL, fallback: fallback, seed: seed)
            }
            if MetadataRoutePlanner.isExplicitBookMetadataURL(sourceURL) {
                return await resolveWebURLMetadata(
                    sourceURL,
                    fallback: fallback,
                    seed: seed,
                    sourceHint: MetadataResolution.metadataSource(for: sourceURL.absoluteString, fallback: .webMeta),
                    defaultRejectMessage: "图书详情页已提取，但未满足自动验证规则。"
                )
            }
        }
        if let isbn = seed.isbn?.swiftlib_nilIfBlank {
            let result = await resolveIdentifierValue(
                isbn,
                as: .isbn(isbn),
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

        if let result = await resolveTitleSeedThroughParallelSources(seed, fallback: fallback) {
            switch result {
            case .verified, .candidate, .blocked:
                return result
            case .seedOnly, .rejected:
                break
            }
        }

        if MetadataRoutePlanner.isBookLike(seed),
           let result = await resolveBookTitleSeed(seed, fallback: fallback) {
            return result
        }

        if seed.shouldSearchCNKI, !MetadataRoutePlanner.isBookLike(seed) {
            return await resolveCNKISeed(seed, fallback: fallback)
        }

        return .seedOnly(
            IntakeEnvelope(
                seed: seed,
                fallbackReference: fallback,
                currentReference: fallback,
                message: "未获得 authoritative metadata；仅保留本地 seed。"
            )
        )
    }

    func retryIntake(_ intake: MetadataIntake) async -> MetadataResolutionResult {
        if let originalInput = intake.originalInput?.swiftlib_nilIfBlank {
            if let url = normalizedHTTPURL(from: originalInput),
               !isCNKIURL(url),
               !MetadataRoutePlanner.isExplicitBookMetadataURL(url),
               SiteAdapterService.shared.adapter(for: url.absoluteString) == nil {
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

    private func resolveBookTitleSeed(
        _ seed: MetadataResolutionSeed,
        fallback: Reference?
    ) async -> MetadataResolutionResult? {
        guard let title = seed.title?.swiftlib_nilIfBlank else { return nil }
        resolverTrace("resolveBookTitleSeed → 按书名查询: \"\(title)\"")

        guard let bookRef = try? await MetadataFetcher.searchBookByTitle(title) else {
            resolverTrace("resolveBookTitleSeed → 无结果")
            return nil
        }

        let evidenceSource = bookRef.metadataSource
            ?? MetadataResolution.metadataSource(for: bookRef.url, fallback: .translationServer)
        let evidence = buildGenericEvidence(
            for: bookRef,
            source: evidenceSource,
            fetchMode: .identifier,
            origin: .identifierAPI,
            recordKey: bookRef.isbn?.swiftlib_nilIfBlank,
            exactIdentifierMatch: false
        )
        let result = verifyFetchedRecord(
            AuthoritativeMetadataRecord(reference: bookRef, evidence: evidence),
            seed: seed,
            fallback: fallback,
            defaultRejectMessage: "书名搜索命中，但仍未满足自动验证规则。"
        )

        switch result {
        case .verified, .candidate, .blocked:
            return result
        case .rejected(let envelope):
            // Historical behavior was to map .rejected → nil here, which dropped the
            // entire book record silently — the user would end up with only the
            // PDF-extracted seed fields (no publisher, no ISBN, no URL).
            //
            // That's especially painful for older Chinese books (pre-ISBN-era, or
            // books whose Douban `extra_attrs.isbn` is empty): B1 requires an ISBN
            // and B2 requires a seed publisher for auto-verification, so when
            // neither fires we still want to surface the Douban record as a
            // candidate the user can confirm with one click.
            resolverTrace("resolveBookTitleSeed → 验证未自动通过，将 \(evidenceSource.displayName) 数据升为 candidate")
            let fetched = envelope.currentReference ?? bookRef
            let candidateDescriptor = MetadataCandidate(
                source: evidenceSource,
                title: fetched.title,
                authors: fetched.authors,
                publisher: fetched.publisher,
                year: fetched.year,
                detailURL: fetched.url ?? "",
                score: 0.80,
                workKind: .book,
                referenceType: fetched.referenceType,
                isbn: fetched.isbn,
                matchedBy: ["title", "author", "year", "publisher"]
            )
            return .candidate(
                CandidateEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fetched,
                    candidates: [candidateDescriptor],
                    message: "按书名命中 \(evidenceSource.displayName)，请确认元数据后加入书库。",
                    evidence: envelope.evidence ?? evidence
                )
            )
        case .seedOnly:
            return nil
        }
    }

    func resolveWebURLMetadata(
        _ url: URL,
        fallback: Reference?,
        seed: MetadataResolutionSeed?,
        sourceHint: MetadataSource,
        defaultRejectMessage: String,
        failureReason: RejectReason = .insufficientEvidence,
        failureMessage: String? = nil
    ) async -> MetadataResolutionResult {
        resolverTrace("resolveWebURLMetadata → 尝试网页元数据提取 URL: \(url.absoluteString)")
        do {
            let extracted = try await scholarlyExtractor.extract(urlString: url.absoluteString)
            let webFallback = fallback.map {
                MetadataResolution.mergeReference(primary: extracted.reference, fallback: $0)
            } ?? extracted.reference

            if let export = extracted.interceptedExport,
               var exportReference = WebExportInterception.parseReference(from: export) {
                if exportReference.url?.swiftlib_nilIfBlank == nil {
                    exportReference.url = extracted.sourceURL
                }
                if exportReference.metadataSource == nil {
                    switch export.format {
                    case .ris:
                        exportReference.metadataSource = .ris
                    case .bibTeX:
                        exportReference.metadataSource = .bibtex
                    case .cnki:
                        exportReference.metadataSource = .cnki
                    }
                }

                let exportEvidence = buildGenericEvidence(
                    for: exportReference,
                    source: exportReference.metadataSource ?? sourceHint,
                    fetchMode: .export,
                    origin: .structuredExport,
                    recordKey: exportReference.doi ?? exportReference.isbn ?? exportReference.pmid,
                    exactIdentifierMatch: false
                )
                let exportResult = verifyFetchedRecord(
                    AuthoritativeMetadataRecord(reference: exportReference, evidence: exportEvidence),
                    seed: seed,
                    fallback: fallback,
                    defaultRejectMessage: "结构化导出已命中，但未满足自动验证规则。"
                )
                switch exportResult {
                case .verified, .candidate, .blocked:
                    return exportResult
                case .rejected(let envelope):
                    if let staged = promoteRejectedRecordToInlineImport(
                        reference: envelope.currentReference ?? exportReference,
                        evidence: envelope.evidence ?? exportEvidence,
                        sourceCount: 1,
                        exactIdentifierMatch: false
                    ) {
                        return staged
                    }
                case .seedOnly:
                    break
                }
            }

            if let identifier = preferredIdentifier(from: webFallback) {
                let identifierResult = await resolveIdentifierValue(
                    identifierString(identifier),
                    as: identifier,
                    seed: seed ?? MetadataResolutionSeed.fromReference(webFallback),
                    fallback: webFallback,
                    existingReference: nil
                )
                switch identifierResult {
                case .verified, .candidate, .blocked:
                    return identifierResult
                case .rejected, .seedOnly:
                    break
                }
            }

            guard extracted.hasCitationMetaTags else {
                if extracted.requiresLogin {
                    return .blocked(
                        BlockedEnvelope(
                            seed: seed,
                            fallbackReference: fallback,
                            currentReference: webFallback,
                            reason: .loginRequired,
                            message: "页面要求先登录或完成机构认证，暂时无法自动抓取。"
                        )
                    )
                }
                return .rejected(
                    RejectedEnvelope(
                        seed: seed,
                        fallbackReference: fallback,
                        currentReference: webFallback,
                        reason: failureReason,
                        message: failureMessage ?? "网页未包含可用的结构化元数据。"
                    )
                )
            }

            var reference = webFallback
            if reference.url?.swiftlib_nilIfBlank == nil {
                reference.url = extracted.sourceURL
            }
            if reference.metadataSource == .webMeta || reference.metadataSource == nil {
                reference.metadataSource = sourceHint
            }
            if reference.siteName?.swiftlib_nilIfBlank == nil {
                reference.siteName = sourceHint.displayName
            }

            let evidenceSource = reference.metadataSource
                ?? MetadataResolution.metadataSource(for: reference.url, fallback: sourceHint)
            let evidence = buildGenericEvidence(
                for: reference,
                source: evidenceSource,
                fetchMode: .detail,
                origin: .structuredDetail,
                recordKey: reference.doi ?? reference.isbn,
                exactIdentifierMatch: false
            )
            let result = verifyFetchedRecord(
                AuthoritativeMetadataRecord(reference: reference, evidence: evidence),
                seed: seed,
                fallback: fallback,
                defaultRejectMessage: defaultRejectMessage
            )
            switch result {
            case .verified, .candidate, .blocked:
                return result
            case .rejected(let envelope):
                if let staged = promoteRejectedRecordToInlineImport(
                    reference: envelope.currentReference ?? reference,
                    evidence: envelope.evidence ?? evidence,
                    sourceCount: 1,
                    exactIdentifierMatch: false
                ) {
                    return staged
                }
                resolverTrace("resolveWebURLMetadata → 网页元数据未通过验证: \(debugLabel(for: result))")
                return result
            case .seedOnly:
                resolverTrace("resolveWebURLMetadata → 网页元数据未通过验证: \(debugLabel(for: result))")
                return result
            }
        } catch {
            resolverTrace("resolveWebURLMetadata → 网页元数据提取失败: \(error.localizedDescription)")
            return .rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: failureReason,
                    message: failureMessage ?? error.localizedDescription
                )
            )
        }
    }

    private func preferredIdentifier(from reference: Reference) -> MetadataFetcher.Identifier? {
        if let doi = reference.doi?.swiftlib_nilIfBlank { return .doi(doi) }
        if let pmid = reference.pmid?.swiftlib_nilIfBlank { return .pmid(pmid) }
        if let isbn = reference.isbn?.swiftlib_nilIfBlank { return .isbn(isbn) }
        return nil
    }
}
