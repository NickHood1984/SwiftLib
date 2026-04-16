import Foundation
import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class MarkdownHTMLRendererTests: XCTestCase {
    func testRenderProducesParagraphsThematicBreaksAndImages() {
        let markdown = """
        **十里** @okooo5km [2026-03-25](https://x.com/example/status/1)

        轻拟物风格图标可根据主题稳定输出，革自己的老命

        ![Image](https://pbs.twimg.com/media/example.jpg)

        ---

        第二段。
        """

        let html = MarkdownHTMLRenderer.render(markdown: markdown, baseURL: nil)

        XCTAssertTrue(html.contains("<p><strong>十里</strong> @okooo5km"))
        XCTAssertTrue(html.contains(#"<a href="https://x.com/example/status/1">2026-03-25</a>"#))
        XCTAssertTrue(html.contains("<p>轻拟物风格图标可根据主题稳定输出，革自己的老命</p>"))
        XCTAssertTrue(html.contains(#"<img class="swiftlib-md-image" src="https://pbs.twimg.com/media/example.jpg" alt="Image" loading="lazy">"#))
        XCTAssertTrue(html.contains("<hr>"))
        XCTAssertTrue(html.contains("<p>第二段。</p>"))
    }

    func testRenderResolvesRelativeLinksAndImagesAgainstBaseURL() {
        let markdown = """
        [Read more](/article)

        ![Hero](images/cover.png)
        """
        let baseURL = URL(string: "https://example.com/posts/swiftlib")!

        let html = MarkdownHTMLRenderer.render(markdown: markdown, baseURL: baseURL)

        XCTAssertTrue(html.contains(#"<a href="https://example.com/article">Read more</a>"#))
        XCTAssertTrue(html.contains(#"src="https://example.com/posts/images/cover.png""#))
    }

    func testRenderSupportsListsBlockquotesAndInlineCode() {
        let markdown = """
        > quoted line

        - first
        - second

        Run `swift test`
        """

        let html = MarkdownHTMLRenderer.render(markdown: markdown, baseURL: nil)

        XCTAssertTrue(html.contains("<blockquote><p>quoted line</p></blockquote>"))
        XCTAssertTrue(html.contains("<ul><li>first</li><li>second</li></ul>"))
        XCTAssertTrue(html.contains("<p>Run <code>swift test</code></p>"))
    }

    func testRenderPreservesInlineAndDisplayMathAsSafeHTMLFallback() {
        let markdown = """
        Inline math: $E = mc^2$

        $$
        a^2 + b^2 = c^2
        $$
        """

        let html = MarkdownHTMLRenderer.render(markdown: markdown, baseURL: nil)

        XCTAssertTrue(html.contains("<p>Inline math: $E = mc^2$</p>"))
        XCTAssertTrue(html.contains("<div class=\"math-display\">$$"))
        XCTAssertTrue(html.contains("a^2 + b^2 = c^2"))
        XCTAssertTrue(html.contains("$$</div>"))
    }

    func testRenderConvertsOCRSuperscriptMarkersInParagraphText() {
        let markdown = "Daniel I. Peters $ ^{a,1} $ $$ ^{ID} $$, Lyndsie M. Collis $ ^{a,b,1,2,*} $"

        let html = MarkdownHTMLRenderer.render(markdown: markdown, baseURL: nil)

        XCTAssertTrue(html.contains("Daniel I. Peters <sup>a,1</sup> <sup>ID</sup>"))
        XCTAssertTrue(html.contains("Lyndsie M. Collis <sup>a,b,1,2,*</sup>"))
    }

    func testRenderConvertsOCRSuperscriptMarkersInsideRawHTMLTable() {
        let markdown = #"<table><tr><td>Species</td><td>Filter feeder: pico- and nanoplankton $ ^{a,b} $</td><td>Limited avoidance, adaptive tolerance $ ^{1} $</td></tr></table>"#

        let html = MarkdownHTMLRenderer.render(markdown: markdown, baseURL: nil)

        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("Filter feeder: pico- and nanoplankton <sup>a,b</sup>"))
        XCTAssertTrue(html.contains("Limited avoidance, adaptive tolerance <sup>1</sup>"))
    }
}
