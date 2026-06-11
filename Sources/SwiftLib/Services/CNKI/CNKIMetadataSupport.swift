import Foundation
import OSLog
import SwiftLibCore
import WebKit
import CoreFoundation

let cnkiMetadataLog = Logger(subsystem: "SwiftLib", category: "CNKIMetadata")

func cnkiDebugTrace(_ message: String) {
    guard SwiftLibDebugLogging.metadataVerbose else { return }
    cnkiMetadataLog.notice("\(message, privacy: .public)")
    if let data = "[CNKIMetadata] \(message)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

@MainActor
final class CNKIParserWebViewPool {
    var available: [WKWebView] = []
    let maxSize = 2

    func acquire(configureDataStore: (WKWebViewConfiguration) -> Void) -> WKWebView {
        if let webView = available.popLast() {
            return webView
        }
        let config = WKWebViewConfiguration()
        HiddenWKWebViewMediaGuard.configure(config)
        configureDataStore(config)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = ReaderExtractionManager.safariLikeUserAgent
        return webView
    }

    func release(_ webView: WKWebView) {
        webView.navigationDelegate = nil
        webView.stopLoading()
        guard available.count < maxSize else { return }
        webView.loadHTMLString("", baseURL: nil)
        available.append(webView)
    }
}

extension CNKIMetadataProvider {
    func decodeCNKIHTML(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
            return utf8
        }
        if let gb18030 = String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))), !gb18030.isEmpty {
            return gb18030
        }
        return String(data: data, encoding: .unicode)
    }


    func firstRegexCapture(in text: String, patterns: [String]) -> String? {
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

    func evaluateJSONScript<T: Decodable>(_ script: String, in webView: WKWebView) async throws -> T {
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

}

@MainActor
final class HTMLLoadDelegate: NSObject, WKNavigationDelegate {
    var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    func load(html: String, in webView: WKWebView, baseURL: URL, timeout: TimeInterval = 15) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            // Offscreen loadHTMLString occasionally never reaches didFinish
            // (e.g. content-process churn); without a deadline that strands the
            // caller — and the whole metadata pipeline — forever.
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(throwing: CNKIMetadataProvider.CNKIError.timedOut)
            }
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    private func finish(throwing error: Error? = nil) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuation = continuation
        self.continuation = nil
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(throwing: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(throwing: error)
    }
}
