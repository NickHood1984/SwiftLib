import Foundation
import SwiftLibCore

// MARK: - CNKI Resolution

extension MetadataResolver {

    func resolveCNKISeed(
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
                if let fallbackResult = await resolveBaiduScholarFallback(seed: seed, fallback: fallback) {
                    return fallbackResult
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

            // Require the best candidate to have a meaningful title similarity.
            // A score below 0.40 means CNKI found something but nothing relevant —
            // treat this the same as "no results" and escalate to Baidu Scholar.
            guard let bestCandidate = topCandidates.first, bestCandidate.score >= 0.40 else {
                resolverTrace("resolveCNKISeed 最高候选评分 < 0.40，视为无有效结果 → 尝试百度学术 fallback")
                if let fallbackResult = await resolveBaiduScholarFallback(seed: seed, fallback: fallback) {
                    return fallbackResult
                }
                return .rejected(
                    RejectedEnvelope(
                        seed: seed,
                        fallbackReference: fallback,
                        currentReference: fallback,
                        reason: .insufficientEvidence,
                        message: "知网搜索结果与查询题名相关性过低，未找到可信匹配。"
                    )
                )
            }

            if shouldAutoResolveCNKICandidate(bestCandidate, second: topCandidates.dropFirst().first, seed: seed) {
                resolverTrace("resolveCNKISeed 原生 CNKI 首候选满足自动解析，继续抓取 authoritative record")
            } else {
                resolverTrace("resolveCNKISeed 原生 CNKI 首候选先做后台详情抓取，尽量避免直接进入候选队列")
            }

            let autoResult = await resolveCandidate(bestCandidate, fallback: fallback, seed: seed)
            resolverTrace("resolveCNKISeed 原生 CNKI 首候选解析结果: \(debugLabel(for: autoResult))")
            switch autoResult {
            case .verified, .blocked:
                return autoResult
            case .rejected, .seedOnly:
                resolverTrace("resolveCNKISeed 原生 CNKI 首候选详情抓取未通过 → 尝试百度学术 fallback")
                if let fallbackResult = await resolveBaiduScholarFallback(seed: seed, fallback: fallback) {
                    return fallbackResult
                }
            case .candidate:
                return autoResult
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
            if let fallbackResult = await resolveBaiduScholarFallback(seed: seed, fallback: fallback) {
                return fallbackResult
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
            if let fallbackResult = await resolveBaiduScholarFallback(seed: seed, fallback: fallback) {
                return fallbackResult
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

    nonisolated private func shouldAutoResolveCNKICandidate(
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
            let normalizedSeed = MetadataResolution.normalizedComparableText(seedAuthor)
            let normalizedTop = MetadataResolution.normalizedComparableText(topAuthor)
            // Use containment check instead of exact match: the seed author may
            // be a malformed concatenation of multiple names (e.g. "林秋奇 韩博平"
            // when the actual first author is "林秋奇"), so accept if either side
            // contains the other.
            let authorMatch = normalizedSeed == normalizedTop
                || normalizedSeed.contains(normalizedTop)
                || normalizedTop.contains(normalizedSeed)
            if !authorMatch { return false }
        }
        return true
    }

    func resolveCNKIURL(_ url: URL, fallback: Reference?, seed: MetadataResolutionSeed?) async -> MetadataResolutionResult {
        resolverTrace("resolveCNKIURL url=\"\(url.absoluteString)\"")
        if MetadataRoutePlanner.isCNKIEBookURL(url) {
            return await resolveWebURLMetadata(
                url,
                fallback: fallback,
                seed: seed,
                sourceHint: .cnki,
                defaultRejectMessage: "知网电子书详情页已提取，但未满足自动验证规则。"
            )
        }
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

    func resolveChineseCorrectionIfNeeded(
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

    private func resolveBaiduScholarFallback(
        seed: MetadataResolutionSeed,
        fallback: Reference?
    ) async -> MetadataResolutionResult? {
        guard MetadataRoutePlanner.shouldUseBaiduScholarFallback(seed: seed) else {
            resolverTrace("resolveBaiduScholarFallback 跳过：当前种子更像图书，不走百度学术")
            return nil
        }
        let baiduOutcome = await BaiduScholarService.searchOutcome(
            title: seed.title ?? "",
            author: seed.firstAuthor
        )

        let baiduRef: Reference
        switch baiduOutcome {
        case .reference(let reference):
            baiduRef = reference
        case .blockedByVerification:
            return .blocked(
                BlockedEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    reason: .verificationRequired,
                    message: "百度学术触发了安全验证，完成验证后可继续检索。"
                )
            )
        case .noResult:
            return nil
        }

        let evidence = buildGenericEvidence(
            for: baiduRef,
            source: .baiduScholar,
            fetchMode: .identifier,
            origin: .identifierAPI,
            recordKey: baiduRef.doi,
            exactIdentifierMatch: false
        )
        let record = AuthoritativeMetadataRecord(reference: baiduRef, evidence: evidence)
        let result = verifyFetchedRecord(
            record,
            seed: seed,
            fallback: fallback,
            defaultRejectMessage: "百度学术候选未满足自动验证规则。"
        )
        switch result {
        case .verified, .candidate, .blocked:
            return result
        case .rejected(let envelope):
            resolverTrace("resolveBaiduScholarFallback 命中但未自动验证通过 → 升为 candidate")
            let fetched = envelope.currentReference ?? baiduRef
            let titleScore = MetadataResolution.titleSimilarity(seed.title ?? "", fetched.title)
            let matchedBy = [
                "title",
                fetched.authors.isEmpty ? nil : "author",
                fetched.year == nil ? nil : "year",
                fetched.journal?.swiftlib_nilIfBlank == nil ? nil : "journal",
                fetched.abstract?.swiftlib_nilIfBlank == nil ? nil : "abstract",
            ].compactMap { $0 }
            let candidateDescriptor = MetadataCandidate(
                source: .baiduScholar,
                title: fetched.title,
                authors: fetched.authors,
                journal: fetched.journal,
                publisher: fetched.publisher,
                year: fetched.year,
                detailURL: fetched.url ?? "",
                score: max(titleScore, 0.60),
                snippet: fetched.abstract,
                workKind: MetadataResolution.workKind(for: fetched.referenceType),
                referenceType: fetched.referenceType,
                isbn: fetched.isbn,
                issn: fetched.issn,
                sourceRecordID: fetched.doi,
                matchedBy: matchedBy
            )
            return .candidate(
                CandidateEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fetched,
                    candidates: [candidateDescriptor],
                    message: "知网未命中，已切换到百度学术候选，请确认后导入。",
                    evidence: envelope.evidence ?? evidence
                )
            )
        case .seedOnly:
            return nil
        }
    }
}
