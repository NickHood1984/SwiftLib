import Foundation
import GRDB

public enum MetadataSource: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case cnki
    case wanfang
    case vip
    case douban
    case duxiu
    case wenjin
    case translationServer
    // v12: additional API sources
    case crossRef
    case openAlex
    case arXiv
    case bibtex
    case ris
    case semanticScholar
    case pubMed
    // v13: native web metadata extraction (replaces translation-server)
    case webMeta
    case baiduScholar

    public var displayName: String {
        switch self {
        case .cnki:
            return "中国知网"
        case .wanfang:
            return "万方"
        case .vip:
            return "维普"
        case .douban:
            return "豆瓣读书"
        case .duxiu:
            return "读秀"
        case .wenjin:
            return "文津"
        case .translationServer:
            return "Translation Server"
        case .crossRef:
            return "CrossRef"
        case .openAlex:
            return "OpenAlex"
        case .arXiv:
            return "arXiv"
        case .bibtex:
            return "BibTeX"
        case .ris:
            return "RIS"
        case .semanticScholar:
            return "Semantic Scholar"
        case .pubMed:
            return "PubMed"
        case .webMeta:
            return "网页元数据"
        case .baiduScholar:
            return "百度学术"
        }
    }
}

public enum MetadataLanguageHint: String, Codable, Sendable {
    case chinese
    case nonChinese
    case unknown
}

public enum MetadataWorkKind: String, Codable, CaseIterable, Sendable {
    case journalArticle
    case book
    case thesis
    case conferencePaper
    case report
    case unknown

    public var referenceType: ReferenceType {
        switch self {
        case .journalArticle:
            return .journalArticle
        case .book:
            return .book
        case .thesis:
            return .thesis
        case .conferencePaper:
            return .conferencePaper
        case .report:
            return .report
        case .unknown:
            return .other
        }
    }

    public var displayName: String {
        switch self {
        case .journalArticle:
            return "期刊论文"
        case .book:
            return "图书"
        case .thesis:
            return "学位论文"
        case .conferencePaper:
            return "会议论文"
        case .report:
            return "报告"
        case .unknown:
            return "未知"
        }
    }
}

public struct CNKIExportLocator: Hashable, Codable, Sendable {
    public var exportID: String?
    public var dbname: String?
    public var filename: String?

    public init(
        exportID: String? = nil,
        dbname: String? = nil,
        filename: String? = nil
    ) {
        self.exportID = exportID?.swiftlib_nilIfBlank
        self.dbname = dbname?.swiftlib_nilIfBlank
        self.filename = filename?.swiftlib_nilIfBlank
    }

    public var hasUsableExport: Bool {
        exportID?.swiftlib_nilIfBlank != nil
            || (dbname?.swiftlib_nilIfBlank != nil && filename?.swiftlib_nilIfBlank != nil)
    }
}

public struct MetadataCandidate: Identifiable, Hashable, Codable, Sendable {
    public var source: MetadataSource
    public var title: String
    public var authors: [AuthorName]
    public var journal: String?
    public var publisher: String?
    public var year: Int?
    public var detailURL: String
    public var score: Double
    public var snippet: String?
    public var workKind: MetadataWorkKind
    public var referenceType: ReferenceType?
    public var isbn: String?
    public var issn: String?
    public var sourceRecordID: String?
    public var matchedBy: [String]
    public var selectionSessionID: String?
    public var selectionItemID: String?
    public var cnkiExport: CNKIExportLocator?

    public var id: String {
        if let sourceRecordID = sourceRecordID?.swiftlib_nilIfBlank {
            return "\(source.rawValue):\(sourceRecordID)"
        }
        if !detailURL.isEmpty {
            return "\(source.rawValue):\(detailURL)"
        }
        return "\(source.rawValue):\(MetadataResolution.normalizedComparableText(title)):\(year.map(String.init) ?? "")"
    }

    public init(
        source: MetadataSource,
        title: String,
        authors: [AuthorName] = [],
        journal: String? = nil,
        publisher: String? = nil,
        year: Int? = nil,
        detailURL: String = "",
        score: Double,
        snippet: String? = nil,
        workKind: MetadataWorkKind = .unknown,
        referenceType: ReferenceType? = nil,
        isbn: String? = nil,
        issn: String? = nil,
        sourceRecordID: String? = nil,
        matchedBy: [String] = [],
        selectionSessionID: String? = nil,
        selectionItemID: String? = nil,
        cnkiExport: CNKIExportLocator? = nil
    ) {
        self.source = source
        self.title = title
        self.authors = authors
        self.journal = journal
        self.publisher = publisher
        self.year = year
        self.detailURL = detailURL
        self.score = score
        self.snippet = snippet
        self.workKind = workKind
        self.referenceType = referenceType
        self.isbn = isbn?.swiftlib_nilIfBlank
        self.issn = issn?.swiftlib_nilIfBlank
        self.sourceRecordID = sourceRecordID?.swiftlib_nilIfBlank
        self.matchedBy = matchedBy
        self.selectionSessionID = selectionSessionID?.swiftlib_nilIfBlank
        self.selectionItemID = selectionItemID?.swiftlib_nilIfBlank
        self.cnkiExport = cnkiExport
    }
}

public enum MetadataResolutionResult: Sendable {
    case verified(VerifiedEnvelope)
    case candidate(CandidateEnvelope)
    case blocked(BlockedEnvelope)
    case seedOnly(IntakeEnvelope)
    case rejected(RejectedEnvelope)
}
