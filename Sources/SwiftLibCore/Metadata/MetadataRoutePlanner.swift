import Foundation

public enum MetadataRoutePlanner {

    public static func isBookLike(_ seed: MetadataResolutionSeed) -> Bool {
        if seed.workKindHint == .book { return true }
        if seed.workKindHint != .unknown { return false }
        if seed.isbn?.swiftlib_nilIfBlank != nil { return true }
        if seed.doi?.swiftlib_nilIfBlank != nil { return false }
        if seed.journal?.swiftlib_nilIfBlank != nil { return false }
        if seed.issn?.swiftlib_nilIfBlank != nil { return false }
        if seed.publisher?.swiftlib_nilIfBlank != nil { return true }
        if seed.edition?.swiftlib_nilIfBlank != nil { return true }

        let probe = seed.title?.swiftlib_nilIfBlank ?? seed.fileName
        return inferWorkKind(fromFreeTextTitle: probe) == .book
    }

    public static func shouldPreferCNKIForImportedPDF(seed: MetadataResolutionSeed) -> Bool {
        seed.shouldSearchCNKI
            && !isBookLike(seed)
            && seed.doi?.swiftlib_nilIfBlank == nil
    }

    public static func inferWorkKind(fromFreeTextTitle rawText: String) -> MetadataWorkKind {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unknown }

        let lowered = text.lowercased()

        let thesisTokens = ["博士学位论文", "硕士学位论文", "学位论文", "博士论文", "硕士论文"]
        if thesisTokens.contains(where: text.contains) {
            return .thesis
        }

        let reportTokens = ["研究报告", "技术报告", "白皮书", "蓝皮书", "年度报告", "report"]
        if reportTokens.contains(where: lowered.contains) {
            return .report
        }

        let conferenceTokens = [
            "会议", "年会", "论坛", "研讨会", "研讨班", "大会", "学术会议",
            "conference", "symposium", "workshop", "proceedings",
        ]
        if conferenceTokens.contains(where: { text.contains($0) || lowered.contains($0) }) {
            return .conferencePaper
        }

        let bookTokens = ["出版社", "isbn", "第", "版", "丛书", "页数", "装帧", "译者", "作者"]
        let hasBookToken = text.contains("出版社")
            || lowered.contains("isbn")
            || text.contains("丛书")
            || text.contains("装帧")
            || text.contains("译者")
            || text.range(of: #"第\s*\d+\s*版"#, options: .regularExpression) != nil
        if hasBookToken || bookTokens.filter({ text.contains($0) || lowered.contains($0) }).count >= 2 {
            return .book
        }

        let strongScholarlyTokens = [
            "基于", "机制", "模型", "算法", "实验", "实证", "调查", "测定", "优化", "仿真",
            "综述", "进展", "学报", "期刊", "杂志", "会议", "doi", "issn", "pmid", "arxiv",
        ]
        if strongScholarlyTokens.contains(where: { text.contains($0) || lowered.contains($0) }) {
            return .journalArticle
        }

        let mediumScholarlyTokens = ["研究", "分析", "探讨", "比较", "应用", "设计", "实现", "评价", "观察", "影响"]
        let mediumHits = mediumScholarlyTokens.reduce(into: 0) { partial, token in
            if text.contains(token) || lowered.contains(token) {
                partial += 1
            }
        }
        if mediumHits >= 2 {
            return .journalArticle
        }

        if MetadataResolution.containsHanCharacters(text),
           text.count <= 28,
           !text.contains("："),
           !text.contains(":"),
           !text.contains("——") {
            return .book
        }

        return .unknown
    }

    public static func isCNKIEBookURL(_ url: URL?) -> Bool {
        guard let url,
              let host = url.host?.lowercased() else {
            return false
        }

        if host.contains("book.oversea.cnki.net") {
            return true
        }

        let absolute = url.absoluteString.lowercased()
        return absolute.contains("/ccgbweb/book/")
            || absolute.contains("/pubdetail?")
    }

    public static func isExplicitBookMetadataURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        if isCNKIEBookURL(url) { return true }

        let source = MetadataResolution.metadataSource(for: url.absoluteString, fallback: .webMeta)
        return source == .douban || source == .wenjin
    }

    public static func shouldUseChineseJournalBrowserFallback(seed: MetadataResolutionSeed) -> Bool {
        seed.shouldSearchCNKI && !isBookLike(seed)
    }

    public static func shouldUseExplicitCNKIBookFallback(
        urlString: String?,
        verificationSourceURL: String?,
        metadataSource: MetadataSource?
    ) -> Bool {
        let urls = [urlString, verificationSourceURL]
            .compactMap { $0?.swiftlib_nilIfBlank }
            .compactMap(URL.init(string:))
        if urls.contains(where: isCNKIEBookURL) {
            return true
        }

        guard metadataSource == .cnki else { return false }
        return [urlString, verificationSourceURL]
            .compactMap { $0?.lowercased() }
            .contains { value in
                value.contains("/ccgbweb/book/")
                    || value.contains("/chn/pubdetail")
                    || value.contains("/tra/pubdetail")
            }
    }
}
