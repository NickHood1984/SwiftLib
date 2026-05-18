import Foundation
import Combine
import GRDB

// MARK: - Metadata Persistence
extension AppDatabase {
    public func saveMetadataIntake(_ intake: inout MetadataIntake) throws {
        try dbWriter.write { db in
            intake.updatedAt = Date()
            if intake.createdAt > intake.updatedAt {
                intake.createdAt = intake.updatedAt
            }
            try intake.save(db)
        }
    }

    public func deleteMetadataIntake(id: Int64) throws {
        try dbWriter.write { db in
            _ = try MetadataIntake.deleteOne(db, id: id)
        }
    }

    public func fetchPendingMetadataIntakes() throws -> [MetadataIntake] {
        try dbWriter.read { db in
            try MetadataIntake
                .filter(
                    [VerificationStatus.seedOnly.rawValue,
                     VerificationStatus.candidate.rawValue,
                     VerificationStatus.blocked.rawValue,
                     VerificationStatus.rejectedAmbiguous.rawValue]
                        .contains(MetadataIntake.Columns.verificationStatus)
                )
                .order(MetadataIntake.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    public func observePendingMetadataIntakes() -> AnyPublisher<[MetadataIntake], Error> {
        ValueObservation
            .tracking { db in
                try MetadataIntake
                    .filter(
                        [VerificationStatus.seedOnly.rawValue,
                         VerificationStatus.candidate.rawValue,
                         VerificationStatus.blocked.rawValue,
                         VerificationStatus.rejectedAmbiguous.rawValue]
                            .contains(MetadataIntake.Columns.verificationStatus)
                    )
                    .order(MetadataIntake.Columns.updatedAt.desc)
                    .fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    public func saveMetadataEvidence(_ evidence: inout MetadataEvidence) throws {
        try dbWriter.write { db in
            try evidence.save(db)
        }
    }

    public func persistMetadataResolution(
        _ result: MetadataResolutionResult,
        options: MetadataPersistenceOptions
    ) throws -> MetadataPersistenceResult {
        try dbWriter.write { db in
            switch result {
            case .verified(var envelope):
                if let preferredPDFPath = options.preferredPDFPath?.swiftlib_nilIfBlank,
                   envelope.reference.pdfPath == nil {
                    envelope.reference.pdfPath = preferredPDFPath
                }
                try ensureLibraryReady(envelope.reference)
                try saveResolvedReference(
                    &envelope.reference,
                    linkedReferenceId: options.linkedReferenceId,
                    db: db
                )

                if let existingIntakeId = options.existingIntakeId,
                   var existingIntake = try MetadataIntake.fetchOne(db, id: existingIntakeId) {
                    existingIntake.verificationStatus = envelope.reference.verificationStatus
                    existingIntake.linkedReferenceId = envelope.reference.id
                    existingIntake.currentReferenceJSON = MetadataVerificationCodec.encodeToJSONString(envelope.reference)
                    existingIntake.evidenceBundleHash = envelope.reference.evidenceBundleHash
                    existingIntake.statusMessage = envelope.reference.verificationStatus.displayName
                    existingIntake.updatedAt = Date()
                    try existingIntake.save(db)
                }

                try upsertEvidence(bundle: envelope.evidence, intakeId: options.existingIntakeId, referenceId: envelope.reference.id, db: db)
                return .verified(envelope.reference)

            case .candidate(let envelope):
                var intake = buildMetadataIntake(
                    status: .candidate,
                    message: envelope.message,
                    seed: envelope.seed,
                    fallbackReference: envelope.fallbackReference,
                    currentReference: envelope.currentReference,
                    candidates: envelope.candidates,
                    evidence: envelope.evidence,
                    options: options
                )
                try intake.save(db)
                try upsertEvidence(bundle: envelope.evidence, intakeId: intake.id, referenceId: nil, db: db)
                if let linkedId = options.linkedReferenceId,
                   var ref = try Reference.fetchOne(db, id: linkedId) {
                    ref.verificationStatus = .candidate
                    try ref.save(db)
                }
                return .intake(intake)

            case .blocked(let envelope):
                var intake = buildMetadataIntake(
                    status: .blocked,
                    message: envelope.message,
                    seed: envelope.seed,
                    fallbackReference: envelope.fallbackReference,
                    currentReference: envelope.currentReference,
                    candidates: envelope.candidates,
                    evidence: envelope.evidence,
                    options: options
                )
                try intake.save(db)
                try upsertEvidence(bundle: envelope.evidence, intakeId: intake.id, referenceId: nil, db: db)
                if let linkedId = options.linkedReferenceId,
                   var ref = try Reference.fetchOne(db, id: linkedId) {
                    ref.verificationStatus = .blocked
                    try ref.save(db)
                }
                return .intake(intake)

            case .seedOnly(let envelope):
                var intake = buildMetadataIntake(
                    status: .seedOnly,
                    message: envelope.message,
                    seed: envelope.seed,
                    fallbackReference: envelope.fallbackReference,
                    currentReference: envelope.currentReference,
                    candidates: [],
                    evidence: envelope.evidence,
                    options: options
                )
                try intake.save(db)
                try upsertEvidence(bundle: envelope.evidence, intakeId: intake.id, referenceId: nil, db: db)
                if let linkedId = options.linkedReferenceId,
                   var ref = try Reference.fetchOne(db, id: linkedId) {
                    ref.verificationStatus = .seedOnly
                    try ref.save(db)
                }
                return .intake(intake)

            case .rejected(let envelope):
                var intake = buildMetadataIntake(
                    status: .rejectedAmbiguous,
                    message: envelope.message,
                    seed: envelope.seed,
                    fallbackReference: envelope.fallbackReference,
                    currentReference: envelope.currentReference,
                    candidates: [],
                    evidence: envelope.evidence,
                    options: options
                )
                try intake.save(db)
                try upsertEvidence(bundle: envelope.evidence, intakeId: intake.id, referenceId: nil, db: db)
                if let linkedId = options.linkedReferenceId,
                   var ref = try Reference.fetchOne(db, id: linkedId) {
                    ref.verificationStatus = .rejectedAmbiguous
                    try ref.save(db)
                }
                return .intake(intake)
            }
        }
    }

    public func confirmMetadataIntake(
        _ intake: MetadataIntake,
        reviewedBy: String?
    ) throws -> Reference {
        guard var reference = intake.bestAvailableReference else {
            throw NSError(
                domain: "SwiftLib.MetadataIntake",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "当前待验证条目缺少可确认的元数据快照。"]
            )
        }

        reference = MetadataVerifier.manuallyVerified(reference, reviewedBy: reviewedBy)
        if let pdfPath = intake.pdfPath?.swiftlib_nilIfBlank, reference.pdfPath == nil {
            reference.pdfPath = pdfPath
        }

        try dbWriter.write { db in
            try normalizeForDirectLibrarySave(&reference)
            try ensureLibraryReady(reference)
            try saveResolvedReference(
                &reference,
                linkedReferenceId: intake.linkedReferenceId,
                db: db
            )

            if var storedIntake = try MetadataIntake.fetchOne(db, id: intake.id) {
                storedIntake.verificationStatus = .verifiedManual
                storedIntake.linkedReferenceId = reference.id
                storedIntake.currentReferenceJSON = MetadataVerificationCodec.encodeToJSONString(reference)
                storedIntake.updatedAt = Date()
                storedIntake.statusMessage = "人工确认入库"
                try storedIntake.save(db)
            }
        }

        return reference
    }

    func buildMetadataIntake(
        status: VerificationStatus,
        message: String,
        seed: MetadataResolutionSeed?,
        fallbackReference: Reference?,
        currentReference: Reference?,
        candidates: [MetadataCandidate],
        evidence: EvidenceBundle?,
        options: MetadataPersistenceOptions
    ) -> MetadataIntake {
        let title = currentReference?.title.swiftlib_nilIfBlank
            ?? fallbackReference?.title.swiftlib_nilIfBlank
            ?? seed?.title.swiftlib_nilIfBlank
            ?? options.originalInput?.swiftlib_nilIfBlank
            ?? "待验证元数据"

        return MetadataIntake(
            id: options.existingIntakeId,
            sourceKind: options.sourceKind,
            verificationStatus: status,
            title: title,
            originalInput: options.originalInput,
            sourceURL: currentReference?.verificationSourceURL
                ?? currentReference?.url
                ?? fallbackReference?.url
                ?? seed?.sourceURL,
            pdfPath: options.preferredPDFPath?.swiftlib_nilIfBlank ?? fallbackReference?.pdfPath ?? currentReference?.pdfPath,
            seedJSON: MetadataVerificationCodec.encodeToJSONString(seed),
            fallbackReferenceJSON: MetadataVerificationCodec.encodeToJSONString(fallbackReference),
            currentReferenceJSON: MetadataVerificationCodec.encodeToJSONString(currentReference),
            candidatesJSON: MetadataVerificationCodec.encodeToJSONString(candidates),
            statusMessage: message,
            linkedReferenceId: options.linkedReferenceId,
            evidenceBundleHash: evidence?.bundleHash
        )
    }

    func saveResolvedReference(
        _ reference: inout Reference,
        linkedReferenceId: Int64?,
        db: Database
    ) throws {
        if let linkedReferenceId,
           var linkedReference = try Reference.fetchOne(db, id: linkedReferenceId) {
            linkedReference = mergedReference(existing: linkedReference, incoming: reference)
            try linkedReference.save(db)
            reference = linkedReference
            return
        }

        if reference.id == nil,
           let duplicateId = try findDuplicateReferenceID(for: reference, db: db),
           var existing = try Reference.fetchOne(db, id: duplicateId) {
            existing = mergedReference(existing: existing, incoming: reference)
            try existing.save(db)
            reference = existing
            return
        }

        try reference.save(db)
    }

    func upsertEvidence(
        bundle: EvidenceBundle?,
        intakeId: Int64?,
        referenceId: Int64?,
        db: Database
    ) throws {
        guard let bundle,
              let bundleHash = bundle.bundleHash,
              let payloadJSON = MetadataVerificationCodec.encodeToJSONString(bundle) else {
            return
        }

        if var existing = try MetadataEvidence
            .filter(MetadataEvidence.Columns.bundleHash == bundleHash)
            .fetchOne(db) {
            existing.intakeId = intakeId ?? existing.intakeId
            existing.referenceId = referenceId ?? existing.referenceId
            existing.payloadJSON = payloadJSON
            try existing.save(db)
            return
        }

        var evidence = MetadataEvidence(
            intakeId: intakeId,
            referenceId: referenceId,
            bundleHash: bundleHash,
            source: bundle.source,
            recordKey: bundle.recordKey,
            sourceURL: bundle.sourceURL,
            fetchMode: bundle.fetchMode,
            payloadJSON: payloadJSON
        )
        try evidence.save(db)
    }

}
