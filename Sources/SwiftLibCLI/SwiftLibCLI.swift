import ArgumentParser
import Foundation
import SwiftLibCore

@main
struct SwiftLibCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftlib-cli",
        abstract: "swiftlib-cli — 在命令行管理文献库",
        version: "1.2.1",
        subcommands: [
            Search.self,
            List.self,
            Get.self,
            Add.self,
            Update.self,
            Delete.self,
            Move.self,
            Cite.self,
            Import.self,
            Collections.self,
            Tags.self,
            Annotations.self,
            Styles.self,
            Export.self,
            TagDOCX.self,
            CNKIDebug.self,
        ]
    )
}

// MARK: - JSON Output Helpers

let jsonEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    return e
}()

func printJSON<T: Encodable>(_ value: T) {
    if let data = try? jsonEncoder.encode(value), let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

func printJSONError(_ message: String) {
    let obj: [String: String] = ["error": message]
    if let data = try? jsonEncoder.encode(obj), let str = String(data: data, encoding: .utf8) {
        FileHandle.standardError.write(Data((str + "\n").utf8))
    }
}

// MARK: - BibTeX Helpers

/// Escape special BibTeX characters in a field value.
private func escapeBibTeX(_ value: String) -> String {
    var s = value
    s = s.replacingOccurrences(of: "\\", with: "\\textbackslash{}")
    s = s.replacingOccurrences(of: "{", with: "\\{")
    s = s.replacingOccurrences(of: "}", with: "\\}")
    s = s.replacingOccurrences(of: "&", with: "\\&")
    s = s.replacingOccurrences(of: "%", with: "\\%")
    s = s.replacingOccurrences(of: "#", with: "\\#")
    s = s.replacingOccurrences(of: "_", with: "\\_")
    s = s.replacingOccurrences(of: "~", with: "\\textasciitilde{}")
    s = s.replacingOccurrences(of: "^", with: "\\textasciicircum{}")
    return s
}

/// Generate a unique BibTeX citation key, appending a/b/c suffix for duplicates.
private func uniqueBibTeXKeys(for refs: [Reference]) -> [String] {
    var counts: [String: Int] = [:]
    var keys: [String] = []
    for ref in refs {
        let base = "\(ref.authors.first?.family ?? "unknown")\(ref.year ?? 0)"
        let count = counts[base, default: 0]
        counts[base] = count + 1
        if count == 0 {
            keys.append(base)
        } else {
            // a=1, b=2, ...
            let suffix = String(UnicodeScalar(UInt8(96 + count)))
            keys.append("\(base)\(suffix)")
        }
    }
    // If any base key had duplicates, retroactively suffix the first occurrence
    var baseSeen: [String: Int] = [:]
    for (i, ref) in refs.enumerated() {
        let base = "\(ref.authors.first?.family ?? "unknown")\(ref.year ?? 0)"
        if (counts[base] ?? 0) > 1 {
            if baseSeen[base] == nil {
                keys[i] = "\(base)a"
                baseSeen[base] = 1
            }
        }
    }
    return keys
}

// MARK: - Reference JSON DTO

struct ReferenceDTO: Encodable {
    let id: Int64?
    let title: String
    let authors: String
    let year: Int?
    let journal: String?
    let volume: String?
    let issue: String?
    let pages: String?
    let doi: String?
    let url: String?
    let abstract: String?
    let referenceType: String
    let collectionId: Int64?
    let dateAdded: Date
    let dateModified: Date
    let pdfPath: String?
    let notes: String?
    let isbn: String?
    let issn: String?
    let publisher: String?
    let language: String?
    let edition: String?

    init(from ref: Reference) {
        self.id = ref.id
        self.title = ref.title
        self.authors = ref.authors.displayString
        self.year = ref.year
        self.journal = ref.journal
        self.volume = ref.volume
        self.issue = ref.issue
        self.pages = ref.pages
        self.doi = ref.doi
        self.url = ref.url
        self.abstract = ref.abstract
        self.referenceType = ref.referenceType.rawValue
        self.collectionId = ref.collectionId
        self.dateAdded = ref.dateAdded
        self.dateModified = ref.dateModified
        self.pdfPath = ref.pdfPath
        self.notes = ref.notes
        self.isbn = ref.isbn
        self.issn = ref.issn
        self.publisher = ref.publisher
        self.language = ref.language
        self.edition = ref.edition
    }
}

struct CitationBibliographyOutput: Encodable {
    let style: String
    let entries: [String]
}

struct CitationDocxCCOutput: Encodable {
    let tag: String
    let text: String
    let style: String
    let isShortTag: Bool?
    let fallbackPayload: String?
}

struct CitationTextOutput: Encodable {
    let style: String
    let inline: String
    let bibliography: [String]
}

struct CNKIDebugOutput: Encodable {
    let seedTitle: String
    let candidateTitle: String
    let titleSimilarity: Double
    let score: Double?
    let threshold: Double
    let accepted: Bool
    let authors: [String]
    let journal: String?
    let year: Int?
    let firstAuthorMatched: Bool
    let journalMatched: Bool
}

// MARK: - Subcommands

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "全文搜索文献")

    @Argument(help: "搜索关键词")
    var query: String

    @Option(name: .shortAndLong, help: "最多返回条数")
    var limit: Int = 20

    func run() throws {
        let refs = try AppDatabase.shared.searchReferences(query: query, limit: limit)
        printJSON(refs.map(ReferenceDTO.init))
    }
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "列出所有文献")

    @Option(name: .shortAndLong, help: "最多返回条数（0 = 全部）")
    var limit: Int = 0

    @Option(name: .long, help: "跳过前 N 条（用于分页）")
    var offset: Int = 0

    @Option(name: .long, help: "按分组 ID 筛选")
    var collection: Int64?

    @Option(name: .long, help: "按标签 ID 筛选")
    var tag: Int64?

    @Option(name: .long, help: "按作者姓名筛选（模糊匹配）")
    var author: String?

    @Option(name: .long, help: "按年份筛选（起始年）")
    var yearFrom: Int?

    @Option(name: .long, help: "按年份筛选（截止年）")
    var yearTo: Int?

    @Option(name: .long, help: "按期刊名称筛选（模糊匹配）")
    var journal: String?

    @Option(name: .customLong("type"), help: "按文献类型筛选（如 'Journal Article'）")
    var referenceType: String?

    @Flag(name: .customLong("has-pdf"), help: "只显示有 PDF 附件的文献")
    var hasPdf = false

    @Option(name: .long, help: "在标题、摘要、备注中关键词搜索")
    var keyword: String?

    func run() throws {
        let hasAdvancedFilter = author != nil || yearFrom != nil || yearTo != nil
            || journal != nil || referenceType != nil || hasPdf || keyword != nil
        var refs: [Reference]
        if hasAdvancedFilter {
            let scope: ReferenceScope = collection.map { .collection($0) }
                ?? tag.map { .tag($0) } ?? .all
            var filter = ReferenceFilter()
            if let a = author { filter.author = a }
            if let yf = yearFrom { filter.yearFrom = yf }
            if let yt = yearTo { filter.yearTo = yt }
            if let j = journal { filter.journal = j }
            if let k = keyword { filter.keyword = k }
            if hasPdf { filter.hasPDF = true }
            if let rt = referenceType {
                guard let type = ReferenceType(rawValue: rt) else {
                    let valid = ReferenceType.allCases.map(\.rawValue).joined(separator: ", ")
                    printJSONError("Unknown reference type '\(rt)'. Valid: \(valid)")
                    throw ExitCode.failure
                }
                filter.referenceType = type
            }
            refs = try AppDatabase.shared.fetchReferences(scope: scope, filter: filter, limit: limit, offset: offset)
        } else if let cid = collection {
            refs = try AppDatabase.shared.fetchReferences(collectionId: cid)
        } else if let tid = tag {
            refs = try AppDatabase.shared.fetchReferences(tagId: tid)
        } else {
            refs = try AppDatabase.shared.fetchAllReferences(limit: limit, offset: offset)
        }
        printJSON(refs.map(ReferenceDTO.init))
    }
}

struct Get: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "按 ID 获取文献详情")

    @Argument(help: "文献 ID")
    var id: Int64

    func run() throws {
        let refs = try AppDatabase.shared.fetchReferences(ids: [id])
        guard let ref = refs.first else {
            printJSONError("Reference \(id) not found")
            throw ExitCode.failure
        }
        printJSON(ReferenceDTO(from: ref))
    }
}

struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "通过 DOI、PMID、arXiv 编号或 BibTeX 添加文献")

    @Option(name: .long, help: "DOI、PMID 或 arXiv 编号")
    var identifier: String?

    @Option(name: .long, help: "BibTeX 字符串")
    var bibtex: String?

    @Option(name: .long, help: "标题（手动录入时使用）")
    var title: String?

    @Option(name: .long, help: "添加到指定分组 ID")
    var collection: Int64?

    func run() async throws {
        if let id = identifier {
            var ref = try await MetadataFetcher.fetch(from: id)
            ref.collectionId = collection
            ref = MetadataVerifier.manuallyVerified(ref, reviewedBy: "cli-identifier")
            try AppDatabase.shared.saveReference(&ref)
            printJSON(ReferenceDTO(from: ref))
        } else if let bib = bibtex {
            let refs = BibTeXImporter.parse(bib)
            guard !refs.isEmpty else {
                printJSONError("No valid BibTeX entries found")
                throw ExitCode.failure
            }
            var imported: [ReferenceDTO] = []
            for var ref in refs {
                ref.collectionId = collection
                try AppDatabase.shared.saveReference(&ref)
                imported.append(ReferenceDTO(from: ref))
            }
            printJSON(imported)
        } else if let t = title {
            var ref = Reference(title: t)
            ref.collectionId = collection
            try AppDatabase.shared.saveReference(&ref)
            printJSON(ReferenceDTO(from: ref))
        } else {
            printJSONError("Provide --identifier, --bibtex, or --title")
            throw ExitCode.failure
        }
    }
}

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "修改已有文献的字段")

    @Argument(help: "文献 ID")
    var id: Int64

    @Option(name: .long, help: "标题")
    var title: String?

    @Option(name: .long, help: "出版年份")
    var year: Int?

    @Option(name: .long, help: "作者（分号分隔，格式：姓, 名; 姓, 名）")
    var authors: String?

    @Option(name: .customLong("type"), help: "文献类型（如 'Journal Article'、'Book'）")
    var referenceType: String?

    @Option(name: .long, help: "期刊名称")
    var journal: String?

    @Option(name: .long, help: "卷号")
    var volume: String?

    @Option(name: .long, help: "期号")
    var issue: String?

    @Option(name: .long, help: "页码（如 '100-110'）")
    var pages: String?

    @Option(name: .long, help: "DOI")
    var doi: String?

    @Option(name: .long, help: "URL")
    var url: String?

    @Option(name: .long, help: "摘要")
    var abstract: String?

    @Option(name: .long, help: "备注")
    var notes: String?

    @Option(name: .long, help: "出版社")
    var publisher: String?

    @Option(name: .long, help: "ISBN")
    var isbn: String?

    @Option(name: .long, help: "ISSN")
    var issn: String?

    @Option(name: .long, help: "语言")
    var language: String?

    @Option(name: .long, help: "版次")
    var edition: String?

    @Option(name: .long, help: "移动到指定分组 ID")
    var collection: Int64?

    @Option(name: .customLong("clear-field"), help: "将某个字段设为空（可重复使用，如 --clear-field doi）")
    var clearFields: [String] = []

    func run() throws {
        let refs = try AppDatabase.shared.fetchReferences(ids: [id])
        guard var ref = refs.first else {
            printJSONError("Reference \(id) not found")
            throw ExitCode.failure
        }
        if let t = title { ref.title = t }
        if let y = year { ref.year = y }
        if let a = authors { ref.authors = AuthorName.parseList(a) }
        if let rt = referenceType {
            guard let type = ReferenceType(rawValue: rt) else {
                let valid = ReferenceType.allCases.map(\.rawValue).joined(separator: ", ")
                printJSONError("Unknown reference type '\(rt)'. Valid: \(valid)")
                throw ExitCode.failure
            }
            ref.referenceType = type
        }
        if let j = journal { ref.journal = j }
        if let v = volume { ref.volume = v }
        if let i = issue { ref.issue = i }
        if let p = pages { ref.pages = p }
        if let d = doi { ref.doi = d }
        if let u = url { ref.url = u }
        if let ab = abstract { ref.abstract = ab }
        if let n = notes { ref.notes = n }
        if let pub = publisher { ref.publisher = pub }
        if let i = isbn { ref.isbn = i }
        if let i = issn { ref.issn = i }
        if let l = language { ref.language = l }
        if let e = edition { ref.edition = e }
        if let cid = collection { ref.collectionId = cid }
        for field in clearFields {
            switch field.lowercased() {
            case "year": ref.year = nil
            case "journal": ref.journal = nil
            case "volume": ref.volume = nil
            case "issue": ref.issue = nil
            case "pages": ref.pages = nil
            case "doi": ref.doi = nil
            case "url": ref.url = nil
            case "abstract": ref.abstract = nil
            case "notes": ref.notes = nil
            case "publisher": ref.publisher = nil
            case "isbn": ref.isbn = nil
            case "issn": ref.issn = nil
            case "language": ref.language = nil
            case "edition": ref.edition = nil
            case "collection": ref.collectionId = nil
            default:
                printJSONError("Unknown field '\(field)'. Valid: year, journal, volume, issue, pages, doi, url, abstract, notes, publisher, isbn, issn, language, edition, collection")
                throw ExitCode.failure
            }
        }
        try AppDatabase.shared.saveReference(&ref)
        printJSON(ReferenceDTO(from: ref))
    }
}

struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "按 ID 删除文献，或批量删除某分组内所有文献")

    @Argument(help: "要删除的文献 ID（使用 --collection 批量删除时可省略）")
    var ids: [Int64] = []

    @Flag(name: .shortAndLong, help: "跳过确认提示")
    var force = false

    @Option(name: .long, help: "删除指定分组 ID 内的所有文献")
    var collection: Int64?

    @Flag(name: .customLong("delete-collection"), help: "同时删除分组记录本身（配合 --collection 使用）")
    var deleteCollection = false

    func run() throws {
        if let cid = collection, ids.isEmpty {
            // Bulk delete all references in the given collection
            let refs = try AppDatabase.shared.fetchReferences(collectionId: cid)
            let refIds = refs.compactMap(\.id)
            if !force && isatty(STDIN_FILENO) != 0 {
                let msg = "Delete \(refs.count) reference(s) in collection \(cid)" +
                    (deleteCollection ? " and delete the collection itself" : "") + "? [y/N] "
                FileHandle.standardError.write(Data(msg.utf8))
                guard let line = readLine(), line.lowercased().hasPrefix("y") else {
                    printJSONError("Aborted")
                    throw ExitCode.failure
                }
            }
            if !refIds.isEmpty {
                let pdfPaths = try AppDatabase.shared.deleteReferencesReturningPDFPaths(ids: refIds)
                for path in pdfPaths { PDFService.deletePDF(at: path) }
            }
            if deleteCollection {
                try AppDatabase.shared.deleteCollection(id: cid)
            }
            var result: [String: String] = ["deletedReferences": "\(refIds.count)"]
            if deleteCollection { result["deletedCollection"] = "\(cid)" }
            printJSON(result)
        } else if !ids.isEmpty {
            if !force && isatty(STDIN_FILENO) != 0 {
                FileHandle.standardError.write(Data("Delete \(ids.count) reference(s) and associated PDFs? [y/N] ".utf8))
                guard let line = readLine(), line.lowercased().hasPrefix("y") else {
                    printJSONError("Aborted")
                    throw ExitCode.failure
                }
            }
            let pdfPaths = try AppDatabase.shared.deleteReferencesReturningPDFPaths(ids: ids)
            for path in pdfPaths { PDFService.deletePDF(at: path) }
            printJSON(["deleted": ids.map(String.init).joined(separator: ",")])
        } else {
            printJSONError("Provide reference IDs as arguments, or --collection <id> for bulk deletion")
            throw ExitCode.failure
        }
    }
}

struct Move: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "将文献移动到某个分组")

    @Argument(help: "要移动的文献 ID")
    var ids: [Int64]

    @Option(name: .long, help: "目标分组 ID")
    var collection: Int64?

    @Flag(name: .long, help: "从所有分组中移除（移至未分组）")
    var remove = false

    func run() throws {
        let targetId: Int64?
        if remove {
            targetId = nil
        } else if let cid = collection {
            targetId = cid
        } else {
            printJSONError("Provide --collection <id> to move into a collection, or --remove to uncategorise")
            throw ExitCode.failure
        }
        try AppDatabase.shared.moveReferences(ids: ids, toCollectionId: targetId)
        printJSON([
            "moved": ids.map(String.init).joined(separator: ","),
            "toCollection": targetId.map(String.init) ?? "none",
        ])
    }
}

struct Cite: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "生成文献引用格式")

    @Argument(help: "文献 ID")
    var ids: [Int64]

    @Option(name: .shortAndLong, help: "引用样式（apa、mla、chicago、ieee、harvard、vancouver、nature）")
    var style: String = "apa"

    @Option(name: .long, help: "输出格式：text、bibliography、docx-cc")
    var format: String = "text"

    func run() throws {
        // Validate citation style
        let validIds = Set(CSLManager.shared.availableStyles().map(\.id))
        guard validIds.contains(style) else {
            let available = validIds.sorted().joined(separator: ", ")
            printJSONError("Unknown citation style '\(style)'. Available: \(available)")
            throw ExitCode.failure
        }

        let refs = try AppDatabase.shared.fetchReferences(ids: ids)
        guard !refs.isEmpty else {
            printJSONError("No references found for given IDs")
            throw ExitCode.failure
        }

        switch format {
        case "bibliography":
            let entries = refs.map { CSLManager.shared.formatBibliography($0, style: style) }
            printJSON(CitationBibliographyOutput(style: style, entries: entries))
        case "docx-cc":
            let uuid = UUID().uuidString.lowercased()
            let idList = refs.compactMap(\.id).map(String.init).joined(separator: ",")
            let encodedStyle = style.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? style
            let fullTag = "swiftlib:v3:cite:\(uuid):\(encodedStyle):\(idList)"
            // Word rejects content-control tags longer than ~220 characters.
            // When the full tag exceeds this limit, emit a short tag (UUID only)
            // and include a fallbackPayload field so callers can set
            // cc.placeholderText = fallbackPayload when writing the DOCX.
            let maxTagLength = 220
            let isShortTag = fullTag.count > maxTagLength
            let tag = isShortTag ? "swiftlib:v3:cite:\(uuid)" : fullTag
            let inlineText = CSLManager.shared.formatCitation(refs, style: style)
            printJSON(
                CitationDocxCCOutput(
                    tag: tag,
                    text: inlineText,
                    style: style,
                    isShortTag: isShortTag ? true : nil,
                    fallbackPayload: isShortTag ? "swiftlib:v3:payload:\(encodedStyle):\(idList)" : nil
                )
            )
        default:
            let inline = CSLManager.shared.formatCitation(refs, style: style)
            let entries = refs.map { CSLManager.shared.formatBibliography($0, style: style) }
            printJSON(CitationTextOutput(style: style, inline: inline, bibliography: entries))
        }
    }
}

struct Import: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "从 BibTeX 或 RIS 文件导入文献（用 '-' 表示标准输入）"
    )

    @Argument(help: ".bib 或 .ris 文件路径，或 '-' 从标准输入读取")
    var file: String

    @Option(name: .long, help: "导入到指定分组 ID")
    var collection: Int64?

    @Option(name: .long, help: "从标准输入读取时指定格式：bib、ris")
    var format: String?

    func run() throws {
        let content: String
        let ext: String

        if file == "-" {
            // Read from stdin
            guard let fmt = format?.lowercased() else {
                printJSONError("--format (bib or ris) is required when reading from stdin")
                throw ExitCode.failure
            }
            ext = fmt
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let str = String(data: data, encoding: .utf8) else {
                printJSONError("Failed to decode stdin as UTF-8")
                throw ExitCode.failure
            }
            content = str
        } else {
            let url = URL(fileURLWithPath: file)
            ext = format?.lowercased() ?? url.pathExtension.lowercased()
            // Guard against excessively large files (50 MB limit)
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? UInt64, size > 50 * 1024 * 1024 {
                printJSONError("File exceeds 50 MB limit (\(size / 1024 / 1024) MB)")
                throw ExitCode.failure
            }
            content = try String(contentsOf: url, encoding: .utf8)
        }

        var refs: [Reference]
        switch ext {
        case "bib", "bibtex":
            refs = BibTeXImporter.parse(content)
        case "ris":
            refs = RISImporter.parse(content)
        default:
            printJSONError("Unsupported file format: .\(ext). Use .bib or .ris")
            throw ExitCode.failure
        }

        if let cid = collection {
            for i in refs.indices { refs[i].collectionId = cid }
        }

        let count = try AppDatabase.shared.batchImportReferences(refs)
        printJSON(["imported": "\(count)", "file": file])
    }
}

struct CNKIDebug: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cnki-debug",
        abstract: "调试 CNKI 标题匹配与候选条目解析（不启动主程序）"
    )

    @Option(name: .long, help: "本地条目/PDF 的原始标题")
    var seedTitle: String

    @Option(name: .long, help: "本地条目的第一作者")
    var seedAuthor: String?

    @Option(name: .long, help: "本地条目的出版年份")
    var seedYear: Int?

    @Option(name: .long, help: "本地条目的期刊名")
    var seedJournal: String?

    @Option(name: .long, help: "CNKI 返回的候选标题")
    var candidateTitle: String

    @Option(name: .long, help: "候选条目的元数据（作者/来源/日期等，通常为一行文本）")
    var metaText: String = ""

    @Option(name: .long, help: "候选条目的摘要片段")
    var snippet: String?

    @Option(name: .long, help: "调试用虚拟详情页 URL")
    var detailURL: String = "https://kns.cnki.net/debug"

    @Option(name: .long, help: "标题不完整时使用的文件名")
    var fileName: String?

    func run() throws {
        let resolvedSeedTitle = seedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = MetadataResolutionSeed(
            fileName: fileName ?? resolvedSeedTitle,
            title: resolvedSeedTitle,
            firstAuthor: seedAuthor,
            year: seedYear,
            journal: seedJournal,
            languageHint: .chinese
        )

        let candidate = MetadataResolution.buildCNKICandidate(
            title: candidateTitle,
            metaText: metaText,
            snippet: snippet,
            detailURL: detailURL,
            seed: seed
        )

        let similarity = MetadataResolution.titleSimilarity(resolvedSeedTitle, candidateTitle)
        let authors = candidate?.authors.map(\.displayName) ?? []
        let firstAuthorMatched: Bool = {
            guard let seedAuthor = seedAuthor?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !seedAuthor.isEmpty else { return false }
            let normalizedSeed = MetadataResolution.normalizedComparableText(seedAuthor)
            return authors.contains { author in
                let normalizedAuthor = MetadataResolution.normalizedComparableText(author)
                return !normalizedAuthor.isEmpty
                    && (normalizedAuthor.contains(normalizedSeed) || normalizedSeed.contains(normalizedAuthor))
            }
        }()
        let journalMatched: Bool = {
            guard let seedJournal = seedJournal?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let candidateJournal = candidate?.journal?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !seedJournal.isEmpty,
                  !candidateJournal.isEmpty else { return false }
            let lhs = MetadataResolution.normalizedComparableText(seedJournal)
            let rhs = MetadataResolution.normalizedComparableText(candidateJournal)
            return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
        }()

        printJSON(
            CNKIDebugOutput(
                seedTitle: resolvedSeedTitle,
                candidateTitle: candidateTitle,
                titleSimilarity: similarity,
                score: candidate?.score,
                threshold: MetadataResolution.cnkiCandidateThreshold,
                accepted: (candidate?.score ?? 0) >= MetadataResolution.cnkiCandidateThreshold,
                authors: authors,
                journal: candidate?.journal,
                year: candidate?.year,
                firstAuthorMatched: firstAuthorMatched,
                journalMatched: journalMatched
            )
        )
    }
}

struct Collections: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "列出或管理分组")

    @Flag(name: .long, help: "新建分组")
    var create = false

    @Option(name: .long, help: "分组名称（用于 --create 或 --rename）")
    var name: String?

    @Option(name: .long, help: "按 ID 删除分组（不会删除其中的文献）")
    var delete: Int64?

    @Flag(name: .customLong("with-references"), help: "删除分组时同时删除该分组内所有文献及 PDF")
    var withReferences = false

    @Flag(name: .shortAndLong, help: "跳过危险操作的确认提示")
    var force = false

    @Flag(name: .long, help: "重命名分组")
    var rename = false

    @Option(name: .long, help: "分组 ID（用于 --rename）")
    var id: Int64?

    func run() throws {
        if let deleteId = delete {
            if withReferences {
                let refs = try AppDatabase.shared.fetchReferences(collectionId: deleteId)
                let refIds = refs.compactMap(\.id)
                if !force && isatty(STDIN_FILENO) != 0 {
                    let msg = "Delete collection \(deleteId), \(refIds.count) reference(s), and associated PDFs? [y/N] "
                    FileHandle.standardError.write(Data(msg.utf8))
                    guard let line = readLine(), line.lowercased().hasPrefix("y") else {
                        printJSONError("Aborted")
                        throw ExitCode.failure
                    }
                }
                if !refIds.isEmpty {
                    let pdfPaths = try AppDatabase.shared.deleteReferencesReturningPDFPaths(ids: refIds)
                    for path in pdfPaths { PDFService.deletePDF(at: path) }
                }
                try AppDatabase.shared.deleteCollection(id: deleteId)
                printJSON(["deletedCollection": "\(deleteId)", "deletedReferences": "\(refIds.count)"])
            } else {
                try AppDatabase.shared.deleteCollection(id: deleteId)
                printJSON(["deleted": "\(deleteId)"])
            }
        } else if create, let n = name {
            var c = Collection(name: n)
            try AppDatabase.shared.saveCollection(&c)
            printJSON(["id": c.id.map(String.init) ?? "", "name": c.name])
        } else if rename, let cid = id, let n = name {
            let all = try AppDatabase.shared.fetchAllCollections()
            guard var col = all.first(where: { $0.id == cid }) else {
                printJSONError("Collection \(cid) not found")
                throw ExitCode.failure
            }
            col.name = n
            try AppDatabase.shared.saveCollection(&col)
            printJSON(["id": col.id.map(String.init) ?? "", "name": col.name])
        } else {
            let collections = try AppDatabase.shared.fetchAllCollections()
            let dtos = collections.map { c in
                ["id": c.id.map(String.init) ?? "", "name": c.name, "icon": c.icon]
            }
            printJSON(dtos)
        }
    }
}

struct Tags: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "列出或管理标签，或为文献关联/取消标签")

    @Flag(name: .long, help: "新建标签")
    var create = false

    @Option(name: .long, help: "标签名称（用于 --create 或 --rename）")
    var name: String?

    @Option(name: .long, help: "标签颜色十六进制（用于 --create，默认 #007AFF）")
    var color: String = "#007AFF"

    @Option(name: .long, help: "按 ID 删除标签")
    var delete: Int64?

    @Flag(name: .long, help: "为文献添加标签（追加，不替换）")
    var assign = false

    @Flag(name: .customLong("remove-tags"), help: "从文献移除指定标签")
    var removeTags = false

    @Option(name: .long, help: "文献 ID（用于 --assign、--remove-tags 或查看文献标签）")
    var reference: Int64?

    @Option(name: .long, help: "逗号分隔的标签 ID（用于 --assign 或 --remove-tags）")
    var tags: String?

    @Flag(name: .long, help: "重命名标签")
    var rename = false

    @Option(name: .long, help: "标签 ID（用于 --rename）")
    var id: Int64?

    func run() throws {
        if let deleteId = delete {
            try AppDatabase.shared.deleteTag(id: deleteId)
            printJSON(["deleted": "\(deleteId)"])
        } else if create, let n = name {
            var t = Tag(name: n, color: color)
            try AppDatabase.shared.saveTag(&t)
            printJSON(["id": t.id.map(String.init) ?? "", "name": t.name, "color": t.color])
        } else if assign, let refId = reference {
            let tagIds = parseTagIds()
            guard !tagIds.isEmpty else {
                printJSONError("Provide --tags <id,...> to assign")
                throw ExitCode.failure
            }
            let existing = try AppDatabase.shared.fetchTags(forReference: refId).compactMap(\.id)
            let merged = Array(Set(existing + tagIds)).sorted()
            try AppDatabase.shared.setTags(forReference: refId, tagIds: merged)
            let result = try AppDatabase.shared.fetchTags(forReference: refId)
            printJSON(result.map { ["id": $0.id.map(String.init) ?? "", "name": $0.name, "color": $0.color] })
        } else if removeTags, let refId = reference {
            let toRemove = Set(parseTagIds())
            guard !toRemove.isEmpty else {
                printJSONError("Provide --tags <id,...> to remove")
                throw ExitCode.failure
            }
            let existing = try AppDatabase.shared.fetchTags(forReference: refId).compactMap(\.id)
            let remaining = existing.filter { !toRemove.contains($0) }
            try AppDatabase.shared.setTags(forReference: refId, tagIds: remaining)
            let result = try AppDatabase.shared.fetchTags(forReference: refId)
            printJSON(result.map { ["id": $0.id.map(String.init) ?? "", "name": $0.name, "color": $0.color] })
        } else if rename, let tagId = id, let n = name {
            let allTags = try AppDatabase.shared.fetchAllTags()
            guard var tag = allTags.first(where: { $0.id == tagId }) else {
                printJSONError("Tag \(tagId) not found")
                throw ExitCode.failure
            }
            tag.name = n
            if color != "#007AFF" { tag.color = color }
            try AppDatabase.shared.saveTag(&tag)
            printJSON(["id": tag.id.map(String.init) ?? "", "name": tag.name, "color": tag.color])
        } else if let refId = reference {
            // List tags for a specific reference
            let result = try AppDatabase.shared.fetchTags(forReference: refId)
            printJSON(result.map { ["id": $0.id.map(String.init) ?? "", "name": $0.name, "color": $0.color] })
        } else {
            let allTags = try AppDatabase.shared.fetchAllTags()
            let dtos = allTags.map { t in
                ["id": t.id.map(String.init) ?? "", "name": t.name, "color": t.color]
            }
            printJSON(dtos)
        }
    }

    private func parseTagIds() -> [Int64] {
        guard let s = tags else { return [] }
        return s.split(separator: ",").compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
    }
}

struct Annotations: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "列出某文献的 PDF 批注")

    @Argument(help: "文献 ID")
    var referenceId: Int64

    func run() throws {
        let annotations = try AppDatabase.shared.fetchAnnotations(referenceId: referenceId)
        struct AnnotationDTO: Encodable {
            let id: Int64?
            let type: String
            let color: String
            let pageIndex: Int
            let selectedText: String?
            let noteText: String?
        }
        let dtos = annotations.map { a in
            AnnotationDTO(
                id: a.id,
                type: a.type.rawValue,
                color: a.color,
                pageIndex: a.pageIndex,
                selectedText: a.selectedText,
                noteText: a.noteText
            )
        }
        printJSON(dtos)
    }
}

struct Styles: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "列出可用的引用样式")

    func run() throws {
        struct StyleDTO: Encodable {
            let id: String
            let title: String
            let isBuiltin: Bool
            let citationKind: String
        }
        let dtos = CSLManager.shared.availableStyles().map { s in
            StyleDTO(id: s.id, title: s.title, isBuiltin: s.isBuiltin, citationKind: s.citationKind.rawValue)
        }
        printJSON(dtos)
    }
}

struct Export: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "将文献导出为 BibTeX、RIS 或 JSON 格式")

    @Option(name: .shortAndLong, help: "格式：json、bibtex、ris")
    var format: String = "json"

    @Option(name: .long, help: "按分组 ID 筛选")
    var collection: Int64?

    func run() throws {
        let refs: [Reference]
        if let cid = collection {
            refs = try AppDatabase.shared.fetchReferences(collectionId: cid)
        } else {
            refs = try AppDatabase.shared.fetchAllReferences()
        }

        switch format {
        case "bibtex":
            let keys = uniqueBibTeXKeys(for: refs)
            var output = ""
            output.reserveCapacity(refs.count * 300)
            for (i, ref) in refs.enumerated() {
                let entryType: String
                switch ref.referenceType {
                case .journalArticle: entryType = "article"
                case .magazineArticle: entryType = "article"
                case .newspaperArticle: entryType = "article"
                case .preprint: entryType = "unpublished"
                case .book: entryType = "book"
                case .bookSection: entryType = "incollection"
                case .conferencePaper: entryType = "inproceedings"
                case .thesis: entryType = "phdthesis"
                case .dataset: entryType = "misc"
                case .software: entryType = "misc"
                case .standard: entryType = "misc"
                case .manuscript: entryType = "unpublished"
                case .interview: entryType = "misc"
                case .presentation: entryType = "misc"
                case .blogPost: entryType = "misc"
                case .forumPost: entryType = "misc"
                case .legalCase: entryType = "misc"
                case .legislation: entryType = "misc"
                case .webpage: entryType = "misc"
                case .report: entryType = "techreport"
                case .patent: entryType = "misc"
                case .other: entryType = "misc"
                }
                output += "@\(entryType){\(keys[i]),\n"
                output += "  title = {\(escapeBibTeX(ref.title))},\n"
                let authStr = ref.authors.map { "\($0.family), \($0.given)" }.joined(separator: " and ")
                if !authStr.isEmpty { output += "  author = {\(escapeBibTeX(authStr))},\n" }
                if let y = ref.year { output += "  year = {\(y)},\n" }
                if let j = ref.journal { output += "  journal = {\(escapeBibTeX(j))},\n" }
                if let v = ref.volume { output += "  volume = {\(v)},\n" }
                if let n = ref.issue { output += "  number = {\(n)},\n" }
                if let p = ref.pages { output += "  pages = {\(p)},\n" }
                if let d = ref.doi { output += "  doi = {\(d)},\n" }
                if let u = ref.url { output += "  url = {\(u)},\n" }
                if let isbn = ref.isbn { output += "  isbn = {\(isbn)},\n" }
                if let issn = ref.issn { output += "  issn = {\(issn)},\n" }
                if let pub = ref.publisher { output += "  publisher = {\(escapeBibTeX(pub))},\n" }
                output += "}\n\n"
            }
            print(output, terminator: "")
        case "ris":
            var output = ""
            output.reserveCapacity(refs.count * 300)
            for ref in refs {
                let risType: String
                switch ref.referenceType {
                case .journalArticle, .magazineArticle, .newspaperArticle: risType = "JOUR"
                case .book: risType = "BOOK"
                case .bookSection: risType = "CHAP"
                case .conferencePaper: risType = "CONF"
                case .thesis: risType = "THES"
                case .report: risType = "RPRT"
                case .patent: risType = "PAT"
                case .webpage, .blogPost, .forumPost: risType = "ELEC"
                case .preprint, .manuscript: risType = "UNPB"
                default: risType = "GEN"
                }
                output += "TY  - \(risType)\n"
                output += "TI  - \(ref.title)\n"
                for author in ref.authors {
                    output += "AU  - \(author.family), \(author.given)\n"
                }
                if let y = ref.year { output += "PY  - \(y)\n" }
                if let j = ref.journal { output += "JO  - \(j)\n" }
                if let v = ref.volume { output += "VL  - \(v)\n" }
                if let n = ref.issue { output += "IS  - \(n)\n" }
                if let p = ref.pages {
                    let parts = p.split(separator: "-", maxSplits: 1)
                    output += "SP  - \(parts.first ?? Substring(p))\n"
                    if parts.count > 1 { output += "EP  - \(parts[1])\n" }
                }
                if let d = ref.doi { output += "DO  - \(d)\n" }
                if let u = ref.url { output += "UR  - \(u)\n" }
                if let isbn = ref.isbn { output += "SN  - \(isbn)\n" }
                if let pub = ref.publisher { output += "PB  - \(pub)\n" }
                if let ab = ref.abstract { output += "AB  - \(ab)\n" }
                output += "ER  - \n\n"
            }
            print(output, terminator: "")
        default:
            printJSON(refs.map(ReferenceDTO.init))
        }
    }
}
