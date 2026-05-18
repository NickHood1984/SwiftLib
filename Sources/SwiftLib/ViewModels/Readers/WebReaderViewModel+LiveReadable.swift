import Foundation

extension WebReaderViewModel {
    func setDisplayMode(_ mode: WebReaderDisplayMode) {
        guard mode != displayMode else { return }
        liveReadableUserMessage = nil
        displayMode = mode
        switch mode {
        case .clippedMarkdown:
            cancelTranscriptLoad()
            cancelLiveReadableSafetyTimeout()
            shouldLoadOriginalURLForReadable = false
            isLiveReadableBusy = false
            resetLiveReadableNavigation?()
            renderContent()
        case .liveReadable:
            let u = reference.resolvedWebReaderURLString() ?? ""
            guard !u.isEmpty, URL(string: u) != nil else {
                liveReadableUserMessage = "没有可用于在线阅读的有效链接。"
                displayMode = .clippedMarkdown
                return
            }
            shouldLoadOriginalURLForReadable = true
            isLiveReadableBusy = true
            scheduleLiveReadableSafetyTimeout()
            let host = URL(string: u)?.host ?? ""
            onlineReadableLog.notice("开始在线阅读 host=\(host, privacy: .public) youtube=\(self.reference.isLikelyYouTubeWatchURL, privacy: .public) — 使用内置 ClipperDefuddle.js，非扩展的 reader-script / Reader.apply")
        }
    }

    func scheduleLiveReadableSafetyTimeout() {
        liveReadableSafetyTask?.cancel()
        let seconds: UInt64 = 90
        liveReadableSafetyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard displayMode == .liveReadable, isLiveReadableBusy else { return }
            readableExtractionFailed(message: "加载或提取正文超时（约 \(seconds) 秒）。请检查网络、页面是否需登录，或改用「剪藏正文」。")
        }
    }

    private func cancelLiveReadableSafetyTimeout() {
        liveReadableSafetyTask?.cancel()
        liveReadableSafetyTask = nil
    }

    /// 由 Coordinator 在开始加载原文 URL 后调用，避免重复触发导航。
    func acknowledgeOriginalURLLoadStarted() {
        shouldLoadOriginalURLForReadable = false
    }

    func readableExtractionFailed(message: String) {
        cancelTranscriptLoad()
        cancelLiveReadableSafetyTimeout()
        isLiveReadableBusy = false
        liveReadableUserMessage = message
        onlineReadableLog.error("在线阅读失败: \(message, privacy: .public)")
        displayMode = .clippedMarkdown
        renderContent()
    }

    func applyReadableExtractionResult(
        title: String?,
        contentHTML: String,
        excerpt: String?,
        byline: String?,
        includeClipperTypography: Bool,
        eyebrowText: String = "在线阅读"
    ) {
        cancelTranscriptLoad()
        var trimmed = contentHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            readableExtractionFailed(message: "在线阅读失败：提取结果为空。")
            return
        }

        isLiveReadableBusy = true
        let ref = reference
        let fs = fontSize
        let cw = contentWidth

        let isYouTube = ref.youTubeVideoId != nil
        // 对 YouTube 条目，清掉抽取结果里的旧播放器/封面/摘要块，只保留正文与字幕。
        if isYouTube {
            trimmed = Self.cleanedYouTubeArticleBodyHTML(trimmed)
        }

        let finalBody = trimmed

        Task.detached(priority: .userInitiated) {
            let html = Self.buildHTMLDocument(
                reference: ref,
                articleBodyHTML: finalBody,
                fontSize: fs,
                contentWidth: cw,
                eyebrowText: eyebrowText,
                headerTitle: title,
                // YouTube：header 不用条目 abstract（正文已有描述），见 omitReferenceAbstract
                summaryText: isYouTube ? nil : excerpt,
                authorOverride: byline,
                includeClipperTypography: includeClipperTypography,
                omitReferenceAbstract: isYouTube,
                omitArticleHeader: isYouTube
            )
            await MainActor.run {
                self.currentArticleBodyHTML = finalBody
                self.shouldPersistTranscriptIntoReference = ref.decodedWebContent?.format == .html
                self.renderedHTML = html
                self.isLiveReadableBusy = false
                self.cancelLiveReadableSafetyTimeout()
                if let vid = ref.youTubeVideoId {
                    self.scheduleYouTubeTranscriptMerge(videoId: vid)
                }
            }
        }
    }

    /// 异步拉取 YouTube 字幕并插入到已渲染的 HTML 中。
}
