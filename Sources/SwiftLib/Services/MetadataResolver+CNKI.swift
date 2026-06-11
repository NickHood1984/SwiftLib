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
                // CNKI 未返回结果，尝试中文浏览器 fallback
                resolverTrace("resolveCNKISeed 原生 CNKI 无结果 → 尝试中文浏览器 fallback")
                if let fallbackResult = await resolveChineseBrowserFallback(seed: seed, fallback: fallback) {
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
            // treat this the same as "no results" and try the browser aggregation path.
            guard let bestCandidate = topCandidates.first, bestCandidate.score >= 0.40 else {
                resolverTrace("resolveCNKISeed 最高候选评分 < 0.40，视为无有效结果 → 尝试中文浏览器 fallback")
                if let fallbackResult = await resolveChineseBrowserFallback(seed: seed, fallback: fallback) {
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
                resolverTrace("resolveCNKISeed 原生 CNKI 首候选详情抓取未通过 → 尝试中文浏览器 fallback")
                if let fallbackResult = await resolveChineseBrowserFallback(seed: seed, fallback: fallback) {
                    return fallbackResult
                }
            case .candidate:
                resolverTrace("resolveCNKISeed 原生 CNKI 仅得到候选 → 继续尝试中文浏览器聚合候选")
                return await augmentCandidateWithChineseBrowserFallbacks(
                    autoResult,
                    seed: seed,
                    fallback: fallback
                )
            }

            let candidateResult = MetadataResolutionResult.candidate(
                CandidateEnvelope(
                    seed: seed,
                    fallbackReference: fallback,
                    currentReference: fallback,
                    candidates: topCandidates,
                    message: "已找到候选结果，需进一步抓取 authoritative record。"
                )
            )
            resolverTrace("resolveCNKISeed 返回 CNKI 候选前 → 继续尝试中文浏览器聚合候选")
            return await augmentCandidateWithChineseBrowserFallbacks(
                candidateResult,
                seed: seed,
                fallback: fallback
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
            // 其他 CNKI 错误：尝试中文浏览器 fallback
            resolverTrace("resolveCNKISeed CNKI 错误 → 尝试中文浏览器 fallback: \(error.localizedDescription)")
            if let fallbackResult = await resolveChineseBrowserFallback(seed: seed, fallback: fallback) {
                return fallbackResult
            }
            return blockedOrRejectedResult(
                error: error,
                seed: seed,
                fallback: fallback,
                message: error.localizedDescription
            )
        } catch {
            // 通用错误：尝试中文浏览器 fallback
            resolverTrace("resolveCNKISeed 通用错误 → 尝试中文浏览器 fallback: \(error.localizedDescription)")
            if let fallbackResult = await resolveChineseBrowserFallback(seed: seed, fallback: fallback) {
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

    private func resolveChineseBrowserFallback(
        seed: MetadataResolutionSeed,
        fallback: Reference?
    ) async -> MetadataResolutionResult? {
        guard MetadataRoutePlanner.shouldUseChineseJournalBrowserFallback(seed: seed) else {
            resolverTrace("resolveChineseBrowserFallback 跳过：当前种子更像图书，不走中文期刊浏览器聚合")
            return nil
        }

        var candidateEnvelopes: [CandidateEnvelope] = []

        if let browserEnvelope = await resolveChineseJournalBrowserFallbackEnvelope(seed: seed, fallback: fallback) {
            candidateEnvelopes.append(browserEnvelope)
        }

        // 最后一道回退：万方/维普都没有产出候选时，尝试百度学术聚合检索。
        // （v1.3.0 引入的百度回退在 v1.4.0 重构中丢失了调用链，这里重新接回。）
        if candidateEnvelopes.isEmpty,
           let baiduEnvelope = await baiduScholarFallbackEnvelope(seed: seed, fallback: fallback) {
            candidateEnvelopes.append(baiduEnvelope)
        }

        if let mergedEnvelope = Self.mergedChineseBrowserCandidateEnvelopes(candidateEnvelopes) {
            return .candidate(mergedEnvelope)
        }

        return nil
    }

    /// 百度学术兜底检索：返回单候选 envelope，统一走人工确认（百度是聚合页，
    /// 证据质量低于知网/万方/维普详情页，不做自动验证）。
    private func baiduScholarFallbackEnvelope(
        seed: MetadataResolutionSeed,
        fallback: Reference?
    ) async -> CandidateEnvelope? {
        guard let title = seed.title?.swiftlib_nilIfBlank else { return nil }

        let outcome = await BaiduScholarService.searchOutcome(title: title, author: seed.firstAuthor)
        guard case .reference(let reference) = outcome else {
            resolverTrace("baiduScholarFallbackEnvelope → 百度学术无结果或受阻")
            return nil
        }

        let score = MetadataResolution.scoreStructuredChineseCandidate(
            seed: seed,
            title: reference.title,
            authors: reference.authors,
            journal: reference.journal,
            year: reference.year
        )
        resolverTrace("baiduScholarFallbackEnvelope → 百度学术候选 title=\"\(reference.title)\" score=\(String(format: "%.3f", score))")

        let candidate = MetadataCandidate(
            source: .baiduScholar,
            title: reference.title,
            authors: reference.authors,
            journal: reference.journal,
            year: reference.year,
            detailURL: reference.url ?? "",
            score: score,
            snippet: reference.abstract,
            workKind: .journalArticle,
            referenceType: .journalArticle,
            matchedBy: [
                "title",
                reference.authors.isEmpty ? nil : "author",
                reference.year == nil ? nil : "year",
                reference.journal?.swiftlib_nilIfBlank == nil ? nil : "journal",
            ].compactMap { $0 }
        )
        return CandidateEnvelope(
            seed: seed,
            fallbackReference: fallback,
            currentReference: fallback,
            candidates: [candidate],
            message: "知网与万方/维普均无结果，已从百度学术检索到候选，请确认后导入。"
        )
    }

    private func resolveChineseJournalBrowserFallbackEnvelope(
        seed: MetadataResolutionSeed,
        fallback: Reference?
    ) async -> CandidateEnvelope? {
        var candidates: [MetadataCandidate] = []
        async let wanfangOutcome = ChineseJournalBrowserSearchService.search(channel: .wanfang, seed: seed)
        async let vipOutcome = ChineseJournalBrowserSearchService.search(channel: .vip, seed: seed)
        let outcomes = await [
            (ChineseJournalBrowserSearchService.Channel.wanfang, wanfangOutcome),
            (.vip, vipOutcome)
        ]

        for (channel, outcome) in outcomes {
            switch outcome {
            case .candidates(let channelCandidates):
                resolverTrace("resolveChineseJournalBrowserFallbackEnvelope \(channel.displayName) 候选数=\(channelCandidates.count)")
                candidates.append(contentsOf: channelCandidates)
            case .blockedByVerification:
                resolverTrace("resolveChineseJournalBrowserFallbackEnvelope \(channel.displayName) 受阻")
            case .noResult:
                resolverTrace("resolveChineseJournalBrowserFallbackEnvelope \(channel.displayName) 无结果")
            }
        }

        guard !candidates.isEmpty else { return nil }
        return CandidateEnvelope(
            seed: seed,
            fallbackReference: fallback,
            currentReference: fallback,
            candidates: candidates.sorted { $0.score > $1.score },
            message: "知网不稳定时，已从万方/维普浏览器检索到候选，请确认后导入。"
        )
    }

    private func augmentCandidateWithChineseBrowserFallbacks(
        _ cnkiResult: MetadataResolutionResult,
        seed: MetadataResolutionSeed,
        fallback: Reference?
    ) async -> MetadataResolutionResult {
        guard case .candidate(let cnkiEnvelope) = cnkiResult else {
            return cnkiResult
        }
        guard let browserResult = await resolveChineseBrowserFallback(seed: seed, fallback: fallback) else {
            return cnkiResult
        }

        switch browserResult {
        case .verified:
            resolverTrace("augmentCandidateWithChineseBrowserFallbacks → 浏览器 fallback 自动验证通过，采用 fallback 结果")
            return browserResult
        case .candidate(let browserEnvelope):
            resolverTrace("augmentCandidateWithChineseBrowserFallbacks → 合并 CNKI + 中文浏览器候选")
            return .candidate(
                Self.mergedChineseBrowserCandidateEnvelope(
                    cnkiEnvelope,
                    fallbackEnvelope: browserEnvelope
                )
            )
        case .blocked:
            resolverTrace("augmentCandidateWithChineseBrowserFallbacks → 浏览器 fallback 受阻，保留 CNKI 候选")
            return cnkiResult
        case .seedOnly, .rejected:
            return cnkiResult
        }
    }

    nonisolated private static func mergedChineseBrowserCandidateEnvelopes(
        _ envelopes: [CandidateEnvelope]
    ) -> CandidateEnvelope? {
        guard var merged = envelopes.first else { return nil }
        for envelope in envelopes.dropFirst() {
            merged = mergedChineseBrowserCandidateEnvelope(merged, fallbackEnvelope: envelope)
        }
        return merged
    }

    nonisolated static func mergedChineseBrowserCandidateEnvelope(
        _ primary: CandidateEnvelope,
        fallbackEnvelope: CandidateEnvelope
    ) -> CandidateEnvelope {
        let seen = Set(primary.candidates.map { candidateIdentity($0) })
        let fallbackCandidates = fallbackEnvelope.candidates.filter { !seen.contains(candidateIdentity($0)) }
        let mergedCandidates = (primary.candidates + fallbackCandidates)
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.source.rawValue < rhs.source.rawValue
                }
                return lhs.score > rhs.score
            }

        let sources = Array(Set(mergedCandidates.map(\.source.displayName))).sorted().joined(separator: "、")
        return CandidateEnvelope(
            seed: primary.seed ?? fallbackEnvelope.seed,
            fallbackReference: primary.fallbackReference ?? fallbackEnvelope.fallbackReference,
            currentReference: primary.currentReference ?? fallbackEnvelope.currentReference,
            candidates: mergedCandidates,
            message: "已聚合中文浏览器候选（\(sources)），请确认最匹配的条目。",
            evidence: primary.evidence ?? fallbackEnvelope.evidence
        )
    }

    nonisolated private static func candidateIdentity(_ candidate: MetadataCandidate) -> String {
        [
            MetadataResolution.normalizedComparableText(candidate.title),
            candidate.source.rawValue,
            candidate.detailURL.lowercased(),
        ].joined(separator: "|")
    }
}
