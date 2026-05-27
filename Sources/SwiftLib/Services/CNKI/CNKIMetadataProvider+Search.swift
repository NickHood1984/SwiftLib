import Foundation
import SwiftLibCore
import WebKit

extension CNKIMetadataProvider {
    func searchViaGridRequest(seed: MetadataResolutionSeed) async throws -> [MetadataCandidate] {
        await CNKISelectorService.shared.autoUpdateIfNeeded()

        var verificationAttempts = 0
        var attemptedHiddenBootstrap = false

        while true {
            do {
                return try await performGridSearch(seed: seed)
            } catch CNKIError.blockedByVerification {
                if !attemptedHiddenBootstrap {
                    attemptedHiddenBootstrap = true
                    switch await searchViaHiddenWebViewBootstrap(seed: seed) {
                    case .candidates(let candidates):
                        return candidates
                    case .noResult:
                        return []
                    case .blockedByVerification:
                        break
                    }
                }
                guard verificationAttempts < 2 else { throw CNKIError.blockedByVerification }
                verificationAttempts += 1
                verificationOperation = .search(seed)
                verificationPreparedOutput = nil
                if let webView,
                   let prepared = await recoverPreparedOutputIfPossible(for: .search(seed), in: webView),
                   case .search(let candidates) = prepared {
                    return candidates
                }
                try await requestVerification(
                    at: verificationURL(for: .search(seed), currentURL: nil),
                    title: verificationAttempts == 1 ? "需要继续知网会话" : "仍需继续知网会话",
                    message: "请在窗口中完成知网验证，并停留在包含目标文献的搜索结果页。页面恢复后会自动继续；如果没有自动关闭，也可以点击“继续检查”。",
                    continueLabel: "继续检查"
                )
                if let prepared = verificationPreparedOutput, case .search(let candidates) = prepared {
                    verificationOperation = nil
                    verificationPreparedOutput = nil
                    return candidates
                }
                verificationOperation = nil
                continue
            }
        }
    }

    func searchViaHiddenWebViewBootstrap(
        seed: MetadataResolutionSeed
    ) async -> HiddenSearchBootstrapResult {
        needsWebView = true

        do {
            let webView = try await requireWebView()
            let output = try await performOperation(.search(seed), in: webView)
            guard case .search(let candidates) = output else {
                return .noResult
            }
            if !candidates.isEmpty {
                cnkiDebugTrace(
                    "search hidden bootstrap resolved title=\(seed.title ?? seed.fileName) candidateCount=\(candidates.count)"
                )
                return .candidates(candidates)
            }
            cnkiDebugTrace(
                "search hidden bootstrap finished without candidates title=\(seed.title ?? seed.fileName)"
            )
            return .noResult
        } catch CNKIError.blockedByVerification {
            cnkiDebugTrace(
                "search hidden bootstrap blocked title=\(seed.title ?? seed.fileName)"
            )
            return .blockedByVerification
        } catch {
            cnkiDebugTrace(
                "search hidden bootstrap failed title=\(seed.title ?? seed.fileName) error=\(error.localizedDescription)"
            )
            return .noResult
        }
    }

    func performGridSearch(seed: MetadataResolutionSeed) async throws -> [MetadataCandidate] {
        let searchExpressions = Self.searchExpressions(for: seed)

        for (index, searchExpression) in searchExpressions.enumerated() {
            let candidates = try await performGridSearchRequest(
                seed: seed,
                searchExpression: searchExpression
            )
            if !candidates.isEmpty {
                return candidates
            }

            if index + 1 < searchExpressions.count {
                cnkiDebugTrace(
                    "performGridSearch 当前表达式无候选，降级重试 expression=\(searchExpression)"
                )
            }
        }

        throw CNKIError.parseFailed("知网搜索页没有返回可用候选。")
    }

    func performGridSearchRequest(
        seed: MetadataResolutionSeed,
        searchExpression: String
    ) async throws -> [MetadataCandidate] {
        // 知网搜索接口需要有效的会话 Cookie。若当前没有 Cookie，交给上层先尝试
        // 隐藏 WebView 建立会话；只有隐藏页面也明确进入拦截状态时，才会弹出可见验证。
        guard let cookieHeader = await cnkiCookieHeader(), !cookieHeader.isEmpty else {
            throw CNKIError.blockedByVerification
        }

        var request = URLRequest(url: Self.mainlandCNKISearchURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = Data(searchRequestBody(for: seed, searchExpression: searchExpression).utf8)
        request.setValue("kns.cnki.net", forHTTPHeaderField: "Host")
        request.setValue(ReaderExtractionManager.safariLikeUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,en-US;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://kns.cnki.net", forHTTPHeaderField: "Origin")
        request.setValue(searchReferer(for: seed), forHTTPHeaderField: "Referer")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await NetworkClient.session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 || statusCode == 403 else {
            throw CNKIError.navigationFailed("知网搜索接口返回 HTTP \(statusCode)")
        }

        guard let html = decodeCNKIHTML(from: data) else {
            if statusCode == 403 {
                throw CNKIError.blockedByVerification
            }
            throw CNKIError.parseFailed("知网搜索接口没有返回可解析内容。")
        }

        let candidates = try await extractSearchCandidates(
            seed: seed,
            fromHTML: html,
            baseURL: Self.mainlandCNKISearchURL
        )
        if !candidates.isEmpty {
            return candidates
        }

        if statusCode == 403 {
            throw CNKIError.blockedByVerification
        }

        if let verificationURL = exportVerificationURL(from: data) {
            let message = verificationURL.absoluteString.lowercased()
            if message.contains("captcha") || message.contains("verify") || message.contains("validate") {
                throw CNKIError.blockedByVerification
            }
        }
        return []
    }


    func extractSearchCandidates(seed: MetadataResolutionSeed, in webView: WKWebView) async throws -> [MetadataCandidate] {
        for _ in 0..<8 {
            let payload: SearchPayload = try await evaluateJSONScript(Self.searchExtractionScript, in: webView)
            let candidates = payload.candidates
                .compactMap {
                    MetadataResolution.buildCNKICandidate(
                        title: $0.title,
                        metaText: $0.metaText,
                        snippet: $0.snippet,
                        detailURL: $0.detailURL,
                        seed: seed,
                        cnkiExport: CNKIExportLocator(
                            exportID: $0.exportID,
                            dbname: $0.dbname,
                            filename: $0.filename
                        )
                    )
                }
                .sorted { $0.score > $1.score }

            if !candidates.isEmpty {
                let enriched = await enrichCandidatePreviews(candidates)
                cnkiDebugTrace(
                    "search DOM resolved url=\(webView.url?.absoluteString ?? "nil") title=\(seed.title ?? seed.fileName) candidateCount=\(candidates.count) blocked=\(payload.blocked) enrichedSnippetCount=\(enriched.filter { trimmedOrNil($0.snippet) != nil }.count)"
                )
                return enriched
            }
            if payload.emptyState {
                cnkiDebugTrace(
                    "search DOM empty-state url=\(webView.url?.absoluteString ?? "nil") title=\(seed.title ?? seed.fileName)"
                )
                return []
            }
            if payload.blocked {
                cnkiDebugTrace(
                    "search DOM blocked url=\(webView.url?.absoluteString ?? "nil") title=\(seed.title ?? seed.fileName) candidateCount=0"
                )
                throw CNKIError.blockedByVerification
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        cnkiDebugTrace(
            "search DOM unresolved url=\(webView.url?.absoluteString ?? "nil") title=\(seed.title ?? seed.fileName)"
        )
        return []
    }

    func extractSearchCandidates(seed: MetadataResolutionSeed, fromHTML html: String, baseURL: URL) async throws -> [MetadataCandidate] {
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

        let payload: SearchPayload = try await evaluateJSONScript(Self.searchExtractionScript, in: parserWebView)
        let candidates = payload.candidates
            .compactMap {
                MetadataResolution.buildCNKICandidate(
                    title: $0.title,
                    metaText: $0.metaText,
                    snippet: $0.snippet,
                    detailURL: $0.detailURL,
                    seed: seed,
                    cnkiExport: CNKIExportLocator(
                        exportID: $0.exportID,
                        dbname: $0.dbname,
                        filename: $0.filename
                    )
                )
            }
            .sorted { $0.score > $1.score }

        if !candidates.isEmpty {
            let enriched = await enrichCandidatePreviews(candidates)
            cnkiDebugTrace(
                "search HTML resolved baseURL=\(baseURL.absoluteString) title=\(seed.title ?? seed.fileName) candidateCount=\(candidates.count) blocked=\(payload.blocked) enrichedSnippetCount=\(enriched.filter { trimmedOrNil($0.snippet) != nil }.count)"
            )
            return enriched
        }
        if payload.emptyState {
            cnkiDebugTrace(
                "search HTML empty-state baseURL=\(baseURL.absoluteString) title=\(seed.title ?? seed.fileName)"
            )
            return []
        }
        if payload.blocked {
            cnkiDebugTrace(
                "search HTML blocked baseURL=\(baseURL.absoluteString) title=\(seed.title ?? seed.fileName)"
            )
            throw CNKIError.blockedByVerification
        }
        return candidates
    }


    nonisolated static func searchTitle(for seed: MetadataResolutionSeed) -> String? {
        if let rawTitle = seed.title?.swiftlib_nilIfBlank {
            let title = MetadataResolution.normalizeWhitespaceAndWidth(rawTitle)
            if let title = Self.trimmedOrNilValue(title) {
                return title
            }
        }
        let normalizedFileName = MetadataResolution.normalizeWhitespaceAndWidth(seed.fileName)
        if MetadataResolution.containsHanCharacters(normalizedFileName) {
            return Self.trimmedOrNilValue(normalizedFileName)
        }
        return nil
    }

    nonisolated static func searchAuthor(for seed: MetadataResolutionSeed) -> String? {
        guard let author = Self.trimmedOrNilValue(seed.firstAuthor),
              MetadataResolution.containsHanCharacters(author) else {
            return nil
        }

        if let normalized = MetadataResolution.extractLikelyAuthorName(from: author),
           Self.trimmedOrNilValue(normalized) != nil {
            return normalized
        }
        return nil
    }

    nonisolated static func searchKeyword(for seed: MetadataResolutionSeed) -> String? {
        if let title = searchTitle(for: seed) {
            return title
        }
        if let doi = Self.trimmedOrNilValue(seed.doi) {
            return doi
        }
        return Self.trimmedOrNilValue(MetadataResolution.normalizeWhitespaceAndWidth(seed.fileName))
    }

    nonisolated static func searchExpressions(for seed: MetadataResolutionSeed) -> [String] {
        let title = searchTitle(for: seed)
        let author = searchAuthor(for: seed)
        let withAuthor = cnkiSearchExpression(
            title: title,
            author: author,
            doi: seed.doi,
            fileName: seed.fileName
        )
        let titleOnly = cnkiSearchExpression(
            title: title,
            author: nil,
            doi: seed.doi,
            fileName: seed.fileName
        )

        var expressions: [String] = []
        for expression in [withAuthor, titleOnly] where !expression.isEmpty {
            if !expressions.contains(expression) {
                expressions.append(expression)
            }
        }
        return expressions
    }

    func searchRequestBody(for seed: MetadataResolutionSeed, searchExpression: String) -> String {
        let searchExpressionAside = searchExpression.replacingOccurrences(of: "'", with: "&#39;")

        let queryJSON: [String: Any] = [
            "Platform": "",
            "Resource": "CROSSDB",
            "Classid": "WD0FTY92",
            "Products": "",
            "QNode": [
                "QGroup": [
                    [
                        "Key": "Subject",
                        "Title": "",
                        "Logic": 0,
                        "Items": [
                            [
                                "Key": "Expert",
                                "Title": "",
                                "Logic": 0,
                                "Field": "EXPERT",
                                "Operator": 0,
                                "Value": searchExpression,
                                "Value2": ""
                            ]
                        ],
                        "ChildItems": []
                    ],
                    [
                        "Key": "ControlGroup",
                        "Title": "",
                        "Logic": 0,
                        "Items": [],
                        "ChildItems": []
                    ]
                ]
            ],
            "ExScope": "1",
            "SearchType": 4,
            "Rlang": "CHINESE",
            "KuaKuCode": "YSTT4HG0,LSTPFY1C,JUP3MUPD,MPMFIG1A,WQ0UVIAA,BLZOG7CK,PWFIRAGL,EMRPGLPA,NLBO1Z6R,NN3FJMUV",
            "SearchFrom": 1
        ]

        let form: [String: Any] = [
            "boolSearch": "true",
            "QueryJson": queryJSON,
            "pageNum": "1",
            "pageSize": "20",
            "sortField": "PT",
            "sortType": "desc",
            "dstyle": "listmode",
            "productStr": "YSTT4HG0,LSTPFY1C,RMJLXHZ3,JQIRZIYA,JUP3MUPD,1UR4K4HZ,BPBAFJ5S,R79MZMCB,MPMFIG1A,WQ0UVIAA,NB3BWEHK,XVLO76FD,HR1YT1Z9,BLZOG7CK,PWFIRAGL,EMRPGLPA,J708GVCE,ML4DRIDX,NLBO1Z6R,NN3FJMUV,",
            "aside": "(\(searchExpressionAside))",
            "searchFrom": "资源范围：总库;++中英文扩展;++时间范围：更新时间：不限;++",
            "CurPage": "1"
        ]
        return urlEncodedFormBody(form)
    }

    nonisolated static func cnkiSearchExpression(title: String?, author: String?, doi: String?, fileName: String) -> String {
        var clauses: [String] = []
        if let doi = Self.trimmedOrNilValue(doi) {
            clauses.append("DOI='\(doi)'")
        }
        if let normalizedTitle = Self.trimmedOrNilValue(title) {
            // 知网专家检索的 TI %= 对过长标题匹配效果差，截断到 60 字符
            let truncated = normalizedTitle.count > 60
                ? String(normalizedTitle.prefix(60))
                : normalizedTitle
            clauses.append("TI %= '\(truncated)'")
        }
        var expression = clauses.joined(separator: " OR ")
        if expression.isEmpty {
            let fallback = Self.trimmedOrNilValue(MetadataResolution.normalizeWhitespaceAndWidth(fileName)) ?? fileName
            expression = "TI %= '\(fallback)'"
        }
        if let author = Self.trimmedOrNilValue(author) {
            expression = "(\(expression)) AND AU='\(author)'"
        }
        return expression
    }

    func searchReferer(for seed: MetadataResolutionSeed) -> String {
        let keyword = Self.searchKeyword(for: seed) ?? MetadataResolution.normalizeWhitespaceAndWidth(seed.fileName)
        let encodedTitle = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        return "https://kns.cnki.net/kns8s/defaultresult/index?crossids=YSTT4HG0%2CLSTPFY1C%2CJUP3MUPD%2CMPMFIG1A%2CWQ0UVIAA%2CBLZOG7CK%2CPWFIRAGL%2CEMRPGLPA%2CNLBO1Z6R%2CNN3FJMUV&korder=SU&kw=\(encodedTitle)"
    }

    func urlEncodedFormBody(_ fields: [String: Any]) -> String {
        fields.map { key, value in
            let encodedValue: String
            if JSONSerialization.isValidJSONObject(value),
               let data = try? JSONSerialization.data(withJSONObject: value),
               let string = String(data: data, encoding: .utf8) {
                encodedValue = string
            } else {
                encodedValue = String(describing: value)
            }
            let escapedKey = formURLEncode(key)
            let escapedValue = formURLEncode(encodedValue)
            return "\(escapedKey)=\(escapedValue)"
        }
        .joined(separator: "&")
    }

    func formURLEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

}
