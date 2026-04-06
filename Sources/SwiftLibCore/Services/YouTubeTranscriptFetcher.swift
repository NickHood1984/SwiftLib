import Foundation
import OSLog

private let ytTranscriptLog = Logger(subsystem: "SwiftLib", category: "YouTubeTranscript")

public protocol YouTubeTranscriptTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: YouTubeTranscriptTransport {}

public protocol YouTubeTranscriptExternalFetcher {
    func fetchPlainText(videoId: String) async throws -> String
}

/// 通过 ANDROID InnerTube client 获取字幕（主流方案）；若失败则回退到 watch 页 HTML 解析 → yt-dlp。
public enum YouTubeTranscriptFetcher {
    private static let watchURLTemplate = "https://www.youtube.com/watch?v="
    private static let innertubePlayerEndpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!
    private static let acceptLanguage = "zh-CN,zh;q=0.9,en;q=0.8"
    private static let androidClientName = "ANDROID"
    private static let androidClientVersion = "20.10.38"
    private static let htmlAcceptHeader = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

    /// 与在线阅读 WKWebView 接近，降低空壳页概率。
    public static let requestUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// GDPR/consent 首访兜底；与 watch 共用 ephemeral session 时仍可能收到 `Set-Cookie` 补充。
    private static let consentCookieHeader =
        "SOCS=CAISNQgDEitib3FfaWRlbnRpdHlmcm9udGVuZHVpc2VydmVyXzIwMjMwODI5LjA3X3AxGgJlbiACGgYIgJnPpwY; CONSENT=PENDING+987"

    public enum FetchError: Error, LocalizedError, Equatable {
        case invalidVideoId
        case noInitialPlayerResponse
        case jsonParseFailed
        case noCaptionTracks
        case captionDownloadFailed(String)
        case captionBlockedOrEmptyAfterFallback
        case captionUnavailableAfterYtDlp(String)
        case transcriptEmpty

        public var errorDescription: String? {
            switch self {
            case .invalidVideoId: return "无效的视频 ID"
            case .noInitialPlayerResponse: return "页面中未找到 ytInitialPlayerResponse"
            case .jsonParseFailed: return "无法解析播放器 JSON"
            case .noCaptionTracks: return "该视频无可用字幕轨道"
            case .captionDownloadFailed(let s): return "字幕下载失败: \(s)"
            case .captionBlockedOrEmptyAfterFallback:
                return "字幕请求返回空内容或被 YouTube 拦截（已尝试 TV fallback）"
            case .captionUnavailableAfterYtDlp(let detail):
                return "字幕仍不可用（已尝试 TV fallback 与 yt-dlp）：\(detail)"
            case .transcriptEmpty: return "字幕内容为空"
            }
        }
    }

    private enum BootstrapStrategy: String {
        case innertubeAndroid = "innertube_android"
        case watchHTML = "watch_html"
    }

    private enum CaptionFetchFailure: Error {
        case transport(Error)
        case http(Int)
        case encoding
        case gatedOrEmpty
        case transcriptEmpty
    }

    private struct WatchPageContext {
        let watchURL: URL
        let apiKey: String?
        let visitorData: String?
        let signatureTimestamp: Int?
        let captionTracks: [[String: Any]]
    }

    private struct CaptionBootstrap {
        let strategy: BootstrapStrategy
        let clientLabel: String
        let captionBaseURL: URL
        let referer: String
        let userAgent: String
    }

    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    /// 拉取并拼接为纯文本（带简单 `[mm:ss]` 前缀，便于扫读）。
    public static func fetchPlainText(videoId: String) async -> Result<String, Error> {
        return await fetchPlainText(
            videoId: videoId,
            transport: sharedSession,
            externalFetcher: YtDlpTranscriptFetcher.shared
        )
    }

    public static func fetchPlainText(
        videoId: String,
        transport: any YouTubeTranscriptTransport,
        externalFetcher: (any YouTubeTranscriptExternalFetcher)? = nil
    ) async -> Result<String, Error> {
        let trimmed = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(FetchError.invalidVideoId)
        }

        do {
            let plain = try await fetchPlainTextOrThrow(
                videoId: trimmed,
                transport: transport,
                externalFetcher: externalFetcher
            )
            guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(FetchError.transcriptEmpty)
            }
            return .success(plain)
        } catch let e as FetchError {
            return .failure(e)
        } catch {
            return .failure(error)
        }
    }

    private static func fetchPlainTextOrThrow(
        videoId: String,
        transport: any YouTubeTranscriptTransport,
        externalFetcher: (any YouTubeTranscriptExternalFetcher)?
    ) async throws -> String {
        do {
            return try await fetchPlainTextDirectOrThrow(videoId: videoId, transport: transport)
        } catch let error as FetchError {
            guard error != .invalidVideoId, let externalFetcher else {
                throw error
            }
            return try await fetchPlainTextViaYtDlpOrThrow(
                videoId: videoId,
                primaryError: error,
                externalFetcher: externalFetcher
            )
        } catch {
            guard let externalFetcher else { throw error }
            return try await fetchPlainTextViaYtDlpOrThrow(
                videoId: videoId,
                primaryError: error,
                externalFetcher: externalFetcher
            )
        }
    }

    private static func fetchPlainTextViaYtDlpOrThrow(
        videoId: String,
        primaryError: Error,
        externalFetcher: any YouTubeTranscriptExternalFetcher
    ) async throws -> String {
        ytTranscriptLog.notice(
            "network subtitle path failed vid=\(videoId, privacy: .public) -> 尝试 yt-dlp fallback error=\(primaryError.localizedDescription, privacy: .public)"
        )
        do {
            let plain = try await externalFetcher.fetchPlainText(videoId: videoId)
            ytTranscriptLog.notice(
                "yt-dlp fallback success vid=\(videoId, privacy: .public) length=\(plain.count, privacy: .public)"
            )
            return plain
        } catch {
            ytTranscriptLog.notice(
                "yt-dlp fallback failed vid=\(videoId, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw combineFailure(primary: primaryError, ytDlpError: error)
        }
    }

    private static func combineFailure(primary: Error, ytDlpError: Error) -> FetchError {
        let primaryText = primary.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let ytText = ytDlpError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail: String
        if ytText.isEmpty {
            detail = primaryText.isEmpty ? "未知错误" : primaryText
        } else if primaryText.isEmpty || primaryText == ytText {
            detail = ytText
        } else {
            detail = "主链路：\(primaryText)；yt-dlp：\(ytText)"
        }
        return .captionUnavailableAfterYtDlp(detail)
    }

    private static func fetchPlainTextDirectOrThrow(
        videoId: String,
        transport: any YouTubeTranscriptTransport
    ) async throws -> String {
        // 主路径：从 watch 页提取 API key → ANDROID InnerTube /player → timedtext
        let apiKey = try await fetchAPIKeyFromWatchPage(videoId: videoId, transport: transport)
        let watchURL = URL(string: watchURLTemplate + videoId)!

        do {
            let androidBootstrap = try await fetchAndroidCaptionBootstrap(
                videoId: videoId,
                apiKey: apiKey,
                watchURL: watchURL,
                transport: transport
            )
            return try await fetchCaptionPlainText(
                transport: transport,
                bootstrap: androidBootstrap,
                videoIdForLog: videoId
            )
        } catch {
            ytTranscriptLog.notice("caption strategy=innertube_android failed vid=\(videoId, privacy: .public) error=\(error.localizedDescription, privacy: .public) -> 尝试 watch HTML fallback")
        }

        // fallback：从 watch 页 HTML 直接解析 ytInitialPlayerResponse 获取 captionTracks
        do {
            let watch = try await fetchWatchPageContext(videoId: videoId, transport: transport)
            let htmlBootstrap = try makeCaptionBootstrap(
                from: watch.captionTracks,
                strategy: .watchHTML,
                clientLabel: "web",
                referer: watch.watchURL.absoluteString,
                userAgent: requestUserAgent
            )
            return try await fetchCaptionPlainText(
                transport: transport,
                bootstrap: htmlBootstrap,
                videoIdForLog: videoId
            )
        } catch {
            ytTranscriptLog.notice("caption strategy=watch_html fallback failed vid=\(videoId, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw FetchError.captionBlockedOrEmptyAfterFallback
        }
    }

    // MARK: - Watch bootstrap

    private static func fetchWatchPageContext(
        videoId: String,
        transport: any YouTubeTranscriptTransport
    ) async throws -> WatchPageContext {
        let watchURL = URL(string: watchURLTemplate + videoId)!
        var htmlFinal: String?
        var playerRoot: Any?
        var sawPlayerJSONMarker = false
        var sawPlayerJSONParseFailure = false

        for attempt in 0 ..< 2 {
            let req = makeWatchRequest(url: watchURL, includeConsentHeader: attempt == 0)
            let (data, resp) = try await transport.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let contentType = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "-"
            ytTranscriptLog.notice(
                "watch attempt=\(attempt) status=\(status) type=\(contentType, privacy: .public) bytes=\(data.count, privacy: .public)"
            )

            guard let html = String(data: data, encoding: .utf8) else {
                continue
            }
            htmlFinal = html

            guard let jsonText = extractYTInitialPlayerResponseJSON(from: html) else {
                if attempt == 0 {
                    ytTranscriptLog.notice("watch: 未解析到 ytInitialPlayerResponse，使用 Cookie 罐重试")
                }
                continue
            }

            sawPlayerJSONMarker = true
            guard let jsonData = jsonText.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: jsonData)
            else {
                sawPlayerJSONParseFailure = true
                continue
            }

            playerRoot = root
            break
        }

        guard let htmlFinal else {
            throw FetchError.noInitialPlayerResponse
        }
        guard let playerRoot else {
            throw sawPlayerJSONMarker || sawPlayerJSONParseFailure ? FetchError.jsonParseFailed : FetchError.noInitialPlayerResponse
        }
        guard let tracks = findCaptionTracks(in: playerRoot), !tracks.isEmpty else {
            throw FetchError.noCaptionTracks
        }

        let ytcfg = extractYTCFGDictionary(from: htmlFinal)
        let apiKey = extractInnertubeAPIKey(from: ytcfg, html: htmlFinal)
        let visitorData = extractVisitorData(from: ytcfg, playerRoot: playerRoot, html: htmlFinal)
        let signatureTimestamp = extractSignatureTimestamp(from: ytcfg, html: htmlFinal)

        return WatchPageContext(
            watchURL: watchURL,
            apiKey: apiKey,
            visitorData: visitorData,
            signatureTimestamp: signatureTimestamp,
            captionTracks: tracks
        )
    }

    private static func makeWatchRequest(url: URL, includeConsentHeader: Bool) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(requestUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(htmlAcceptHeader, forHTTPHeaderField: "Accept")
        req.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        if includeConsentHeader {
            req.setValue(consentCookieHeader, forHTTPHeaderField: "Cookie")
        }
        return req
    }

    // MARK: - ANDROID InnerTube (主路径，与 youtube-transcript-api 一致)

    private static func fetchAPIKeyFromWatchPage(
        videoId: String,
        transport: any YouTubeTranscriptTransport
    ) async throws -> String {
        let watchURL = URL(string: watchURLTemplate + videoId)!

        for attempt in 0 ..< 2 {
            let req = makeWatchRequest(url: watchURL, includeConsentHeader: attempt == 0)
            let (data, resp) = try await transport.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            ytTranscriptLog.notice(
                "watch(api_key) attempt=\(attempt) status=\(status) bytes=\(data.count, privacy: .public)"
            )

            guard let html = String(data: data, encoding: .utf8) else { continue }

            if let key = extractInnertubeAPIKey(from: nil, html: html), !key.isEmpty {
                return key
            }

            if let ytcfg = extractYTCFGDictionary(from: html),
               let key = ytcfg["INNERTUBE_API_KEY"] as? String, !key.isEmpty {
                return key
            }
        }

        throw FetchError.noInitialPlayerResponse
    }

    private static func fetchAndroidCaptionBootstrap(
        videoId: String,
        apiKey: String,
        watchURL: URL,
        transport: any YouTubeTranscriptTransport
    ) async throws -> CaptionBootstrap {
        guard var components = URLComponents(url: innertubePlayerEndpoint, resolvingAgainstBaseURL: false) else {
            throw FetchError.captionBlockedOrEmptyAfterFallback
        }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw FetchError.captionBlockedOrEmptyAfterFallback
        }

        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": androidClientName,
                    "clientVersion": androidClientVersion
                ]
            ],
            "videoId": videoId
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")

        let (data, resp) = try await transport.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        let contentType = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "-"
        ytTranscriptLog.notice(
            "bootstrap strategy=innertube_android client=\(androidClientName, privacy: .public) status=\(status) type=\(contentType, privacy: .public) bytes=\(data.count, privacy: .public) vid=\(videoId, privacy: .public)"
        )

        guard status < 400 else {
            throw FetchError.captionDownloadFailed("player HTTP \(status)")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw FetchError.jsonParseFailed
        }
        guard let tracks = findCaptionTracks(in: root), !tracks.isEmpty else {
            throw FetchError.noCaptionTracks
        }

        return try makeCaptionBootstrap(
            from: tracks,
            strategy: .innertubeAndroid,
            clientLabel: androidClientName,
            referer: watchURL.absoluteString,
            userAgent: requestUserAgent
        )
    }

    // MARK: - Caption fetch

    private static func makeCaptionBootstrap(
        from tracks: [[String: Any]],
        strategy: BootstrapStrategy,
        clientLabel: String,
        referer: String,
        userAgent: String
    ) throws -> CaptionBootstrap {
        let chosen = selectCaptionTrack(from: tracks)
        guard let base = chosen["baseUrl"] as? String,
              let captionBaseURL = URL(string: base)
        else {
            throw FetchError.noCaptionTracks
        }

        return CaptionBootstrap(
            strategy: strategy,
            clientLabel: clientLabel,
            captionBaseURL: captionBaseURL,
            referer: referer,
            userAgent: userAgent
        )
    }

    private static func fetchCaptionPlainText(
        transport: any YouTubeTranscriptTransport,
        bootstrap: CaptionBootstrap,
        videoIdForLog: String
    ) async throws -> String {
        let variants = buildCaptionURLVariants(bootstrap.captionBaseURL)
        var lastFailure: CaptionFetchFailure = .gatedOrEmpty
        var sawGatedOrEmpty = false

        for (idx, url) in variants.enumerated() {
            var req = URLRequest(url: url)
            req.setValue(bootstrap.userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
            req.setValue(bootstrap.referer, forHTTPHeaderField: "Referer")

            let capData: Data
            let capResp: URLResponse
            do {
                (capData, capResp) = try await transport.data(for: req)
            } catch {
                ytTranscriptLog.notice(
                    "caption strategy=\(bootstrap.strategy.rawValue, privacy: .public) client=\(bootstrap.clientLabel, privacy: .public) try=\(idx) transport_error vid=\(videoIdForLog, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                lastFailure = .transport(error)
                continue
            }

            let code = (capResp as? HTTPURLResponse)?.statusCode ?? -1
            let contentType = (capResp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "-"
            let bodyLen = capData.count

            if code >= 400 {
                ytTranscriptLog.notice(
                    "caption strategy=\(bootstrap.strategy.rawValue, privacy: .public) client=\(bootstrap.clientLabel, privacy: .public) try=\(idx) status=\(code) type=\(contentType, privacy: .public) bytes=\(bodyLen, privacy: .public) vid=\(videoIdForLog, privacy: .public)"
                )
                lastFailure = .http(code)
                continue
            }

            guard let capStr = String(data: capData, encoding: .utf8) else {
                ytTranscriptLog.notice(
                    "caption strategy=\(bootstrap.strategy.rawValue, privacy: .public) client=\(bootstrap.clientLabel, privacy: .public) try=\(idx) encoding_error type=\(contentType, privacy: .public) bytes=\(bodyLen, privacy: .public) vid=\(videoIdForLog, privacy: .public)"
                )
                lastFailure = .encoding
                continue
            }

            let trimmedBody = capStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBody.isEmpty {
                ytTranscriptLog.notice(
                    "caption strategy=\(bootstrap.strategy.rawValue, privacy: .public) client=\(bootstrap.clientLabel, privacy: .public) try=\(idx) empty_body status=\(code) type=\(contentType, privacy: .public) bytes=\(bodyLen, privacy: .public) vid=\(videoIdForLog, privacy: .public)"
                )
                sawGatedOrEmpty = true
                lastFailure = .gatedOrEmpty
                continue
            }

            let plain: String
            if trimmedBody.hasPrefix("{") {
                guard let p = parseYouTubeCaptionJSON3(trimmedBody),
                      !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    ytTranscriptLog.notice(
                        "caption strategy=\(bootstrap.strategy.rawValue, privacy: .public) client=\(bootstrap.clientLabel, privacy: .public) try=\(idx) json3_empty type=\(contentType, privacy: .public) bytes=\(bodyLen, privacy: .public) vid=\(videoIdForLog, privacy: .public)"
                    )
                    lastFailure = .transcriptEmpty
                    continue
                }
                plain = p
            } else {
                plain = parseTimedTextXMLToPlain(capStr)
                if plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ytTranscriptLog.notice(
                        "caption strategy=\(bootstrap.strategy.rawValue, privacy: .public) client=\(bootstrap.clientLabel, privacy: .public) try=\(idx) xml_empty type=\(contentType, privacy: .public) bytes=\(bodyLen, privacy: .public) vid=\(videoIdForLog, privacy: .public)"
                    )
                    lastFailure = .transcriptEmpty
                    continue
                }
            }

            ytTranscriptLog.notice(
                "caption strategy=\(bootstrap.strategy.rawValue, privacy: .public) client=\(bootstrap.clientLabel, privacy: .public) try=\(idx) success type=\(contentType, privacy: .public) len=\(plain.count, privacy: .public) vid=\(videoIdForLog, privacy: .public)"
            )
            return plain
        }

        if sawGatedOrEmpty {
            throw CaptionFetchFailure.gatedOrEmpty
        }
        throw lastFailure
    }

    private static func mapCaptionFailure(_ failure: CaptionFetchFailure) -> FetchError {
        switch failure {
        case .transport(let error):
            return .captionDownloadFailed(error.localizedDescription)
        case .http(let code):
            return .captionDownloadFailed("HTTP \(code)")
        case .encoding:
            return .captionDownloadFailed("encoding")
        case .gatedOrEmpty:
            return .captionBlockedOrEmptyAfterFallback
        case .transcriptEmpty:
            return .transcriptEmpty
        }
    }

    private static func buildCaptionURLVariants(_ base: URL) -> [URL] {
        var out: [URL] = []
        var seen = Set<String>()
        func add(_ u: URL) {
            let s = u.absoluteString
            if seen.insert(s).inserted { out.append(u) }
        }

        // 主流方案：去掉 &fmt=srv3，让 YouTube 返回纯 XML
        let stripped = base.absoluteString.replacingOccurrences(of: "&fmt=srv3", with: "")
        if let strippedURL = URL(string: stripped) {
            add(strippedURL)
        }
        add(base)

        return out
    }

    public static func parseYouTubeCaptionJSON3(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]]
        else { return nil }
        var lines: [String] = []
        for ev in events {
            let tMs = (ev["tStartMs"] as? NSNumber)?.doubleValue ?? 0
            let secs = tMs / 1000.0
            let mm = Int(secs) / 60
            let ss = Int(secs) % 60
            guard let segs = ev["segs"] as? [[String: Any]] else { continue }
            for seg in segs {
                if let utf8 = seg["utf8"] as? String, !utf8.isEmpty {
                    lines.append(String(format: "[%02d:%02d] %@", mm, ss, utf8))
                }
            }
        }
        let result = lines.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    // MARK: - HTML / JSON

    public static func extractYTInitialPlayerResponseJSON(from html: String) -> String? {
        let needle = "ytInitialPlayerResponse"
        guard let range = html.range(of: needle) else { return nil }
        var i = range.upperBound
        while i < html.endIndex {
            let ch = html[i]
            if ch == "=" {
                i = html.index(after: i)
                break
            }
            if !ch.isWhitespace && ch != ":" { return nil }
            i = html.index(after: i)
        }
        while i < html.endIndex, html[i].isWhitespace || html[i] == "=" { i = html.index(after: i) }
        guard i < html.endIndex, html[i] == "{" else { return nil }
        return extractBalancedJSON(from: html, startBrace: i)
    }

    private static func extractYTCFGJSON(from html: String) -> String? {
        let needle = "ytcfg.set("
        guard let range = html.range(of: needle) else { return nil }
        guard let brace = html[range.upperBound...].firstIndex(of: "{") else { return nil }
        return extractBalancedJSON(from: html, startBrace: brace)
    }

    private static func extractBalancedJSON(from s: String, startBrace: String.Index) -> String? {
        var depth = 0
        var i = startBrace
        var inString = false
        var isEscaped = false
        while i < s.endIndex {
            let c = s[i]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if c == "\\" {
                    isEscaped = true
                } else if c == "\"" {
                    inString = false
                }
            } else {
                if c == "\"" {
                    inString = true
                } else if c == "{" {
                    depth += 1
                } else if c == "}" {
                    depth -= 1
                    if depth == 0 { return String(s[startBrace...i]) }
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func extractYTCFGDictionary(from html: String) -> [String: Any]? {
        guard let json = extractYTCFGJSON(from: html),
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return dict
    }

    private static func extractInnertubeAPIKey(from ytcfg: [String: Any]?, html: String) -> String? {
        if let key = ytcfg?["INNERTUBE_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return extractJSONStringValue(named: "INNERTUBE_API_KEY", from: html)
    }

    private static func extractVisitorData(from ytcfg: [String: Any]?, playerRoot: Any, html: String) -> String? {
        if let value = ((ytcfg?["INNERTUBE_CONTEXT"] as? [String: Any])?["client"] as? [String: Any])?["visitorData"] as? String,
           !value.isEmpty {
            return value
        }
        if let dict = playerRoot as? [String: Any],
           let responseContext = dict["responseContext"] as? [String: Any],
           let value = responseContext["visitorData"] as? String,
           !value.isEmpty {
            return value
        }
        return extractJSONStringValue(named: "VISITOR_DATA", from: html)
            ?? extractJSONStringValue(named: "visitorData", from: html)
    }

    private static func extractSignatureTimestamp(from ytcfg: [String: Any]?, html: String) -> Int? {
        if let sts = ytcfg?["STS"] as? Int {
            return sts
        }
        if let sts = ytcfg?["STS"] as? NSNumber {
            return sts.intValue
        }
        return extractJSONIntValue(named: "STS", from: html)
    }

    private static func extractJSONStringValue(named name: String, from html: String) -> String? {
        let pattern = #"""# + NSRegularExpression.escapedPattern(for: name) + #""\s*:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[valueRange])
    }

    private static func extractJSONIntValue(named name: String, from html: String) -> Int? {
        let pattern = #"""# + NSRegularExpression.escapedPattern(for: name) + #""\s*:\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: html)
        else { return nil }
        return Int(html[valueRange])
    }

    static func findCaptionTracks(in any: Any) -> [[String: Any]]? {
        if let dict = any as? [String: Any] {
            if let tracks = dict["captionTracks"] as? [[String: Any]], !tracks.isEmpty { return tracks }
            for (_, v) in dict {
                if let found = findCaptionTracks(in: v) { return found }
            }
        } else if let arr = any as? [Any] {
            for v in arr {
                if let found = findCaptionTracks(in: v) { return found }
            }
        }
        return nil
    }

    /// 优先简体中文 → 任意 zh → 英文 → 首条。
    static func selectCaptionTrack(from tracks: [[String: Any]]) -> [String: Any] {
        func code(_ t: [String: Any]) -> String {
            (t["languageCode"] as? String ?? "")
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
        }
        if let t = tracks.first(where: {
            let lang = code($0)
            return lang == "zh-hans" || lang.hasPrefix("zh-hans-") || lang == "zh-cn"
        }) { return t }
        if let t = tracks.first(where: { code($0).hasPrefix("zh") }) { return t }
        if let t = tracks.first(where: { code($0).hasPrefix("en") }) { return t }
        return tracks[0]
    }

    // MARK: - XML timedtext

    static func parseTimedTextXMLToPlain(_ xml: String) -> String {
        var lines: [String] = []
        let parts = xml.components(separatedBy: "</text>")
        for part in parts {
            guard let open = part.range(of: "<text", options: .caseInsensitive) else { continue }
            let tail = String(part[open.lowerBound...])
            guard let gt = tail.firstIndex(of: ">") else { continue }
            let attrs = String(tail[tail.startIndex..<gt])
            let inner = String(tail[tail.index(after: gt)...])
            let seconds = startSeconds(fromTimedTextAttributes: attrs)
            let mm = Int(seconds) / 60
            let ss = Int(seconds) % 60
            let decoded = decodeXMLEntities(inner)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !decoded.isEmpty {
                lines.append(String(format: "[%02d:%02d] %@", mm, ss, decoded))
            }
        }
        if lines.isEmpty {
            return xml.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        }
        return lines.joined(separator: "\n")
    }

    private static func startSeconds(fromTimedTextAttributes attrs: String) -> Double {
        guard let r = attrs.range(of: "start=\"", options: .literal) else { return 0 }
        let after = attrs[r.upperBound...]
        guard let end = after.firstIndex(of: "\"") else { return 0 }
        return Double(String(after[..<end])) ?? 0
    }

    private static func decodeXMLEntities(_ s: String) -> String {
        var r = s
        let map = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
            "&nbsp;": " "
        ]
        for (k, v) in map { r = r.replacingOccurrences(of: k, with: v) }
        return r
    }
}
