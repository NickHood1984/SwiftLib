import Foundation

/// Unified import service that routes parsed references through the verification
/// pipeline before persisting. Provides backward-compatible `--skip-verify` mode.
public enum ImportIntakeService {

    /// Result of a batch import operation.
    public struct ImportResult: Codable, Sendable {
        public var imported: Int
        public var verified: Int
        public var candidates: Int
        public var rejected: Int
        public var skipped: Int
        public var errors: [String]

        public init(imported: Int = 0, verified: Int = 0, candidates: Int = 0,
                    rejected: Int = 0, skipped: Int = 0, errors: [String] = []) {
            self.imported = imported
            self.verified = verified
            self.candidates = candidates
            self.rejected = rejected
            self.skipped = skipped
            self.errors = errors
        }
    }

    /// Import references parsed from BibTeX/RIS with optional verification.
    ///
    /// - Parameters:
    ///   - references: Parsed references from BibTeX/RIS importer
    ///   - collectionId: Optional collection to assign
    ///   - skipVerify: If true, import directly without verification (legacy behavior)
    ///   - enrichWithOpenAlex: If true, attempt OpenAlex enrichment for DOI-bearing items
    ///   - easyScholarSecretKey: If non-empty, attempt easyScholar journal-rank enrichment
    /// - Returns: Summary of the import operation
    public static func batchImport(
        references: [Reference],
        collectionId: Int64? = nil,
        skipVerify: Bool = false,
        enrichWithOpenAlex: Bool = true,
        easyScholarSecretKey: String = "",
        database: AppDatabase = .shared,
        sourceKind: MetadataIntakeSourceKind = .importFile
    ) async throws -> ImportResult {
        var result = ImportResult()

        var refsToImport: [Reference] = []

        for var ref in references {
            if let cid = collectionId {
                ref.collectionId = cid
            }

        if skipVerify {
                // Legacy path: import directly without verification.
                // Explicitly mark as .legacy so LibraryHealth can surface
                // these records and let the user trigger re-verification.
                var legacyRef = ref
                if legacyRef.verificationStatus == .verifiedAuto
                    || legacyRef.verificationStatus == .verifiedManual {
                    // Preserve existing verified status from the source file
                    // (BibTeX/RIS may carry their own provenance signals).
                } else {
                    legacyRef.verificationStatus = .legacy
                }
                refsToImport.append(legacyRef)
                continue
            }

            // Build seed from parsed reference for verification
            let seed = MetadataResolutionSeed(
                fileName: ref.title,
                title: ref.title,
                firstAuthor: ref.authors.first?.displayName,
                year: ref.year,
                doi: ref.doi,
                journal: ref.journal,
                isbn: ref.isbn
            )

            // Attempt OpenAlex enrichment if DOI available
            if enrichWithOpenAlex, let doi = ref.doi, !doi.isEmpty {
                if let enrichment = await MetadataFetcher.enrichWithOpenAlex(doi: doi) {
                    ref = MetadataResolution.applyEnrichment(enrichment, to: ref)
                }
            }

            // easyScholar journal-rank enrichment
            if !easyScholarSecretKey.isEmpty, let journal = ref.journal, !journal.isEmpty {
                let rankResponse = await MetadataFetcher.enrichWithEasyScholar(journal: journal, secretKey: easyScholarSecretKey)
                ref = MetadataResolution.applyEasyScholarEnrichment(rankResponse, to: ref)
            }

            // Build evidence from parsed data
            let evidence = buildImportEvidence(for: ref, seed: seed)

            // Run through verifier
            let decision = MetadataVerifier.verify(reference: ref, seed: seed, evidence: evidence)

            let resolution = resolutionResult(
                from: decision,
                originalReference: ref,
                collectionId: collectionId
            )
            let originalInput = ref.doi?.swiftlib_nilIfBlank
                ?? ref.pmid?.swiftlib_nilIfBlank
                ?? ref.isbn?.swiftlib_nilIfBlank
                ?? ref.title.swiftlib_nilIfBlank

            do {
                let persisted = try database.persistMetadataResolution(
                    resolution,
                    options: MetadataPersistenceOptions(
                        sourceKind: sourceKind,
                        originalInput: originalInput,
                        preferredPDFPath: ref.pdfPath
                    )
                )

                switch decision {
                case .verified:
                    result.verified += 1
                case .candidate:
                    result.candidates += 1
                case .rejected:
                    result.rejected += 1
                case .blocked:
                    result.skipped += 1
                }

                switch persisted {
                case .verified:
                    result.imported += 1
                case .intake:
                    break
                }
            } catch {
                result.errors.append(error.localizedDescription)
            }
        }

        if !refsToImport.isEmpty {
            do {
                let batchResult = try database.batchImportReferences(refsToImport)
                result.imported += batchResult.total
            } catch {
                result.errors.append(error.localizedDescription)
            }
        }

        return result
    }

    /// Build an evidence bundle for a parsed/imported reference.
    private static func buildImportEvidence(for ref: Reference, seed: MetadataResolutionSeed?) -> EvidenceBundle {
        let source: MetadataSource = ref.metadataSource ?? .bibtex
        let hasStructuredTitle = !ref.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasStructuredAuthors = !ref.authors.isEmpty
        let hasStructuredJournal = ref.journal?.swiftlib_nilIfBlank != nil
        let hasIdentifier = ref.doi?.swiftlib_nilIfBlank != nil
            || ref.isbn?.swiftlib_nilIfBlank != nil
            || ref.pmid?.swiftlib_nilIfBlank != nil

        return EvidenceBundle(
            source: source,
            recordKey: ref.doi ?? ref.isbn,
            fetchedAt: Date(),
            fetchMode: .structured,
            verificationHints: VerificationHints(
                hasStructuredTitle: hasStructuredTitle,
                hasStructuredAuthors: hasStructuredAuthors,
                hasStructuredJournal: hasStructuredJournal,
                usedIdentifierFetch: hasIdentifier,
                exactIdentifierMatch: hasIdentifier
            )
        )
    }

    private static func resolutionResult(
        from decision: MetadataVerificationDecision,
        originalReference: Reference,
        collectionId: Int64?
    ) -> MetadataResolutionResult {
        switch decision {
        case .verified(var envelope):
            if envelope.reference.collectionId == nil {
                envelope.reference.collectionId = collectionId
            }
            return .verified(envelope)

        case .candidate(var envelope):
            envelope.currentReference = withCollectionId(envelope.currentReference ?? originalReference, collectionId: collectionId)
            envelope.fallbackReference = withCollectionId(envelope.fallbackReference ?? originalReference, collectionId: collectionId)
            return .candidate(envelope)

        case .blocked(var envelope):
            envelope.currentReference = withCollectionId(envelope.currentReference ?? originalReference, collectionId: collectionId)
            envelope.fallbackReference = withCollectionId(envelope.fallbackReference ?? originalReference, collectionId: collectionId)
            return .blocked(envelope)

        case .rejected(var envelope):
            envelope.currentReference = withCollectionId(envelope.currentReference ?? originalReference, collectionId: collectionId)
            envelope.fallbackReference = withCollectionId(envelope.fallbackReference ?? originalReference, collectionId: collectionId)
            return .rejected(envelope)
        }
    }

    private static func withCollectionId(_ reference: Reference, collectionId: Int64?) -> Reference {
        guard let collectionId else { return reference }
        var reference = reference
        if reference.collectionId == nil {
            reference.collectionId = collectionId
        }
        return reference
    }
}
