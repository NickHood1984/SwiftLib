import Foundation
import SwiftLibCore
import WebKit

extension CNKIMetadataProvider {
    func enrichCandidatePreviews(_ candidates: [MetadataCandidate], limit: Int = 3) async -> [MetadataCandidate] {
        guard !candidates.isEmpty else { return candidates }
        let hydrationIndices = candidates.indices
            .filter { shouldHydrateCandidatePreview(candidates[$0]) }
            .prefix(limit)

        guard !hydrationIndices.isEmpty else { return candidates }

        var enriched = candidates
        await withTaskGroup(of: (Int, MetadataCandidate).self) { group in
            for index in hydrationIndices {
                let candidate = candidates[index]
                group.addTask { [self] in
                    let hydrated = await hydrateCandidatePreview(candidate)
                    return (index, hydrated)
                }
            }

            for await (index, hydratedCandidate) in group {
                enriched[index] = hydratedCandidate
            }
        }

        return enriched
    }

    func shouldHydrateCandidatePreview(_ candidate: MetadataCandidate) -> Bool {
        guard candidate.source == .cnki else { return false }
        guard !candidate.detailURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let snippet = trimmedOrNil(candidate.snippet) else { return true }
        if snippet.count < 80 { return true }
        return snippet.hasSuffix("...") || snippet.hasSuffix("…")
    }

    func hydrateCandidatePreview(_ candidate: MetadataCandidate) async -> MetadataCandidate {
        do {
            guard let payload = try await fetchDetailPreviewPayload(for: candidate) else { return candidate }

            var enriched = candidate
            let bodyText = payload.bodyText ?? ""
            let abstract = normalizedCandidateSnippet(
                trimmedOrNil(payload.abstract) ?? extractAbstract(from: bodyText)
            )
            if shouldReplaceCandidateSnippet(current: candidate.snippet, replacement: abstract) {
                enriched.snippet = abstract
            }

            if enriched.authors.isEmpty {
                let authors = Self.resolvedDetailAuthors(
                    extractedAuthors: payload.authors,
                    fallbackAuthors: candidate.authors
                )
                if !authors.isEmpty {
                    enriched.authors = authors
                }
            }

            if trimmedOrNil(enriched.journal) == nil {
                enriched.journal = Self.resolveJournal(extractedJournal: payload.journal, fallbackCandidate: candidate)
            }

            if enriched.year == nil {
                enriched.year = MetadataResolution.extractYear(fromMetadataText: payload.yearText ?? bodyText)
            }

            cnkiDebugTrace(
                "candidate preview hydrated title=\(candidate.title) abstractLen=\(abstract?.count ?? 0) authorCount=\(enriched.authors.count) journal=\(enriched.journal ?? "nil")"
            )
            return enriched
        } catch {
            cnkiDebugTrace(
                "candidate preview skipped title=\(candidate.title) error=\(error.localizedDescription)"
            )
            return candidate
        }
    }

    func fetchDetailPreviewPayload(for candidate: MetadataCandidate) async throws -> DetailPayload? {
        guard let url = URL(string: candidate.detailURL) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue(ReaderExtractionManager.safariLikeUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,en-US;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.mainlandCNKIHomeURL.absoluteString, forHTTPHeaderField: "Referer")
        if let cookieHeader = await cnkiCookieHeader(), !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await NetworkClient.session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            throw CNKIError.navigationFailed("候选详情预览返回 HTTP \(statusCode)")
        }
        guard let html = decodeCNKIHTML(from: data) else {
            throw CNKIError.parseFailed("候选详情预览没有返回可解析内容。")
        }

        let payload = try await extractDetailPayload(fromHTML: html, baseURL: url)
        guard !payload.blocked else {
            cnkiDebugTrace(
                "candidate preview blocked title=\(candidate.title) reason=\(payload.blockedReason ?? "nil")"
            )
            return nil
        }
        return payload
    }

    func extractDetailPayload(fromHTML html: String, baseURL: URL) async throws -> DetailPayload {
        let parserWebView = parserPool.acquire { configureWebView($0) }
        defer { parserPool.release(parserWebView) }

        let wrapperHTML: String = {
            if html.range(of: #"<html[\s>]"#, options: [.regularExpression, .caseInsensitive]) != nil {
                return html
            }
            return """
            <html>
              <head>
                <meta charset="utf-8">
                <base href="\(baseURL.absoluteString)">
              </head>
              <body>
                \(html)
              </body>
            </html>
            """
        }()

        let loadDelegate = HTMLLoadDelegate()
        parserWebView.navigationDelegate = loadDelegate
        try await loadDelegate.load(html: wrapperHTML, in: parserWebView, baseURL: baseURL)
        return try await evaluateJSONScript(Self.detailExtractionScript, in: parserWebView)
    }

    func extractReference(candidate: MetadataCandidate, in webView: WKWebView) async throws -> AuthoritativeMetadataRecord {
        for _ in 0..<8 {
            let payload: DetailPayload = try await evaluateJSONScript(Self.detailExtractionScript, in: webView)
            let title = Self.resolvedDetailTitle(
                extractedTitle: payload.title,
                fallbackCandidateTitle: candidate.title
            )
            let displayAuthors = Self.resolvedDetailAuthors(
                extractedAuthors: payload.authors,
                fallbackAuthors: candidate.authors
            )
            let verificationAuthors = Self.verificationDetailAuthors(extractedAuthors: payload.authors)
            let bodyText = payload.bodyText ?? ""
            let parsedVIP = MetadataResolution.parseVolumeIssuePages(from: bodyText)
            let pages = Self.resolvedPages(
                firstPage: payload.firstPage,
                lastPage: payload.lastPage,
                fallbackPages: parsedVIP.pages
            )
            let yearText = payload.yearText ?? bodyText
            let inferredWorkKind = inferWorkKind(from: bodyText, fallbackCandidate: candidate)
            let institution = inferredWorkKind == .thesis ? extractInstitution(from: bodyText) : nil
            let thesisType = inferredWorkKind == .thesis ? extractThesisGenre(from: bodyText) : nil
            if Self.shouldAcceptResolvedDetail(
                resolvedTitle: title,
                resolvedAuthors: verificationAuthors,
                journal: payload.journal,
                doi: payload.doi,
                yearText: yearText,
                pages: pages,
                institution: institution,
                thesisType: thesisType
            ), let title {
                cnkiDebugTrace(
                    "detail resolved url=\(payload.url ?? webView.url?.absoluteString ?? candidate.detailURL) title=\(title) authorSource=\(payload.authorSource ?? "none") extractedAuthorCount=\(payload.authors.count) displayAuthorCount=\(displayAuthors.count) verificationAuthorCount=\(verificationAuthors.count) blocked=\(payload.blocked) journal=\(payload.journal ?? "nil")"
                )
                return reference(
                    from: payload,
                    fallbackCandidate: candidate,
                    resolvedTitle: title,
                    resolvedAuthors: verificationAuthors,
                    displayAuthors: displayAuthors
                )
            }
            if payload.blocked {
                cnkiDebugTrace(
                    "detail blocked url=\(payload.url ?? webView.url?.absoluteString ?? candidate.detailURL) reason=\(payload.blockedReason ?? "nil") rawTitle=\(payload.title ?? "nil") authorSource=\(payload.authorSource ?? "none") extractedAuthorCount=\(payload.authors.count) displayAuthorCount=\(displayAuthors.count) verificationAuthorCount=\(verificationAuthors.count) journal=\(payload.journal ?? "nil") abstractLen=\(payload.abstract?.count ?? 0)"
                )
                throw CNKIError.blockedByVerification
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        cnkiDebugTrace(
            "detail unresolved url=\(webView.url?.absoluteString ?? candidate.detailURL) fallbackAuthorCount=\(candidate.authors.count)"
        )
        throw CNKIError.parseFailed("未能从详情页提取到完整题名和作者。")
    }

    nonisolated static func resolveTitle(extractedTitle: String?) -> String? {
        if let extractedTitle = extractedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !extractedTitle.isEmpty,
           !MetadataResolution.isSuspiciousExtractedTitle(extractedTitle) {
            return extractedTitle
        }
        return nil
    }

    nonisolated static func resolvedDetailTitle(
        extractedTitle: String?,
        fallbackCandidateTitle: String?
    ) -> String? {
        guard let extracted = resolveTitle(extractedTitle: extractedTitle) else {
            return resolveTitle(extractedTitle: fallbackCandidateTitle)
        }
        // If we have a known-good candidate title, check whether the extracted title
        // diverges wildly — e.g. CNKI returned an affiliation instead of the real title.
        if let candidateTitle = fallbackCandidateTitle,
           !candidateTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let similarity = MetadataResolution.titleSimilarity(extracted, candidateTitle)
            if similarity < 0.30 {
                return resolveTitle(extractedTitle: candidateTitle) ?? extracted
            }
        }
        return extracted
    }

    nonisolated static func resolveAuthors(extractedAuthors: [String]) -> [AuthorName] {
        extractedAuthors
            .compactMap(Self.normalizedAuthorName(_:))
            .map { name -> AuthorName in
                if MetadataResolution.containsHanCharacters(name) {
                    return AuthorName(given: "", family: name)
                }
                return AuthorName.parse(name)
            }
    }

    nonisolated static func resolvedDetailAuthors(
        extractedAuthors: [String],
        fallbackAuthors: [AuthorName]
    ) -> [AuthorName] {
        let resolved = resolveAuthors(extractedAuthors: extractedAuthors)
        if !resolved.isEmpty {
            return resolved
        }
        return fallbackAuthors
    }

    nonisolated static func verificationDetailAuthors(extractedAuthors: [String]) -> [AuthorName] {
        resolveAuthors(extractedAuthors: extractedAuthors)
    }

    nonisolated static func resolvedPages(
        firstPage: String?,
        lastPage: String?,
        fallbackPages: String?
    ) -> String? {
        let firstPage = firstPage?.trimmingCharacters(in: .whitespacesAndNewlines).swiftlib_nilIfBlank
        let lastPage = lastPage?.trimmingCharacters(in: .whitespacesAndNewlines).swiftlib_nilIfBlank
        if let firstPage, let lastPage, firstPage != lastPage {
            return "\(firstPage)-\(lastPage)"
        }
        return firstPage ?? fallbackPages?.swiftlib_nilIfBlank
    }

    nonisolated static func shouldAcceptResolvedDetail(
        resolvedTitle: String?,
        resolvedAuthors: [AuthorName],
        journal: String?,
        doi: String?,
        yearText: String?,
        pages: String?,
        institution: String?,
        thesisType: String?
    ) -> Bool {
        guard resolvedTitle != nil else { return false }
        if !resolvedAuthors.isEmpty {
            return true
        }
        if doi?.swiftlib_nilIfBlank != nil {
            return true
        }
        if journal?.swiftlib_nilIfBlank != nil
            && yearText?.swiftlib_nilIfBlank != nil
            && pages?.swiftlib_nilIfBlank != nil {
            return true
        }
        if institution?.swiftlib_nilIfBlank != nil
            && thesisType?.swiftlib_nilIfBlank != nil
            && yearText?.swiftlib_nilIfBlank != nil {
            return true
        }
        return false
    }

    nonisolated static func normalizedAuthorName(_ raw: String) -> String? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"[0-9０-９¹²³⁴⁵⁶⁷⁸⁹]+$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[\*†‡#]+$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        let lowered = cleaned.lowercased()
        let blockedFragments = [
            "大学", "学院", "研究所", "管理局", "水文局", "实验室", "中心", "医院", "部门", "工程", "水利部",
            "有限公司", "股份有限公司", "出版社", "编辑部", "作者简介", "关键词", "摘要", "基金资助",
            "印刷版", "打印版", "下载", "引用", "分享", "收藏", "自动登录", "安全验证",
            "university", "college", "institute", "laboratory", "center", "centre", "hospital", "department"
        ]
        if blockedFragments.contains(where: lowered.contains) {
            return nil
        }
        if MetadataResolution.containsHanCharacters(cleaned) {
            guard cleaned.range(of: #"^[\p{Han}]{2,4}(?:·[\p{Han}]{1,6})?$"#, options: .regularExpression) != nil else {
                return nil
            }
            return cleaned
        }

        guard cleaned.range(of: #"^[A-Za-z][A-Za-z .'-]{1,60}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return cleaned
    }

    /// 预处理知网 NoteExpress/CAJ 导出格式的作者字符串。
    /// 知网紧凑格式示例：`"匡晨亿 王森洋, 等 梁智策"` — 前几位作者空格分隔，"等"作为 et al. 标记，最后是通讯作者。
    /// 转换为 `AuthorName.parseList` 可正确解析的分号分隔格式。
    nonisolated static func normalizeCNKIExportAuthors(_ raw: String) -> String {
        // 1. 规范化标点
        var s = raw
            .replacingOccurrences(of: "；", with: ";")
            .replacingOccurrences(of: "，", with: ",")
        // 2. 去掉"等"et al.标记，将周围的分隔符统一为分号
        s = s.replacingOccurrences(of: #",?\s*等\s+"#, with: ";", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+等\s*,?"#, with: ";", options: .regularExpression)
        // 3. 对每个分号分隔的段落，如果是多个汉字人名空格拼接（每段 2-4 个汉字），拆开为单独人名
        let segments = s.components(separatedBy: ";")
        let expanded = segments.flatMap { segment -> [String] in
            let t = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = t.components(separatedBy: " ").filter { !$0.isEmpty }
            // 每个部分都像汉字人名（2-4个字）时，视为多个独立姓名
            let allChineseName = parts.count >= 2 && parts.allSatisfy { part in
                guard part.count >= 2 && part.count <= 4 else { return false }
                return part.unicodeScalars.allSatisfy { scalar in
                    (0x4E00...0x9FFF).contains(scalar.value) ||
                    (0x3400...0x4DBF).contains(scalar.value) ||
                    scalar.value == 0x00B7  // 中圆点（蒙古族姓名）
                }
            }
            return allChineseName ? parts : [t]
        }
        return expanded.filter { !$0.isEmpty }.joined(separator: ";")
    }

    nonisolated static func resolveJournal(extractedJournal: String?, fallbackCandidate: MetadataCandidate) -> String? {
        MetadataResolution.normalizeJournalName(extractedJournal)
            ?? MetadataResolution.normalizeJournalName(fallbackCandidate.journal)
    }

    func reference(
        from payload: DetailPayload,
        fallbackCandidate: MetadataCandidate,
        resolvedTitle: String,
        resolvedAuthors: [AuthorName],
        displayAuthors: [AuthorName]
    ) -> AuthoritativeMetadataRecord {
        let bodyText = payload.bodyText ?? ""

        let parsedVIP = MetadataResolution.parseVolumeIssuePages(from: bodyText)
        let pages = Self.resolvedPages(
            firstPage: payload.firstPage,
            lastPage: payload.lastPage,
            fallbackPages: parsedVIP.pages
        )

        let year = MetadataResolution.extractYear(fromMetadataText: payload.yearText ?? bodyText)
        let doi = trimmedOrNil(payload.doi) ?? extractDOI(from: bodyText)
        let abstract = trimmedOrNil(payload.abstract) ?? extractAbstract(from: bodyText)
        let inferredWorkKind = inferWorkKind(from: bodyText, fallbackCandidate: fallbackCandidate)
        let referenceType = resolvedReferenceType(for: inferredWorkKind, fallbackCandidate: fallbackCandidate)
        let journal = referenceType == .journalArticle
            ? Self.resolveJournal(extractedJournal: payload.journal, fallbackCandidate: fallbackCandidate)
            : nil

        var reference = Reference(
            title: resolvedTitle,
            authors: resolvedAuthors,
            year: year,
            journal: journal,
            volume: trimmedOrNil(payload.volume) ?? parsedVIP.volume,
            issue: trimmedOrNil(payload.issue) ?? parsedVIP.issue,
            pages: pages,
            doi: doi,
            url: trimmedOrNil(payload.url) ?? fallbackCandidate.detailURL,
            abstract: abstract,
            referenceType: referenceType,
            metadataSource: .cnki
        )
        reference = enrich(reference, fallbackCandidate: fallbackCandidate, sourceText: bodyText)

        let detailURL = trimmedOrNil(payload.url) ?? fallbackCandidate.detailURL
        let recordKey = resolvedCNKIRecordKey(for: fallbackCandidate)
        var evidenceFields: [FieldEvidence] = [
            FieldEvidence(field: "title", value: resolvedTitle, origin: .structuredDetail),
        ]
        if !resolvedAuthors.isEmpty {
            evidenceFields.append(
                FieldEvidence(
                    field: "authors",
                    value: resolvedAuthors.displayString,
                    origin: .structuredDetail,
                    selectorOrPath: payload.authorSource,
                    rawSnippet: displayAuthors.displayString
                )
            )
        }
        if let year {
            evidenceFields.append(FieldEvidence(field: "year", value: String(year), origin: .structuredDetail))
        }
        if let journal {
            evidenceFields.append(FieldEvidence(field: "journal", value: journal, origin: .structuredDetail))
        }
        if let pages {
            evidenceFields.append(FieldEvidence(field: "pages", value: pages, origin: .structuredDetail))
        }
        if let doi {
            evidenceFields.append(FieldEvidence(field: "doi", value: doi, origin: .structuredDetail))
        }
        if let institution = reference.institution?.swiftlib_nilIfBlank {
            evidenceFields.append(FieldEvidence(field: "institution", value: institution, origin: .structuredDetail))
        }
        if let thesisType = reference.genre?.swiftlib_nilIfBlank {
            evidenceFields.append(FieldEvidence(field: "thesisType", value: thesisType, origin: .structuredDetail))
        }

        let evidence = EvidenceBundle(
            source: .cnki,
            recordKey: recordKey,
            sourceURL: detailURL,
            fetchMode: .detail,
            rawArtifacts: [
                RawArtifactManifest(
                    kind: .html,
                    sha256: MetadataVerificationCodec.sha256Hex(for: bodyText),
                    contentType: "text/html",
                    preview: String(bodyText.prefix(240))
                )
            ],
            fieldEvidence: evidenceFields,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: !resolvedAuthors.isEmpty,
                hasStructuredJournal: journal?.swiftlib_nilIfBlank != nil,
                hasStructuredInstitution: reference.institution?.swiftlib_nilIfBlank != nil,
                hasStructuredPages: pages?.swiftlib_nilIfBlank != nil,
                hasStructuredThesisType: reference.genre?.swiftlib_nilIfBlank != nil,
                hasStableRecordKey: recordKey != nil,
                usedStructuredDetail: true
            )
        )
        return AuthoritativeMetadataRecord(reference: reference, evidence: evidence)
    }

    nonisolated static func trimmedOrNilValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func trimmedOrNil(_ value: String?) -> String? {
        Self.trimmedOrNilValue(value)
    }

    func normalizedCandidateSnippet(_ value: String?) -> String? {
        guard let value = trimmedOrNil(value) else { return nil }
        let normalized = MetadataResolution.normalizeWhitespaceAndWidth(value)
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    func shouldReplaceCandidateSnippet(current: String?, replacement: String?) -> Bool {
        guard let replacement = trimmedOrNil(replacement) else { return false }
        guard let current = trimmedOrNil(current) else { return true }
        if current.count < 80 { return true }
        if current.hasSuffix("...") || current.hasSuffix("…") { return true }
        return replacement.count > current.count + 40
    }

    func resolvedCNKIRecordKey(for candidate: MetadataCandidate) -> String? {
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

    func exportEvidence(
        for reference: Reference,
        sanitizedText: String,
        fallbackCandidate: MetadataCandidate,
        recordKey: String?,
        artifact: RawArtifactManifest
    ) -> EvidenceBundle {
        var fields: [FieldEvidence] = [
            FieldEvidence(field: "title", value: reference.title, origin: .structuredExport),
            FieldEvidence(field: "authors", value: reference.authors.displayString, origin: .structuredExport),
        ]
        if let year = reference.year {
            fields.append(FieldEvidence(field: "year", value: String(year), origin: .structuredExport))
        }
        if let journal = reference.journal?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "journal", value: journal, origin: .structuredExport))
        }
        if let pages = reference.pages?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "pages", value: pages, origin: .structuredExport))
        }
        if let doi = reference.doi?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "doi", value: doi, origin: .structuredExport))
        }
        if let institution = reference.institution?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "institution", value: institution, origin: .structuredExport))
        }
        if let thesisType = reference.genre?.swiftlib_nilIfBlank {
            fields.append(FieldEvidence(field: "thesisType", value: thesisType, origin: .structuredExport))
        }

        return EvidenceBundle(
            source: .cnki,
            recordKey: recordKey,
            sourceURL: reference.url ?? fallbackCandidate.detailURL,
            fetchMode: .export,
            rawArtifacts: [artifact],
            fieldEvidence: fields,
            verificationHints: VerificationHints(
                hasStructuredTitle: true,
                hasStructuredAuthors: !reference.authors.isEmpty,
                hasStructuredJournal: reference.journal?.swiftlib_nilIfBlank != nil,
                hasStructuredInstitution: reference.institution?.swiftlib_nilIfBlank != nil,
                hasStructuredPages: reference.pages?.swiftlib_nilIfBlank != nil,
                hasStructuredThesisType: reference.genre?.swiftlib_nilIfBlank != nil,
                hasStableRecordKey: recordKey != nil,
                usedStructuredExport: true
            )
        )
    }

    func isBlank(_ value: String?) -> Bool {
        trimmedOrNil(value) == nil
    }

    func extractDOI(from text: String) -> String? {
        let pattern = #"(10\.\d{4,9}\/[^\s]+[^\s\.,;\]\)])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    func extractAbstract(from text: String) -> String? {
        let patterns = [
            #"摘\s*要\s*[:：]?\s*([\s\S]{40,2000}?)(?=\s*(?:关键词|关键字|引言|1[\.\s、]|一、))"#,
            #"(?i)abstract\s*[:：]?\s*([\s\S]{40,2000}?)(?=\s*(?:keywords?|introduction|1[\.\s]))"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let abstract = String(text[range])
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if abstract.count >= 40 {
                return String(abstract.prefix(2000))
            }
        }
        return nil
    }

    func inferWorkKind(from text: String, fallbackCandidate: MetadataCandidate) -> MetadataWorkKind {
        let normalized = MetadataResolution.normalizeWhitespaceAndWidth(text)
        if normalized.range(of: #"(博士|硕士)学位论文|学位授予单位|导师|答辩日期"#, options: .regularExpression) != nil {
            return .thesis
        }
        if normalized.range(of: #"会议论文|学术会议|会议名称|conference"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return .conferencePaper
        }
        if normalized.range(of: #"出版社|ISBN|图书在版编目|版次"#, options: .regularExpression) != nil {
            return .book
        }
        if normalized.range(of: #"研究报告|报告编号|report"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return .report
        }
        if fallbackCandidate.workKind != .unknown {
            return fallbackCandidate.workKind
        }
        if let referenceType = fallbackCandidate.referenceType {
            return MetadataResolution.workKind(for: referenceType)
        }
        return .journalArticle
    }

    func resolvedReferenceType(for workKind: MetadataWorkKind, fallbackCandidate: MetadataCandidate) -> ReferenceType {
        switch workKind {
        case .unknown:
            if let fallbackType = fallbackCandidate.referenceType, fallbackType != .other {
                return fallbackType
            }
            return .journalArticle
        default:
            return workKind.referenceType
        }
    }

    func enrich(_ reference: Reference, fallbackCandidate: MetadataCandidate, sourceText: String) -> Reference {
        var enriched = reference
        let normalized = MetadataResolution.normalizeWhitespaceAndWidth(sourceText)
        let referenceType = enriched.referenceType

        enriched.metadataSource = .cnki
        enriched.siteName = enriched.siteName ?? MetadataSource.cnki.displayName
        enriched.isbn = enriched.isbn.swiftlib_nilIfBlank ?? extractISBN(from: normalized)
        enriched.issn = enriched.issn.swiftlib_nilIfBlank ?? extractISSN(from: normalized)
        enriched.publisher = enriched.publisher.swiftlib_nilIfBlank ?? extractPublisher(from: normalized)
        enriched.publisherPlace = enriched.publisherPlace.swiftlib_nilIfBlank ?? extractPublisherPlace(from: normalized)
        enriched.numberOfPages = enriched.numberOfPages.swiftlib_nilIfBlank ?? extractNumberOfPages(from: normalized)
        enriched.language = enriched.language.swiftlib_nilIfBlank ?? (MetadataResolution.containsHanCharacters(normalized) ? "zh-CN" : nil)

        switch referenceType {
        case .thesis:
            enriched.genre = enriched.genre.swiftlib_nilIfBlank ?? extractThesisGenre(from: normalized)
            enriched.institution = enriched.institution.swiftlib_nilIfBlank ?? extractInstitution(from: normalized)
            enriched.journal = nil
        case .book, .bookSection:
            enriched.journal = nil
        case .conferencePaper:
            enriched.eventTitle = enriched.eventTitle.swiftlib_nilIfBlank
                ?? extractConferenceName(from: normalized)
                ?? fallbackCandidate.journal?.swiftlib_nilIfBlank
        case .report:
            enriched.genre = enriched.genre.swiftlib_nilIfBlank ?? "Research Report"
            enriched.journal = nil
        default:
            break
        }

        return enriched
    }

    func extractISBN(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [#"(?:ISBN(?:-13)?)[\s:：]*([0-9Xx\-]{10,20})"#]
        )?.replacingOccurrences(of: " ", with: "")
    }

    func extractISSN(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [#"(?:ISSN)[\s:：]*([0-9]{4}-[0-9Xx]{4})"#]
        )
    }

    func extractPublisher(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [
                #"出版社[\s:：]*([^\n]{2,40})"#,
                #"出版单位[\s:：]*([^\n]{2,40})"#
            ]
        )
    }

    func extractPublisherPlace(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [
                #"出版地[\s:：]*([^\n]{2,20})"#,
                #"出版地点[\s:：]*([^\n]{2,20})"#
            ]
        )
    }

    func extractInstitution(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [
                #"(?:学位授予单位|授予单位|培养单位|授予机构)[\s:：]*([^\n]{2,80})"#,
                #"(?:university|institution)[\s:：]*([^\n]{2,80})"#
            ]
        )
    }

    func extractThesisGenre(from text: String) -> String? {
        if text.contains("博士学位论文") {
            return "Doctoral dissertation"
        }
        if text.contains("硕士学位论文") {
            return "Master's thesis"
        }
        return nil
    }

    func extractConferenceName(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [
                #"会议名称[\s:：]*([^\n]{4,120})"#,
                #"conference name[\s:：]*([^\n]{4,120})"#
            ]
        )
    }

    func extractNumberOfPages(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [
                #"总页数[\s:：]*([0-9]{1,5})"#,
                #"页数[\s:：]*([0-9]{1,5})"#
            ]
        )
    }

}
