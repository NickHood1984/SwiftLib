import Foundation
import CoreGraphics
import SwiftLibCore

extension WebReaderViewModel {
    func renderContent() {
        cancelTranscriptLoad()
        guard let storedContent = reference.decodedWebContent else {
            renderedHTML = Self.emptyDocument(title: reference.title)
            return
        }

        isRendering = true
        let reference = self.reference
        let fontSize = self.fontSize
        let contentWidth = self.contentWidth

        Task.detached(priority: .userInitiated) {
            let isYouTube = reference.youTubeVideoId != nil
            let includeClipperTypography = storedContent.format == .html
            let rawBodyHTML: String
            switch storedContent.format {
            case .markdown:
                rawBodyHTML = Self.renderedMarkdownHTML(
                    from: storedContent.body,
                    baseURL: reference.resolvedWebReaderURLString().flatMap(URL.init(string:))
                )
            case .html:
                rawBodyHTML = storedContent.body
            }

            let finalBodyHTML: String
            if reference.youTubeVideoId != nil {
                finalBodyHTML = Self.cleanedYouTubeArticleBodyHTML(rawBodyHTML)
            } else {
                finalBodyHTML = rawBodyHTML
            }

            let html = Self.buildHTMLDocument(
                reference: reference,
                articleBodyHTML: finalBodyHTML,
                fontSize: fontSize,
                contentWidth: contentWidth,
                eyebrowText: isYouTube ? "YouTube 剪藏" : "剪藏正文",
                includeClipperTypography: includeClipperTypography,
                omitReferenceAbstract: isYouTube,
                omitArticleHeader: isYouTube
            )
            await MainActor.run {
                self.currentArticleBodyHTML = finalBodyHTML
                self.shouldPersistTranscriptIntoReference = storedContent.format == .html
                self.renderedHTML = html
                self.isRendering = false
                if let vid = reference.youTubeVideoId {
                    self.scheduleYouTubeTranscriptMerge(videoId: vid)
                }
            }
        }
    }

    /// 合并 Obsidian Web Clipper 的 `reader.css` 与 `highlighter.css`（打包于 Resources）。
    nonisolated private static func bundledClipperReaderStyleBlock() -> String? {
        guard let urlR = Bundle.module.url(forResource: "ClipperReader", withExtension: "css"),
              let urlH = Bundle.module.url(forResource: "ClipperHighlighter", withExtension: "css"),
              let r = try? String(contentsOf: urlR, encoding: .utf8),
              let h = try? String(contentsOf: urlH, encoding: .utf8) else {
            return nil
        }
        return r + "\n" + h
    }

    /// - Parameters:
    ///   - articleBodyHTML: 已生成的 HTML 片段（Markdown 渲染结果或 Readability 的 `content`），不做 HTML 转义。
    ///   - headerTitle/summaryText/authorOverride: 在线阅读时可用抽取结果覆盖条目元数据展示。
    ///   - omitReferenceAbstract: 为 true 时头部摘要仅使用 `summaryText`（可为空），不回退到 `reference.abstract`（YouTube 正文已含描述）。
    ///   - includeClipperTypography: 为 true 时注入 Obsidian Clipper 的 `reader.css` / `highlighter.css` 及主题 class（与 Defuddle 在线阅读配套）。
    nonisolated static func buildHTMLDocument(
        reference: Reference,
        articleBodyHTML: String,
        fontSize: Double,
        contentWidth: CGFloat,
        eyebrowText: String = "Web Article",
        headerTitle: String? = nil,
        summaryText: String? = nil,
        authorOverride: String? = nil,
        includeClipperTypography: Bool = false,
        omitReferenceAbstract: Bool = false,
        omitArticleHeader: Bool = false
    ) -> String {
        let rawHeaderTitle = (headerTitle ?? reference.title).trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = rawHeaderTitle.isEmpty ? reference.title : rawHeaderTitle
        let title = htmlEscape(displayTitle)

        let rawAuthor = authorOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = htmlEscape(rawAuthor.isEmpty ? reference.authors.displayString : rawAuthor)

        let rawSummary: String
        if omitReferenceAbstract {
            rawSummary = (summaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            rawSummary = (summaryText ?? reference.abstract ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let summary = htmlEscape(rawSummary)

        let siteRaw = (reference.siteName ?? reference.journal ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let urlRaw = (reference.resolvedWebReaderURLString() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let site = htmlEscape(siteRaw)
        let url = htmlEscape(urlRaw)
        let showURLInMeta = !urlRaw.isEmpty && !metaSiteAndURLAreRedundant(site: siteRaw, url: urlRaw)
        let eyebrow = htmlEscape(eyebrowText)
        let bodyHTML = articleBodyHTML
        let articleHeaderHTML = omitArticleHeader ? "" : """
              <header class="article-header">
                <div class="eyebrow">\(eyebrow)</div>
                <h1>\(title)</h1>
                <div class="meta">
                  \(author.isEmpty ? "" : "<span>\(author)</span>")
                  \(site.isEmpty ? "" : "<span>\(site)</span>")
                  \(showURLInMeta ? "<span>\(url)</span>" : "")
                </div>
                \(summary.isEmpty ? "" : "<div id=\"swiftlib-article-summary\" class=\"summary\" title=\"在侧栏查看摘要\">\(summary)</div>")
              </header>
"""

        let htmlOpeningTag = includeClipperTypography ? #"<html class="obsidian-reader-active theme-light">"# : "<html>"
        let clipperHeadInjection: String = {
            guard includeClipperTypography else { return "" }
            let vars = """
          <style>
            html.obsidian-reader-active {
              --obsidian-reader-font-size: \(fontSize)px;
              --obsidian-reader-line-height: 1.65;
              --obsidian-reader-line-width: \(Int(contentWidth))px;
            }
          </style>
"""
            guard let bundled = bundledClipperReaderStyleBlock() else { return vars }
            return vars + "\n          <style>\(bundled)</style>\n"
        }()
        let bodyLeadScript = includeClipperTypography
            ? """
          <script>(function(){try{var m=window.matchMedia&&window.matchMedia("(prefers-color-scheme: dark)");if(m&&m.matches){document.documentElement.classList.remove("theme-light");document.documentElement.classList.add("theme-dark");}}catch(_){}})();</script>

"""
            : ""

        return """
        <!doctype html>
        \(htmlOpeningTag)
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: light dark;
              --reader-font-size: \(fontSize)px;
              --reader-max-width: \(Int(contentWidth))px;
              --reader-line-height: 1.8;
            }

            html, body {
              margin: 0;
              padding: 0;
            }

            body {
              background: #ffffff;
              color: #1b1d21;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            }

            #reader-root {
              padding: 28px 32px 48px;
            }

            .article {
              max-width: var(--reader-max-width);
              margin: 0 auto;
              background: transparent;
              padding: 6px 0 46px;
            }

            .article-header {
              margin-bottom: 28px;
              border-bottom: 1px solid rgba(15, 23, 42, 0.08);
              padding-bottom: 22px;
            }

            .eyebrow {
              display: inline-flex;
              align-items: center;
              gap: 8px;
              font-size: 12px;
              font-weight: 600;
              color: #4b5563;
              background: rgba(99, 102, 241, 0.08);
              border-radius: 999px;
              padding: 5px 10px;
            }

            .article-header h1 {
              margin: 14px 0 10px;
              font-size: 34px;
              line-height: 1.22;
              letter-spacing: -0.02em;
            }

            .meta {
              display: flex;
              flex-wrap: wrap;
              gap: 10px 16px;
              color: #6b7280;
              font-size: 14px;
            }

            .summary {
              margin-top: 14px;
              color: #4b5563;
              font-size: 15px;
              line-height: 1.7;
            }

            #swiftlib-article-summary {
              cursor: pointer;
              border-radius: 8px;
              margin-left: -6px;
              margin-right: -6px;
              padding: 6px 8px;
              transition: background-color 0.15s ease;
            }

            #swiftlib-article-summary:hover {
              background: rgba(15, 23, 42, 0.04);
            }

            @keyframes swiftlibSummaryPulse {
              0%, 100% { background-color: transparent; }
              50% { background-color: rgba(99, 102, 241, 0.14); }
            }

            #swiftlib-article-summary.swiftlib-summary-flash {
              animation: swiftlibSummaryPulse 0.55s ease 0s 2;
            }

            html {
              scrollbar-width: thin;
              scrollbar-color: rgba(100, 116, 139, 0.16) transparent;
            }

            html::-webkit-scrollbar,
            body::-webkit-scrollbar {
              width: 9px;
              height: 9px;
            }

            html::-webkit-scrollbar-track,
            body::-webkit-scrollbar-track {
              background: transparent;
            }

            html::-webkit-scrollbar-thumb,
            body::-webkit-scrollbar-thumb {
              background-color: rgba(100, 116, 139, 0.16);
              border-radius: 999px;
              border: 2px solid transparent;
              background-clip: padding-box;
            }

            html::-webkit-scrollbar-thumb:hover,
            body::-webkit-scrollbar-thumb:hover {
              background-color: rgba(100, 116, 139, 0.26);
            }

            html::-webkit-scrollbar-corner,
            body::-webkit-scrollbar-corner {
              background: transparent;
            }

            #article-content {
              font-size: var(--reader-font-size);
              line-height: var(--reader-line-height);
              word-break: break-word;
            }

            #article-content h1,
            #article-content h2,
            #article-content h3,
            #article-content h4 {
              line-height: 1.3;
              margin-top: 1.55em;
              margin-bottom: 0.7em;
              letter-spacing: -0.015em;
            }

            #article-content p,
            #article-content ul,
            #article-content ol,
            #article-content blockquote,
            #article-content pre,
            #article-content table,
            #article-content hr,
            #article-content figure,
            #article-content .swiftlib-md-media-block {
              margin-top: 0;
              margin-bottom: 1em;
            }

            #article-content ul,
            #article-content ol {
              padding-left: 1.5em;
            }

            #article-content li + li {
              margin-top: 0.35em;
            }

            #article-content img {
              max-width: 100%;
              height: auto;
              border-radius: 12px;
            }

            #article-content hr {
              border: 0;
              border-top: 1px solid rgba(15, 23, 42, 0.12);
            }

            #article-content pre {
              background: rgba(15, 23, 42, 0.06);
              border-radius: 12px;
              padding: 14px 16px;
              overflow-x: auto;
            }

            #article-content code {
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: 0.92em;
            }

            #article-content blockquote {
              border-left: 4px solid rgba(59, 130, 246, 0.35);
              padding-left: 14px;
              color: #4b5563;
            }

            #article-content a {
              color: #2563eb;
              text-decoration: none;
            }

            #article-content a:hover {
              text-decoration: underline;
            }

            .swiftlib-annotation {
              border-radius: 5px;
              cursor: pointer;
              transition: box-shadow 0.15s ease, background-color 0.15s ease;
            }

            .swiftlib-annotation.active {
              box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.35);
            }

            /* YouTube transcript (播放器在 SwiftUI 内联 WKWebView) */
            .swiftlib-yt-desc {
              color: #4b5563;
              font-size: 15px;
              line-height: 1.7;
            }
            .swiftlib-yt-transcript {
              margin-top: 1.5em;
              border: none;
              border-radius: 0;
              overflow: visible;
            }
            .swiftlib-yt-transcript summary {
              cursor: pointer;
              padding: 8px 0;
              font-weight: 600;
              font-size: 13px;
              color: #9ca3af;
              letter-spacing: 0.02em;
              text-transform: uppercase;
              background: none;
              user-select: none;
              border-top: 1px solid rgba(15, 23, 42, 0.06);
            }
            .swiftlib-yt-transcript-body {
              font-size: 0.88em;
              line-height: 1.75;
              padding: 8px 0;
              margin: 0;
              max-height: none;
              overflow-y: visible;
            }
            .swiftlib-yt-line {
              display: block;
            }
            .swiftlib-yt-ts {
              display: inline-block;
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: 0.92em;
              color: #6366f1;
              text-decoration: none;
              cursor: pointer;
              margin-right: 0.4em;
              padding: 1px 4px;
              border-radius: 4px;
              transition: background 0.15s;
            }
            .swiftlib-yt-ts:hover {
              background: rgba(99, 102, 241, 0.12);
              text-decoration: none;
            }

            @media (prefers-color-scheme: dark) {
              html {
                scrollbar-color: rgba(148, 163, 184, 0.22) transparent;
              }

              html::-webkit-scrollbar-thumb,
              body::-webkit-scrollbar-thumb {
                background-color: rgba(148, 163, 184, 0.22);
              }

              html::-webkit-scrollbar-thumb:hover,
              body::-webkit-scrollbar-thumb:hover {
                background-color: rgba(148, 163, 184, 0.34);
              }

              body {
                background: #1e1e1e;
                color: #eceef2;
              }

              #swiftlib-article-summary:hover {
                background: rgba(255, 255, 255, 0.06);
              }

              @keyframes swiftlibSummaryPulseDark {
                0%, 100% { background-color: transparent; }
                50% { background-color: rgba(99, 102, 241, 0.22); }
              }

              #swiftlib-article-summary.swiftlib-summary-flash {
                animation: swiftlibSummaryPulseDark 0.55s ease 0s 2;
              }

              .article {
                background: transparent;
              }

              .article-header {
                border-bottom-color: rgba(255, 255, 255, 0.08);
              }

              .eyebrow {
                color: #d1d5db;
                background: rgba(99, 102, 241, 0.16);
              }

              .meta,
              .summary,
              #article-content blockquote {
                color: #aeb6c2;
              }

              #article-content pre {
                background: rgba(255, 255, 255, 0.06);
              }

              #article-content hr {
                border-top-color: rgba(255, 255, 255, 0.12);
              }

              #article-content a {
                color: #7fb3ff;
              }

              .swiftlib-yt-desc {
                color: #aeb6c2;
              }
              .swiftlib-yt-transcript {
                border-color: transparent;
              }
              .swiftlib-yt-transcript summary {
                color: #6b7280;
                background: none;
                border-top-color: rgba(255, 255, 255, 0.08);
              }
            }
          </style>
        \(clipperHeadInjection)
        </head>
        <body>
        \(bodyLeadScript)<main id="reader-root">
            <article class="article">
              \(articleHeaderHTML)
              <div id="article-content">\(bodyHTML)</div>
            </article>
          </main>
          <script>
            (function () {
              const article = document.getElementById('article-content');
              let activeId = null;

              function send(name, payload) {
                try {
                  window.webkit.messageHandlers[name].postMessage(payload);
                } catch (_) {}
              }

              function hexToRgba(hex, alpha) {
                const normalized = (hex || '#FFDE59').replace('#', '');
                const safe = normalized.length === 6 ? normalized : 'FFDE59';
                const r = parseInt(safe.slice(0, 2), 16);
                const g = parseInt(safe.slice(2, 4), 16);
                const b = parseInt(safe.slice(4, 6), 16);
                return `rgba(${r}, ${g}, ${b}, ${alpha})`;
              }

              function unwrapAnnotations() {
                const nodes = Array.from(document.querySelectorAll('span[data-annotation-id]'));
                nodes.forEach((span) => {
                  const parent = span.parentNode;
                  if (!parent) return;
                  while (span.firstChild) {
                    parent.insertBefore(span.firstChild, span);
                  }
                  parent.removeChild(span);
                  parent.normalize();
                });
              }

              function collectTextNodes(root) {
                const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
                  acceptNode(node) {
                    if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
                    if (node.parentElement && node.parentElement.closest('[data-annotation-id]')) return NodeFilter.FILTER_REJECT;
                    return NodeFilter.FILTER_ACCEPT;
                  }
                });

                const result = [];
                while (walker.nextNode()) {
                  result.push(walker.currentNode);
                }
                return result;
              }

              function buildIndex(root) {
                const nodes = collectTextNodes(root);
                const map = [];
                let text = '';

                nodes.forEach((node) => {
                  const start = text.length;
                  const value = node.nodeValue || '';
                  text += value;
                  map.push({ node, start, end: text.length });
                });

                return { text, map };
              }

              function resolvePoint(map, target) {
                for (const entry of map) {
                  if (target >= entry.start && target <= entry.end) {
                    return { node: entry.node, offset: target - entry.start };
                  }
                }
                return null;
              }

              function scoreMatch(fullText, index, annotation) {
                let score = 0;
                if (annotation.prefixText) {
                  const actualPrefix = fullText.slice(Math.max(0, index - annotation.prefixText.length), index);
                  if (actualPrefix.endsWith(annotation.prefixText)) score += annotation.prefixText.length * 2;
                }
                if (annotation.suffixText) {
                  const actualSuffix = fullText.slice(
                    index + annotation.anchorText.length,
                    index + annotation.anchorText.length + annotation.suffixText.length
                  );
                  if (actualSuffix.startsWith(annotation.suffixText)) score += annotation.suffixText.length * 2;
                }
                return score;
              }

              function locateRange(annotation) {
                if (!annotation.anchorText) return null;
                const indexed = buildIndex(article);
                const fullText = indexed.text;
                if (!fullText) return null;

                let bestIndex = -1;
                let bestScore = -1;
                let searchFrom = 0;
                while (searchFrom <= fullText.length) {
                  const idx = fullText.indexOf(annotation.anchorText, searchFrom);
                  if (idx === -1) break;
                  const score = scoreMatch(fullText, idx, annotation);
                  if (score > bestScore) {
                    bestScore = score;
                    bestIndex = idx;
                  }
                  searchFrom = idx + Math.max(annotation.anchorText.length, 1);
                }

                if (bestIndex === -1) return null;
                const start = resolvePoint(indexed.map, bestIndex);
                const end = resolvePoint(indexed.map, bestIndex + annotation.anchorText.length);
                if (!start || !end) return null;

                const range = document.createRange();
                range.setStart(start.node, start.offset);
                range.setEnd(end.node, end.offset);
                return range;
              }

              function applyAnnotationStyle(span, annotation) {
                const color = annotation.color || '#FFDE59';
                const highlightColor = hexToRgba(color, annotation.type === 'underline' ? 0 : 0.3);
                span.className = `swiftlib-annotation ${annotation.type}`;
                span.dataset.annotationId = String(annotation.id || '');
                span.style.backgroundColor = annotation.type === 'underline' ? 'transparent' : highlightColor;
                span.style.borderBottom = annotation.type === 'underline' ? `3px solid ${color}` : 'none';
                span.style.paddingBottom = annotation.type === 'underline' ? '1px' : '0';
                if (annotation.noteText) {
                  span.title = annotation.noteText;
                }
              }

              function wrapRange(range, annotation) {
                const span = document.createElement('span');
                applyAnnotationStyle(span, annotation);

                try {
                  range.surroundContents(span);
                } catch (_) {
                  const fragment = range.extractContents();
                  span.appendChild(fragment);
                  range.insertNode(span);
                }
              }

              function setActive(id) {
                activeId = id;
                document.querySelectorAll('[data-annotation-id]').forEach((node) => {
                  const matches = Number(node.dataset.annotationId) === Number(id);
                  node.classList.toggle('active', matches);
                });
              }

              function setAnnotations(annotations) {
                unwrapAnnotations();
                (annotations || []).forEach((annotation) => {
                  const range = locateRange(annotation);
                  if (range) {
                    wrapRange(range, annotation);
                  }
                });
                if (activeId !== null) {
                  setActive(activeId);
                }
              }

              function currentSelectionPayload() {
                const selection = window.getSelection();
                if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return null;
                const range = selection.getRangeAt(0);
                if (!article.contains(range.commonAncestorContainer)) return null;

                const text = selection.toString().trim();
                if (!text) return null;

                const prefixRange = range.cloneRange();
                prefixRange.selectNodeContents(article);
                prefixRange.setEnd(range.startContainer, range.startOffset);

                const suffixRange = range.cloneRange();
                suffixRange.selectNodeContents(article);
                suffixRange.setStart(range.endContainer, range.endOffset);

                const domRect = range.getBoundingClientRect();
                const rect =
                  domRect.width >= 1 && domRect.height >= 1
                    ? { left: domRect.left, top: domRect.top, width: domRect.width, height: domRect.height }
                    : null;

                return {
                  text,
                  prefixText: prefixRange.toString().slice(-48),
                  suffixText: suffixRange.toString().slice(0, 48),
                  rect
                };
              }

              function emitSelectionState() {
                const payload = currentSelectionPayload();
                if (payload) {
                  send('selectionChanged', payload);
                } else {
                  send('selectionCleared', null);
                }
              }

              let selectionScrollScheduled = false;
              function scheduleSelectionEmitOnScroll() {
                if (selectionScrollScheduled) return;
                selectionScrollScheduled = true;
                requestAnimationFrame(() => {
                  selectionScrollScheduled = false;
                  if (currentSelectionPayload()) {
                    emitSelectionState();
                  }
                });
              }

              document.addEventListener('mouseup', () => setTimeout(emitSelectionState, 0));
              document.addEventListener('keyup', () => setTimeout(emitSelectionState, 0));
              window.addEventListener('scroll', scheduleSelectionEmitOnScroll, true);
              window.addEventListener('resize', scheduleSelectionEmitOnScroll);

              article.addEventListener('click', (event) => {
                const target = event.target;
                if (!(target instanceof Element)) return;
                const marker = target.closest('[data-annotation-id]');
                if (!marker) return;
                const id = Number(marker.dataset.annotationId);
                setActive(id);
                const rect = marker.getBoundingClientRect();
                send('annotationActivated', {
                  id,
                  rectX: rect.x,
                  rectY: rect.y,
                  rectW: rect.width,
                  rectH: rect.height
                });
              });

              const summaryBlock = document.getElementById('swiftlib-article-summary');
              if (summaryBlock) {
                summaryBlock.addEventListener('click', (event) => {
                  event.preventDefault();
                  send('summarySectionClicked', {});
                });
              }

              window.SwiftLibReader = {
                setAnnotations,
                seekYouTube(seconds) {
                  const n = Number(seconds);
                  if (!Number.isFinite(n) || n < 0) return;
                  send('youtubeSeek', { seconds: Math.floor(n) });
                },
                clearSelection() {
                  const selection = window.getSelection();
                  if (selection) selection.removeAllRanges();
                  emitSelectionState();
                },
                scrollToAnnotation(id) {
                  const target = document.querySelector(`[data-annotation-id="${id}"]`);
                  if (!target) return;
                  setActive(id);
                  target.scrollIntoView({ behavior: 'smooth', block: 'center' });
                },
                scrollToSummary() {
                  const el = document.getElementById('swiftlib-article-summary');
                  if (!el) return;
                  el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                  el.classList.remove('swiftlib-summary-flash');
                  void el.offsetWidth;
                  el.classList.add('swiftlib-summary-flash');
                  window.setTimeout(() => el.classList.remove('swiftlib-summary-flash'), 1300);
                },
                updateAppearance(fontSize, maxWidth) {
                  document.documentElement.style.setProperty('--reader-font-size', `${fontSize}px`);
                  document.documentElement.style.setProperty('--reader-max-width', `${maxWidth}px`);
                  requestAnimationFrame(() => emitSelectionState());
                }
              };
            })();
          </script>
        </body>
        </html>
        """
    }

    nonisolated static func renderedMarkdownHTML(from markdown: String, baseURL: URL? = nil) -> String {
        MarkdownHTMLRenderer.render(markdown: markdown, baseURL: baseURL)
    }

    nonisolated static func emptyDocument(title: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; padding: 40px; background: #ffffff; color: #1f2937; }
            .empty { max-width: 720px; margin: 40px auto; padding: 32px; text-align: center; }
          </style>
        </head>
        <body>
          <div class="empty">
            <h2>\(htmlEscape(title))</h2>
            <p>这个网页条目还没有抓取到正文内容。</p>
          </div>
        </body>
        </html>
        """
    }

    /// 去掉正文中的 YouTube 内嵌播放器（Readability 会保留 video iframe；WKWebView 会报 152-4）。
    nonisolated private static func htmlByStrippingYouTubePlayerEmbeds(_ html: String) -> String {
        var result = html
        // 使用普通字符串，避免 raw string 内 \" 与字符类 [\"'] 冲突。
        let patterns: [(String, NSRegularExpression.Options)] = [
            (
                "<iframe\\b[^>]*\\bsrc\\s*=\\s*[\"'][^\"']*(?:youtube\\.com|youtu\\.be|youtube-nocookie)[^\"']*[\"'][^>]*>[\\s\\S]*?</iframe>",
                [.caseInsensitive, .dotMatchesLineSeparators]
            ),
            (
                "<iframe\\b[^>]*\\bsrc\\s*=\\s*[^\\s>]*(?:youtube\\.com|youtu\\.be|youtube-nocookie)[^>]*>[\\s\\S]*?</iframe>",
                [.caseInsensitive, .dotMatchesLineSeparators]
            ),
            (
                "<embed\\b[^>]*(?:youtube\\.com|youtu\\.be|youtube-nocookie)[^>]*\\/?>",
                [.caseInsensitive]
            ),
            (
                "<object\\b[^>]*(?:youtube\\.com|youtu\\.be|youtube-nocookie)[^>]*>[\\s\\S]*?</object>",
                [.caseInsensitive, .dotMatchesLineSeparators]
            )
        ]
        for (pattern, opts) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }
            for _ in 0 ..< 48 {
                let range = NSRange(result.startIndex..., in: result)
                guard let m = re.firstMatch(in: result, options: [], range: range),
                      let r = Range(m.range, in: result) else { break }
                result.replaceSubrange(r, with: "")
            }
        }
        return result
    }

    nonisolated static func cleanedYouTubeArticleBodyHTML(_ html: String) -> String {
        var result = htmlByStrippingYouTubePlayerEmbeds(html)
        result = htmlByRemovingLegacyYouTubeFallbackChrome(result)
        result = htmlByRemovingLeadingYouTubeCoverMedia(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 兼容清理旧版 YouTube fallback 存量 HTML，避免正文里重复出现封面卡、外链按钮和摘要。
    nonisolated static func htmlByRemovingLegacyYouTubeFallbackChrome(_ html: String) -> String {
        var result = html
        result = htmlByRemovingElement(tagName: "div", containingClass: "swiftlib-yt-player-shell", from: result)
        result = htmlByRemovingElement(tagName: "div", containingClass: "swiftlib-yt-player-actions", from: result)
        result = htmlByRemovingElement(tagName: "p", containingClass: "swiftlib-yt-desc", from: result)

        let patterns: [(String, NSRegularExpression.Options)] = [
            (#"<p>\s*<a\b[^>]*class\s*=\s*["'][^"']*swiftlib-yt-open-link[^"']*["'][^>]*>[\s\S]*?</a>\s*</p>\s*"#, [.caseInsensitive, .dotMatchesLineSeparators]),
            (#"^\s*<p>\s*<a\b[^>]*href\s*=\s*["']https?://(?:www\.)?youtube\.com/watch[^"']*["'][^>]*>\s*(?:在浏览器中打开|Open(?:\s+in)?\s+browser)\s*</a>\s*</p>\s*"#, [.caseInsensitive, .dotMatchesLineSeparators]),
        ]
        for (pattern, opts) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }
            for _ in 0 ..< 12 {
                let range = NSRange(result.startIndex..., in: result)
                guard let match = re.firstMatch(in: result, options: [], range: range),
                      let swiftRange = Range(match.range, in: result) else { break }
                result.removeSubrange(swiftRange)
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func htmlByRemovingElement(
        tagName: String,
        containingClass className: String,
        from html: String
    ) -> String {
        let escapedClass = NSRegularExpression.escapedPattern(for: className)
        let pattern = "<\(tagName)\\b[^>]*class\\s*=\\s*[\"'][^\"']*\\b\(escapedClass)\\b[^\"']*[\"'][^>]*>"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return html
        }

        var result = html
        for _ in 0 ..< 12 {
            let range = NSRange(result.startIndex..., in: result)
            guard let match = re.firstMatch(in: result, options: [], range: range),
                  let openingTagRange = Range(match.range, in: result),
                  let elementRange = htmlElementRange(in: result, tagName: tagName, openingTagRange: openingTagRange) else {
                break
            }
            result.removeSubrange(elementRange)
        }

        return result
    }

    nonisolated private static func htmlElementRange(
        in html: String,
        tagName: String,
        openingTagRange: Range<String.Index>
    ) -> Range<String.Index>? {
        var searchStart = openingTagRange.upperBound
        var depth = 1
        let openPattern = "<\(tagName)\\b"
        let closePattern = "</\(tagName)>"

        while searchStart < html.endIndex {
            let searchRange = searchStart..<html.endIndex
            let nextOpen = html.range(of: openPattern, options: [.regularExpression, .caseInsensitive], range: searchRange)
            let nextClose = html.range(of: closePattern, options: [.caseInsensitive], range: searchRange)
            guard let closeRange = nextClose else { return nil }

            if let openRange = nextOpen, openRange.lowerBound < closeRange.lowerBound {
                depth += 1
                searchStart = openRange.upperBound
            } else {
                depth -= 1
                searchStart = closeRange.upperBound
                if depth == 0 {
                    return openingTagRange.lowerBound..<closeRange.upperBound
                }
            }
        }

        return nil
    }

    /// YouTube 剪藏正文常会把封面图再保存一份，和顶部视频卡重复；仅移除首屏独立媒体块，保留正文其它图片。
    nonisolated static func htmlByRemovingLeadingYouTubeCoverMedia(_ html: String) -> String {
        var result = html
        let patterns: [(String, NSRegularExpression.Options)] = [
            (#"^\s*<div\b[^>]*class\s*=\s*["'][^"']*swiftlib-md-media-block[^"']*["'][^>]*>\s*[\s\S]*?</div>\s*"#, [.caseInsensitive, .dotMatchesLineSeparators]),
            (#"^\s*<p>\s*(?:<a\b[^>]*>\s*)?<img\b[^>]*>(?:\s*</a>)?\s*</p>\s*"#, [.caseInsensitive, .dotMatchesLineSeparators]),
            (#"^\s*<figure\b[^>]*>\s*[\s\S]*?</figure>\s*"#, [.caseInsensitive, .dotMatchesLineSeparators]),
            (#"^\s*(?:<a\b[^>]*>\s*)?<img\b[^>]*>(?:\s*</a>)?\s*"#, [.caseInsensitive, .dotMatchesLineSeparators]),
        ]

        for (pattern, opts) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            guard let match = re.firstMatch(in: result, options: [], range: range),
                  let swiftRange = Range(match.range, in: result) else { continue }
            result.removeSubrange(swiftRange)
            break
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `site` 与 `url` 是否指向同一 http(s) 资源，避免元信息区重复展示同一链接。
    nonisolated private static func metaSiteAndURLAreRedundant(site: String, url: String) -> Bool {
        let s = site.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !u.isEmpty else { return false }
        if s.caseInsensitiveCompare(u) == .orderedSame { return true }
        return httpURLsAreEquivalent(s, u)
    }

    nonisolated private static func httpURLsAreEquivalent(_ a: String, _ b: String) -> Bool {
        guard let ua = URL(string: a), let ub = URL(string: b) else { return false }
        let sa = (ua.scheme ?? "").lowercased()
        let sb = (ub.scheme ?? "").lowercased()
        guard ["http", "https"].contains(sa), ["http", "https"].contains(sb) else { return false }
        func normHost(_ h: String?) -> String {
            let x = h?.lowercased() ?? ""
            if x.hasPrefix("www.") { return String(x.dropFirst(4)) }
            return x
        }
        guard normHost(ua.host) == normHost(ub.host) else { return false }
        return ua.path == ub.path && (ua.query ?? "") == (ub.query ?? "")
    }

    nonisolated private static func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
