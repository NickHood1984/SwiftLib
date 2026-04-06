import CryptoKit
import Foundation
import GRDB

public enum VerificationStatus: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case legacy
    case seedOnly
    case candidate
    case blocked
    case rejectedAmbiguous
    case verifiedAuto
    case verifiedManual

    public var isLibraryReady: Bool {
        switch self {
        case .verifiedAuto, .verifiedManual:
            return true
        case .legacy, .seedOnly, .candidate, .blocked, .rejectedAmbiguous:
            return false
        }
    }

    public var isPendingQueueVisible: Bool {
        switch self {
        case .seedOnly, .candidate, .blocked, .rejectedAmbiguous:
            return true
        case .legacy, .verifiedAuto, .verifiedManual:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .legacy:
            return "历史条目"
        case .seedOnly:
            return "仅种子"
        case .candidate:
            return "待选候选"
        case .blocked:
            return "抓取受阻"
        case .rejectedAmbiguous:
            return "验证未通过"
        case .verifiedAuto:
            return "自动验证"
        case .verifiedManual:
            return "人工确认"
        }
    }
}

public enum AcceptedRuleID: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case j1DOIExact = "J1_DOI_EXACT"
    case j2SourceRecordKey = "J2_SOURCE_RECORD_KEY"
    case j3CNKINoDOI = "J3_CNKI_NO_DOI"
    case t1ThesisSourceKey = "T1_THESIS_SOURCE_KEY"
    case b1ISBNOrRecordKey = "B1_ISBN_OR_RECORD_KEY"
}

public enum FetchMode: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case identifier
    case detail
    case searchToDetail
    case export
    case translator
    case manual
}

public enum EvidenceOrigin: String, Codable, CaseIterable, Sendable {
    case structuredExport
    case structuredDetail
    case identifierAPI
    case searchResult
    case translator
    case fallbackSeed
    case manual
}

public enum RawArtifactKind: String, Codable, CaseIterable, Sendable {
    case html
    case exportText
    case json
    case text
}

public enum BlockReason: String, Codable, CaseIterable, Sendable {
    case verificationRequired
    case loginRequired
    case timedOut
    case remoteUnavailable
    case unknown
}

public enum RejectReason: String, Codable, CaseIterable, Sendable {
    case ambiguousCandidates
    case insufficientEvidence
    case verifierRuleNotSatisfied
    case unsupportedRoute
}

public struct RawArtifactManifest: Codable, Hashable, Sendable {
    public var kind: RawArtifactKind
    public var sha256: String?
    public var storagePath: String?
    public var contentType: String?
    public var preview: String?

    public init(
        kind: RawArtifactKind,
        sha256: String? = nil,
        storagePath: String? = nil,
        contentType: String? = nil,
        preview: String? = nil
    ) {
        self.kind = kind
        self.sha256 = sha256
        self.storagePath = storagePath
        self.contentType = contentType
        self.preview = preview
    }
}

public struct FieldEvidence: Codable, Hashable, Sendable {
    public var field: String
    public var value: String
    public var origin: EvidenceOrigin
    public var selectorOrPath: String?
    public var rawSnippet: String?
    public var confidence: Double?

    public init(
        field: String,
        value: String,
        origin: EvidenceOrigin,
        selectorOrPath: String? = nil,
        rawSnippet: String? = nil,
        confidence: Double? = nil
    ) {
        self.field = field
        self.value = value
        self.origin = origin
        self.selectorOrPath = selectorOrPath
        self.rawSnippet = rawSnippet
        self.confidence = confidence
    }
}

public struct VerificationHints: Codable, Hashable, Sendable {
    public var hasStructuredTitle: Bool
    public var hasStructuredAuthors: Bool
    public var hasStructuredJournal: Bool
    public var hasStructuredInstitution: Bool
    public var hasStructuredPages: Bool
    public var hasStructuredThesisType: Bool
    public var hasStableRecordKey: Bool
    public var usedStructuredExport: Bool
    public var usedStructuredDetail: Bool
    public var usedIdentifierFetch: Bool
    public var exactIdentifierMatch: Bool
    public var competingCandidateCount: Int

    public init(
        hasStructuredTitle: Bool = false,
        hasStructuredAuthors: Bool = false,
        hasStructuredJournal: Bool = false,
        hasStructuredInstitution: Bool = false,
        hasStructuredPages: Bool = false,
        hasStructuredThesisType: Bool = false,
        hasStableRecordKey: Bool = false,
        usedStructuredExport: Bool = false,
        usedStructuredDetail: Bool = false,
        usedIdentifierFetch: Bool = false,
        exactIdentifierMatch: Bool = false,
        competingCandidateCount: Int = 0
    ) {
        self.hasStructuredTitle = hasStructuredTitle
        self.hasStructuredAuthors = hasStructuredAuthors
        self.hasStructuredJournal = hasStructuredJournal
        self.hasStructuredInstitution = hasStructuredInstitution
        self.hasStructuredPages = hasStructuredPages
        self.hasStructuredThesisType = hasStructuredThesisType
        self.hasStableRecordKey = hasStableRecordKey
        self.usedStructuredExport = usedStructuredExport
        self.usedStructuredDetail = usedStructuredDetail
        self.usedIdentifierFetch = usedIdentifierFetch
        self.exactIdentifierMatch = exactIdentifierMatch
        self.competingCandidateCount = competingCandidateCount
    }
}

public struct EvidenceBundle: Codable, Hashable, Sendable {
    public var source: MetadataSource
    public var recordKey: String?
    public var sourceURL: String?
    public var fetchedAt: Date
    public var fetchMode: FetchMode
    public var rawArtifacts: [RawArtifactManifest]
    public var fieldEvidence: [FieldEvidence]
    public var verificationHints: VerificationHints

    public init(
        source: MetadataSource,
        recordKey: String? = nil,
        sourceURL: String? = nil,
        fetchedAt: Date = Date(),
        fetchMode: FetchMode,
        rawArtifacts: [RawArtifactManifest] = [],
        fieldEvidence: [FieldEvidence] = [],
        verificationHints: VerificationHints = .init()
    ) {
        self.source = source
        self.recordKey = recordKey?.trimmingCharacters(in: .whitespacesAndNewlines).swiftlib_nilIfBlank
        self.sourceURL = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines).swiftlib_nilIfBlank
        self.fetchedAt = fetchedAt
        self.fetchMode = fetchMode
        self.rawArtifacts = rawArtifacts
        self.fieldEvidence = fieldEvidence
        self.verificationHints = verificationHints
    }

    public var bundleHash: String? {
        MetadataVerificationCodec.sha256Hex(for: self)
    }

    public func fieldValue(_ field: String) -> String? {
        fieldEvidence.last { $0.field == field }?.value.swiftlib_nilIfBlank
    }
}

public struct VerifiedEnvelope: Codable, Hashable, Sendable {
    public var reference: Reference
    public var evidence: EvidenceBundle

    public init(reference: Reference, evidence: EvidenceBundle) {
        self.reference = reference
        self.evidence = evidence
    }
}

public struct AuthoritativeMetadataRecord: Codable, Hashable, Sendable {
    public var reference: Reference
    public var evidence: EvidenceBundle

    public init(reference: Reference, evidence: EvidenceBundle) {
        self.reference = reference
        self.evidence = evidence
    }
}

public struct CandidateEnvelope: Codable, Hashable, Sendable {
    public var seed: MetadataResolutionSeed?
    public var fallbackReference: Reference?
    public var currentReference: Reference?
    public var candidates: [MetadataCandidate]
    public var message: String
    public var evidence: EvidenceBundle?

    public init(
        seed: MetadataResolutionSeed?,
        fallbackReference: Reference?,
        currentReference: Reference? = nil,
        candidates: [MetadataCandidate],
        message: String,
        evidence: EvidenceBundle? = nil
    ) {
        self.seed = seed
        self.fallbackReference = fallbackReference
        self.currentReference = currentReference
        self.candidates = candidates
        self.message = message
        self.evidence = evidence
    }
}

public struct BlockedEnvelope: Codable, Hashable, Sendable {
    public var seed: MetadataResolutionSeed?
    public var fallbackReference: Reference?
    public var currentReference: Reference?
    public var candidates: [MetadataCandidate]
    public var reason: BlockReason
    public var message: String
    public var evidence: EvidenceBundle?

    public init(
        seed: MetadataResolutionSeed?,
        fallbackReference: Reference?,
        currentReference: Reference? = nil,
        candidates: [MetadataCandidate] = [],
        reason: BlockReason,
        message: String,
        evidence: EvidenceBundle? = nil
    ) {
        self.seed = seed
        self.fallbackReference = fallbackReference
        self.currentReference = currentReference
        self.candidates = candidates
        self.reason = reason
        self.message = message
        self.evidence = evidence
    }
}

public struct IntakeEnvelope: Codable, Hashable, Sendable {
    public var seed: MetadataResolutionSeed?
    public var fallbackReference: Reference?
    public var currentReference: Reference?
    public var message: String
    public var evidence: EvidenceBundle?

    public init(
        seed: MetadataResolutionSeed?,
        fallbackReference: Reference?,
        currentReference: Reference? = nil,
        message: String,
        evidence: EvidenceBundle? = nil
    ) {
        self.seed = seed
        self.fallbackReference = fallbackReference
        self.currentReference = currentReference
        self.message = message
        self.evidence = evidence
    }
}

public struct RejectedEnvelope: Codable, Hashable, Sendable {
    public var seed: MetadataResolutionSeed?
    public var fallbackReference: Reference?
    public var currentReference: Reference?
    public var reason: RejectReason
    public var message: String
    public var evidence: EvidenceBundle?

    public init(
        seed: MetadataResolutionSeed?,
        fallbackReference: Reference?,
        currentReference: Reference? = nil,
        reason: RejectReason,
        message: String,
        evidence: EvidenceBundle? = nil
    ) {
        self.seed = seed
        self.fallbackReference = fallbackReference
        self.currentReference = currentReference
        self.reason = reason
        self.message = message
        self.evidence = evidence
    }
}

public enum MetadataVerificationDecision: Sendable {
    case verified(VerifiedEnvelope)
    case candidate(CandidateEnvelope)
    case blocked(BlockedEnvelope)
    case rejected(RejectedEnvelope)
}

public enum MetadataVerificationCodec {
    public static func encodeToJSONString<T: Encodable>(_ value: T?) -> String? {
        guard let value else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeFromJSONString<T: Decodable>(_ text: String?, as type: T.Type) -> T? {
        guard let text = text?.swiftlib_nilIfBlank,
              let data = text.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    public static func sha256Hex<T: Encodable>(for value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum MetadataIntakeSourceKind: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case importedPDF
    case manualEntry
    case refresh
    case batchIdentifier
    case candidateSelection
}

public struct MetadataPersistenceOptions: Sendable {
    public var sourceKind: MetadataIntakeSourceKind
    public var originalInput: String?
    public var preferredPDFPath: String?
    public var linkedReferenceId: Int64?
    public var existingIntakeId: Int64?

    public init(
        sourceKind: MetadataIntakeSourceKind,
        originalInput: String? = nil,
        preferredPDFPath: String? = nil,
        linkedReferenceId: Int64? = nil,
        existingIntakeId: Int64? = nil
    ) {
        self.sourceKind = sourceKind
        self.originalInput = originalInput
        self.preferredPDFPath = preferredPDFPath
        self.linkedReferenceId = linkedReferenceId
        self.existingIntakeId = existingIntakeId
    }
}

public enum MetadataPersistenceResult: Sendable {
    case verified(Reference)
    case intake(MetadataIntake)
}

public struct SourceInput: Codable, Hashable, Sendable {
    public var url: String?
    public var identifier: String?
    public var seed: MetadataResolutionSeed?

    public init(url: String? = nil, identifier: String? = nil, seed: MetadataResolutionSeed? = nil) {
        self.url = url
        self.identifier = identifier
        self.seed = seed
    }
}

public struct DetectionResult: Codable, Hashable, Sendable {
    public var source: MetadataSource
    public var isSupported: Bool
    public var canSearch: Bool
    public var canFetchDetail: Bool

    public init(source: MetadataSource, isSupported: Bool, canSearch: Bool, canFetchDetail: Bool) {
        self.source = source
        self.isSupported = isSupported
        self.canSearch = canSearch
        self.canFetchDetail = canFetchDetail
    }
}

public struct RecordLocator: Codable, Hashable, Sendable {
    public var source: MetadataSource
    public var recordKey: String?
    public var detailURL: String?
    public var opaqueLocator: String?

    public init(source: MetadataSource, recordKey: String? = nil, detailURL: String? = nil, opaqueLocator: String? = nil) {
        self.source = source
        self.recordKey = recordKey
        self.detailURL = detailURL
        self.opaqueLocator = opaqueLocator
    }
}

public struct RawRecord: Codable, Hashable, Sendable {
    public var locator: RecordLocator
    public var payload: String
    public var contentType: String?

    public init(locator: RecordLocator, payload: String, contentType: String? = nil) {
        self.locator = locator
        self.payload = payload
        self.contentType = contentType
    }
}

public struct StructuredRecord: Codable, Hashable, Sendable {
    public var locator: RecordLocator
    public var payload: String
    public var contentType: String?

    public init(locator: RecordLocator, payload: String, contentType: String? = nil) {
        self.locator = locator
        self.payload = payload
        self.contentType = contentType
    }
}

public protocol SourceAdapter: Sendable {
    func detect(input: SourceInput) async -> DetectionResult
    func search(seed: MetadataResolutionSeed) async throws -> [MetadataCandidate]
    func fetchDetail(locator: RecordLocator) async throws -> RawRecord
    func fetchStructured(locator: RecordLocator) async throws -> StructuredRecord?
    func normalizeToEvidence(raw: RawRecord?, structured: StructuredRecord?, fallbackReference: Reference?) throws -> EvidenceBundle
    func extractRecordKey(from locator: RecordLocator) -> String?
}
