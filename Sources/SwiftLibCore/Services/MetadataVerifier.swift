import Foundation

public enum MetadataVerifier {
    public static func verify(
        reference: Reference,
        seed: MetadataResolutionSeed?,
        evidence: EvidenceBundle
    ) -> MetadataVerificationDecision {
        switch reference.referenceType {
        case .thesis:
            return verifyThesis(reference: reference, seed: seed, evidence: evidence)
        case .book, .bookSection:
            return verifyBook(reference: reference, seed: seed, evidence: evidence)
        case .preprint:
            return verifyPreprint(reference: reference, seed: seed, evidence: evidence)
        case .conferencePaper:
            return verifyConference(reference: reference, seed: seed, evidence: evidence)
        case .report:
            return verifyReport(reference: reference, seed: seed, evidence: evidence)
        case .dataset:
            return verifyDataset(reference: reference, seed: seed, evidence: evidence)
        default:
            return verifyJournalLike(reference: reference, seed: seed, evidence: evidence)
        }
    }

    public static func manuallyVerified(
        _ reference: Reference,
        evidence: EvidenceBundle? = nil,
        reviewedBy: String?
    ) -> Reference {
        var manual = reference
        if let evidence = evidence {
            manual.metadataSource = evidence.source
            manual.recordKey = evidence.recordKey?.swiftlib_nilIfBlank ?? manual.recordKey
            manual.verificationSourceURL = evidence.sourceURL?.swiftlib_nilIfBlank ?? manual.verificationSourceURL
            manual.evidenceBundleHash = evidence.bundleHash ?? manual.evidenceBundleHash
        }
        manual.verificationStatus = .verifiedManual
        manual.acceptedByRuleID = nil
        manual.evidenceBundleHash = manual.evidenceBundleHash ?? MetadataVerificationCodec.sha256Hex(for: reference)
        manual.verifiedAt = Date()
        manual.reviewedBy = reviewedBy?.swiftlib_nilIfBlank ?? "manual-review"
        return manual
    }

    private static func verifyJournalLike(
        reference: Reference,
        seed: MetadataResolutionSeed?,
        evidence: EvidenceBundle
    ) -> MetadataVerificationDecision {
        let title = normalized(reference.title)
        guard !title.isEmpty else {
            return .rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: nil,
                    currentReference: reference,
                    reason: .insufficientEvidence,
                    message: "缺少可验证的题名。",
                    evidence: evidence
                )
            )
        }

        let titleScore = MetadataResolution.titleSimilarity(seed?.title ?? "", reference.title)
        let firstAuthorExact = authorsMatch(seed?.firstAuthor, reference.authors.first?.displayName)
        let yearExact = seed?.year != nil && seed?.year == reference.year
        let journalExact = journalMatch(seed?.journal, reference.journal)
        let doiExact = identifierMatch(seed?.doi, reference.doi)
        let recordKeyPresent = evidence.recordKey?.swiftlib_nilIfBlank != nil || evidence.verificationHints.hasStableRecordKey
        let noCompetingCandidate = evidence.verificationHints.competingCandidateCount <= 1

        let firstAuthorCompatible = normalized(seed?.firstAuthor).isEmpty || firstAuthorExact
        let yearCompatible = seed?.year == nil || yearExact
        let journalCompatible = normalized(seed?.journal).isEmpty || journalExact

        // 判断是否为中文文献
        let isChinese = MetadataResolution.containsHanCharacters(reference.title)
            || MetadataResolution.containsHanCharacters(seed?.title ?? "")
            || [.cnki, .wanfang, .vip].contains(evidence.source)

        // 英文文献必须有 DOI 才能通过验证；无 DOI 直接拒绝。
        if !isChinese, reference.doi?.swiftlib_nilIfBlank == nil, seed?.doi?.swiftlib_nilIfBlank == nil {
            return .rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: nil,
                    currentReference: reference,
                    reason: .insufficientEvidence,
                    message: "英文期刊文献缺少 DOI，无法自动验证。请补充 DOI 后重试。",
                    evidence: evidence
                )
            )
        }

        if doiExact && titleScore >= 0.92 && (yearExact || firstAuthorExact) {
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .j1DOIExact, seed: seed))
        }

        if recordKeyPresent
            && (evidence.verificationHints.usedStructuredExport || evidence.verificationHints.usedStructuredDetail)
            && titleScore >= 0.90
            && firstAuthorExact
            && yearExact
            && journalExact {
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .j2SourceRecordKey, seed: seed))
        }

        if [.cnki, .wanfang, .vip].contains(evidence.source)
            && recordKeyPresent
            && evidence.verificationHints.hasStructuredTitle
            && evidence.verificationHints.hasStructuredAuthors
            && noCompetingCandidate
            && titleScore >= 0.92
            && firstAuthorCompatible
            && yearCompatible
            && journalCompatible {
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .j3CNKINoDOI, seed: seed))
        }

        if evidence.verificationHints.competingCandidateCount > 1 {
            return .candidate(
                CandidateEnvelope(
                    seed: seed,
                    fallbackReference: nil,
                    currentReference: reference,
                    candidates: [],
                    message: "存在多个未区分开的候选结果，需人工确认。",
                    evidence: evidence
                )
            )
        }

        return .rejected(
            RejectedEnvelope(
                seed: seed,
                fallbackReference: nil,
                currentReference: reference,
                reason: .verifierRuleNotSatisfied,
                message: "未满足期刊类自动验证规则。",
                evidence: evidence
            )
        )
    }

    private static func verifyThesis(
        reference: Reference,
        seed: MetadataResolutionSeed?,
        evidence: EvidenceBundle
    ) -> MetadataVerificationDecision {
        let recordKeyPresent = evidence.recordKey?.swiftlib_nilIfBlank != nil || evidence.verificationHints.hasStableRecordKey
        let titleScore = MetadataResolution.titleSimilarity(seed?.title ?? "", reference.title)
        let authorExact = authorsMatch(seed?.firstAuthor, reference.authors.first?.displayName)
        let institutionExact = normalized(seed?.publisher ?? "") == normalized(reference.institution ?? "")
            || normalized(seed?.journal ?? "") == normalized(reference.institution ?? "")
            || evidence.verificationHints.hasStructuredInstitution
        let yearExact = seed?.year != nil && seed?.year == reference.year
        let thesisTypePresent = reference.genre?.swiftlib_nilIfBlank != nil || evidence.verificationHints.hasStructuredThesisType

        if recordKeyPresent && titleScore >= 0.90 && authorExact && institutionExact && yearExact && thesisTypePresent {
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .t1ThesisSourceKey, seed: seed))
        }

        return .rejected(
            RejectedEnvelope(
                seed: seed,
                fallbackReference: nil,
                currentReference: reference,
                reason: .verifierRuleNotSatisfied,
                message: "未满足学位论文自动验证规则。",
                evidence: evidence
            )
        )
    }

    private static func verifyBook(
        reference: Reference,
        seed: MetadataResolutionSeed?,
        evidence: EvidenceBundle
    ) -> MetadataVerificationDecision {
        let hasISBN = identifierMatch(seed?.isbn, reference.isbn)
        let recordKeyPresent = evidence.recordKey?.swiftlib_nilIfBlank != nil || evidence.verificationHints.hasStableRecordKey
        let titleScore = MetadataResolution.titleSimilarity(seed?.title ?? "", reference.title)
        let publisherExact = normalized(seed?.publisher ?? "") == normalized(reference.publisher ?? "")
            || evidence.fieldValue("publisher")?.swiftlib_nilIfBlank != nil
        let yearExact = seed?.year != nil && seed?.year == reference.year

        // B1: ISBN or source record-key pins the edition.
        if (hasISBN || recordKeyPresent) && titleScore >= 0.90 && publisherExact && yearExact {
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .b1ISBNOrRecordKey, seed: seed))
        }

        // B2: Older books (especially pre-ISBN-era Chinese titles) come back from
        // Douban / 文津 without an ISBN in extra_attrs. If the trusted book source
        // agrees on title + first author + year + publisher, that's strong enough
        // to auto-verify without requiring a record key.
        //
        // Safety clamps (to prevent a loose string match from auto-promoting bad
        // data):
        //   * source must be a trusted book database
        //   * seed MUST have both a publisher AND a first-author (i.e. we're
        //     actually cross-checking 4 fields, not 2)
        //   * title similarity ≥ 0.90 (bigram Jaccard, whitespace/width normalized)
        let trustedBookSources: Set<MetadataSource> = [.douban, .wenjin, .duxiu]
        let authorExact = authorsMatch(seed?.firstAuthor, reference.authors.first?.displayName)
        let seedPublisher = normalized(seed?.publisher ?? "")
        let refPublisher = normalized(reference.publisher ?? "")
        let publisherStrict = !seedPublisher.isEmpty && seedPublisher == refPublisher
        let seedHasFirstAuthor = !normalized(seed?.firstAuthor).isEmpty

        if trustedBookSources.contains(evidence.source)
            && titleScore >= 0.90
            && authorExact
            && yearExact
            && publisherStrict
            && seedHasFirstAuthor {
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .b2BookTitleConsensus, seed: seed))
        }

        return .rejected(
            RejectedEnvelope(
                seed: seed,
                fallbackReference: nil,
                currentReference: reference,
                reason: .verifierRuleNotSatisfied,
                message: "未满足图书类自动验证规则。",
                evidence: evidence
            )
        )
    }

    // MARK: - P1 Preprint (arXiv)

    private static func verifyPreprint(
        reference: Reference,
        seed: MetadataResolutionSeed?,
        evidence: EvidenceBundle
    ) -> MetadataVerificationDecision {
        let titleScore = MetadataResolution.titleSimilarity(seed?.title ?? "", reference.title)
        let authorExact = authorsMatch(seed?.firstAuthor, reference.authors.first?.displayName)
        let yearExact = seed?.year != nil && seed?.year == reference.year
        let hasArxivId = reference.doi?.lowercased().contains("arxiv") == true
            || reference.url?.lowercased().contains("arxiv.org") == true
            || evidence.source == .arXiv

        if hasArxivId && titleScore >= 0.90 && authorExact && yearExact {
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .p1PreprintArxiv, seed: seed))
        }

        // Fall through to journal-like rules (preprints can also match J1/J2)
        return verifyJournalLike(reference: reference, seed: seed, evidence: evidence)
    }

    // MARK: - C1 Conference Paper

    private static func verifyConference(
        reference: Reference,
        seed: MetadataResolutionSeed?,
        evidence: EvidenceBundle
    ) -> MetadataVerificationDecision {
        let recordKeyPresent = evidence.recordKey?.swiftlib_nilIfBlank != nil || evidence.verificationHints.hasStableRecordKey
        let titleScore = MetadataResolution.titleSimilarity(seed?.title ?? "", reference.title)
        let authorExact = authorsMatch(seed?.firstAuthor, reference.authors.first?.displayName)
        let yearExact = seed?.year != nil && seed?.year == reference.year
        let hasEventTitle = reference.eventTitle?.swiftlib_nilIfBlank != nil
            || reference.collectionTitle?.swiftlib_nilIfBlank != nil

        if recordKeyPresent && titleScore >= 0.90 && authorExact && yearExact && hasEventTitle {
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .c1ConferenceRecordKey, seed: seed))
        }

        // Fall through to journal-like rules (many conference papers also match DOI rules)
        return verifyJournalLike(reference: reference, seed: seed, evidence: evidence)
    }

    // MARK: - R1 Report

    private static func verifyReport(
        reference: Reference,
        seed: MetadataResolutionSeed?,
        evidence: EvidenceBundle
    ) -> MetadataVerificationDecision {
        let recordKeyPresent = evidence.recordKey?.swiftlib_nilIfBlank != nil || evidence.verificationHints.hasStableRecordKey
        let titleScore = MetadataResolution.titleSimilarity(seed?.title ?? "", reference.title)
        let authorExact = authorsMatch(seed?.firstAuthor, reference.authors.first?.displayName)
        let yearExact = seed?.year != nil && seed?.year == reference.year
        let hasInstitution = reference.institution?.swiftlib_nilIfBlank != nil
            || reference.publisher?.swiftlib_nilIfBlank != nil

        if recordKeyPresent && titleScore >= 0.90 && authorExact && yearExact && hasInstitution {
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .r1ReportRecordKey, seed: seed))
        }

        return verifyJournalLike(reference: reference, seed: seed, evidence: evidence)
    }

    // MARK: - D1 Dataset

    private static func verifyDataset(
        reference: Reference,
        seed: MetadataResolutionSeed?,
        evidence: EvidenceBundle
    ) -> MetadataVerificationDecision {
        let isChinese = MetadataResolution.containsHanCharacters(reference.title)
            || MetadataResolution.containsHanCharacters(seed?.title ?? "")
            || [.cnki, .wanfang, .vip].contains(evidence.source)

        // 英文 Dataset 也必须有 DOI
        if !isChinese, reference.doi?.swiftlib_nilIfBlank == nil, seed?.doi?.swiftlib_nilIfBlank == nil {
            return .rejected(
                RejectedEnvelope(
                    seed: seed,
                    fallbackReference: nil,
                    currentReference: reference,
                    reason: .insufficientEvidence,
                    message: "英文 Dataset 缺少 DOI，无法自动验证。",
                    evidence: evidence
                )
            )
        }

        let doiExact = identifierMatch(seed?.doi, reference.doi)
        let titleScore = MetadataResolution.titleSimilarity(seed?.title ?? "", reference.title)
        let yearExact = seed?.year != nil && seed?.year == reference.year

        if doiExact && titleScore >= 0.88 && yearExact {
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .d1DatasetDOI, seed: seed))
        }

        return verifyJournalLike(reference: reference, seed: seed, evidence: evidence)
    }

    // MARK: - Confidence Score

    /// Calculate a 0–1 confidence score based on evidence quality and match strength.
    public static func calculateConfidenceScore(
        reference: Reference,
        seed: MetadataResolutionSeed?,
        evidence: EvidenceBundle
    ) -> Double {
        var score = 0.0
        let titleScore = MetadataResolution.titleSimilarity(seed?.title ?? "", reference.title)

        // Base: title similarity (up to 0.40)
        score += min(titleScore, 1.0) * 0.40

        // Identifier match (0.25)
        if identifierMatch(seed?.doi, reference.doi) { score += 0.25 }
        else if identifierMatch(seed?.isbn, reference.isbn) { score += 0.20 }

        // Author match (0.15)
        if authorsMatch(seed?.firstAuthor, reference.authors.first?.displayName) { score += 0.15 }

        // Year match (0.10)
        if seed?.year != nil && seed?.year == reference.year { score += 0.10 }

        // Enrichment bonus (up to 0.10)
        let hints = evidence.verificationHints
        var enrichBonus = 0.0
        if hints.hasKeywords { enrichBonus += 0.025 }
        if hints.hasTopics { enrichBonus += 0.025 }
        if hints.hasOaStatus { enrichBonus += 0.025 }
        if hints.hasFundingInfo { enrichBonus += 0.025 }
        score += enrichBonus

        return min(score, 1.0)
    }

    private static func verifiedEnvelope(
        _ reference: Reference,
        evidence: EvidenceBundle,
        rule: AcceptedRuleID,
        seed: MetadataResolutionSeed? = nil
    ) -> VerifiedEnvelope {
        var verified = reference
        verified.verificationStatus = .verifiedAuto
        verified.acceptedByRuleID = rule.rawValue
        verified.recordKey = evidence.recordKey
        verified.verificationSourceURL = evidence.sourceURL
        verified.metadataSource = evidence.source
        verified.evidenceBundleHash = evidence.bundleHash
        verified.verifiedAt = Date()
        verified.confidenceScore = calculateConfidenceScore(reference: reference, seed: seed, evidence: evidence)
        return VerifiedEnvelope(reference: verified, evidence: evidence)
    }

    private static func authorsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }

    private static func identifierMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }

    private static func journalMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = normalized(MetadataResolution.normalizeJournalName(lhs) ?? lhs)
        let right = normalized(MetadataResolution.normalizeJournalName(rhs) ?? rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }

    private static func normalized(_ value: String?) -> String {
        MetadataResolution.normalizedComparableText(value ?? "")
    }
}
