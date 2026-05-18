import SwiftUI
import WebKit
import AppKit

// MARK: - OCR Markdown View

struct OCRMarkdownView: View {
    let markdown: String
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var translatedMarkdown: String?
    @State private var showOriginalMarkdown = false
    @State private var isShowingPromptEditor = false
    @State private var promptTemplate = SwiftLibPreferences.ocrDocumentTranslationPromptTemplate
    @State private var translationProgress: OCRDocumentTranslationService.Progress?
    @State private var translationError: String?
    @State private var isTranslating = false
    @State private var translationTask: Task<Void, Never>?

    private var renderedHTML: String {
        OCRMarkdownWebView.documentHTML(for: activeMarkdown, colorScheme: colorScheme)
    }

    private var activeMarkdown: String {
        if let translatedMarkdown, !showOriginalMarkdown {
            return translatedMarkdown
        }
        return markdown
    }

    private var copyHelpText: String {
        translatedMarkdown == nil || showOriginalMarkdown ? "复制当前 Markdown" : "复制当前双语 Markdown"
    }

    private var targetLanguageName: String {
        SwiftLibPreferences.abstractTranslationLanguageOptions
            .first { $0.code == SwiftLibPreferences.abstractTranslationLanguage }?
            .name ?? "中文"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("智能识别结果", systemImage: "doc.text.viewfinder")
                    .font(.headline)
                Spacer()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(activeMarkdown, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help(copyHelpText)

                if translatedMarkdown != nil {
                    Button(showOriginalMarkdown ? "查看双语" : "查看原文") {
                        showOriginalMarkdown.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                }

                Button {
                    if isTranslating {
                        translationTask?.cancel()
                    } else {
                        promptTemplate = SwiftLibPreferences.ocrDocumentTranslationPromptTemplate
                        isShowingPromptEditor = true
                    }
                } label: {
                    if isTranslating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("停止翻译")
                                .font(.system(size: 12))
                        }
                    } else {
                        Label(translatedMarkdown == nil ? "连续翻译" : "重新翻译", systemImage: "character.book.closed")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.borderless)
                .help("通过 AI 助手自动分段翻译整篇 OCR Markdown")

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("返回 PDF")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            if let translationProgress {
                HStack(spacing: 8) {
                    ProgressView(
                        value: Double(translationProgress.completedBlocks),
                        total: Double(max(translationProgress.totalBlocks, 1))
                    )
                    .controlSize(.small)

                    Text("已翻译 \(translationProgress.completedBlocks)/\(translationProgress.totalBlocks) 段")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if translationProgress.failedBlocks > 0 {
                        Text("· 跳过 \(translationProgress.failedBlocks) 段")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    Text("第 \(translationProgress.completedBatches)/\(translationProgress.totalBatches) 批")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }

            if let translationError, !translationError.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(translationError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }

            Divider()

            OCRMarkdownWebView(html: renderedHTML)
                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color(nsColor: NSColor(calibratedWhite: 0.08, alpha: 1.0)) : .white)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sheet(isPresented: $isShowingPromptEditor) {
            OCRTranslationPromptEditorSheet(
                promptTemplate: $promptTemplate,
                targetLanguageName: targetLanguageName
            ) {
                startContinuousTranslation()
            }
        }
        .onAppear {
            // 启动时尝试从磁盘恢复之前已经翻译过的双语 markdown
            loadCachedTranslationIfAvailable()
        }
        .onChange(of: markdown) { _, _ in
            translationTask?.cancel()
            translationTask = nil
            translatedMarkdown = nil
            showOriginalMarkdown = false
            translationProgress = nil
            translationError = nil
            isTranslating = false
            // 切到新 PDF 后再读一次缓存
            loadCachedTranslationIfAvailable()
        }
        .onDisappear {
            translationTask?.cancel()
        }
    }

    private func loadCachedTranslationIfAvailable() {
        let cached = OCRTranslationCache.load(
            sourceMarkdown: markdown,
            targetLanguage: targetLanguageName
        )
        if let cached, !cached.isEmpty {
            translatedMarkdown = cached
            showOriginalMarkdown = false
        }
    }

    private func startContinuousTranslation() {
        translationTask?.cancel()
        translationError = nil
        translationProgress = nil
        isTranslating = true
        SwiftLibPreferences.ocrDocumentTranslationPromptTemplate = promptTemplate

        let sourceMarkdown = markdown
        let template = promptTemplate
        let languageName = targetLanguageName

        translationTask = Task { @MainActor in
            do {
                let translated = try await OCRDocumentTranslationService.translate(
                    markdown: sourceMarkdown,
                    options: .init(
                        targetLanguage: languageName,
                        promptTemplate: template
                    ),
                    sender: { prompt in
                        try await AIChatWindowManager.shared.sendText(prompt)
                    },
                    onProgress: { progress in
                        translationProgress = progress
                    },
                    onPartial: { partial in
                        // 流式：每批完成后即时更新双语视图，避免等到全部跑完
                        translatedMarkdown = partial
                        showOriginalMarkdown = false
                        // 同步落盘：万一中途取消/崩溃，已翻译部分也不会丢
                        OCRTranslationCache.save(
                            sourceMarkdown: sourceMarkdown,
                            targetLanguage: languageName,
                            translatedMarkdown: partial
                        )
                    }
                )

                guard !Task.isCancelled else { return }
                translatedMarkdown = translated
                showOriginalMarkdown = false
                OCRTranslationCache.save(
                    sourceMarkdown: sourceMarkdown,
                    targetLanguage: languageName,
                    translatedMarkdown: translated
                )
            } catch is CancellationError {
                translationError = "连续翻译已停止（已翻译部分已自动保存）。"
            } catch {
                translationError = error.localizedDescription
            }

            isTranslating = false
            translationTask = nil
        }
    }
}

private struct OCRMarkdownWebView: NSViewRepresentable {
        let html: String

        func makeCoordinator() -> Coordinator {
                Coordinator()
        }

        func makeNSView(context: Context) -> WKWebView {
                let configuration = WKWebViewConfiguration()
                let webView = WKWebView(frame: .zero, configuration: configuration)
                webView.navigationDelegate = context.coordinator
                webView.allowsBackForwardNavigationGestures = false
                webView.setValue(false, forKey: "drawsBackground")
                DispatchQueue.main.async {
                    webView.applySwiftLibElegantScrollersRecursively(forceVerticalScroller: true)
                }
                return webView
        }

        func updateNSView(_ nsView: WKWebView, context: Context) {
                DispatchQueue.main.async {
                    nsView.applySwiftLibElegantScrollersRecursively(forceVerticalScroller: true)
                }
                guard context.coordinator.lastLoadedHTML != html else { return }
                context.coordinator.lastLoadedHTML = html
                nsView.loadHTMLString(html, baseURL: nil)
        }

        static func documentHTML(for markdown: String, colorScheme: ColorScheme) -> String {
                let bodyHTML = MarkdownHTMLRenderer.render(markdown: markdown, baseURL: nil)
                let resolvedBodyHTML = bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "<p>识别结果为空。</p>"
                        : bodyHTML

                let palette: (bg: String, text: String, secondary: String, border: String, code: String, link: String) = {
                        switch colorScheme {
                        case .dark:
                                return (
                                        bg: "#111418",
                                        text: "#eef2f7",
                                        secondary: "#b6c0cc",
                                        border: "rgba(255, 255, 255, 0.12)",
                                        code: "rgba(255, 255, 255, 0.08)",
                                        link: "#8ec5ff"
                                )
                        default:
                                return (
                                        bg: "#ffffff",
                                        text: "#1f2937",
                                        secondary: "#4b5563",
                                        border: "rgba(15, 23, 42, 0.12)",
                                        code: "#f3f4f6",
                                        link: "#2563eb"
                                )
                        }
                }()

                let colorSchemeName = colorScheme == .dark ? "dark" : "light"

                return """
                <!doctype html>
                <html>
                <head>
                    <meta charset="utf-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1">
                    <style>
                        :root {
                            color-scheme: \(colorSchemeName);
                            --ocr-bg: \(palette.bg);
                            --ocr-text: \(palette.text);
                            --ocr-secondary: \(palette.secondary);
                            --ocr-border: \(palette.border);
                            --ocr-code-bg: \(palette.code);
                            --ocr-link: \(palette.link);
                            --ocr-translation-bg: \(colorScheme == .dark ? "rgba(255,255,255,0.05)" : "rgba(37,99,235,0.05)");
                            --swiftlib-scroll-thumb: \(colorScheme == .dark ? "rgba(255,255,255,0.22)" : "rgba(15,23,42,0.14)");
                            --swiftlib-scroll-thumb-hover: \(colorScheme == .dark ? "rgba(255,255,255,0.34)" : "rgba(15,23,42,0.24)");
                        }

                        * {
                            box-sizing: border-box;
                        }

                        html, body {
                            margin: 0;
                            padding: 0;
                            background: transparent;
                            color: var(--ocr-text);
                            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
                            font-size: 15px;
                            line-height: 1.72;
                            -webkit-font-smoothing: antialiased;
                        }

                        body {
                            padding: 24px 28px 32px;
                        }

                        #article-content {
                            max-width: 920px;
                            margin: 0 auto;
                            user-select: text;
                            word-break: break-word;
                        }

                        #article-content h1,
                        #article-content h2,
                        #article-content h3,
                        #article-content h4,
                        #article-content h5,
                        #article-content h6 {
                            line-height: 1.28;
                            margin: 1.35em 0 0.55em;
                        }

                        #article-content p,
                        #article-content ul,
                        #article-content ol,
                        #article-content pre,
                        #article-content table,
                        #article-content blockquote,
                        #article-content hr,
                        #article-content .math-display,
                        #article-content .swiftlib-md-media-block {
                            margin: 1em 0;
                        }

                        #article-content .swiftlib-ocr-translation {
                            margin: -0.35rem 0 1.15rem;
                            padding: 0.7rem 0.9rem;
                            border-left: 2px solid var(--ocr-border);
                            border-radius: 0 10px 10px 0;
                            background: var(--ocr-translation-bg);
                            color: var(--ocr-secondary);
                            font-size: 0.92rem;
                            line-height: 1.7;
                        }

                        #article-content .swiftlib-ocr-translation > :last-child {
                            margin-bottom: 0;
                        }

                        #article-content ul,
                        #article-content ol {
                            padding-left: 1.5em;
                        }

                        #article-content li + li {
                            margin-top: 0.28em;
                        }

                        #article-content code,
                        #article-content pre,
                        #article-content .math-display {
                            font-family: ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace;
                        }

                        #article-content code {
                            background: var(--ocr-code-bg);
                            border-radius: 6px;
                            padding: 0.12em 0.4em;
                            font-size: 0.92em;
                        }

                        #article-content pre,
                        #article-content .math-display {
                            background: var(--ocr-code-bg);
                            border: 1px solid var(--ocr-border);
                            border-radius: 12px;
                            padding: 14px 16px;
                            overflow-x: auto;
                            white-space: pre-wrap;
                        }

                        #article-content pre code {
                            background: transparent;
                            border-radius: 0;
                            padding: 0;
                        }

                        #article-content blockquote {
                            color: var(--ocr-secondary);
                            border-left: 3px solid var(--ocr-border);
                            padding-left: 14px;
                        }

                        #article-content table {
                            width: 100%;
                            border-collapse: collapse;
                            display: block;
                            overflow-x: auto;
                        }

                        #article-content th,
                        #article-content td {
                            border: 1px solid var(--ocr-border);
                            padding: 8px 10px;
                            vertical-align: top;
                        }

                        #article-content th {
                            background: var(--ocr-code-bg);
                            font-weight: 600;
                        }

                        #article-content hr {
                            border: none;
                            border-top: 1px solid var(--ocr-border);
                        }

                        #article-content a {
                            color: var(--ocr-link);
                            text-decoration: none;
                        }

                        #article-content a:hover {
                            text-decoration: underline;
                        }

                        html { scrollbar-width: thin; scrollbar-color: var(--swiftlib-scroll-thumb) transparent; }
                        ::-webkit-scrollbar { width: 5px; height: 5px; }
                        ::-webkit-scrollbar-track { background: transparent; }
                        ::-webkit-scrollbar-thumb { border-radius: 999px; background: var(--swiftlib-scroll-thumb); }
                        ::-webkit-scrollbar-thumb:hover { background: var(--swiftlib-scroll-thumb-hover); }

                        #article-content img,
                        #article-content .swiftlib-md-image {
                            display: block;
                            max-width: 100%;
                            height: auto;
                            margin: 18px auto;
                            border-radius: 10px;
                        }
                    </style>
                </head>
                <body>
                    <div id="article-content">\(resolvedBodyHTML)</div>
                </body>
                </html>
                """
        }

        final class Coordinator: NSObject, WKNavigationDelegate {
                var lastLoadedHTML = ""

                func webView(
                        _ webView: WKWebView,
                        decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
                ) {
                        if navigationAction.navigationType == .linkActivated,
                             let url = navigationAction.request.url,
                             let scheme = url.scheme?.lowercased(),
                             scheme != "about",
                             scheme != "data" {
                                NSWorkspace.shared.open(url)
                                decisionHandler(.cancel)
                                return
                        }

                        decisionHandler(.allow)
                }
        }
}

private struct OCRTranslationPromptEditorSheet: View {
    @Binding var promptTemplate: String
    let targetLanguageName: String
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("连续翻译 Prompt")
                .font(.headline)

            Text("目标语言：\(targetLanguageName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $promptTemplate)
                .font(.system(size: 12, design: .monospaced))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )

            Text("请保留 `{{target_language}}` 和 `{{batch_json}}` 两个占位符；默认每批 1 段，AI 只需返回译文。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("恢复默认") {
                    promptTemplate = SwiftLibPreferences.defaultOCRDocumentTranslationPromptTemplate
                }

                Spacer()

                Button("取消") {
                    dismiss()
                }

                Button("开始翻译") {
                    dismiss()
                    onStart()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 460)
        .swiftLibElegantScrollersInSubtree()
    }
}
