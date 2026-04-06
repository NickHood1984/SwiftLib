import Foundation
import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class YouTubeTranscriptFetcherTests: XCTestCase {
    /// 主路径：watch 页提取 API key → ANDROID InnerTube /player → timedtext XML
    func testFetchPlainTextViaAndroidInnerTubeXML() async throws {
        let captionURL = URL(string: "https://www.youtube.com/api/timedtext?lang=en&fmt=srv3")!
        // 去掉 &fmt=srv3 后的 URL
        let strippedCaptionURL = URL(string: "https://www.youtube.com/api/timedtext?lang=en")!
        let transport = MockTransport { request in
            switch (request.httpMethod ?? "GET", request.url?.host, request.url?.path) {
            case ("GET", "www.youtube.com", "/watch"):
                return Self.response(
                    url: request.url!,
                    body: Self.watchHTMLWithAPIKey()
                )
            case ("POST", "www.youtube.com", "/youtubei/v1/player"):
                let body = try XCTUnwrap(request.httpBody)
                let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(payload["videoId"] as? String, "abc123")
                let context = try XCTUnwrap(payload["context"] as? [String: Any])
                let client = try XCTUnwrap(context["client"] as? [String: Any])
                XCTAssertEqual(client["clientName"] as? String, "ANDROID")
                XCTAssertEqual(client["clientVersion"] as? String, "20.10.38")

                return Self.response(
                    url: request.url!,
                    contentType: "application/json",
                    body: Self.playerJSON(
                        tracks: [
                            ["languageCode": "en", "baseUrl": captionURL.absoluteString]
                        ]
                    )
                )
            case ("GET", "www.youtube.com", "/api/timedtext"):
                XCTAssertEqual(request.url, strippedCaptionURL)
                return Self.response(
                    url: request.url!,
                    contentType: "text/xml; charset=utf-8",
                    body: """
                    <transcript>
                      <text start="0.0">Hello world</text>
                    </transcript>
                    """
                )
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "nil")")
                throw MockError.unexpectedRequest
            }
        }

        let result = await YouTubeTranscriptFetcher.fetchPlainText(videoId: "abc123", transport: transport)

        guard case .success(let text) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(text, "[00:00] Hello world")
    }

    /// ANDROID 失败 → 回退到 watch HTML 解析 captionTracks
    func testFallsBackToWatchHTMLWhenAndroidFails() async {
        let captionURL = URL(string: "https://example.com/caption?lang=en")!
        let transport = MockTransport { request in
            switch (request.httpMethod ?? "GET", request.url?.host, request.url?.path) {
            case ("GET", "www.youtube.com", "/watch"):
                return Self.response(
                    url: request.url!,
                    body: Self.watchHTML(
                        tracks: [
                            ["languageCode": "en", "baseUrl": captionURL.absoluteString]
                        ]
                    )
                )
            case ("POST", "www.youtube.com", "/youtubei/v1/player"):
                // ANDROID InnerTube 返回无字幕
                return Self.response(
                    url: request.url!,
                    contentType: "application/json",
                    body: Self.playerJSON(tracks: [])
                )
            case ("GET", "example.com", "/caption"):
                return Self.response(
                    url: request.url!,
                    contentType: "text/xml; charset=utf-8",
                    body: """
                    <transcript>
                      <text start="0.0">Fallback line</text>
                    </transcript>
                    """
                )
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "nil")")
                throw MockError.unexpectedRequest
            }
        }

        let result = await YouTubeTranscriptFetcher.fetchPlainText(videoId: "abc123", transport: transport)

        guard case .success(let text) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(text, "[00:00] Fallback line")
    }

    func testNoCaptionTracksReturnsExpectedError() async {
        let transport = MockTransport { request in
            switch (request.httpMethod ?? "GET", request.url?.host, request.url?.path) {
            case ("GET", "www.youtube.com", "/watch"):
                return Self.response(
                    url: request.url!,
                    body: Self.watchHTMLWithAPIKey()
                )
            case ("POST", "www.youtube.com", "/youtubei/v1/player"):
                return Self.response(
                    url: request.url!,
                    contentType: "application/json",
                    body: Self.playerJSON(tracks: [])
                )
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "nil")")
                throw MockError.unexpectedRequest
            }
        }

        let result = await YouTubeTranscriptFetcher.fetchPlainText(videoId: "abc123", transport: transport)

        guard case .failure = result else {
            return XCTFail("Expected failure, got \(result)")
        }
    }

    func testSelectCaptionTrackPrefersZhHansThenZhThenEnglishThenFirst() {
        let zhHans = YouTubeTranscriptFetcher.selectCaptionTrack(from: [
            ["languageCode": "en", "baseUrl": "https://example.com/en"],
            ["languageCode": "zh-Hant", "baseUrl": "https://example.com/zh-hant"],
            ["languageCode": "zh-Hans", "baseUrl": "https://example.com/zh-hans"]
        ])
        XCTAssertEqual(zhHans["languageCode"] as? String, "zh-Hans")

        let zh = YouTubeTranscriptFetcher.selectCaptionTrack(from: [
            ["languageCode": "en", "baseUrl": "https://example.com/en"],
            ["languageCode": "zh-Hant", "baseUrl": "https://example.com/zh-hant"]
        ])
        XCTAssertEqual(zh["languageCode"] as? String, "zh-Hant")

        let english = YouTubeTranscriptFetcher.selectCaptionTrack(from: [
            ["languageCode": "fr", "baseUrl": "https://example.com/fr"],
            ["languageCode": "en-US", "baseUrl": "https://example.com/en-us"]
        ])
        XCTAssertEqual(english["languageCode"] as? String, "en-US")

        let first = YouTubeTranscriptFetcher.selectCaptionTrack(from: [
            ["languageCode": "fr", "baseUrl": "https://example.com/fr"],
            ["languageCode": "de", "baseUrl": "https://example.com/de"]
        ])
        XCTAssertEqual(first["languageCode"] as? String, "fr")
    }

    func testFallbackExhaustionSurfacesBlockedOrEmptyError() async {
        let captionURL = URL(string: "https://example.com/empty?lang=en")!
        let transport = MockTransport { request in
            switch (request.httpMethod ?? "GET", request.url?.host, request.url?.path) {
            case ("GET", "www.youtube.com", "/watch"):
                return Self.response(
                    url: request.url!,
                    body: Self.watchHTML(
                        tracks: [
                            ["languageCode": "en", "baseUrl": captionURL.absoluteString]
                        ]
                    )
                )
            case ("POST", "www.youtube.com", "/youtubei/v1/player"):
                return Self.response(
                    url: request.url!,
                    contentType: "application/json",
                    body: Self.playerJSON(
                        tracks: [
                            ["languageCode": "en", "baseUrl": captionURL.absoluteString]
                        ]
                    )
                )
            case ("GET", "example.com", "/empty"):
                return Self.response(url: request.url!, body: "")
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "nil")")
                throw MockError.unexpectedRequest
            }
        }

        let result = await YouTubeTranscriptFetcher.fetchPlainText(videoId: "abc123", transport: transport)

        guard case .failure(let error) = result,
              let fetchError = error as? YouTubeTranscriptFetcher.FetchError
        else {
            return XCTFail("Expected failure, got \(result)")
        }
        XCTAssertEqual(fetchError, .captionBlockedOrEmptyAfterFallback)
    }

    func testYtDlpFallbackReturnsTranscriptWhenBothPathsFail() async {
        let captionURL = URL(string: "https://example.com/empty?lang=en")!
        let transport = MockTransport { request in
            switch (request.httpMethod ?? "GET", request.url?.host, request.url?.path) {
            case ("GET", "www.youtube.com", "/watch"):
                return Self.response(
                    url: request.url!,
                    body: Self.watchHTML(
                        tracks: [
                            ["languageCode": "en", "baseUrl": captionURL.absoluteString]
                        ]
                    )
                )
            case ("POST", "www.youtube.com", "/youtubei/v1/player"):
                return Self.response(
                    url: request.url!,
                    contentType: "application/json",
                    body: Self.playerJSON(
                        tracks: [
                            ["languageCode": "en", "baseUrl": captionURL.absoluteString]
                        ]
                    )
                )
            case ("GET", "example.com", "/empty"):
                return Self.response(url: request.url!, body: "")
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "nil")")
                throw MockError.unexpectedRequest
            }
        }
        let externalFetcher = MockExternalFetcher(result: .success("[00:00] yt-dlp line"))

        let result = await YouTubeTranscriptFetcher.fetchPlainText(
            videoId: "abc123",
            transport: transport,
            externalFetcher: externalFetcher
        )

        guard case .success(let text) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(text, "[00:00] yt-dlp line")
        XCTAssertEqual(externalFetcher.requestedVideoIDs, ["abc123"])
    }

    func testYtDlpSubtitleFileSelectionPrefersPreferredLanguageAndFormat() {
        let files = [
            URL(fileURLWithPath: "/tmp/abc123.en.vtt"),
            URL(fileURLWithPath: "/tmp/abc123.zh-Hans.vtt"),
            URL(fileURLWithPath: "/tmp/abc123.zh-Hans.json3"),
            URL(fileURLWithPath: "/tmp/abc123.fr.json3")
        ]

        let chosen = YtDlpTranscriptFetcher.selectSubtitleFile(from: files)
        XCTAssertEqual(chosen?.lastPathComponent, "abc123.zh-Hans.json3")
    }

    func testYtDlpSelectionPrefersBestExactLanguageWithoutTranslatedSubs() {
        let selection = YtDlpTranscriptFetcher.selectSubtitleSelection(
            subtitles: [
                "en": [],
                "zh": [],
                "zh-Hant": []
            ],
            automaticCaptions: [
                "en": [],
                "zh": [],
                "zh-Hant": [],
                "zh-Hans-zh": []
            ]
        )

        XCTAssertEqual(selection?.languageCode, "zh")
        XCTAssertEqual(selection?.source, .manual)
    }

    func testYtDlpSelectionPrefersManualOverAutomaticForSameLanguage() {
        let selection = YtDlpTranscriptFetcher.selectSubtitleSelection(
            subtitles: [
                "en": []
            ],
            automaticCaptions: [
                "en": []
            ]
        )

        XCTAssertEqual(selection?.languageCode, "en")
        XCTAssertEqual(selection?.source, .manual)
    }

    // MARK: - Helpers

    private static func watchHTMLWithAPIKey(apiKey: String = "test-key") -> String {
        """
        <html><body>
        <script>ytcfg.set({"INNERTUBE_API_KEY":"\(apiKey)"});</script>
        </body></html>
        """
    }

    private static func watchHTML(
        tracks: [[String: Any]],
        apiKey: String = "test-key",
        visitorData: String = "visitor-1",
        signatureTimestamp: Int = 20179
    ) -> String {
        let ytcfg = jsonString([
            "INNERTUBE_API_KEY": apiKey,
            "INNERTUBE_CONTEXT": [
                "client": [
                    "visitorData": visitorData
                ]
            ],
            "STS": signatureTimestamp
        ])
        let player = playerJSON(tracks: tracks, visitorData: visitorData)
        return """
        <html><body>
        <script>ytcfg.set(\(ytcfg));</script>
        <script>var ytInitialPlayerResponse = \(player);</script>
        </body></html>
        """
    }

    private static func playerJSON(
        tracks: [[String: Any]],
        visitorData: String = "visitor-1"
    ) -> String {
        jsonString([
            "captions": [
                "playerCaptionsTracklistRenderer": [
                    "captionTracks": tracks
                ]
            ],
            "responseContext": [
                "visitorData": visitorData
            ]
        ])
    }

    private static func jsonString(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private static func response(
        url: URL,
        status: Int = 200,
        contentType: String = "text/html; charset=utf-8",
        body: String
    ) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
        return (Data(body.utf8), response)
    }
}

private enum MockError: Error {
    case unexpectedRequest
}

private final class MockTransport: YouTubeTranscriptTransport {
    private let handler: (URLRequest) throws -> (Data, URLResponse)

    init(handler: @escaping (URLRequest) throws -> (Data, URLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try handler(request)
    }
}

private final class MockExternalFetcher: YouTubeTranscriptExternalFetcher {
    private let result: Result<String, Error>
    private(set) var requestedVideoIDs: [String] = []

    init(result: Result<String, Error>) {
        self.result = result
    }

    func fetchPlainText(videoId: String) async throws -> String {
        requestedVideoIDs.append(videoId)
        return try result.get()
    }
}
