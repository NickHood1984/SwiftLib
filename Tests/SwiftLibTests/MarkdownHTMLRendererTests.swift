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
}
