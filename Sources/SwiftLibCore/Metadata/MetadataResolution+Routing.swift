import Foundation

extension MetadataResolution {
    public static func fallbackReference(from extracted: PDFService.ExtractedMetadata, url: URL) -> Reference {
        let seed = MetadataResolutionSeed.fromImportedPDF(url: url, extracted: extracted)
        return Reference(
            title: extracted.title?.swiftlib_nilIfBlank ?? seed.title ?? cleanPDFSeedFilename(url.deletingPathExtension().lastPathComponent),
            authors: extracted.authors,
            year: extracted.year,
            journal: extracted.journal,
            doi: extracted.doi,
            abstract: extracted.abstract,
            referenceType: extracted.workKindHint.referenceType,
            publisher: extracted.publisher,
            edition: extracted.edition,
            isbn: extracted.isbn,
            issn: extracted.issn,
            language: extracted.language
        )
    }

    public static func workKind(for referenceType: ReferenceType) -> MetadataWorkKind {
        switch referenceType {
        case .journalArticle, .magazineArticle, .newspaperArticle, .preprint:
            return .journalArticle
        case .book, .bookSection:
            return .book
        case .conferencePaper:
            return .conferencePaper
        case .thesis:
            return .thesis
        case .report, .standard:
            return .report
        case .dataset,
             .software,
             .manuscript,
             .interview,
             .presentation,
             .blogPost,
             .forumPost,
             .legalCase,
             .legislation,
             .webpage,
             .patent,
             .other:
            return .unknown
        }
    }

    public static func metadataSource(for urlString: String?, fallback: MetadataSource = .translationServer) -> MetadataSource {
        guard let urlString = urlString?.swiftlib_nilIfBlank,
              let host = URL(string: urlString)?.host?.lowercased() else {
            return fallback
        }
        switch host {
        case let host where host.contains("cnki"):
            return .cnki
        case let host where host.contains("wanfang"):
            return .wanfang
        case let host where host.contains("cqvip") || host.contains("vip"):
            return .vip
        case let host where host.contains("douban"):
            return .douban
        case let host where host.contains("duxiu"):
            return .duxiu
        case let host where host.contains("nlc.cn") || host.contains("wenjin"):
            return .wenjin
        default:
            return fallback
        }
    }

    public static func shouldPreferCNKIForImportedPDF(seed: MetadataResolutionSeed) -> Bool {
        MetadataRoutePlanner.shouldPreferCNKIForImportedPDF(seed: seed)
    }

    public static func shouldAcceptDOIReference(_ reference: Reference, seed: MetadataResolutionSeed) -> Bool {
        guard !reference.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let completeness = completenessScore(for: reference)
        guard completeness >= 0.28 else { return false }

        if !seed.shouldSearchCNKI {
            return completeness >= 0.45
        }

        let titleScore = titleSimilarity(seed.title ?? "", reference.title)
        let institutionalAuthorRatio = institutionalAuthorRatio(for: reference.authors)

        if titleScore >= 0.82 { return true }
        if titleScore >= 0.58 && institutionalAuthorRatio < 0.5 { return true }
        if containsHanCharacters(reference.title) && completeness >= 0.7 && institutionalAuthorRatio < 0.8 { return true }
        return false
    }


    private static func completenessScore(for reference: Reference) -> Double {
        var score = 0.0
        if !reference.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 0.28 }
        if !reference.authors.isEmpty { score += 0.2 }
        if reference.year != nil { score += 0.12 }
        if reference.journal?.swiftlib_nilIfBlank != nil { score += 0.12 }
        if reference.doi?.swiftlib_nilIfBlank != nil { score += 0.1 }
        if reference.abstract?.swiftlib_nilIfBlank != nil { score += 0.08 }
        if reference.pages?.swiftlib_nilIfBlank != nil { score += 0.05 }
        if reference.volume?.swiftlib_nilIfBlank != nil || reference.issue?.swiftlib_nilIfBlank != nil { score += 0.05 }
        return score
    }

}
