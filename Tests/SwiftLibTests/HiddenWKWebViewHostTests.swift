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

    func testWebExportInterceptionDetectsStructuredFormats() {
        XCTAssertEqual(
            WebExportInterception.detectFormat(
                url: URL(string: "https://example.com/export.ris"),
                mimeType: "application/x-research-info-systems"
            ),
            .ris
        )
        XCTAssertEqual(
            WebExportInterception.detectFormat(
                url: URL(string: "https://example.com/citation"),
                label: "BibTeX"
            ),
            .bibTeX
        )
    }

    @MainActor
    func testWebSessionBrokerUsesPersistentStores() {
        let configuration = WKWebViewConfiguration()
        let profile = WebSessionBroker.shared.scholarlyProfile(for: URL(string: "https://kns.cnki.net"))

        WebSessionBroker.shared.configure(configuration, profile: profile)

        XCTAssertTrue(configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(configuration.websiteDataStore.identifier, WebSessionBroker.shared.dataStore(for: profile).identifier)
    }
}
