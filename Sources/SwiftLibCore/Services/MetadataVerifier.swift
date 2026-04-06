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

        if doiExact && titleScore >= 0.92 && (yearExact || firstAuthorExact) {
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .j1DOIExact))
        }

        if recordKeyPresent
            && (evidence.verificationHints.usedStructuredExport || evidence.verificationHints.usedStructuredDetail)
            && titleScore >= 0.90
            && firstAuthorExact
            && yearExact
            && journalExact {
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .j2SourceRecordKey))
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
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .j3CNKINoDOI))
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
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .t1ThesisSourceKey))
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

        if (hasISBN || recordKeyPresent) && titleScore >= 0.90 && publisherExact && yearExact {
            return .verified(verifiedEnvelope(reference, evidence: evidence, rule: .b1ISBNOrRecordKey))
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

    private static func verifiedEnvelope(
        _ reference: Reference,
        evidence: EvidenceBundle,
        rule: AcceptedRuleID
    ) -> VerifiedEnvelope {
        var verified = reference
        verified.verificationStatus = .verifiedAuto
        verified.acceptedByRuleID = rule.rawValue
        verified.recordKey = evidence.recordKey
        verified.verificationSourceURL = evidence.sourceURL
        verified.metadataSource = evidence.source
        verified.evidenceBundleHash = evidence.bundleHash
        verified.verifiedAt = Date()
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
