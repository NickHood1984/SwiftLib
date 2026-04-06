import Foundation
import OSLog
import SwiftLibCore
import WebKit
import CoreFoundation

private let cnkiMetadataLog = Logger(subsystem: "SwiftLib", category: "CNKIMetadata")

private func cnkiDebugTrace(_ message: String) {
    guard SwiftLibDebugLogging.metadataVerbose else { return }
    cnkiMetadataLog.notice("\(message, privacy: .public)")
    if let data = "[CNKIMetadata] \(message)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

@MainActor
final class CNKIMetadataProvider: NSObject, ObservableObject {
    enum CNKIError: LocalizedError {
        case webViewNotReady
        case busy
        case timedOut
        case navigationFailed(String)
        case blockedByVerification
        case verificationCancelled
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .webViewNotReady:
                return "知网抓取组件尚未就绪，请稍后再试。"
            case .busy:
                return "已有进行中的知网抓取任务。"
            case .timedOut:
                return "知网页面加载超时。"
            case .navigationFailed(let message):
                return "无法打开知网页面：\(message)"
            case .blockedByVerification:
                return "知网页面进入安全验证或登录拦截，暂时无法自动抓取。"
            case .verificationCancelled:
                return "已取消知网验证。"
            case .parseFailed(let message):
                return "知网页面解析失败：\(message)"
            }
        }
    }

    struct VerificationSession: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let title: String
        let message: String
        let continueLabel: String
    }

    @Published private(set) var isWorking = false
    @Published private(set) var verificationSession: VerificationSession?
    /// Set to `true` before any operation so the hosting view can lazily create the hidden WKWebView.
    @Published private(set) var needsWebView = false

    private static let sharedDataStore = WKWebsiteDataStore.default()
    private static let mainlandCNKIHomeURL = URL(string: "https://kns.cnki.net/kns8s/defaultresult/index")!
    private static let mainlandCNKISearchURL = URL(string: "https://kns.cnki.net/kns8s/brief/grid")!

    private enum PendingOperation {
        case search(MetadataResolutionSeed)
        case resolve(MetadataCandidate)
    }

    private enum OperationOutput {
        case search([MetadataCandidate])
        case resolve(AuthoritativeMetadataRecord)
    }

    private struct SearchPayload: Decodable {
        struct Candidate: Decodable {
            let title: String
            let detailURL: String
            let metaText: String
            let snippet: String?
            let exportID: String?
            let dbname: String?
            let filename: String?
        }

        let blocked: Bool
        let candidates: [Candidate]
    }

    private struct DetailPayload: Decodable {
        let blocked: Bool
        let blockedReason: String?
        let title: String?
        let authors: [String]
        let authorSource: String?
        let journal: String?
        let doi: String?
        let abstract: String?
        let volume: String?
        let issue: String?
        let firstPage: String?
        let lastPage: String?
        let yearText: String?
        let bodyText: String?
        let url: String?
    }

    struct PageAssessmentPayload: Decodable {
        let markerBlocked: Bool
        let searchRowCount: Int
        let hasDetailTitle: Bool
        let hasDetailAuthors: Bool
        let hasDetailSummary: Bool
        let hasVisibleDetailScaffold: Bool?
        let blockedReason: String?

        init(
            markerBlocked: Bool,
            searchRowCount: Int,
            hasDetailTitle: Bool,
            hasDetailAuthors: Bool,
            hasDetailSummary: Bool,
            hasVisibleDetailScaffold: Bool? = nil,
            blockedReason: String? = nil
        ) {
            self.markerBlocked = markerBlocked
            self.searchRowCount = searchRowCount
            self.hasDetailTitle = hasDetailTitle
            self.hasDetailAuthors = hasDetailAuthors
            self.hasDetailSummary = hasDetailSummary
            self.hasVisibleDetailScaffold = hasVisibleDetailScaffold
            self.blockedReason = blockedReason
        }
    }

    enum PageResolutionState: Equatable {
        case resolvedSearch
        case resolvedDetail
        case blocked
        case loadingOrUnknown

        var isReady: Bool {
            switch self {
            case .resolvedSearch, .resolvedDetail:
                return true
            case .blocked, .loadingOrUnknown:
                return false
            }
        }
    }

    private weak var webView: WKWebView?
    private var pendingOperation: PendingOperation?
    private var pendingContinuation: CheckedContinuation<OperationOutput, Error>?
    private var verificationContinuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var inspectionTask: Task<Void, Never>?
    private var lastNavigationStatusCode: Int?
    private var verificationOperation: PendingOperation?
    private var verificationPreparedOutput: OperationOutput?

    func configureWebView(_ configuration: WKWebViewConfiguration) {
        configuration.websiteDataStore = Self.sharedDataStore
    }

    func registerWebView(_ webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self
    }

    func continueVerification() {
        let continuation = verificationContinuation
        verificationContinuation = nil
        verificationSession = nil
        continuation?.resume()
    }

    func cancelVerification() {
        let continuation = verificationContinuation
        verificationContinuation = nil
        verificationSession = nil
        verificationOperation = nil
        verificationPreparedOutput = nil
        continuation?.resume(throwing: CNKIError.verificationCancelled)
    }

    func prepareVerificationResultIfPossible(from webView: WKWebView) async -> Bool {
        guard verificationPreparedOutput == nil, let operation = verificationOperation else {
            return verificationPreparedOutput != nil
        }

        do {
            switch operation {
            case .search(let seed):
                let candidates = try await extractSearchCandidates(seed: seed, in: webView)
                if !candidates.isEmpty {
                    verificationPreparedOutput = .search(candidates)
                }
            case .resolve(let candidate):
                let record = try await extractReference(candidate: candidate, in: webView)
                verificationPreparedOutput = .resolve(record)
            }
        } catch {
            // Ignore parse failures here and fall back to the normal retry path.
        }
        return verificationPreparedOutput != nil
    }

    func pageResolutionState(in webView: WKWebView) async -> PageResolutionState {
        do {
            let payload: PageAssessmentPayload = try await evaluateJSONScript(Self.pageAssessmentScript, in: webView)
            let state = Self.pageResolutionState(from: payload)
            cnkiDebugTrace(
                "pageState url=\(webView.url?.absoluteString ?? "nil") state=\(String(describing: state)) blocked=\(payload.markerBlocked) reason=\(payload.blockedReason ?? "nil") searchRows=\(payload.searchRowCount) detailTitle=\(payload.hasDetailTitle) detailAuthors=\(payload.hasDetailAuthors) detailSummary=\(payload.hasDetailSummary) scaffold=\(payload.hasVisibleDetailScaffold ?? false)"
            )
            return state
        } catch {
            cnkiDebugTrace(
                "pageState evaluate failed url=\(webView.url?.absoluteString ?? "nil") error=\(error.localizedDescription)"
            )
            return .loadingOrUnknown
        }
    }

    nonisolated static func pageResolutionState(from payload: PageAssessmentPayload) -> PageResolutionState {
        if payload.searchRowCount > 0 {
            return .resolvedSearch
        }
        let hasVisibleDetailScaffold = payload.hasVisibleDetailScaffold
            ?? (payload.hasDetailTitle && (payload.hasDetailAuthors || payload.hasDetailSummary))
        if hasVisibleDetailScaffold || payload.hasDetailTitle {
            return .resolvedDetail
        }
        if payload.markerBlocked {
            return .blocked
        }
        return .loadingOrUnknown
    }

    func search(seed: MetadataResolutionSeed) async throws -> [MetadataCandidate] {
        try await searchViaGridRequest(seed: seed)
    }

    func fetchAuthoritativeRecord(candidate: MetadataCandidate) async throws -> AuthoritativeMetadataRecord {
        if candidate.cnkiExport?.hasUsableExport == true,
           let exportRecord = try await resolveViaExportFallback(candidate: candidate) {
            return exportRecord
        }

        do {
            let result = try await runOperation(.resolve(candidate))
            guard case .resolve(let record) = result else {
                throw CNKIError.parseFailed("知网详情返回了意外结果。")
            }
            return record
        } catch {
            guard shouldAttemptExportFallback(after: error),
                  let record = try await resolveViaExportFallback(candidate: candidate) else {
                throw error
            }
            return record
        }
    }

    func resolve(candidate: MetadataCandidate) async throws -> Reference {
        try await fetchAuthoritativeRecord(candidate: candidate).reference
    }

    func fetchAuthoritativeRecord(detailURL: URL) async throws -> AuthoritativeMetadataRecord {
        try await fetchAuthoritativeRecord(
            candidate: MetadataCandidate(
                source: .cnki,
                title: detailURL.lastPathComponent,
                detailURL: detailURL.absoluteString,
                score: 1
            )
        )
    }

    func resolve(detailURL: URL) async throws -> Reference {
        try await fetchAuthoritativeRecord(detailURL: detailURL).reference
    }

    private func requireWebView() async throws -> WKWebView {
        for _ in 0..<80 {
            if let webView { return webView }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw CNKIError.webViewNotReady
    }

    private func recoverPreparedOutputIfPossible(
        for operation: PendingOperation,
        in webView: WKWebView
    ) async -> OperationOutput? {
        verificationOperation = operation
        verificationPreparedOutput = nil
        guard await prepareVerificationResultIfPossible(from: webView),
              let prepared = verificationPreparedOutput else {
            return nil
        }
        verificationOperation = nil
        verificationPreparedOutput = nil
        return prepared
    }

    private func recoverResolvedRecordIfPossible(candidate: MetadataCandidate) async -> AuthoritativeMetadataRecord? {
        guard let webView else { return nil }
        // Only attempt recovery if the WebView is actually showing this candidate's detail page.
        // Otherwise we'd extract stale data from whatever page was previously loaded.
        if let currentURL = webView.url,
           let candidateURL = URL(string: candidate.detailURL),
           !Self.urlMatchesCNKIDetail(currentURL, candidateURL) {
            return nil
        }
        guard let prepared = await recoverPreparedOutputIfPossible(for: .resolve(candidate), in: webView),
              case .resolve(let record) = prepared else {
            return nil
        }
        return record
    }

    private static func urlMatchesCNKIDetail(_ current: URL, _ candidate: URL) -> Bool {
        guard current.host?.lowercased() == candidate.host?.lowercased() else { return false }
        let currentPath = current.path.lowercased()
        let candidatePath = candidate.path.lowercased()
        guard currentPath == candidatePath else { return false }
        let currentParams = URLComponents(url: current, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let candidateParams = URLComponents(url: candidate, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let currentMap = Dictionary(currentParams.map { ($0.name.lowercased(), $0.value?.lowercased() ?? "") }, uniquingKeysWith: { _, b in b })
        let candidateMap = Dictionary(candidateParams.map { ($0.name.lowercased(), $0.value?.lowercased() ?? "") }, uniquingKeysWith: { _, b in b })
        for (key, value) in candidateMap {
            if currentMap[key] != value { return false }
        }
        return true
    }

    private func searchViaGridRequest(seed: MetadataResolutionSeed) async throws -> [MetadataCandidate] {
        var verificationAttempts = 0

        while true {
            do {
                return try await performGridSearch(seed: seed)
            } catch CNKIError.blockedByVerification {
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

    private func performGridSearch(seed: MetadataResolutionSeed) async throws -> [MetadataCandidate] {
        var request = URLRequest(url: Self.mainlandCNKISearchURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = Data(searchRequestBody(for: seed).utf8)
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
        if let cookieHeader = await cnkiCookieHeader(), !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
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

        throw CNKIError.parseFailed("知网搜索页没有返回可用候选。")
    }

    private func runOperation(_ operation: PendingOperation) async throws -> OperationOutput {
        needsWebView = true
        let webView = try await requireWebView()
        var verificationAttempts = 0

        while true {
            do {
                return try await performOperation(operation, in: webView)
            } catch CNKIError.blockedByVerification {
                guard verificationAttempts < 2 else { throw CNKIError.blockedByVerification }
                verificationAttempts += 1
                verificationOperation = operation
                verificationPreparedOutput = nil
                if let prepared = await recoverPreparedOutputIfPossible(for: operation, in: webView) {
                    return prepared
                }
                try await requestVerification(
                    at: verificationURL(for: operation, currentURL: webView.url),
                    title: verificationAttempts == 1 ? "需要继续知网会话" : "仍需继续知网会话",
                    message: "请在窗口中完成知网验证，并停留在目标文献详情页。页面恢复后会自动继续；如果没有自动关闭，也可以点击“继续检查”。",
                    continueLabel: "继续检查"
                )
                if let prepared = verificationPreparedOutput {
                    verificationOperation = nil
                    verificationPreparedOutput = nil
                    return prepared
                }
                verificationOperation = nil
                continue
            }
        }
    }

    private func performOperation(_ operation: PendingOperation, in webView: WKWebView) async throws -> OperationOutput {
        try await withCheckedThrowingContinuation { continuation in
            guard pendingContinuation == nil else {
                continuation.resume(throwing: CNKIError.busy)
                return
            }

            pendingOperation = operation
            pendingContinuation = continuation
            isWorking = true
            lastNavigationStatusCode = nil

            timeoutTask?.cancel()
            inspectionTask?.cancel()
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard !Task.isCancelled else { return }
                self.fail(CNKIError.timedOut)
            }

            webView.stopLoading()
            webView.load(URLRequest(url: url(for: operation)))
        }
    }

    private func url(for operation: PendingOperation) -> URL {
        switch operation {
        case .search(let seed):
            var components = URLComponents(url: Self.mainlandCNKIHomeURL, resolvingAgainstBaseURL: false)!
            let query = searchKeyword(for: seed) ?? MetadataResolution.normalizeWhitespaceAndWidth(seed.fileName)
            components.queryItems = [URLQueryItem(name: "kw", value: query)]
            return components.url!
        case .resolve(let candidate):
            return URL(string: candidate.detailURL)!
        }
    }

    private func verificationURL(for operation: PendingOperation, currentURL: URL?) -> URL {
        if let currentURL {
            return currentURL
        }
        switch operation {
        case .search:
            return Self.mainlandCNKIHomeURL
        case .resolve(let candidate):
            return URL(string: candidate.detailURL) ?? Self.mainlandCNKIHomeURL
        }
    }

    private func scheduleInspection(for webView: WKWebView) {
        inspectionTask?.cancel()
        inspectionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard let self, self.pendingContinuation != nil, self.webView === webView else { return }
            await self.inspectLoadedPage(in: webView)
        }
    }

    private func inspectLoadedPage(in webView: WKWebView) async {
        guard let operation = pendingOperation else { return }

        do {
            switch operation {
            case .search(let seed):
                let candidates = try await extractSearchCandidates(seed: seed, in: webView)
                complete(.search(candidates))
            case .resolve(let candidate):
                let record = try await extractReference(candidate: candidate, in: webView)
                complete(.resolve(record))
            }
        } catch {
            fail(error)
        }
    }

    private func extractSearchCandidates(seed: MetadataResolutionSeed, in webView: WKWebView) async throws -> [MetadataCandidate] {
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

    private func extractSearchCandidates(seed: MetadataResolutionSeed, fromHTML html: String, baseURL: URL) async throws -> [MetadataCandidate] {
        let parserWebView = WKWebView(frame: .zero, configuration: {
            let configuration = WKWebViewConfiguration()
            HiddenWKWebViewMediaGuard.configure(configuration)
            configureWebView(configuration)
            return configuration
        }())
        parserWebView.customUserAgent = ReaderExtractionManager.safariLikeUserAgent

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
        if payload.blocked {
            cnkiDebugTrace(
                "search HTML blocked baseURL=\(baseURL.absoluteString) title=\(seed.title ?? seed.fileName)"
            )
            throw CNKIError.blockedByVerification
        }
        return candidates
    }

    private func enrichCandidatePreviews(_ candidates: [MetadataCandidate], limit: Int = 3) async -> [MetadataCandidate] {
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

    private func shouldHydrateCandidatePreview(_ candidate: MetadataCandidate) -> Bool {
        guard candidate.source == .cnki else { return false }
        guard !candidate.detailURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let snippet = trimmedOrNil(candidate.snippet) else { return true }
        if snippet.count < 80 { return true }
        return snippet.hasSuffix("...") || snippet.hasSuffix("…")
    }

    private func hydrateCandidatePreview(_ candidate: MetadataCandidate) async -> MetadataCandidate {
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

    private func fetchDetailPreviewPayload(for candidate: MetadataCandidate) async throws -> DetailPayload? {
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

        let (data, response) = try await URLSession.shared.data(for: request)
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

    private func extractDetailPayload(fromHTML html: String, baseURL: URL) async throws -> DetailPayload {
        let parserWebView = WKWebView(frame: .zero, configuration: {
            let configuration = WKWebViewConfiguration()
            HiddenWKWebViewMediaGuard.configure(configuration)
            configureWebView(configuration)
            return configuration
        }())
        parserWebView.customUserAgent = ReaderExtractionManager.safariLikeUserAgent

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

    private func extractReference(candidate: MetadataCandidate, in webView: WKWebView) async throws -> AuthoritativeMetadataRecord {
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

    nonisolated static func resolveJournal(extractedJournal: String?, fallbackCandidate: MetadataCandidate) -> String? {
        MetadataResolution.normalizeJournalName(extractedJournal)
            ?? MetadataResolution.normalizeJournalName(fallbackCandidate.journal)
    }

    private func reference(
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

    private func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedCandidateSnippet(_ value: String?) -> String? {
        guard let value = trimmedOrNil(value) else { return nil }
        let normalized = MetadataResolution.normalizeWhitespaceAndWidth(value)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(320))
    }

    private func shouldReplaceCandidateSnippet(current: String?, replacement: String?) -> Bool {
        guard let replacement = trimmedOrNil(replacement) else { return false }
        guard let current = trimmedOrNil(current) else { return true }
        if current.count < 80 { return true }
        if current.hasSuffix("...") || current.hasSuffix("…") { return true }
        return replacement.count > current.count + 40
    }

    private func resolvedCNKIRecordKey(for candidate: MetadataCandidate) -> String? {
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

    private func exportEvidence(
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

    private func isBlank(_ value: String?) -> Bool {
        trimmedOrNil(value) == nil
    }

    private func extractDOI(from text: String) -> String? {
        let pattern = #"(10\.\d{4,9}\/[^\s]+[^\s\.,;\]\)])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private func extractAbstract(from text: String) -> String? {
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

    private func inferWorkKind(from text: String, fallbackCandidate: MetadataCandidate) -> MetadataWorkKind {
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

    private func resolvedReferenceType(for workKind: MetadataWorkKind, fallbackCandidate: MetadataCandidate) -> ReferenceType {
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

    private func enrich(_ reference: Reference, fallbackCandidate: MetadataCandidate, sourceText: String) -> Reference {
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

    private func extractISBN(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [#"(?:ISBN(?:-13)?)[\s:：]*([0-9Xx\-]{10,20})"#]
        )?.replacingOccurrences(of: " ", with: "")
    }

    private func extractISSN(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [#"(?:ISSN)[\s:：]*([0-9]{4}-[0-9Xx]{4})"#]
        )
    }

    private func extractPublisher(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [
                #"出版社[\s:：]*([^\n]{2,40})"#,
                #"出版单位[\s:：]*([^\n]{2,40})"#
            ]
        )
    }

    private func extractPublisherPlace(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [
                #"出版地[\s:：]*([^\n]{2,20})"#,
                #"出版地点[\s:：]*([^\n]{2,20})"#
            ]
        )
    }

    private func extractInstitution(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [
                #"(?:学位授予单位|授予单位|培养单位|授予机构)[\s:：]*([^\n]{2,80})"#,
                #"(?:university|institution)[\s:：]*([^\n]{2,80})"#
            ]
        )
    }

    private func extractThesisGenre(from text: String) -> String? {
        if text.contains("博士学位论文") {
            return "Doctoral dissertation"
        }
        if text.contains("硕士学位论文") {
            return "Master's thesis"
        }
        return nil
    }

    private func extractConferenceName(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [
                #"会议名称[\s:：]*([^\n]{4,120})"#,
                #"conference name[\s:：]*([^\n]{4,120})"#
            ]
        )
    }

    private func extractNumberOfPages(from text: String) -> String? {
        firstRegexCapture(
            in: text,
            patterns: [
                #"总页数[\s:：]*([0-9]{1,5})"#,
                #"页数[\s:：]*([0-9]{1,5})"#
            ]
        )
    }

    private func searchTitle(for seed: MetadataResolutionSeed) -> String? {
        if let rawTitle = seed.title?.swiftlib_nilIfBlank {
            let title = MetadataResolution.normalizeWhitespaceAndWidth(rawTitle)
            if let title = trimmedOrNil(title) {
                return title
            }
        }
        let normalizedFileName = MetadataResolution.normalizeWhitespaceAndWidth(seed.fileName)
        if MetadataResolution.containsHanCharacters(normalizedFileName) {
            return trimmedOrNil(normalizedFileName)
        }
        return nil
    }

    private func searchAuthor(for seed: MetadataResolutionSeed) -> String? {
        guard let author = trimmedOrNil(seed.firstAuthor) else { return nil }
        if MetadataResolution.containsHanCharacters(author) {
            return author
        }
        return nil
    }

    private func searchKeyword(for seed: MetadataResolutionSeed) -> String? {
        if let title = searchTitle(for: seed) {
            return title
        }
        if let doi = trimmedOrNil(seed.doi) {
            return doi
        }
        return trimmedOrNil(MetadataResolution.normalizeWhitespaceAndWidth(seed.fileName))
    }

    private func searchRequestBody(for seed: MetadataResolutionSeed) -> String {
        let title = searchTitle(for: seed)
        let searchExpression = cnkiSearchExpression(title: title, author: searchAuthor(for: seed), doi: seed.doi, fileName: seed.fileName)
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
            "sortField": "",
            "sortType": "",
            "dstyle": "listmode",
            "productStr": "YSTT4HG0,LSTPFY1C,RMJLXHZ3,JQIRZIYA,JUP3MUPD,1UR4K4HZ,BPBAFJ5S,R79MZMCB,MPMFIG1A,WQ0UVIAA,NB3BWEHK,XVLO76FD,HR1YT1Z9,BLZOG7CK,PWFIRAGL,EMRPGLPA,J708GVCE,ML4DRIDX,NLBO1Z6R,NN3FJMUV,",
            "aside": "(\(searchExpressionAside))",
            "searchFrom": "资源范围：总库;++中英文扩展;++时间范围：更新时间：不限;++",
            "CurPage": "1"
        ]
        return urlEncodedFormBody(form)
    }

    private func cnkiSearchExpression(title: String?, author: String?, doi: String?, fileName: String) -> String {
        var clauses: [String] = []
        if let doi = trimmedOrNil(doi) {
            clauses.append("DOI='\(doi)'")
        }
        if let normalizedTitle = trimmedOrNil(title) {
            clauses.append("TI %= '\(normalizedTitle)'")
        }
        var expression = clauses.joined(separator: " OR ")
        if expression.isEmpty {
            let fallback = trimmedOrNil(MetadataResolution.normalizeWhitespaceAndWidth(fileName)) ?? fileName
            expression = "TI %= '\(fallback)'"
        }
        if let author = trimmedOrNil(author) {
            expression = "(\(expression)) AND AU='\(author)'"
        }
        return expression
    }

    private func searchReferer(for seed: MetadataResolutionSeed) -> String {
        let keyword = searchKeyword(for: seed) ?? MetadataResolution.normalizeWhitespaceAndWidth(seed.fileName)
        let encodedTitle = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        return "https://kns.cnki.net/kns8s/defaultresult/index?crossids=YSTT4HG0%2CLSTPFY1C%2CJUP3MUPD%2CMPMFIG1A%2CWQ0UVIAA%2CBLZOG7CK%2CPWFIRAGL%2CEMRPGLPA%2CNLBO1Z6R%2CNN3FJMUV&korder=SU&kw=\(encodedTitle)"
    }

    private func urlEncodedFormBody(_ fields: [String: Any]) -> String {
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

    private func formURLEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func decodeCNKIHTML(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
            return utf8
        }
        if let gb18030 = String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))), !gb18030.isEmpty {
            return gb18030
        }
        return String(data: data, encoding: .unicode)
    }

    private func requestVerification(
        at url: URL,
        title: String,
        message: String,
        continueLabel: String
    ) async throws {
        guard verificationContinuation == nil else {
            throw CNKIError.busy
        }

        cnkiDebugTrace(
            "requestVerification title=\(title) url=\(url.absoluteString) message=\(message)"
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            verificationContinuation = continuation
            verificationSession = VerificationSession(
                url: url,
                title: title,
                message: message,
                continueLabel: continueLabel
            )
        }
    }

    private func shouldAttemptExportFallback(after error: Error) -> Bool {
        guard let cnkiError = error as? CNKIError else { return false }
        switch cnkiError {
        case .blockedByVerification, .parseFailed, .navigationFailed:
            return true
        case .webViewNotReady, .busy, .timedOut, .verificationCancelled:
            return false
        }
    }

    private func resolveViaExportFallback(candidate: MetadataCandidate) async throws -> AuthoritativeMetadataRecord? {
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

    private func fetchCNKIExportText(locator: CNKIExportLocator, referer: String) async throws -> String? {
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

            let (data, response) = try await URLSession.shared.data(for: request)
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
    private func exportRequestBody(for locator: CNKIExportLocator) -> String? {
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

    private func cnkiCookieHeader() async -> String? {
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

    private func exportVerificationURL(from data: Data) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String,
              let url = URL(string: message),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private func exportText(from data: Data) -> String? {
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

    private func sanitizeExportText(_ raw: String) -> String {
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

    private func record(fromExportText text: String, fallbackCandidate: MetadataCandidate) -> AuthoritativeMetadataRecord? {
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
            let authors = AuthorName.parseList(
                rawAuthors
                    .replacingOccurrences(of: "；", with: ";")
                    .replacingOccurrences(of: "，", with: ",")
            )
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

    private func firstRegexCapture(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let value = String(text[range])
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func evaluateJSONScript<T: Decodable>(_ script: String, in webView: WKWebView) async throws -> T {
        let rawValue = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }

        guard let json = rawValue as? String, let data = json.data(using: .utf8) else {
            throw CNKIError.parseFailed("知网页面没有返回可解析数据。")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func complete(_ output: OperationOutput) {
        let continuation = pendingContinuation
        pendingContinuation = nil
        pendingOperation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        inspectionTask?.cancel()
        inspectionTask = nil
        isWorking = false
        continuation?.resume(returning: output)
    }

    private func fail(_ error: Error) {
        let continuation = pendingContinuation
        pendingContinuation = nil
        pendingOperation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        inspectionTask?.cancel()
        inspectionTask = nil
        isWorking = false
        webView?.stopLoading()
        continuation?.resume(throwing: error)
    }

    private static let pageAssessmentScript = #"""
    (() => {
      const normalize = (value) => String(value || "").replace(/\s+/g, " ").trim();
      const isVisible = (el) => {
        if (!el) return false;
        const style = window.getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden') return false;
        const rect = el.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      };
      const cleanAuthor = (value) => normalize(value)
        .replace(/[\d０-９¹²³⁴⁵⁶⁷⁸⁹]+$/g, '')
        .replace(/[\*†‡#]+$/g, '')
        .trim();
      const isLikelyAuthorToken = (value) => {
        const cleaned = cleanAuthor(value);
        if (!cleaned) return false;
        return /^[\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?$/.test(cleaned)
          || /^[A-Za-z][A-Za-z .'-]{1,60}$/.test(cleaned);
      };
      const isLikelyAuthorLine = (line) => {
        const normalized = normalize(line);
        if (!normalized) return false;
        const numberedMatches = Array.from(
          normalized.matchAll(/([\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?)(?=\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹])/g)
        )
          .map((match) => cleanAuthor(match[1]))
          .filter(isLikelyAuthorToken);
        if (numberedMatches.length >= 2) return true;
        const segments = normalized
          .split(/[，,；;、|\s]+/)
          .map(cleanAuthor)
          .filter(Boolean);
        return segments.length >= 2 && segments.every(isLikelyAuthorToken);
      };
      const isSuspiciousTitle = (value) => {
        const normalized = normalize(value);
        if (!normalized || normalized.length > 160) return true;
        const lowered = normalized.toLowerCase();
        const badTokens = ['cnki', '中国知网', 'network first', 'doi', 'journal', 'issn', 'online first'];
        const exactBadTitles = ['自动登录', '用户登录', '机构用户登录', '安全验证', '访问异常', '异常访问', '验证码'];
        if (badTokens.some((token) => lowered.includes(token))) return true;
        if (exactBadTitles.includes(normalized)) return true;
        if (normalized.length <= 12 && (normalized.includes('登录') || normalized.includes('验证'))) return true;
        if (lowered.startsWith('author') || lowered.startsWith('title')) return true;
        if (/^\d+$/.test(normalized)) return true;
        return false;
      };
      const rawPageText = String(document.body?.innerText || "");
      const marker = normalize((document.title || "") + " " + rawPageText.slice(0, 1800));
      const hasVisibleVerificationUI = Array.from(document.querySelectorAll('input, iframe, img, div, span, p, a, button'))
        .filter(isVisible)
        .some((el) => {
          const text = normalize(el.innerText || el.textContent || "");
          const hint = normalize(`${el.className || ''} ${el.id || ''} ${el.getAttribute?.('placeholder') || ''} ${el.getAttribute?.('aria-label') || ''}`).toLowerCase();
          return (!!text && text.length <= 120 && /安全验证|请完成验证|验证码|访问异常|异常访问|验证后继续访问/.test(text))
            || /(captcha|verify|verification)/.test(hint);
        });
      const blockedSignals = /安全验证|请完成验证|验证码|访问异常|异常访问|验证后继续访问|机构用户登录/.test(marker) || hasVisibleVerificationUI;
      const searchRowCount = document.querySelectorAll('table.result-table-list > tbody > tr, .result-table-list tbody tr, .result-table tbody tr, tr[data-dbcode]').length;
      const lines = rawPageText
        .replace(/\r/g, '')
        .split(/\n+/)
        .map(normalize)
        .filter(Boolean)
        .slice(0, 40);
      const contextualTitle = lines.find((line) =>
        line.length >= 6
        && line.length <= 80
        && /[\u3400-\u9FFF]/.test(line)
        && !isLikelyAuthorLine(line)
        && !/^(文献知网节|摘要|关键词|基金资助|专辑|专题|分类号|DOI|doi)/.test(line)
        && !/[0-9]{4}.*\([0-9]{2}\)|查看该刊数据库收录/.test(line)
        && !/[:：]/.test(line)
      ) || "";
      const headingTitles = Array.from(document.querySelectorAll('.wx-tit > h1, .xx_title > h1, .title > h1, .brief h1, h1'))
        .filter(isVisible)
        .map((el) => normalize(el.innerText || el.textContent || ""))
        .filter(Boolean);
      const titleCandidates = [
        document.querySelector('meta[name="citation_title"]')?.getAttribute('content'),
        ...headingTitles,
        contextualTitle,
      ]
        .map(normalize)
        .filter((value) => !!value && !isLikelyAuthorLine(value));
      const visibleTitle = titleCandidates.find((value) => !isSuspiciousTitle(value)) || titleCandidates[0] || "";
      const hasDetailTitle = !!visibleTitle && !isSuspiciousTitle(visibleTitle);
      const hasDetailAuthors = document.querySelectorAll(
        '.author a, .authors a, .wx-tit .author a, .author-list a, #authorpart a, .brief .author a, .xx_title .author a, meta[name="citation_author"]'
      ).length > 0 || /[\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹]/.test(rawPageText.slice(0, 1600));
      const hasDetailSummary = !!document.querySelector('#ChDivSummary, .summary, .abstract, .abstract-text')
        || /(?:摘要|abstract)\s*[:：]/i.test(rawPageText.slice(0, 4000));
      const hasVisibleDetailScaffold = hasDetailTitle && (hasDetailAuthors || hasDetailSummary);
      const markerBlocked = blockedSignals && !hasVisibleDetailScaffold;
      return JSON.stringify({
        markerBlocked,
        searchRowCount,
        hasDetailTitle,
        hasDetailAuthors,
        hasDetailSummary,
        hasVisibleDetailScaffold,
        blockedReason: markerBlocked ? (hasVisibleVerificationUI ? 'verification-ui' : 'verification-marker') : null
      });
    })();
    """#

    private static let searchExtractionScript = #"""
    (() => {
      const normalize = (value) => String(value || "").replace(/\s+/g, " ").trim();
      const pageText = normalize(document.body?.innerText || "");
      const marker = normalize((document.title || "") + " " + pageText.slice(0, 4000));
      const blocked = /安全验证|请完成验证|验证码|访问异常|异常访问|验证后继续访问|登录后可用|登录查看全文|机构用户登录/.test(marker);
      const seen = new Set();
      const candidates = [];

      const firstText = (container, selectors) => {
        for (const selector of selectors) {
          const el = container?.querySelector?.(selector);
          const value = normalize(el?.textContent || el?.innerText || "");
          if (value) return value;
        }
        return "";
      };

      for (const anchor of Array.from(document.querySelectorAll('a[href], a[data-href]'))) {
        const rawHref = anchor.getAttribute('href') || anchor.getAttribute('data-href') || '';
        if (!rawHref || rawHref.startsWith('javascript:')) continue;

        let href = '';
        try {
          href = new URL(rawHref, location.href).href;
        } catch {
          continue;
        }

        if (!/(detail|KCMS|kcms2\/article\/abstract|detail\.aspx|kns\/detail)/i.test(href)) continue;

        const title = normalize(anchor.textContent || anchor.getAttribute('title') || "");
        if (!title || title.length < 4) continue;

        const container = anchor.closest('tr, li, article, .result-table-list, .result-table, .list-item, .record-item, .item, .brief, .result-item') || anchor.parentElement || document.body;
        const authorText = firstText(container, ['td.author', '.author', '.authors', '[class*="author"]']);
        const sourceText = firstText(container, ['td.source', '.source', '.journal', '[class*="source"]']);
        const dateText = firstText(container, ['td.date', '.date', '.year', '[class*="date"]']);
        const citationText = firstText(container, ['td.quote', '.quote', '.citation', '[class*="quote"]']);
        const metaText = [authorText, sourceText, dateText, citationText]
          .filter(Boolean)
          .join(' | ');
        const snippetEl = container?.querySelector?.('.abstract, .summary, .brief, .item-summary, .item-abstract, p');
        const snippet = normalize(snippetEl?.textContent || "");
        const exportNode = container?.querySelector?.('[data-dbname][data-filename]');
        const exportIDNode = container?.querySelector?.('td.seq input, .seq input, input[value]');
        const exportID = normalize(exportIDNode?.value || exportIDNode?.getAttribute?.('value') || "");
        const dbname = normalize(exportNode?.getAttribute?.('data-dbname') || "");
        const filename = normalize(exportNode?.getAttribute?.('data-filename') || "");
        const key = href + '|' + title;
        if (seen.has(key)) continue;
        seen.add(key);
        candidates.push({
          title,
          detailURL: href,
          metaText,
          snippet: snippet || null,
          exportID: exportID || null,
          dbname: dbname || null,
          filename: filename || null
        });
      }

      return JSON.stringify({
        blocked,
        candidates: candidates.slice(0, 20)
      });
    })();
    """#

    private static let detailExtractionScript = #"""
    (() => {
      const normalize = (value) => String(value || "").replace(/\s+/g, " ").trim();
      const unique = (values) => Array.from(new Set(values.filter(Boolean)));
      const rawPageText = String(document.body?.innerText || "");
      const pageText = normalize(rawPageText);
      const marker = normalize((document.title || "") + " " + pageText.slice(0, 1800));
      const isSuspiciousTitle = (value) => {
        const normalized = normalize(value);
        if (!normalized || normalized.length > 160) return true;
        const lowered = normalized.toLowerCase();
        const badTokens = ['cnki', '中国知网', 'network first', 'doi', 'journal', 'issn', 'online first'];
        const exactBadTitles = ['自动登录', '用户登录', '机构用户登录', '安全验证', '访问异常', '异常访问', '验证码'];
        if (badTokens.some((token) => lowered.includes(token))) return true;
        if (exactBadTitles.includes(normalized)) return true;
        if (normalized.length <= 12 && (normalized.includes('登录') || normalized.includes('验证'))) return true;
        if (lowered.startsWith('author') || lowered.startsWith('title')) return true;
        if (/^\d+$/.test(normalized)) return true;
        return false;
      };

      const metaValues = (names) => {
        const result = [];
        for (const name of names) {
          for (const el of Array.from(document.querySelectorAll(`meta[name="${name}"], meta[property="${name}"], meta[itemprop="${name}"]`))) {
            const value = normalize(el.getAttribute('content') || el.content || "");
            if (value) result.push(value);
          }
        }
        return Array.from(new Set(result));
      };

      const cleanAuthor = (value) => normalize(value)
        .replace(/[\d０-９¹²³⁴⁵⁶⁷⁸⁹]+$/g, '')
        .replace(/[\*†‡#]+$/g, '')
        .trim();
      const institutionLike = (value) => /大学|学院|研究所|研究院|管理局|水文局|实验室|中心|医院|部门|工程|水利部|出版社|编辑部|有限公司|股份有限公司|信息中心|勘测设计|研究院|集团|公司/.test(value);
      const authorNoiseLike = (value) => /印刷版|打印版|作者简介|基金资助|关键词|摘要|下载|引用|分享|收藏|导出|扫码|阅读|自动登录|安全验证|查看全文|AI/.test(value);
      const isLikelyAuthorToken = (value) => {
        const cleaned = cleanAuthor(value);
        if (!cleaned) return false;
        if (authorNoiseLike(cleaned) || institutionLike(cleaned) || isSuspiciousTitle(cleaned)) return false;
        return /^[\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?$/.test(cleaned)
          || /^[A-Za-z][A-Za-z .'-]{1,60}$/.test(cleaned);
      };
      const parseAuthorTokens = (line) => unique(
        String(line || '')
          .split(/[，,；;、|]/)
          .flatMap((part) => part.split(/\s+/))
          .map(cleanAuthor)
          .filter(isLikelyAuthorToken)
      );
      const isLikelyAuthorLine = (line) => {
        const normalized = normalize(line);
        if (!normalized) return false;
        if (/摘要|关键词|基金资助|Abstract|Key words/i.test(normalized)) return false;
        const numberedMatches = Array.from(
          normalized.matchAll(/([\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?)(?=\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹])/g)
        )
          .map((match) => cleanAuthor(match[1]))
          .filter(isLikelyAuthorToken);
        if (numberedMatches.length >= 2) return true;

        const segments = normalized
          .split(/[，,；;、|\s]+/)
          .map(cleanAuthor)
          .filter(Boolean);
        if (segments.length >= 2 && segments.every(isLikelyAuthorToken)) {
          return true;
        }

        const parsed = parseAuthorTokens(normalized);
        return parsed.length >= 3;
      };

      const extractTitleFromContext = () => {
        const lines = rawPageText
          .replace(/\r/g, '')
          .split(/\n+/)
          .map(normalize)
          .filter(Boolean);

        const looksLikeAuthorLine = (line) =>
          /[\u3400-\u9FFF]{2,4}\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹]/.test(line)
          && /[\u3400-\u9FFF]{2,4}\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹].*[\u3400-\u9FFF]{2,4}\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹]/.test(line);

        const badTitleTokens = /^(文献知网节|摘要|关键词|基金资助|专辑|专题|分类号|DOI|doi)/;

        for (let index = 0; index < lines.length; index += 1) {
          const line = lines[index];
          if (line.length < 6 || line.length > 80) continue;
          if (!/[\u3400-\u9FFF]/.test(line)) continue;
          if (badTitleTokens.test(line)) continue;
          if (isLikelyAuthorLine(line)) continue;
          if (/[0-9]{4}.*\([0-9]{2}\)|查看该刊数据库收录/.test(line)) continue;
          if (/[:：]/.test(line)) continue;

          const next = lines[index + 1] || '';
          const nextNext = lines[index + 2] || '';
          if (looksLikeAuthorLine(next) || /^(摘要|关键词)/.test(next) || /^(摘要|关键词)/.test(nextNext)) {
            return line;
          }
        }

        return "";
      };

      const collectTexts = (selectors, transform = normalize) => {
        const values = [];
        for (const selector of selectors) {
          for (const el of Array.from(document.querySelectorAll(selector))) {
            const text = transform(el.textContent || el.innerText || "");
            if (text) values.push(text);
          }
        }
        return unique(values);
      };

      const extractElementText = (el) => {
        if (!el) return "";
        const clone = el.cloneNode(true);
        for (const noise of Array.from(clone.querySelectorAll('sup, sub, script, style, [class*="tool"], [class*="btn"], [class*="icon"], [class*="operate"], [class*="action"], button'))) {
          noise.remove();
        }
        return normalize(clone.textContent || clone.innerText || "");
      };

      const firstText = (selectors) => {
        for (const selector of selectors) {
          for (const el of Array.from(document.querySelectorAll(selector))) {
            const text = extractElementText(el);
            if (text) return text;
          }
        }
        return "";
      };

      const pickBestTitle = (values) => {
        const normalizedValues = values.map(normalize).filter(Boolean);
        return normalizedValues.find((value) => !isSuspiciousTitle(value) && !isLikelyAuthorLine(value))
          || normalizedValues.find((value) => !isSuspiciousTitle(value))
          || "";
      };

      const isVisible = (el) => {
        if (!el) return false;
        const style = window.getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden') return false;
        const rect = el.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      };

      const isToolbarLikeElement = (el) => {
        const hint = normalize(`${el?.className || ''} ${el?.id || ''} ${el?.getAttribute?.('role') || ''}`).toLowerCase();
        return /btn|tool|icon|operate|action|download|share|collect|quote|print|toolbar|menu|ai/.test(hint)
          || !!el?.closest?.('[class*="tool"], [class*="btn"], [class*="icon"], [class*="operate"], [class*="action"], button, .download, .share, .collect, .quote, .print');
      };

      const extractHeadingTitle = () => {
        const selectors = ['.wx-tit > h1', '.xx_title > h1', '.title > h1', '.brief h1', 'h1'];
        const candidates = Array.from(document.querySelectorAll(selectors.join(',')))
          .filter(isVisible)
          .map((el) => {
            const text = extractElementText(el);
            const rect = el.getBoundingClientRect();
            const fontSize = parseFloat(window.getComputedStyle(el).fontSize || '0') || 0;
            return { el, text, top: rect.top, fontSize };
          })
          .filter((item) => item.text && !isSuspiciousTitle(item.text) && !isLikelyAuthorLine(item.text))
          .sort((lhs, rhs) => rhs.fontSize - lhs.fontSize || lhs.top - rhs.top || lhs.text.length - rhs.text.length);
        return candidates[0]?.text || "";
      };

      const extractAuthorsNearTitle = (titleText) => {
        let windowText = rawPageText.replace(/\r/g, '');
        if (titleText) {
          const index = windowText.indexOf(titleText);
          if (index >= 0) {
            windowText = windowText.slice(index + titleText.length, index + titleText.length + 600);
          }
        }

        const stopTokens = ['摘要', 'Abstract', '关键词', 'Key words', '基金资助', '专辑', '专题'];
        let stopIndex = windowText.length;
        for (const token of stopTokens) {
          const index = windowText.indexOf(token);
          if (index >= 0) stopIndex = Math.min(stopIndex, index);
        }
        windowText = windowText.slice(0, stopIndex);
        const lines = windowText
          .split(/\n+/)
          .map(normalize)
          .filter(Boolean)
          .slice(0, 8);

        const looksLikeInstitutionLine = (line) =>
          /^(?:\d+[.．、]|[①②③④⑤⑥⑦⑧⑨⑩])/.test(line)
          || institutionLike(line);
        const looksLikeAuthorLine = (line) => {
          const numberedMatches = Array.from(
            line.matchAll(/([\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?)(?=\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹])/g)
          )
            .map((match) => cleanAuthor(match[1]))
            .filter(isLikelyAuthorToken);
          if (numberedMatches.length >= 2) return true;
          return parseAuthorTokens(line).length >= 2;
        };

        const authorLines = [];
        for (const line of lines) {
          if (authorNoiseLike(line) && !looksLikeAuthorLine(line)) continue;
          if (looksLikeInstitutionLine(line)) {
            if (authorLines.length > 0) break;
            continue;
          }
          if (looksLikeAuthorLine(line)) {
            authorLines.push(line);
            continue;
          }
          if (authorLines.length > 0) break;
        }

        const numberedChineseAuthors = authorLines.flatMap((line) =>
          Array.from(line.matchAll(/([\u3400-\u9FFF]{2,4}(?:·[\u3400-\u9FFF]{1,6})?)(?=\s*[0-9０-９¹²³⁴⁵⁶⁷⁸⁹])/g))
            .map((match) => cleanAuthor(match[1]))
            .filter(isLikelyAuthorToken)
        );
        if (numberedChineseAuthors.length > 0) {
          return unique(numberedChineseAuthors);
        }

        return unique(authorLines.flatMap(parseAuthorTokens));
      };

      const findTitleElement = (titleText) => {
        if (titleText) {
          const globalCandidates = Array.from(document.querySelectorAll('h1, h2, h3, div, p, span, strong'))
            .filter(isVisible)
            .map((el) => ({ el, text: extractElementText(el) }))
            .filter((item) =>
              item.text
              && !isSuspiciousTitle(item.text)
              && !isLikelyAuthorLine(item.text)
              && item.text.length <= Math.max(titleText.length + 24, 64)
              && (item.text === titleText || item.text.includes(titleText) || titleText.includes(item.text))
            )
            .sort((lhs, rhs) => {
              const lhsRect = lhs.el.getBoundingClientRect();
              const rhsRect = rhs.el.getBoundingClientRect();
              const lhsDelta = Math.abs(lhs.text.length - titleText.length);
              const rhsDelta = Math.abs(rhs.text.length - titleText.length);
              const lhsArea = lhsRect.width * lhsRect.height;
              const rhsArea = rhsRect.width * rhsRect.height;
              return lhsDelta - rhsDelta
                || lhsArea - rhsArea
                || lhsRect.top - rhsRect.top;
            });
          if (globalCandidates.length > 0) {
            return globalCandidates[0].el;
          }
        }

        const selectors = ['.wx-tit > h1', '.xx_title > h1', '.title > h1', '.brief h1', 'h1'];
        const candidates = Array.from(document.querySelectorAll(selectors.join(',')))
          .filter(isVisible)
          .map((el) => ({ el, text: extractElementText(el) }))
          .filter((item) => item.text && !isSuspiciousTitle(item.text) && !isLikelyAuthorLine(item.text));

        if (titleText) {
          const exact = candidates
            .filter((item) => item.text === titleText || item.text.includes(titleText) || titleText.includes(item.text))
            .sort((lhs, rhs) => lhs.text.length - rhs.text.length);
          if (exact.length > 0) {
            return exact[0].el;
          }
        }

        const byHeading = candidates
          .filter((item) => /^H[1-3]$/.test(item.el.tagName))
          .sort((lhs, rhs) => {
            const left = lhs.el.getBoundingClientRect();
            const right = rhs.el.getBoundingClientRect();
            return left.top - right.top || lhs.text.length - rhs.text.length;
          });
        return byHeading[0]?.el || candidates[0]?.el || null;
      };

      const extractAuthorsFromTitleRegion = (titleText) => {
        const titleElement = findTitleElement(titleText);
        if (!titleElement) return [];

        const titleRect = titleElement.getBoundingClientRect();
        const roots = [];
        const scopedRoot = titleElement.closest('.wx-tit, .xx_title, .title, .brief, .wxBaseinfo');
        if (scopedRoot) roots.push(scopedRoot);
        if (scopedRoot?.nextElementSibling) roots.push(scopedRoot.nextElementSibling);
        if (scopedRoot?.nextElementSibling?.nextElementSibling) roots.push(scopedRoot.nextElementSibling.nextElementSibling);
        roots.push(document.body);

        const evaluated = [];
        for (const root of roots) {
          const nodes = root === document.body
            ? Array.from(document.querySelectorAll('a, span, div, p, li'))
            : [root, ...Array.from(root.querySelectorAll('a, span, div, p, li'))];

          for (const el of nodes) {
            if (!isVisible(el) || el === titleElement || titleElement.contains(el) || isToolbarLikeElement(el)) continue;
            const rect = el.getBoundingClientRect();
            if (rect.top < titleRect.bottom - 8 || rect.top > titleRect.bottom + 140) continue;
            if (rect.right < titleRect.left - 40 || rect.left > titleRect.right + 120) continue;

            const nodeText = normalize(el.innerText || el.textContent || '');
            if (!nodeText || nodeText.length > 180) continue;
            if (/^(摘要|关键词|Abstract|Key words|基金资助|专辑|专题)/.test(nodeText)) continue;

            const nestedAuthors = unique(
              Array.from(el.querySelectorAll('a, span'))
                .flatMap((node) => parseAuthorTokens(node.innerText || node.textContent || ''))
            );
            const lineAuthors = parseAuthorTokens(nodeText);
            const authors = unique([...nestedAuthors, ...lineAuthors]);
            if (authors.length < 2) continue;

            evaluated.push({
              authors,
              top: rect.top,
              left: rect.left,
              width: rect.width,
              textLength: nodeText.length
            });
          }

          if (evaluated.length > 0 && root !== document.body) break;
        }

        evaluated.sort((lhs, rhs) =>
          rhs.authors.length - lhs.authors.length
          || Math.abs(lhs.top - titleRect.bottom) - Math.abs(rhs.top - titleRect.bottom)
          || Math.abs(lhs.left - titleRect.left) - Math.abs(rhs.left - titleRect.left)
          || lhs.textLength - rhs.textLength
        );

        return evaluated[0]?.authors || [];
      };

      const title = pickBestTitle([
        extractHeadingTitle(),
        ...metaValues(['citation_title', 'dc.title', 'DC.title']),
        firstText(['.wx-tit > h1', '.xx_title > h1', '.title > h1', '.brief h1', 'h1']),
        extractTitleFromContext(),
      ]);
      const titleRegionAuthors = extractAuthorsFromTitleRegion(title);
      const contextualAuthors = titleRegionAuthors.length > 0 ? titleRegionAuthors : extractAuthorsNearTitle(title);
      const authorCandidates = [
        ...metaValues(['citation_author', 'dc.creator', 'DC.creator']).map(cleanAuthor),
        ...collectTexts([
          '.author a',
          '.authors a',
          '.wx-tit .author a',
          '.wx-tit [class*="author"] a',
          '.author-list a',
          '#authorpart a',
          '.brief .author a',
          '.xx_title .author a'
        ], cleanAuthor)
      ].filter(isLikelyAuthorToken);
      const authorBlock = firstText([
        '.author',
        '.authors',
        '.wx-tit .author',
        '.wx-tit [class*="author"]',
        '.author-list',
        '#authorpart',
          '.brief .author',
          '.xx_title .author'
        ]);
      const blockAuthors = authorBlock ? parseAuthorTokens(authorBlock) : [];
      let authors = [];
      let authorSource = 'none';
      if (titleRegionAuthors.length > 0) {
        authors = titleRegionAuthors;
        authorSource = 'titleRegion';
      } else if (blockAuthors.length > 0) {
        authors = unique([...blockAuthors, ...authorCandidates]);
        authorSource = 'authorBlock';
      } else if (authorCandidates.length > 0) {
        authors = unique(authorCandidates);
        authorSource = 'metaOrLinks';
      } else if (contextualAuthors.length > 0) {
        authors = contextualAuthors;
        authorSource = 'contextual';
      } else {
        authors = [];
        authorSource = 'none';
      }
      const journal = metaValues(['citation_journal_title', 'citation_publication_title'])[0]
        || firstText(['.top-tip span a', '.wxBaseinfo .top-tip a', '.source a', '.source']);
      const doi = metaValues(['citation_doi', 'dc.identifier'])[0]
        || firstText(['.doi', '.wxBaseinfo .doi']);
      const abstractText = metaValues(['description', 'dc.description'])[0]
        || firstText(['#ChDivSummary', '.summary', '.abstract', '.abstract-text', '.wxBaseinfo .abstract']);
      const volume = metaValues(['citation_volume'])[0] || "";
      const issue = metaValues(['citation_issue'])[0] || "";
      const firstPage = metaValues(['citation_firstpage'])[0] || "";
      const lastPage = metaValues(['citation_lastpage'])[0] || "";
      const yearText = metaValues(['citation_publication_date', 'citation_date'])[0]
        || firstText(['.top-tip', '.source', '.wxBaseinfo']);
      const hasVisibleVerificationUI = Array.from(document.querySelectorAll('input, iframe, img, div, span, p, a, button'))
        .filter(isVisible)
        .some((el) => {
          const text = normalize(el.innerText || el.textContent || "");
          const hint = normalize(`${el.className || ''} ${el.id || ''} ${el.getAttribute?.('placeholder') || ''} ${el.getAttribute?.('aria-label') || ''}`).toLowerCase();
          return (!!text && text.length <= 120 && /安全验证|请完成验证|验证码|访问异常|异常访问|验证后继续访问/.test(text))
            || /(captcha|verify|verification)/.test(hint);
        });
      const hasVisibleDetailScaffold = !!title && (authors.length > 0 || !!abstractText || !!journal || !!doi);
      const blockedSignals = /安全验证|请完成验证|验证码|访问异常|异常访问|验证后继续访问|机构用户登录/.test(marker)
        || hasVisibleVerificationUI;
      const blockedReason = blockedSignals ? (hasVisibleVerificationUI ? 'verification-ui' : 'verification-marker') : null;
      const blocked = blockedSignals && !hasVisibleDetailScaffold;

      return JSON.stringify({
        blocked,
        blockedReason,
        title: title || null,
        authors,
        authorSource,
        journal: journal || null,
        doi: doi || null,
        abstract: abstractText || null,
        volume: volume || null,
        issue: issue || null,
        firstPage: firstPage || null,
        lastPage: lastPage || null,
        yearText: yearText || null,
        bodyText: pageText.slice(0, 12000),
        url: location.href
      });
    })();
    """#
}

@MainActor
private final class HTMLLoadDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(html: String, in webView: WKWebView, baseURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(throwing: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(throwing: error)
    }
}

extension CNKIMetadataProvider: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            lastNavigationStatusCode = httpResponse.statusCode
        } else {
            lastNavigationStatusCode = nil
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard pendingContinuation != nil else { return }
        if lastNavigationStatusCode == 403 {
            fail(CNKIError.blockedByVerification)
            return
        }
        scheduleInspection(for: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard pendingContinuation != nil else { return }
        fail(CNKIError.navigationFailed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard pendingContinuation != nil else { return }
        fail(CNKIError.navigationFailed(error.localizedDescription))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard pendingContinuation != nil else { return }
        fail(CNKIError.parseFailed("知网页面渲染进程已终止。"))
    }
}
