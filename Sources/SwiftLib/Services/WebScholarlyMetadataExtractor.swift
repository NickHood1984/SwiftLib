import Foundation
import OSLog
import SwiftLibCore
import WebKit

private let scholarLog = Logger(subsystem: "SwiftLib", category: "WebScholarlyMeta")

/// 通用学术网页元数据提取器。
/// 用隐藏 WKWebView 加载指定 URL → 注入 scholarly-meta-extract.js → 解析 citation meta tags / JSON-LD 等。
@MainActor
final class WebScholarlyMetadataExtractor: NSObject, ObservableObject {

    // MARK: - Types

    struct ScholarlyResult: Sendable {
        var reference: Reference
        var sourceURL: String
        var hasCitationMetaTags: Bool
        var interceptedExport: InterceptedWebExport?
        var requiresLogin: Bool
    }

    enum ExtractionError: LocalizedError {
        case invalidURL
        case webViewNotReady
        case timedOut
        case navigationFailed(String)
        case noScholarlyMetadata
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "请输入以 http 或 https 开头的有效链接。"
            case .webViewNotReady: return "网页组件尚未就绪，请稍候再试。"
            case .timedOut: return "学术元数据抓取超时（15 秒），请检查网络。"
            case .navigationFailed(let s): return "无法打开页面：\(s)"
            case .noScholarlyMetadata: return "该页面未包含可识别的学术元数据标签。"
            case .extractionFailed(let s): return s
            }
        }
    }

    // MARK: - State

    @Published private(set) var isExtracting = false

    private var _webView: WKWebView?
    private var pendingContinuation: CheckedContinuation<ScholarlyResult, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var startedURLString = ""
    private var activeProfile: WebSessionBroker.Profile?
    private var interceptedExport: InterceptedWebExport?
    private var pageRequiresLogin = false

    private static var scriptCache: String?

    // MARK: - Public

    /// 允许外部（如 View）注册已有的 WKWebView。
    func registerWebView(_ webView: WKWebView) {
        _webView = webView
        webView.navigationDelegate = self
    }

    func extract(urlString raw: String) async throws -> ScholarlyResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            throw ExtractionError.invalidURL
        }

        let profile = WebSessionBroker.shared.scholarlyProfile(for: url)
        let wv = ensureWebView(for: url, profile: profile)

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ScholarlyResult, Error>) in
            guard pendingContinuation == nil else {
                cont.resume(throwing: ExtractionError.extractionFailed("已有进行中的抓取。"))
                return
            }
            pendingContinuation = cont
            startedURLString = url.absoluteString
            isExtracting = true
            activeProfile = profile
            interceptedExport = nil
            pageRequiresLogin = false

            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15s
                guard !Task.isCancelled else { return }
                self.failExtraction(.timedOut)
            }

            wv.stopLoading()
            scholarLog.notice("开始学术元数据抓取 url=\(trimmed, privacy: .public)")
            wv.load(URLRequest(url: url))
        }
    }

    // MARK: - Private

    /// 懒创建一个隐藏的 WKWebView（无需嵌入 View 层级）。
    private func ensureWebView(for url: URL, profile: WebSessionBroker.Profile) -> WKWebView {
        if let wv = _webView, activeProfile?.id == profile.id { return wv }

        _webView?.navigationDelegate = nil
        _webView?.stopLoading()

        let configuration = WKWebViewConfiguration()
        HiddenWKWebViewMediaGuard.configure(configuration)
        WebSessionBroker.shared.configure(configuration, profile: profile)

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 4, height: 4), configuration: configuration)
        wv.customUserAgent = ReaderExtractionManager.safariLikeUserAgent
        wv.navigationDelegate = self
        _webView = wv
        activeProfile = profile
        return wv
    }

    private func runSiteAdapterExtraction(adapter: SiteAdapter, in webView: WKWebView) {
        guard let script = SiteAdapterService.shared.buildScript(for: adapter) else {
            scholarLog.warning("站点适配器脚本构建失败，回退到通用提取 adapter=\(adapter.id, privacy: .public)")
            runScholarlyExtraction(in: webView)
            return
        }

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self, self.isExtracting else { return }

            if let error {
                scholarLog.warning("站点适配器脚本执行失败，回退到通用提取: \(error.localizedDescription, privacy: .public)")
                self.runScholarlyExtraction(in: webView)
                return
            }

            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8)
            else {
                scholarLog.warning("站点适配器返回空结果，回退到通用提取")
                self.runScholarlyExtraction(in: webView)
                return
            }

            do {
                let raw = try JSONDecoder().decode(RawScholarlyMetadata.self, from: data)
                // 如果标题为空，说明适配器选择器可能失效，回退
                if (raw.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    scholarLog.warning("站点适配器未提取到标题，回退到通用提取 adapter=\(adapter.id, privacy: .public)")
                    self.runScholarlyExtraction(in: webView)
                    return
                }
                let mapped = self.mapToResult(raw)
                scholarLog.notice("站点适配器提取成功 adapter=\(adapter.id, privacy: .public) title=\(mapped.reference.title.prefix(40), privacy: .public)")
                self.completeExtraction(mapped)
            } catch {
                scholarLog.warning("站点适配器 JSON 解析失败，回退到通用提取: \(error.localizedDescription, privacy: .public)")
                if self.completeFromExportIfAvailable() {
                    return
                }
                self.runScholarlyExtraction(in: webView)
            }
        }
    }

    private func runScholarlyExtraction(in webView: WKWebView) {
        guard let script = Self.loadScript() else {
            scholarLog.error("未找到 scholarly-meta-extract.js")
            failExtraction(.extractionFailed("内部错误：未找到提取脚本。"))
            return
        }

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self, self.isExtracting else { return }
            if let error {
                scholarLog.error("scholarly-meta-extract.js 执行失败: \(error.localizedDescription, privacy: .public)")
                self.failExtraction(.extractionFailed("脚本执行失败：\(error.localizedDescription)"))
                return
            }

            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8)
            else {
                if self.completeFromExportIfAvailable() {
                    return
                }
                self.failExtraction(.noScholarlyMetadata)
                return
            }

            do {
                let raw = try JSONDecoder().decode(RawScholarlyMetadata.self, from: data)
                let mapped = self.mapToResult(raw)
                self.completeExtraction(mapped)
            } catch {
                scholarLog.error("scholarly JSON 解析失败: \(error.localizedDescription, privacy: .public)")
                if self.completeFromExportIfAvailable() {
                    return
                }
                self.failExtraction(.extractionFailed("元数据解析失败。"))
            }
        }
    }

    private func mapToResult(_ raw: RawScholarlyMetadata) -> ScholarlyResult {
        let title = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let authors = (raw.authors ?? []).map { AuthorName.parse($0) }

        let year: Int? = {
            guard let dateStr = raw.date else { return nil }
            let pattern = #"(19|20)\d{2}"#
            guard let range = dateStr.range(of: pattern, options: .regularExpression) else { return nil }
            return Int(dateStr[range])
        }()

        let refType = mapItemType(raw.itemType)
        let pages = raw.pages?.trimmingCharacters(in: .whitespacesAndNewlines)
        let abstract = raw.abstract?.trimmingCharacters(in: .whitespacesAndNewlines)

        let institution: String? = raw.dissertation_institution ?? raw.technical_report_institution
        let genre: String? = refType == .thesis ? (raw.dissertation_institution != nil ? "学位论文" : nil) : nil

        var reference = Reference(
            title: title,
            authors: authors,
            year: year,
            journal: raw.journal,
            volume: raw.volume,
            issue: raw.issue,
            pages: pages,
            doi: raw.doi,
            url: raw.url,
            abstract: abstract,
            referenceType: refType,
            metadataSource: .webMeta,
            publisher: raw.publisher,
            isbn: raw.isbn,
            issn: raw.issn,
            genre: genre,
            institution: institution,
            language: raw.language
        )

        if let export = interceptedExport,
           let exportReference = WebExportInterception.parseReference(from: export),
           exportReference.title.swiftlib_nilIfBlank != nil {
            reference = MetadataResolution.mergeReference(primary: exportReference, fallback: reference)
        }

        let hasCitation = raw._sources?.highwire == true
            || raw._sources?.bepress == true
            || raw._sources?.jsonld == true
            || raw._sources?.siteAdapter == true

        return ScholarlyResult(
            reference: reference,
            sourceURL: raw.url ?? startedURLString,
            hasCitationMetaTags: hasCitation || interceptedExport != nil,
            interceptedExport: interceptedExport,
            requiresLogin: pageRequiresLogin
        )
    }

    private func mapItemType(_ itemType: String?) -> ReferenceType {
        switch itemType {
        case "journalArticle": return .journalArticle
        case "book": return .book
        case "conferencePaper": return .conferencePaper
        case "thesis": return .thesis
        case "report": return .report
        case "webpage": return .webpage
        default: return .other
        }
    }

    private func completeExtraction(_ result: ScholarlyResult) {
        guard let cont = pendingContinuation else { return }
        pendingContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        isExtracting = false

        let titleLen = result.reference.title.count
        let hasDOI = result.reference.doi != nil
        scholarLog.notice("学术元数据提取成功 titleLen=\(titleLen) hasDOI=\(hasDOI) hasCitation=\(result.hasCitationMetaTags)")
        cont.resume(returning: result)
    }

    private func failExtraction(_ error: ExtractionError) {
        guard let cont = pendingContinuation else { return }
        pendingContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        isExtracting = false
        _webView?.stopLoading()
        scholarLog.error("学术元数据提取失败: \(error.localizedDescription, privacy: .public)")
        cont.resume(throwing: error)
    }

    private static func loadScript() -> String? {
        if let cached = scriptCache { return cached }
        if let url = Bundle.module.url(forResource: "scholarly-meta-extract", withExtension: "js", subdirectory: "Resources"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            scriptCache = s
            return s
        }
        if let url = Bundle.module.url(forResource: "scholarly-meta-extract", withExtension: "js"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            scriptCache = s
            return s
        }
        return nil
    }

    private func completeFromExportIfAvailable() -> Bool {
        guard let export = interceptedExport,
              var reference = WebExportInterception.parseReference(from: export) else {
            return false
        }

        if reference.url?.swiftlib_nilIfBlank == nil {
            reference.url = startedURLString
        }
        if reference.metadataSource == nil {
            switch export.format {
            case .ris:
                reference.metadataSource = .ris
            case .bibTeX:
                reference.metadataSource = .bibtex
            case .cnki:
                reference.metadataSource = .cnki
            }
        }

        completeExtraction(
            ScholarlyResult(
                reference: reference,
                sourceURL: reference.url ?? startedURLString,
                hasCitationMetaTags: true,
                interceptedExport: export,
                requiresLogin: pageRequiresLogin
            )
        )
        return true
    }

    private func inspectPageState(in webView: WKWebView) async -> WebExportSnapshot? {
        do {
            let raw = try await webView.evaluateJavaScript(WebExportInterception.snapshotScript)
            guard let jsonString = raw as? String,
                  let data = jsonString.data(using: .utf8) else {
                return nil
            }
            return try JSONDecoder().decode(WebExportSnapshot.self, from: data)
        } catch {
            scholarLog.warning("导出快照采集失败: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func prefetchStructuredExport(from snapshot: WebExportSnapshot) async -> InterceptedWebExport? {
        guard let profile = activeProfile else { return nil }

        for candidate in snapshot.candidates {
            guard let candidateURL = normalizedHTTPURL(candidate.url),
                  let hintedFormat = WebExportInterception.detectFormat(
                    url: candidateURL,
                    label: candidate.label,
                    hint: candidate.hint
                  ) else {
                continue
            }

            do {
                let request = await WebSessionBroker.shared.request(url: candidateURL, profile: profile)
                let (data, response) = try await NetworkClient.session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let payload = WebExportInterception.decodeText(data: data, response: response) else {
                    continue
                }

                let resolvedFormat = WebExportInterception.detectFormat(
                    url: candidateURL,
                    mimeType: response.mimeType,
                    fileName: response.suggestedFilename,
                    label: candidate.label,
                    hint: candidate.hint
                ) ?? hintedFormat

                let export = InterceptedWebExport(
                    format: resolvedFormat,
                    payload: payload,
                    sourceURL: candidateURL.absoluteString,
                    mimeType: response.mimeType,
                    fileName: response.suggestedFilename
                )
                if WebExportInterception.parseReference(from: export) != nil {
                    scholarLog.notice("导出拦截命中 url=\(candidateURL.absoluteString, privacy: .public) format=\(resolvedFormat.rawValue, privacy: .public)")
                    return export
                }
            } catch {
                scholarLog.warning("导出候选抓取失败 url=\(candidate.url, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }

        return nil
    }

    private func fetchExport(
        from url: URL,
        mimeType: String?,
        fileName: String?
    ) async -> InterceptedWebExport? {
        guard let profile = activeProfile,
              let format = WebExportInterception.detectFormat(url: url, mimeType: mimeType, fileName: fileName) else {
            return nil
        }

        do {
            let request = await WebSessionBroker.shared.request(url: url, profile: profile)
            let (data, response) = try await NetworkClient.session.data(for: request)
            guard let payload = WebExportInterception.decodeText(data: data, response: response) else {
                return nil
            }
            let resolvedFormat = WebExportInterception.detectFormat(
                url: url,
                mimeType: response.mimeType ?? mimeType,
                fileName: response.suggestedFilename ?? fileName
            ) ?? format

            let export = InterceptedWebExport(
                format: resolvedFormat,
                payload: payload,
                sourceURL: url.absoluteString,
                mimeType: response.mimeType ?? mimeType,
                fileName: response.suggestedFilename ?? fileName
            )
            return WebExportInterception.parseReference(from: export) == nil ? nil : export
        } catch {
            scholarLog.warning("下载型导出抓取失败 url=\(url.absoluteString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func normalizedHTTPURL(_ value: String?) -> URL? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }
}

// MARK: - WKNavigationDelegate

extension WebScholarlyMetadataExtractor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isExtracting else { return }
        let pageURL = webView.url?.absoluteString ?? startedURLString
        scholarLog.notice("WK didFinish url=\(pageURL, privacy: .public)")

        // 延迟 1 秒，等待 JS 渲染完成（部分学术网站 meta tags 由 JS 动态插入）
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, self.isExtracting, self._webView === webView else { return }

            if let snapshot = await self.inspectPageState(in: webView) {
                self.pageRequiresLogin = snapshot.loginRequired
                if self.interceptedExport == nil {
                    self.interceptedExport = await self.prefetchStructuredExport(from: snapshot)
                }
            }

            // 优先检查站点适配器
            if let adapter = SiteAdapterService.shared.adapter(for: pageURL) {
                scholarLog.notice("使用站点适配器 \(adapter.name, privacy: .public)")
                self.runSiteAdapterExtraction(adapter: adapter, in: webView)
            } else {
                self.runScholarlyExtraction(in: webView)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard isExtracting else { return }
        failExtraction(.navigationFailed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard isExtracting else { return }
        failExtraction(.navigationFailed(error.localizedDescription))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard isExtracting,
              interceptedExport == nil,
              let url = navigationResponse.response.url,
              let format = WebExportInterception.detectFormat(
                url: url,
                mimeType: navigationResponse.response.mimeType,
                fileName: navigationResponse.response.suggestedFilename
              ) else {
            decisionHandler(.allow)
            return
        }

        decisionHandler(.cancel)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.interceptedExport = await self.fetchExport(
                from: url,
                mimeType: navigationResponse.response.mimeType,
                fileName: navigationResponse.response.suggestedFilename
            )
            scholarLog.notice("导航响应导出拦截 url=\(url.absoluteString, privacy: .public) format=\(format.rawValue, privacy: .public)")
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard isExtracting else { return }
        failExtraction(.extractionFailed("网页渲染进程已终止。"))
    }
}

// MARK: - Raw JSON Model

private struct RawScholarlyMetadata: Decodable {
    var title: String?
    var authors: [String]?
    var doi: String?
    var journal: String?
    var volume: String?
    var issue: String?
    var pages: String?
    var date: String?
    var abstract: String?
    var isbn: String?
    var issn: String?
    var publisher: String?
    var language: String?
    var pdfURL: String?
    var keywords: [String]?
    var url: String?
    var siteName: String?
    var conference: String?
    var dissertation_institution: String?
    var technical_report_institution: String?
    var itemType: String?
    // swiftlint:disable:next identifier_name
    var _sources: SourceFlags?

    struct SourceFlags: Decodable {
        var highwire: Bool?
        var bepress: Bool?
        var dublinCore: Bool?
        var jsonld: Bool?
        var siteAdapter: Bool?
    }
}
