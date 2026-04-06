import WebKit
import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class HiddenWKWebViewHostTests: XCTestCase {
    func testBackgroundWebViewConfigurationSuppressesMediaPlayback() {
        let configuration = WKWebViewConfiguration()

        HiddenWKWebViewMediaGuard.configure(configuration)

        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, .all)
        XCTAssertFalse(configuration.allowsAirPlayForMediaPlayback)
        XCTAssertTrue(
            configuration.userContentController.userScripts.contains {
                $0.injectionTime == .atDocumentStart &&
                $0.source.contains("HTMLMediaElement") &&
                $0.source.contains("pause()")
            }
        )
    }
}
