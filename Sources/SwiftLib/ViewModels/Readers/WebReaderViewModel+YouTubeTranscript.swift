import Foundation
import SwiftLibCore

extension WebReaderViewModel {
    func scheduleYouTubeTranscriptMerge(videoId: String) {
        cancelTranscriptLoad()
        if Self.htmlContainsRenderedTranscriptBlock(renderedHTML) {
            onlineReadableLog.notice("YouTube 字幕已存在于页内 fallback，跳过网络抓取 vid=\(videoId)")
            return
        }
        // 先插入"正在加载字幕"占位符
        if let placeholder = Self.htmlInsertingYouTubeTranscriptPlaceholder(renderedHTML) {
            renderedHTML = placeholder
        }

        transcriptLoadSequence &+= 1
        let sequence = transcriptLoadSequence
        var pendingSources: Set<TranscriptLoadSource> = [.network]
        if canAttemptTranscriptDOMFallback {
            pendingSources.insert(.dom)
        }
        transcriptLoadState = TranscriptLoadState(
            sequence: sequence,
            pendingSources: pendingSources,
            failures: [:],
            resolved: false
        )

        let networkTask = Task(priority: .utility) { [weak self] in
            let result = await YouTubeTranscriptFetcher.fetchPlainText(videoId: videoId)
            guard let self else { return }
            self.handleNetworkTranscriptResult(result, videoId: videoId, sequence: sequence)
        }
        transcriptLoadTasks.append(networkTask)

        if canAttemptTranscriptDOMFallback {
            let domTask = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                let transcript = await self.fetchTranscriptDOMFallbackText(videoId: videoId)
                self.handleDOMTranscriptResult(transcript, videoId: videoId, sequence: sequence)
            }
            transcriptLoadTasks.append(domTask)
        }

        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.transcriptLoadTimeoutNanoseconds)
            self?.handleTranscriptLoadTimeout(videoId: videoId, sequence: sequence)
        }
        transcriptLoadTasks.append(timeoutTask)
    }

    private var canAttemptTranscriptDOMFallback: Bool {
        reference.isLikelyYouTubeWatchURL
            && reference.resolvedWebReaderURLString() != nil
            && fetchTranscriptFromOriginalPage != nil
    }

    private func fetchTranscriptDOMFallbackText(videoId: String) async -> String? {
        guard reference.isLikelyYouTubeWatchURL,
              let urlString = reference.resolvedWebReaderURLString(),
              let fetcher = fetchTranscriptFromOriginalPage else {
            return nil
        }

        onlineReadableLog.notice("并行启动隐藏 WKWebView transcript DOM fallback vid=\(videoId, privacy: .public)")
        guard let transcript = await fetcher(urlString) else {
            return nil
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func handleNetworkTranscriptResult(
        _ result: Result<String, Error>,
        videoId: String,
        sequence: UInt64
    ) {
        guard let state = transcriptLoadState,
              state.sequence == sequence,
              !state.resolved else {
            return
        }

        switch result {
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                onlineReadableLog.notice("YouTube 网络字幕为空 vid=\(videoId, privacy: .public)")
                recordTranscriptFailure(
                    source: .network,
                    message: "该视频字幕内容为空。",
                    sequence: sequence
                )
                return
            }
            onlineReadableLog.notice("YouTube 网络字幕成功 vid=\(videoId, privacy: .public) length=\(trimmed.count, privacy: .public)")
            completeTranscriptLoad(with: trimmed, source: .network, videoId: videoId, sequence: sequence)
        case .failure(let error):
            let msg = (error as? YouTubeTranscriptFetcher.FetchError)?.errorDescription ?? error.localizedDescription
            onlineReadableLog.error("YouTube 网络字幕失败 vid=\(videoId, privacy: .public) error=\(msg, privacy: .public)")
            recordTranscriptFailure(source: .network, message: msg, sequence: sequence)
        }
    }

    private func handleDOMTranscriptResult(_ transcript: String?, videoId: String, sequence: UInt64) {
        guard let state = transcriptLoadState,
              state.sequence == sequence,
              !state.resolved else {
            return
        }

        guard let transcript else {
            onlineReadableLog.notice("YouTube transcript DOM fallback 未返回内容 vid=\(videoId, privacy: .public)")
            recordTranscriptFailure(
                source: .dom,
                message: "页面 transcript 面板未返回内容。",
                sequence: sequence
            )
            return
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onlineReadableLog.notice("YouTube transcript DOM fallback 返回空字幕 vid=\(videoId, privacy: .public)")
            recordTranscriptFailure(
                source: .dom,
                message: "页面 transcript 面板未返回内容。",
                sequence: sequence
            )
            return
        }

        onlineReadableLog.notice("YouTube transcript DOM fallback 成功 vid=\(videoId, privacy: .public) length=\(trimmed.count, privacy: .public)")
        completeTranscriptLoad(with: trimmed, source: .dom, videoId: videoId, sequence: sequence)
    }

    private func completeTranscriptLoad(
        with transcript: String,
        source: TranscriptLoadSource,
        videoId: String,
        sequence: UInt64
    ) {
        guard var state = transcriptLoadState,
              state.sequence == sequence,
              !state.resolved else {
            return
        }

        state.resolved = true
        state.pendingSources.removeAll()
        transcriptLoadState = state
        cancelTranscriptLoadTasks()

        let lines = transcript.components(separatedBy: "\n")
        var htmlLines: [String] = []
        for line in lines {
            let escaped = line
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            if let range = escaped.range(of: #"^\[(\d{2}):(\d{2})\]"#, options: .regularExpression) {
                let timestamp = String(escaped[range])
                let rest = String(escaped[range.upperBound...])
                let digits = timestamp.filter { $0.isNumber }
                if digits.count == 4 {
                    let mm = Int(digits.prefix(2)) ?? 0
                    let ss = Int(digits.suffix(2)) ?? 0
                    let totalSeconds = mm * 60 + ss
                    let link = "<a href=\"javascript:void(0)\" class=\"swiftlib-yt-ts\" data-time=\"\(totalSeconds)\" onclick=\"window.SwiftLibReader && window.SwiftLibReader.seekYouTube(\(totalSeconds))\">\(timestamp)</a>"
                    htmlLines.append("<span class=\"swiftlib-yt-line\">\(link)\(rest)</span>")
                    continue
                }
            }
            htmlLines.append("<span class=\"swiftlib-yt-line\">\(escaped)</span>")
        }
        let transcriptHTML = htmlLines.joined(separator: "\n")
        let block = "<details class=\"swiftlib-yt-transcript\" open><summary>字幕 / Transcript</summary><div class=\"swiftlib-yt-transcript-body\">\(transcriptHTML)</div></details>"
        replaceTranscriptPlaceholder(with: block, isHTML: true)
        if let bodyHTML = currentArticleBodyHTML,
           !Self.htmlContainsRenderedTranscriptBlock(bodyHTML) {
            let mergedBodyHTML = Self.htmlByAppendingHTMLBlockToArticle(bodyHTML, blockHTML: block)
            currentArticleBodyHTML = mergedBodyHTML
            persistTranscriptIntoStoredReferenceIfNeeded(mergedBodyHTML)
        }
        onlineReadableLog.notice("YouTube 字幕完成 source=\(String(describing: source), privacy: .public) vid=\(videoId, privacy: .public)")
    }

    private func recordTranscriptFailure(
        source: TranscriptLoadSource,
        message: String,
        sequence: UInt64
    ) {
        guard var state = transcriptLoadState,
              state.sequence == sequence,
              !state.resolved else {
            return
        }

        state.pendingSources.remove(source)
        state.failures[source] = message

        if state.pendingSources.isEmpty {
            state.resolved = true
            transcriptLoadState = state
            cancelTranscriptLoadTasks()
            replaceTranscriptPlaceholder(with: Self.transcriptFailureMessage(failures: state.failures))
            return
        }

        transcriptLoadState = state
    }

    private func handleTranscriptLoadTimeout(videoId: String, sequence: UInt64) {
        guard var state = transcriptLoadState,
              state.sequence == sequence,
              !state.resolved else {
            return
        }

        state.resolved = true
        transcriptLoadState = state
        cancelTranscriptLoadTasks()
        let message = Self.transcriptTimeoutMessage(failures: state.failures)
        onlineReadableLog.error("YouTube 字幕加载超时 vid=\(videoId, privacy: .public) message=\(message, privacy: .public)")
        replaceTranscriptPlaceholder(with: message)
    }

    func cancelTranscriptLoad() {
        cancelTranscriptLoadTasks()
        transcriptLoadState = nil
    }

    private func cancelTranscriptLoadTasks() {
        transcriptLoadTasks.forEach { $0.cancel() }
        transcriptLoadTasks.removeAll()
    }

    nonisolated private static let transcriptPlaceholderId = "swiftlib-yt-transcript-loading"
    nonisolated private static let transcriptLoadTimeoutNanoseconds: UInt64 = 15_000_000_000

    nonisolated static func htmlContainsRenderedTranscriptBlock(_ html: String) -> Bool {
        html.contains("<details class=\"swiftlib-yt-transcript\"")
            || html.contains("<div id=\"\(transcriptPlaceholderId)\"")
    }

    private func persistTranscriptIntoStoredReferenceIfNeeded(_ articleBodyHTML: String) {
        guard shouldPersistTranscriptIntoReference,
              reference.youTubeVideoId != nil,
              let referenceID = reference.id,
              let encoded = Reference.encodeWebContent(articleBodyHTML, format: .html) else {
            return
        }

        let db = self.db
        Task.detached(priority: .utility) {
            do {
                try db.updateReferenceWebContent(id: referenceID, webContent: encoded)
            } catch {
                onlineReadableLog.error("缓存 YouTube 正文失败 refId=\(referenceID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func htmlInsertingYouTubeTranscriptPlaceholder(_ html: String) -> String? {
        let block = "<div id=\"\(transcriptPlaceholderId)\" class=\"swiftlib-yt-transcript\"><summary style=\"list-style:none;padding:10px 14px;font-size:14px;color:#6b7280;\">正在加载字幕…</summary></div>"
        guard let range = html.range(of: "</article>", options: .backwards) else { return nil }
        return String(html[..<range.lowerBound]) + block + String(html[range.lowerBound...])
    }

    private static func htmlByAppendingHTMLBlockToArticle(_ html: String, blockHTML: String) -> String {
        if let range = html.range(of: "</article>", options: .backwards) {
            return String(html[..<range.lowerBound]) + blockHTML + String(html[range.lowerBound...])
        }
        return html + blockHTML
    }

    nonisolated private static func transcriptFailureMessage(failures: [TranscriptLoadSource: String]) -> String {
        if let network = failures[.network]?.trimmingCharacters(in: .whitespacesAndNewlines), !network.isEmpty {
            return network
        }
        if let dom = failures[.dom]?.trimmingCharacters(in: .whitespacesAndNewlines), !dom.isEmpty {
            return dom
        }
        return "字幕不可用。"
    }

    nonisolated private static func transcriptTimeoutMessage(failures: [TranscriptLoadSource: String]) -> String {
        let base = "字幕加载超时，请稍后重试。"
        if let network = failures[.network]?.trimmingCharacters(in: .whitespacesAndNewlines), !network.isEmpty {
            return "\(base) 当前结果：\(network)"
        }
        return base
    }

    private func replaceTranscriptPlaceholder(with content: String, isHTML: Bool = false) {
        let placeholderId = Self.transcriptPlaceholderId
        guard let startRange = renderedHTML.range(of: "<div id=\"\(placeholderId)\"") else {
            // 占位符不在，直接在 </article> 前插入
            if isHTML {
                if let range = renderedHTML.range(of: "</article>", options: .backwards) {
                    renderedHTML = String(renderedHTML[..<range.lowerBound]) + content + String(renderedHTML[range.lowerBound...])
                }
            }
            return
        }
        // 找到占位符的结束 </div>
        let afterStart = renderedHTML[startRange.lowerBound...]
        guard let endRange = afterStart.range(of: "</div>") else { return }
        let fullRange = startRange.lowerBound..<endRange.upperBound

        if isHTML {
            renderedHTML.replaceSubrange(fullRange, with: content)
        } else {
            let escaped = content
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
            let errorBlock = "<div class=\"swiftlib-yt-transcript\"><summary style=\"list-style:none;padding:10px 14px;font-size:14px;color:#6b7280;\">字幕不可用：\(escaped)</summary></div>"
            renderedHTML.replaceSubrange(fullRange, with: errorBlock)
        }
    }

}
