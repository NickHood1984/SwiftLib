import Foundation
import SwiftLibCore
import WebKit

extension CNKIMetadataProvider {
    func shouldAttemptExportFallback(after error: Error) -> Bool {
        guard let cnkiError = error as? CNKIError else { return false }
        switch cnkiError {
        case .blockedByVerification, .parseFailed, .navigationFailed:
            return true
        case .webViewNotReady, .busy, .timedOut, .verificationCancelled:
            return false
        }
    }

    func resolveViaExportFallback(candidate: MetadataCandidate) async throws -> AuthoritativeMetadataRecord? {
        if let recovered = await recoverResolvedRecordIfPossible(candidate: candidate) {
            return recovered
        }
        guard let locator = candidate.cnkiExport, locator.hasUsableExport else { return nil }
        guard let exportText = try await fetchCNKIExportText(locator: locator, referer: candidate.detailURL),
              !exportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return record(fromExportText: exportText, fallbackCandidate: candidate)
    }

    func fetchCNKIExportText(locator: CNKIExportLocator, referer: String) async throws -> String? {
        guard let body = exportRequestBody(for: locator) else { return nil }
        let endpoint = URL(string: "https://kns.cnki.net/dm8/API/GetExport")!

        for attempt in 0..<2 {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.httpBody = Data("\(body)&displaymode=GBTREFER%2Celearning%2CEndNote".utf8)
            request.setValue("text/plain, */*; q=0.01", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,en-US;q=0.7,en;q=0.3", forHTTPHeaderField: "Accept-Language")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("kns.cnki.net", forHTTPHeaderField: "Host")
            request.setValue("https://www.cnki.net", forHTTPHeaderField: "Origin")
            request.setValue(referer, forHTTPHeaderField: "Referer")
            request.setValue(ReaderExtractionManager.safariLikeUserAgent, forHTTPHeaderField: "User-Agent")
            if let cookieHeader = await cnkiCookieHeader(), !cookieHeader.isEmpty {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }

            let (data, response) = try await NetworkClient.session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if statusCode == 403 {
                guard attempt == 0 else { throw CNKIError.blockedByVerification }
                let verificationURL = exportVerificationURL(from: data) ?? URL(string: referer) ?? Self.mainlandCNKIHomeURL
                try await requestVerification(
                    at: verificationURL,
                    title: "需要继续知网会话",
                    message: "CNKI 导出接口暂时拒绝了后台请求。请确认窗口中的知网页面可正常访问，并停留在目标文献详情页，然后点击“继续检查”。",
                    continueLabel: "继续检查"
                )
                continue
            }

            guard statusCode == 200 else {
                throw CNKIError.navigationFailed("CNKI 导出接口返回 HTTP \(statusCode)")
            }

            if let exportText = exportText(from: data) {
                return exportText
            }

            if attempt == 0, let verificationURL = exportVerificationURL(from: data) {
                try await requestVerification(
                    at: verificationURL,
                    title: "需要继续知网会话",
                    message: "CNKI 导出接口返回了会话页面。请确认窗口中的知网页面可正常访问，并停留在目标文献详情页，然后点击“继续检查”。",
                    continueLabel: "继续检查"
                )
                continue
            }

            return nil
        }

        return nil
    }
    func exportRequestBody(for locator: CNKIExportLocator) -> String? {
        if let exportID = locator.exportID?.trimmingCharacters(in: .whitespacesAndNewlines), !exportID.isEmpty {
            return "filename=\(exportID)&uniplatform=NZKPT"
        }
        if let dbname = locator.dbname?.trimmingCharacters(in: .whitespacesAndNewlines),
           let filename = locator.filename?.trimmingCharacters(in: .whitespacesAndNewlines),
           !dbname.isEmpty, !filename.isEmpty {
            return "filename=\(dbname)!\(filename)!1!0"
        }
        return nil
    }

    func cnkiCookieHeader() async -> String? {
        let cookies = await withCheckedContinuation { continuation in
            Self.sharedDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        let relevant = cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            return domain.contains("cnki")
        }
        guard !relevant.isEmpty else { return nil }
        return relevant.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func exportVerificationURL(from data: Data) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String,
              let url = URL(string: message),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    func exportText(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? Int, code == 1,
           let items = json["data"] as? [[String: Any]] {
            for item in items {
                let key = (item["key"] as? String)?.lowercased()
                if key == "endnote" || key == "refworks" || key == "ris" {
                    if let values = item["value"] as? [String], let first = values.first {
                        return sanitizeExportText(first)
                    }
                    if let value = item["value"] as? String {
                        return sanitizeExportText(value)
                    }
                }
            }
        }

        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let sanitized = sanitizeExportText(raw)
        return sanitized.isEmpty ? nil : sanitized
    }

    func sanitizeExportText(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        let htmlEntities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
        ]
        for (entity, replacement) in htmlEntities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    func record(fromExportText text: String, fallbackCandidate: MetadataCandidate) -> AuthoritativeMetadataRecord? {
        let sanitized = sanitizeExportText(text)
        let recordKey = resolvedCNKIRecordKey(for: fallbackCandidate)
        let artifact = RawArtifactManifest(
            kind: .exportText,
            sha256: MetadataVerificationCodec.sha256Hex(for: sanitized),
            contentType: "text/plain",
            preview: String(sanitized.prefix(240))
        )

        if var risReference = RISImporter.parse(sanitized).first {
            if risReference.title == "Untitled"
                || MetadataResolution.isSuspiciousExtractedTitle(risReference.title) {
                let candidateTitle = fallbackCandidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if candidateTitle.isEmpty || MetadataResolution.isSuspiciousExtractedTitle(candidateTitle) {
                    return nil
                }
                risReference.title = candidateTitle
            }
            if risReference.authors.isEmpty {
                return nil
            }
            risReference.journal = MetadataResolution.normalizeJournalName(risReference.journal)
                ?? MetadataResolution.normalizeJournalName(fallbackCandidate.journal)
            if risReference.journal == nil {
                risReference.journal = fallbackCandidate.journal
            }
            if risReference.year == nil {
                risReference.year = fallbackCandidate.year
            }
            if isBlank(risReference.url) {
                risReference.url = fallbackCandidate.detailURL
            }
            if risReference.referenceType == .other {
                let workKind = inferWorkKind(from: sanitized, fallbackCandidate: fallbackCandidate)
                risReference.referenceType = resolvedReferenceType(for: workKind, fallbackCandidate: fallbackCandidate)
            }
            risReference.metadataSource = .cnki
            let enriched = enrich(risReference, fallbackCandidate: fallbackCandidate, sourceText: sanitized)
            return AuthoritativeMetadataRecord(
                reference: enriched,
                evidence: exportEvidence(
                    for: enriched,
                    sanitizedText: sanitized,
                    fallbackCandidate: fallbackCandidate,
                    recordKey: recordKey,
                    artifact: artifact
                )
            )
        }

        let workKind = inferWorkKind(from: sanitized, fallbackCandidate: fallbackCandidate)
        var reference = Reference(
            title: "",
            authors: [],
            year: fallbackCandidate.year,
            journal: resolvedReferenceType(for: workKind, fallbackCandidate: fallbackCandidate) == .journalArticle
                ? MetadataResolution.normalizeJournalName(fallbackCandidate.journal)
                : nil,
            url: fallbackCandidate.detailURL,
            referenceType: resolvedReferenceType(for: workKind, fallbackCandidate: fallbackCandidate),
            metadataSource: .cnki
        )

        if let title = firstRegexCapture(
            in: sanitized,
            patterns: [
                #"(?mi)^(?:Title(?:-题名)?|题名)\s*[:：-]\s*(.+)$"#,
                #"(?mi)^(?:TI|T1)\s*-\s*(.+)$"#
            ]
        ), let title = trimmedOrNil(title),
           !MetadataResolution.isSuspiciousExtractedTitle(title) {
            reference.title = title
        }

        if let rawAuthors = firstRegexCapture(
            in: sanitized,
            patterns: [
                #"(?mi)^(?:Author(?:-作者)?|作者)\s*[:：-]\s*(.+)$"#,
                #"(?mi)^(?:AU|A1)\s*-\s*(.+)$"#
            ]
        ), let rawAuthors = trimmedOrNil(rawAuthors) {
            let authors = AuthorName.parseList(Self.normalizeCNKIExportAuthors(rawAuthors))
            if !authors.isEmpty {
                reference.authors = authors
            }
        }
        if let journal = firstRegexCapture(
            in: sanitized,
            patterns: [
                #"(?mi)^(?:Source(?:-刊名)?|刊名)\s*[:：-]\s*(.+)$"#,
                #"(?mi)^(?:JO|JF|T2)\s*-\s*(.+)$"#
            ]
        ), let journal = MetadataResolution.normalizeJournalName(trimmedOrNil(journal)) {
            reference.journal = journal
        }

        if let volume = firstRegexCapture(
            in: sanitized,
            patterns: [
                #"(?mi)^(?:Roll(?:-卷)?|卷)\s*[:：-]\s*(.+)$"#,
                #"(?mi)^(?:VL)\s*-\s*(.+)$"#
            ]
        ), let volume = trimmedOrNil(volume) {
            reference.volume = volume
        }

        if let issue = firstRegexCapture(
            in: sanitized,
            patterns: [
                #"(?mi)^(?:Period(?:-期)?|期)\s*[:：-]\s*(.+)$"#,
                #"(?mi)^(?:IS)\s*-\s*(.+)$"#
            ]
        ), let issue = trimmedOrNil(issue) {
            reference.issue = issue
        }

        if let pages = firstRegexCapture(
            in: sanitized,
            patterns: [
                #"(?mi)^(?:Page(?:-页码)?|页码)\s*[:：-]\s*(.+)$"#,
                #"(?mi)^(?:SP)\s*-\s*(.+)$"#
            ]
        ), let pages = trimmedOrNil(pages) {
            reference.pages = pages
        }

        let parsedVIP = MetadataResolution.parseVolumeIssuePages(from: sanitized)
        if isBlank(reference.volume) {
            reference.volume = parsedVIP.volume
        }
        if isBlank(reference.issue) {
            reference.issue = parsedVIP.issue
        }
        if isBlank(reference.pages) {
            reference.pages = parsedVIP.pages
        }
        if reference.year == nil {
            reference.year = MetadataResolution.extractYear(fromMetadataText: sanitized)
        }
        if isBlank(reference.doi) {
            reference.doi = extractDOI(from: sanitized)
        }
        if isBlank(reference.abstract) {
            reference.abstract = extractAbstract(from: sanitized)
        }

        let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              !MetadataResolution.isSuspiciousExtractedTitle(title),
              !reference.authors.isEmpty else {
            return nil
        }
        let enriched = enrich(reference, fallbackCandidate: fallbackCandidate, sourceText: sanitized)
        return AuthoritativeMetadataRecord(
            reference: enriched,
            evidence: exportEvidence(
                for: enriched,
                sanitizedText: sanitized,
                fallbackCandidate: fallbackCandidate,
                recordKey: recordKey,
                artifact: artifact
            )
        )
    }

}
