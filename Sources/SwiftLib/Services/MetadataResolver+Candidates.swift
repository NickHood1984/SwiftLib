import Foundation
import SwiftLibCore

// MARK: - Candidate Resolution & Manual Confirmation

extension MetadataResolver {

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

    nonisolated static func referenceFromCandidate(
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

    nonisolated static func recordKey(for candidate: MetadataCandidate) -> String? {
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
}
