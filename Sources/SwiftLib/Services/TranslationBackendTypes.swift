import Foundation
import SwiftLibCore

// MARK: - Enums

enum TranslationBackendInputType: String, Codable {
    case url
    case identifier
}

enum TranslationBackendRuntimeMode: String, Codable {
    case bundled
    case external
    case development
    case unavailable
}

// MARK: - Input / Connection

struct TranslationBackendInput: Encodable {
    var inputType: TranslationBackendInputType
    var value: String
}

struct TranslationBackendConnection {
    var baseURL: URL
    var token: String
}

// MARK: - Result

enum TranslationBackendResult {
    case resolved(Reference)
    case candidates([MetadataCandidate])
    case unresolved(String)
    case unavailable(String)

    var debugLabel: String {
        switch self {
        case .resolved(let ref):
            return "resolved title=\"\(ref.title)\""
        case .candidates(let list):
            return "candidates count=\(list.count)"
        case .unresolved(let msg):
            return "unresolved message=\"\(msg)\""
        case .unavailable(let msg):
            return "unavailable message=\"\(msg)\""
        }
    }
}

// MARK: - Handshake / Capabilities

struct TranslationBackendHandshake: Codable {
    var port: Int
    var token: String
    var version: String
    var capabilities: TranslationBackendCapabilities
}

struct TranslationBackendCapabilities: Codable {
    var translationServerRevision: String?
    var translatorsCNRevision: String?
    var supportedInputs: [TranslationBackendInputType]
    var supportsRefresh: Bool
    var supportsChineseSearch: Bool?
    var supportsBaiduScholar: Bool?
    var runtimeMode: TranslationBackendRuntimeMode?
    var overlayRevision: String?
    var licensesVersion: String?
}

// MARK: - Maintenance

struct TranslationBackendMaintenanceResult: Codable {
    var ok: Bool
    var message: String
    var translationServerRevision: String?
    var translatorsCNRevision: String?
    var runtimeMode: TranslationBackendRuntimeMode?
    var overlayRevision: String?
    var licensesVersion: String?
    var runtimeRoot: String?
    var updatedAt: String?
}

// MARK: - ZoteroAPIItem

struct ZoteroAPIItem: Codable {
    var itemType: String?
    var title: String?
    var creators: [ZoteroCreator]?
    var date: String?
    var publicationTitle: String?
    var volume: String?
    var issue: String?
    var pages: String?
    // swiftlint:disable identifier_name
    var DOI: String?
    var ISSN: String?
    var ISBN: String?
    // swiftlint:enable identifier_name
    var abstractNote: String?
    var publisher: String?
    var place: String?
    var university: String?
    var url: String?
    var language: String?
    var tags: [ZoteroTag]?

    // Extra fields for extended metadata
    var bookTitle: String?
    var proceedingsTitle: String?
    var thesisType: String?
    var reportType: String?
    var institution: String?
    var edition: String?
    var numberOfPages: String?
    var numPages: String?
    var conferenceName: String?

    // Internal source marker
    // swiftlint:disable:next identifier_name
    var _source: String?

    struct ZoteroCreator: Codable {
        var creatorType: String?
        var name: String?
        var firstName: String?
        var lastName: String?
    }

    struct ZoteroTag: Codable {
        var tag: String?
    }

    func asReference() -> Reference {
        let authors = (creators ?? []).map { creator -> AuthorName in
            if let name = creator.name, !name.isEmpty {
                return AuthorName.parse(name)
            }
            return AuthorName(
                given: creator.firstName ?? "",
                family: creator.lastName ?? ""
            )
        }

        let year: Int? = {
            guard let dateStr = date else { return nil }
            let pattern = #"(19|20)\d{2}"#
            guard let range = dateStr.range(of: pattern, options: .regularExpression) else { return nil }
            return Int(dateStr[range])
        }()

        let refType = mapItemType(itemType)

        let journal: String? = publicationTitle ?? bookTitle ?? proceedingsTitle

        let resolvedPublisher: String? = publisher ?? (refType == .thesis ? university : nil)
        let resolvedInstitution: String? = institution ?? (refType == .thesis ? university : nil)
        let resolvedGenre: String? = thesisType ?? reportType

        return Reference(
            title: title ?? "",
            authors: authors,
            year: year,
            journal: journal,
            volume: volume,
            issue: issue,
            pages: pages,
            doi: DOI,
            url: url,
            abstract: abstractNote,
            referenceType: refType,
            metadataSource: mapSource(_source),
            publisher: resolvedPublisher,
            publisherPlace: place,
            edition: edition,
            isbn: ISBN,
            issn: ISSN,
            genre: resolvedGenre,
            institution: resolvedInstitution,
            numberOfPages: numberOfPages ?? numPages,
            language: language
        )
    }

    private func mapItemType(_ itemType: String?) -> ReferenceType {
        switch itemType {
        case "journalArticle": return .journalArticle
        case "magazineArticle": return .magazineArticle
        case "newspaperArticle": return .newspaperArticle
        case "book": return .book
        case "bookSection": return .bookSection
        case "conferencePaper": return .conferencePaper
        case "thesis": return .thesis
        case "report": return .report
        case "patent": return .patent
        case "webpage": return .webpage
        case "blogPost": return .blogPost
        case "forumPost": return .forumPost
        case "preprint": return .preprint
        case "dataset": return .dataset
        case "software": return .software
        case "manuscript": return .manuscript
        case "presentation": return .presentation
        case "interview": return .interview
        default: return .other
        }
    }

    private func mapSource(_ source: String?) -> MetadataSource? {
        switch source {
        case "baiduScholar", "cnki", "cnki-export-api", "cnki-showexport":
            return .cnki
        case "wanfang": return .wanfang
        case "vip": return .vip
        case "douban": return .douban
        case "duxiu": return .duxiu
        case "wenjin": return .wenjin
        case "translationServer": return .translationServer
        default: return .translationServer
        }
    }
}

// MARK: - TranslationBackendCandidate

struct TranslationBackendCandidate: Codable {
    var id: String?
    var title: String
    var creators: [String]?
    var year: Int?
    var source: String?
    var referenceType: String?
    var publisher: String?
    var containerTitle: String?
    var detailURL: String?
    var matchedBy: [String]?
    var workKind: String?
    var sessionID: String?

    func metadataCandidate() -> MetadataCandidate {
        let authors = (creators ?? []).map { AuthorName.parse($0) }

        let metaSource: MetadataSource = {
            switch source {
            case "cnki": return .cnki
            case "wanfang": return .wanfang
            case "vip": return .vip
            case "douban": return .douban
            case "duxiu": return .duxiu
            case "wenjin": return .wenjin
            default: return .translationServer
            }
        }()

        let metaWorkKind: MetadataWorkKind = {
            switch workKind {
            case "journalArticle": return .journalArticle
            case "book": return .book
            case "thesis": return .thesis
            case "conferencePaper": return .conferencePaper
            case "report": return .report
            default: return .unknown
            }
        }()

        return MetadataCandidate(
            source: metaSource,
            title: title,
            authors: authors,
            journal: containerTitle,
            publisher: publisher,
            year: year,
            detailURL: detailURL ?? "",
            score: 0.5,
            workKind: metaWorkKind,
            matchedBy: matchedBy ?? [],
            selectionSessionID: sessionID,
            selectionItemID: id
        )
    }
}
