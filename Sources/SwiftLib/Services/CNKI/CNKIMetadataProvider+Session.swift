import Foundation
import SwiftLibCore
import WebKit

extension CNKIMetadataProvider {
    func requireWebView() async throws -> WKWebView {
        for _ in 0..<80 {
            if let webView { return webView }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw CNKIError.webViewNotReady
    }

    func recoverPreparedOutputIfPossible(
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

    func recoverResolvedRecordIfPossible(candidate: MetadataCandidate) async -> AuthoritativeMetadataRecord? {
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

    static func urlMatchesCNKIDetail(_ current: URL, _ candidate: URL) -> Bool {
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


    func runOperation(_ operation: PendingOperation) async throws -> OperationOutput {
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

    func performOperation(_ operation: PendingOperation, in webView: WKWebView) async throws -> OperationOutput {
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

    func url(for operation: PendingOperation) -> URL {
        switch operation {
        case .search(let seed):
            var components = URLComponents(url: Self.mainlandCNKIHomeURL, resolvingAgainstBaseURL: false)!
            let query = Self.searchKeyword(for: seed) ?? MetadataResolution.normalizeWhitespaceAndWidth(seed.fileName)
            components.queryItems = [URLQueryItem(name: "kw", value: query)]
            return components.url!
        case .resolve(let candidate):
            return URL(string: candidate.detailURL)!
        }
    }

    func verificationURL(for operation: PendingOperation, currentURL: URL?) -> URL {
        if let currentURL {
            return currentURL
        }
        switch operation {
        case .search:
            // 使用带关键词的搜索 URL，让验证窗口直接展示搜索结果，
            // 而不是一个没有 kw= 参数的空白页。
            return url(for: operation)
        case .resolve(let candidate):
            return URL(string: candidate.detailURL) ?? Self.mainlandCNKIHomeURL
        }
    }

    func scheduleInspection(for webView: WKWebView) {
        inspectionTask?.cancel()
        inspectionTask = Task { @MainActor [weak self] in
            // Quick first check after 200ms; if page isn't ready, retry after another 650ms.
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self, self.pendingContinuation != nil, self.webView === webView else { return }
            let state = await self.pageResolutionState(in: webView)
            if state.isReady {
                await self.inspectLoadedPage(in: webView)
                return
            }
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled, self.pendingContinuation != nil, self.webView === webView else { return }
            await self.inspectLoadedPage(in: webView)
        }
    }

    func inspectLoadedPage(in webView: WKWebView) async {
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


    func requestVerification(
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


    func complete(_ output: OperationOutput) {
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

    func fail(_ error: Error) {
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
