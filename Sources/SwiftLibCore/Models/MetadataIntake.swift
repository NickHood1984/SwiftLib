import Foundation
import GRDB

public struct MetadataIntake: Identifiable, Codable, Hashable, Sendable {
    public static let databaseTableName = "metadataIntake"

    public var id: Int64?
    public var sourceKind: MetadataIntakeSourceKind
    public var verificationStatus: VerificationStatus
    public var title: String
    public var originalInput: String?
    public var sourceURL: String?
    public var pdfPath: String?
    public var seedJSON: String?
    public var fallbackReferenceJSON: String?
    public var currentReferenceJSON: String?
    public var candidatesJSON: String?
    public var statusMessage: String?
    public var linkedReferenceId: Int64?
    public var evidenceBundleHash: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        sourceKind: MetadataIntakeSourceKind,
        verificationStatus: VerificationStatus,
        title: String,
        originalInput: String? = nil,
        sourceURL: String? = nil,
        pdfPath: String? = nil,
        seedJSON: String? = nil,
        fallbackReferenceJSON: String? = nil,
        currentReferenceJSON: String? = nil,
        candidatesJSON: String? = nil,
        statusMessage: String? = nil,
        linkedReferenceId: Int64? = nil,
        evidenceBundleHash: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.verificationStatus = verificationStatus
        self.title = title
        self.originalInput = originalInput?.swiftlib_nilIfBlank
        self.sourceURL = sourceURL?.swiftlib_nilIfBlank
        self.pdfPath = pdfPath?.swiftlib_nilIfBlank
        self.seedJSON = seedJSON?.swiftlib_nilIfBlank
        self.fallbackReferenceJSON = fallbackReferenceJSON?.swiftlib_nilIfBlank
        self.currentReferenceJSON = currentReferenceJSON?.swiftlib_nilIfBlank
        self.candidatesJSON = candidatesJSON?.swiftlib_nilIfBlank
        self.statusMessage = statusMessage?.swiftlib_nilIfBlank
        self.linkedReferenceId = linkedReferenceId
        self.evidenceBundleHash = evidenceBundleHash?.swiftlib_nilIfBlank
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var decodedSeed: MetadataResolutionSeed? {
        MetadataVerificationCodec.decodeFromJSONString(seedJSON, as: MetadataResolutionSeed.self)
    }

    public var decodedFallbackReference: Reference? {
        MetadataVerificationCodec.decodeFromJSONString(fallbackReferenceJSON, as: Reference.self)
    }

    public var decodedCurrentReference: Reference? {
        MetadataVerificationCodec.decodeFromJSONString(currentReferenceJSON, as: Reference.self)
    }

    public var decodedCandidates: [MetadataCandidate] {
        MetadataVerificationCodec.decodeFromJSONString(candidatesJSON, as: [MetadataCandidate].self) ?? []
    }

    public var bestAvailableReference: Reference? {
        decodedCurrentReference ?? decodedFallbackReference
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public enum Columns: String, ColumnExpression {
        case id, sourceKind, verificationStatus, title, originalInput, sourceURL, pdfPath
        case seedJSON, fallbackReferenceJSON, currentReferenceJSON, candidatesJSON
        case statusMessage, linkedReferenceId, evidenceBundleHash, createdAt, updatedAt
    }
}

extension MetadataIntake: FetchableRecord, MutablePersistableRecord {
    public init(row: Row) {
        id = row["id"]
        sourceKind = row["sourceKind"]
        verificationStatus = row["verificationStatus"]
        title = row["title"]
        originalInput = row["originalInput"]
        sourceURL = row["sourceURL"]
        pdfPath = row["pdfPath"]
        seedJSON = row["seedJSON"]
        fallbackReferenceJSON = row["fallbackReferenceJSON"]
        currentReferenceJSON = row["currentReferenceJSON"]
        candidatesJSON = row["candidatesJSON"]
        statusMessage = row["statusMessage"]
        linkedReferenceId = row["linkedReferenceId"]
        evidenceBundleHash = row["evidenceBundleHash"]
        createdAt = row["createdAt"]
        updatedAt = row["updatedAt"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["sourceKind"] = sourceKind
        container["verificationStatus"] = verificationStatus
        container["title"] = title
        container["originalInput"] = originalInput
        container["sourceURL"] = sourceURL
        container["pdfPath"] = pdfPath
        container["seedJSON"] = seedJSON
        container["fallbackReferenceJSON"] = fallbackReferenceJSON
        container["currentReferenceJSON"] = currentReferenceJSON
        container["candidatesJSON"] = candidatesJSON
        container["statusMessage"] = statusMessage
        container["linkedReferenceId"] = linkedReferenceId
        container["evidenceBundleHash"] = evidenceBundleHash
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}

public struct MetadataEvidence: Identifiable, Codable, Hashable, Sendable {
    public static let databaseTableName = "metadataEvidence"

    public var id: Int64?
    public var intakeId: Int64?
    public var referenceId: Int64?
    public var bundleHash: String
    public var source: MetadataSource
    public var recordKey: String?
    public var sourceURL: String?
    public var fetchMode: FetchMode
    public var payloadJSON: String
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        intakeId: Int64? = nil,
        referenceId: Int64? = nil,
        bundleHash: String,
        source: MetadataSource,
        recordKey: String? = nil,
        sourceURL: String? = nil,
        fetchMode: FetchMode,
        payloadJSON: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.intakeId = intakeId
        self.referenceId = referenceId
        self.bundleHash = bundleHash
        self.source = source
        self.recordKey = recordKey?.swiftlib_nilIfBlank
        self.sourceURL = sourceURL?.swiftlib_nilIfBlank
        self.fetchMode = fetchMode
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }

    public var decodedBundle: EvidenceBundle? {
        MetadataVerificationCodec.decodeFromJSONString(payloadJSON, as: EvidenceBundle.self)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public enum Columns: String, ColumnExpression {
        case id, intakeId, referenceId, bundleHash, source, recordKey, sourceURL, fetchMode, payloadJSON, createdAt
    }
}

extension MetadataEvidence: FetchableRecord, MutablePersistableRecord {
    public init(row: Row) {
        id = row["id"]
        intakeId = row["intakeId"]
        referenceId = row["referenceId"]
        bundleHash = row["bundleHash"]
        source = row["source"]
        recordKey = row["recordKey"]
        sourceURL = row["sourceURL"]
        fetchMode = row["fetchMode"]
        payloadJSON = row["payloadJSON"]
        createdAt = row["createdAt"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["intakeId"] = intakeId
        container["referenceId"] = referenceId
        container["bundleHash"] = bundleHash
        container["source"] = source
        container["recordKey"] = recordKey
        container["sourceURL"] = sourceURL
        container["fetchMode"] = fetchMode
        container["payloadJSON"] = payloadJSON
        container["createdAt"] = createdAt
    }
}
