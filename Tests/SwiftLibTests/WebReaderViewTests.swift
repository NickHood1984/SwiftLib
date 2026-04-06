import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class WebReaderViewTests: XCTestCase {
    func testTranscriptMarkupDetectionIgnoresCSSClassDefinitions() {
        let html = """
        <html>
        <head>
          <style>
            .swiftlib-yt-transcript { border: 1px solid red; }
          </style>
        </head>
        <body>
          <article class="article"><div id="article-content">Hello</div></article>
        </body>
        </html>
        """

        XCTAssertFalse(WebReaderViewModel.htmlContainsRenderedTranscriptBlock(html))
    }

    func testTranscriptMarkupDetectionRecognizesRenderedBlockAndPlaceholder() {
        let rendered = #"<details class="swiftlib-yt-transcript" open><summary>字幕 / Transcript</summary><pre>x</pre></details>"#
        XCTAssertTrue(WebReaderViewModel.htmlContainsRenderedTranscriptBlock(rendered))

        let placeholder = #"<div id="swiftlib-yt-transcript-loading" class="swiftlib-yt-transcript"></div>"#
        XCTAssertTrue(WebReaderViewModel.htmlContainsRenderedTranscriptBlock(placeholder))
    }

    func testYouTubeCoverCleanupRemovesLeadingStandaloneMediaBlock() {
        let html = """
        <div class="swiftlib-md-media-block"><img class="swiftlib-md-image" src="https://img.youtube.com/vi/demo/mqdefault.jpg" alt="cover" loading="lazy"></div>
        <p>正文第一段</p>
        """

        let cleaned = WebReaderViewModel.htmlByRemovingLeadingYouTubeCoverMedia(html)

        XCTAssertFalse(cleaned.contains("swiftlib-md-media-block"))
        XCTAssertTrue(cleaned.contains("<p>正文第一段</p>"))
    }

    func testYouTubeCleanupRemovesLegacyFallbackShellAndSummary() {
        let html = """
        <article class="swiftlib-youtube-fallback"><div class="swiftlib-yt-player-shell" data-watch-url="https://www.youtube.com/watch?v=demo"><button class="swiftlib-yt-player-wrap" type="button"><img src="https://img.youtube.com/vi/demo/maxresdefault.jpg" alt=""><div class="swiftlib-yt-play-btn">▶</div></button><div class="swiftlib-yt-player-actions"><a class="swiftlib-yt-open-link" href="https://www.youtube.com/watch?v=demo" target="_blank" rel="noopener noreferrer">在浏览器中打开</a></div></div><p class="swiftlib-yt-desc">摘要</p><details class="swiftlib-yt-transcript" open><summary>字幕 / Transcript</summary><pre>line</pre></details></article>
        """

        let cleaned = WebReaderViewModel.cleanedYouTubeArticleBodyHTML(html)

        XCTAssertFalse(cleaned.contains("swiftlib-yt-player-shell"))
        XCTAssertFalse(cleaned.contains("swiftlib-yt-desc"))
        XCTAssertFalse(cleaned.contains("在浏览器中打开"))
        XCTAssertTrue(cleaned.contains("swiftlib-yt-transcript"))
    }
}
