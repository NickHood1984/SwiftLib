import Foundation
import OSLog
import WebKit
import SwiftLibCore

private let readerExtractionLog = Logger(subsystem: "SwiftLib", category: "OnlineReadable")

/// 在线阅读：原文页注入 Defuddle / Readability / YouTube 降级；`readerResult` 由本类接收，`deinit` 移除 handler。
final class ReaderExtractionManager: NSObject, WKScriptMessageHandler {
    static let readerResultHandlerName = "readerResult"

    /// 与 Safari 接近，减轻部分站点对 WKWebView 默认 UA 的拦截。
    static let safariLikeUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    weak var hostWebView: WKWebView?

    /// 当前导航是否为 YouTube（Readability 失败时走降级页）。
    var isYouTubeExtractionContext = false

    /// 仍为「在线阅读」且处于 busy（未最终失败）时返回 true。
    var isLiveReadableBusyContext: (() -> Bool)?

    var onDefuddleSuccess: ((String?, String, String?, String?) -> Void)?
    var onReadabilitySuccess: ((String?, String, String?, String?) -> Void)?
    var onYouTubeFallbackSuccess: ((String?, String, String?, String?) -> Void)?
    var onTerminalFailure: ((String) -> Void)?

    private var hasRetriedAfterDelay = false
    private var defuddleResultHandled = false

    private static var readabilityScriptCache: String?
    private static var clipperDefuddleScriptCache: String?

    func resetForNewNavigation() {
        hasRetriedAfterDelay = false
        defuddleResultHandled = false
    }

    private func resetDefuddleOnly() {
        defuddleResultHandled = false
    }

    deinit {
        let name = Self.readerResultHandlerName
        let ucc = hostWebView?.configuration.userContentController
        DispatchQueue.main.async {
            ucc?.removeScriptMessageHandler(forName: name)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.readerResultHandlerName,
              let body = message.body as? [String: Any],
              let source = body["source"] as? String,
              source == "defuddle"
        else { return }

        defuddleResultHandled = true
        let ok = (body["ok"] as? Bool) == true
        guard ok,
              let content = body["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            readerExtractionLog.notice("readerResult defuddle ok=false → Readability")
            DispatchQueue.main.async { [weak self] in
                guard let self, let wv = self.hostWebView else { return }
                self.runReadabilityForOnlineRead(in: wv, isYouTube: self.isYouTubeExtractionContext)
            }
            return
        }

        let title = body["title"] as? String
        let excerpt = (body["description"] as? String) ?? (body["excerpt"] as? String)
        let byline = body["author"] as? String
        readerExtractionLog.notice("readerResult Defuddle 成功 contentLength=\(content)")
        DispatchQueue.main.async { [weak self] in
            self?.onDefuddleSuccess?(title, content, excerpt, byline)
        }
    }

    // MARK: - Pipeline

    func runOnlineArticleExtraction(from webView: WKWebView) {
        hostWebView = webView
        readerExtractionLog.notice("ReaderExtractionManager: 注入 ClipperDefuddle.js 并调用 SwiftLibDefuddleExtract()")
        guard let defuddleSrc = Self.loadClipperDefuddleScript() else {
            readerExtractionLog.error("未找到 ClipperDefuddle.js → Readability")
            runReadabilityForOnlineRead(in: webView, isYouTube: isYouTubeExtractionContext)
            return
        }

        webView.evaluateJavaScript(defuddleSrc) { [weak self] _, error in
            guard let self else { return }
            if let error {
                readerExtractionLog.error("注入 ClipperDefuddle.js 失败: \(error.localizedDescription) → Readability")
                self.runReadabilityForOnlineRead(in: webView, isYouTube: self.isYouTubeExtractionContext)
                return
            }
            readerExtractionLog.notice("ClipperDefuddle.js 已执行，调用 SwiftLibDefuddleExtract()…")
            self.defuddleResultHandled = false
            webView.evaluateJavaScript("SwiftLibDefuddleExtract()") { [weak self] result, err2 in
                guard let self else { return }
                if let err2 {
                    readerExtractionLog.error("SwiftLibDefuddleExtract 异常: \(err2.localizedDescription) → Readability")
                    self.runReadabilityForOnlineRead(in: webView, isYouTube: self.isYouTubeExtractionContext)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self else { return }
                    if self.defuddleResultHandled { return }
                    self.processDefuddleJSONFallback(result as? String, webView: webView)
                }
            }
        }
    }

    private func processDefuddleJSONFallback(_ jsonStr: String?, webView: WKWebView) {
        guard let jsonStr,
              let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ok"] as? Bool) == true,
              let content = obj["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            let parsed = jsonStr.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let err = parsed?["error"] as? String
            readerExtractionLog.notice("Defuddle completion 回退解析失败 ok=\(parsed?["ok"] as? Bool ?? false) err=\(err ?? "nil") → Readability")
            runReadabilityForOnlineRead(in: webView, isYouTube: isYouTubeExtractionContext)
            return
        }
        let title = obj["title"] as? String
        let excerpt = (obj["description"] as? String) ?? (obj["excerpt"] as? String)
        let byline = obj["author"] as? String
        readerExtractionLog.notice("Defuddle completion 回退成功 contentLength=\(content.count)")
        onDefuddleSuccess?(title, content, excerpt, byline)
    }

    func runReadabilityForOnlineRead(in webView: WKWebView, isYouTube: Bool) {
        readerExtractionLog.notice("runReadabilityForOnlineRead isYouTube=\(isYouTube)")
        guard let scriptSource = Self.loadReadabilityScript() else {
            onTerminalFailure?("缺少 Readability.js 资源文件。")
            return
        }
        let js = scriptSource + "\n" + Self.readabilityBootstrapJS
        runReadabilityExtractionCore(in: webView, script: js, isYouTube: isYouTube)
    }

    private func runReadabilityExtractionCore(in webView: WKWebView, script js: String, isYouTube: Bool) {
        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self else { return }
            if let error {
                self.failOrRetry(webView: webView, message: "抽取脚本错误：\(error.localizedDescription)")
                return
            }
            guard let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                self.failOrRetry(webView: webView, message: "在线阅读失败：无法解析抽取结果。")
                return
            }

            let ok = (obj["ok"] as? Bool) == true
            guard ok, let content = obj["content"] as? String else {
                if isYouTube {
                    readerExtractionLog.notice("Readability 失败 → YouTube 降级页")
                    self.runYouTubeFallback(in: webView)
                    return
                }
                let err = (obj["err"] as? String) ?? "parse_failed"
                self.failOrRetry(webView: webView, message: "无法从页面提取正文（\(err)）。可改用「剪藏正文」或检查是否需登录。")
                return
            }

            let title = obj["title"] as? String
            let excerpt = obj["excerpt"] as? String
            let byline = obj["byline"] as? String
            readerExtractionLog.notice("Readability 成功 contentLength=\(content.count)")
            self.onReadabilitySuccess?(title, content, excerpt, byline)
        }
    }

    private func runYouTubeFallback(in webView: WKWebView) {
        readerExtractionLog.notice("runYouTubeFallback")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let transcript = await self.fetchYouTubeTranscriptFromPage(in: webView)
            let js = Self.youtubeFallbackBootstrapJS
            do {
                let result = try await webView.evaluateJavaScript(js)
                guard let jsonStr = result as? String,
                      let data = jsonStr.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (obj["ok"] as? Bool) == true,
                      let rawContent = obj["content"] as? String,
                      !rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    self.failOrRetry(
                        webView: webView,
                        message: "YouTube 页面无法在应用内可靠生成摘要。请改用「剪藏正文」或在浏览器中打开原链接观看。"
                    )
                    return
                }
                let title = obj["title"] as? String
                let excerpt = obj["excerpt"] as? String
                let byline = obj["byline"] as? String
                let content = self.contentByAppendingTranscript(rawContent, transcript: transcript)
                self.onYouTubeFallbackSuccess?(title, content, excerpt, byline)
            } catch {
                self.failOrRetry(
                    webView: webView,
                    message: "YouTube 摘要页生成失败：\(error.localizedDescription)。请改用「剪藏正文」或在浏览器中打开链接。"
                )
            }
        }
    }

    @MainActor
    private func fetchYouTubeTranscriptFromPage(in webView: WKWebView) async -> String? {
        await Self.fetchYouTubeTranscriptFromLoadedPage(in: webView)
    }

    @MainActor
    static func fetchYouTubeTranscriptFromLoadedPage(in webView: WKWebView) async -> String? {
        do {
            let result = try await webView.callAsyncJavaScript(
                Self.youtubeTranscriptBootstrapJS,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            guard let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                readerExtractionLog.notice("YouTube 页内 transcript fallback: 结果解析失败")
                return nil
            }
            if (obj["ok"] as? Bool) == true,
               let transcript = obj["transcript"] as? String,
               !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let lang = obj["languageCode"] as? String ?? ""
                let source = obj["source"] as? String ?? "unknown"
                readerExtractionLog.notice("YouTube 页内 transcript fallback 成功 source=\(source, privacy: .public) lang=\(lang, privacy: .public) length=\(transcript.count, privacy: .public)")
                return transcript
            }
            let err = obj["err"] as? String ?? "unknown"
            let source = obj["source"] as? String ?? "unknown"
            readerExtractionLog.notice("YouTube 页内 transcript fallback 失败 source=\(source, privacy: .public) err=\(err, privacy: .public)")
            return nil
        } catch {
            readerExtractionLog.notice("YouTube 页内 transcript fallback 异常 \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func contentByAppendingTranscript(_ content: String, transcript: String?) -> String {
        guard let transcript,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return content
        }
        let block = "<details class=\"swiftlib-yt-transcript\" open><summary>字幕 / Transcript</summary><pre>\(Self.htmlEscape(transcript))</pre></details>"
        if let range = content.range(of: "</article>", options: .backwards) {
            return String(content[..<range.lowerBound]) + block + String(content[range.lowerBound...])
        }
        return content + block
    }

    private func failOrRetry(webView: WKWebView, message: String) {
        Task { @MainActor in
            guard self.isLiveReadableBusyContext?() == true else { return }
            if !self.hasRetriedAfterDelay {
                self.hasRetriedAfterDelay = true
                readerExtractionLog.notice("抽取全链失败，1.5s 后重试一轮：\(message)")
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard self.isLiveReadableBusyContext?() == true else { return }
                self.resetDefuddleOnly()
                self.runOnlineArticleExtraction(from: webView)
                return
            }
            self.onTerminalFailure?(message)
        }
    }

    // MARK: - Scripts

    private static func loadClipperDefuddleScript() -> String? {
        if let cached = Self.clipperDefuddleScriptCache { return cached }
        guard let url = Bundle.module.url(forResource: "ClipperDefuddle", withExtension: "js"),
              let s = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        Self.clipperDefuddleScriptCache = s
        return s
    }

    private static func loadReadabilityScript() -> String? {
        if let cached = Self.readabilityScriptCache { return cached }
        guard let url = Bundle.module.url(forResource: "Readability", withExtension: "js"),
              let s = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        Self.readabilityScriptCache = s
        return s
    }

    private static let readabilityBootstrapJS = """
    (function() {
      try {
        var clone = document.cloneNode(true);
        if (!clone || !clone.documentElement) {
          return JSON.stringify({ ok: false, err: 'no_document' });
        }
        var reader = new Readability(clone);
        var art = reader.parse();
        if (!art || !art.content) {
          return JSON.stringify({ ok: false, err: 'parse_failed' });
        }
        return JSON.stringify({
          ok: true,
          title: art.title || '',
          content: art.content,
          excerpt: art.excerpt || '',
          byline: art.byline || ''
        });
      } catch (e) {
        return JSON.stringify({ ok: false, err: String(e) });
      }
    })();
    """

    private static let youtubeFallbackBootstrapJS = #"""
    (function() {
      function esc(s) {
        return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;');
      }
      function meta(prop, name) {
        var el = document.querySelector('meta[property="' + prop + '"]') || document.querySelector('meta[name="' + name + '"]');
        return el ? String(el.getAttribute('content') || '') : '';
      }
      try {
        var href = String(document.URL || '');
        var id = null;
        var m = href.match(/[?&]v=([^&?#]+)/); if (m) id = m[1];
        if (!id) { m = href.match(/youtu\.be\/([^?&#]+)/); if (m) id = m[1]; }
        if (!id) { m = href.match(/youtube\.com\/shorts\/([^?&#]+)/); if (m) id = m[1]; }
        if (!id) { m = href.match(/youtube\.com\/live\/([^?&#]+)/); if (m) id = m[1]; }
        if (!id) { m = href.match(/youtube\.com\/embed\/([^?&#]+)/); if (m) id = m[1]; }
        var title = meta('og:title', 'title').trim() || document.title || 'YouTube';
        var desc = meta('og:description', 'description').trim();
        if (!id) {
          var html = '<article class="swiftlib-youtube-fallback"><p>未能从当前地址解析视频 ID。</p><p>请使用系统浏览器打开原链接观看。</p></article>';
          return JSON.stringify({ ok: true, title: title, content: html, excerpt: desc, byline: '' });
        }
        var html = '<article class="swiftlib-youtube-fallback"></article>';
        return JSON.stringify({ ok: true, title: title, content: html, excerpt: desc, byline: 'YouTube' });
      } catch (e) {
        return JSON.stringify({ ok: false, err: String(e) });
      }
    })();
    """#

    private static let youtubeTranscriptBootstrapJS = #"""
    return (async function() {
      function stringify(obj) {
        try { return JSON.stringify(obj); } catch (e) { return JSON.stringify({ ok: false, err: String(e) }); }
      }
      function wait(ms) {
        return new Promise(function(resolve) { setTimeout(resolve, ms); });
      }
      function ytcfgGet(key) {
        try {
          if (window.ytcfg && typeof window.ytcfg.get === 'function') return window.ytcfg.get(key);
          if (window.ytcfg && window.ytcfg.data_) return window.ytcfg.data_[key];
        } catch (_) {}
        return null;
      }
      function extractInitialData() {
        if (window.ytInitialData && typeof window.ytInitialData === 'object') return window.ytInitialData;
        if (window.__INITIAL_DATA__ && typeof window.__INITIAL_DATA__ === 'object') return window.__INITIAL_DATA__;
        var scripts = document.scripts || [];
        for (var i = 0; i < scripts.length; i++) {
          var text = String((scripts[i] && scripts[i].textContent) || '');
          var idx = text.indexOf('ytInitialData');
          if (idx === -1) continue;
          var start = text.indexOf('{', idx);
          if (start === -1) continue;
          var depth = 0;
          var inStr = false;
          var esc = false;
          for (var j = start; j < text.length; j++) {
            var ch = text[j];
            if (inStr) {
              if (esc) { esc = false; }
              else if (ch === '\\') { esc = true; }
              else if (ch === '"') { inStr = false; }
            } else {
              if (ch === '"') { inStr = true; }
              else if (ch === '{') { depth += 1; }
              else if (ch === '}') {
                depth -= 1;
                if (depth === 0) {
                  try { return JSON.parse(text.slice(start, j + 1)); } catch (_) { break; }
                }
              }
            }
          }
        }
        return null;
      }
      function extractTranscriptEndpoint(any) {
        if (!any) return null;
        if (Array.isArray(any)) {
          for (var i = 0; i < any.length; i++) {
            var found = extractTranscriptEndpoint(any[i]);
            if (found && found.params) return found;
          }
          return null;
        }
        if (typeof any === 'object') {
          var directParams = any.getTranscriptEndpoint && any.getTranscriptEndpoint.params;
          var continuation = any.continuationEndpoint || null;
          var continuationParams = continuation && continuation.getTranscriptEndpoint && continuation.getTranscriptEndpoint.params;
          var metadata = (continuation && continuation.commandMetadata) || any.commandMetadata || {};
          var webMeta = metadata.webCommandMetadata || {};
          var apiUrl = String(webMeta.apiUrl || '/youtubei/v1/get_transcript');

          if (directParams || continuationParams) {
            return {
              params: String(directParams || continuationParams || ''),
              apiUrl: apiUrl,
              targetId: String(any.targetId || ''),
              source: continuationParams ? 'continuation_endpoint' : 'direct_endpoint'
            };
          }

          for (var k in any) {
            if (!Object.prototype.hasOwnProperty.call(any, k)) continue;
            var nested = extractTranscriptEndpoint(any[k]);
            if (nested && nested.params) return nested;
          }
        }
        return null;
      }
      function textFromRuns(value) {
        if (!value) return '';
        if (typeof value === 'string') return value;
        if (Array.isArray(value)) {
          return value.map(textFromRuns).join('').trim();
        }
        if (typeof value === 'object') {
          if (typeof value.simpleText === 'string') return value.simpleText;
          if (Array.isArray(value.runs)) {
            return value.runs.map(function(run) { return String((run && run.text) || ''); }).join('');
          }
          if (typeof value.text === 'string') return value.text;
        }
        return '';
      }
      function extractLanguageCode(any) {
        if (!any) return '';
        if (Array.isArray(any)) {
          for (var i = 0; i < any.length; i++) {
            var nestedLang = extractLanguageCode(any[i]);
            if (nestedLang) return nestedLang;
          }
          return '';
        }
        if (typeof any === 'object') {
          if (typeof any.languageCode === 'string' && any.languageCode) return any.languageCode;
          if (any.selectedAccessibilityLanguage && typeof any.selectedAccessibilityLanguage.languageCode === 'string') {
            return any.selectedAccessibilityLanguage.languageCode;
          }
          for (var k in any) {
            if (!Object.prototype.hasOwnProperty.call(any, k)) continue;
            var nested = extractLanguageCode(any[k]);
            if (nested) return nested;
          }
        }
        return '';
      }
      function transcriptLineFromRenderer(renderer) {
        if (!renderer || typeof renderer !== 'object') return '';
        var rawTimestamp = textFromRuns(renderer.startTimeText) ||
          textFromRuns(renderer.startOffsetText) ||
          textFromRuns(renderer.endTimeText) ||
          '';
        var body = textFromRuns(renderer.snippet) ||
          textFromRuns(renderer.content) ||
          textFromRuns(renderer.cue) ||
          '';

        if (!body) {
          var label = String((((renderer.accessibility || {}).accessibilityData || {}).label) || '').replace(/\s+/g, ' ').trim();
          if (label) {
            if (rawTimestamp && label.indexOf(rawTimestamp) === 0) {
              body = label.slice(rawTimestamp.length).trim();
            } else {
              body = label;
            }
          }
        }

        body = String(body || '').replace(/\s+/g, ' ').trim();
        if (!body) return '';
        var normalizedTimestamp = normalizeTimestamp(rawTimestamp);
        return (normalizedTimestamp ? '[' + normalizedTimestamp + '] ' : '') + body;
      }
      function extractTranscriptFromRendererJSON(root) {
        var lines = [];
        function walk(any) {
          if (!any) return;
          if (Array.isArray(any)) {
            for (var i = 0; i < any.length; i++) walk(any[i]);
            return;
          }
          if (typeof any !== 'object') return;

          if (any.transcriptSegmentRenderer) {
            var direct = transcriptLineFromRenderer(any.transcriptSegmentRenderer);
            if (direct) lines.push(direct);
            return;
          }
          if (any.transcriptSegmentListItemRenderer && any.transcriptSegmentListItemRenderer.transcriptSegmentRenderer) {
            var listItem = transcriptLineFromRenderer(any.transcriptSegmentListItemRenderer.transcriptSegmentRenderer);
            if (listItem) lines.push(listItem);
            return;
          }
          if (any.transcriptCueGroupRenderer && Array.isArray(any.transcriptCueGroupRenderer.cues)) {
            walk(any.transcriptCueGroupRenderer.cues);
          }
          for (var k in any) {
            if (!Object.prototype.hasOwnProperty.call(any, k)) continue;
            walk(any[k]);
          }
        }
        walk(root);
        var deduped = [];
        for (var i = 0; i < lines.length; i++) {
          if (!deduped.length || deduped[deduped.length - 1] !== lines[i]) {
            deduped.push(lines[i]);
          }
        }
        return deduped.join('\n').trim();
      }
      function findCaptionTracks(any) {
        if (!any) return null;
        if (Array.isArray(any)) {
          for (var i = 0; i < any.length; i++) {
            var found = findCaptionTracks(any[i]);
            if (found && found.length) return found;
          }
          return null;
        }
        if (typeof any === 'object') {
          if (Array.isArray(any.captionTracks) && any.captionTracks.length) return any.captionTracks;
          for (var k in any) {
            if (!Object.prototype.hasOwnProperty.call(any, k)) continue;
            var nested = findCaptionTracks(any[k]);
            if (nested && nested.length) return nested;
          }
        }
        return null;
      }
      function normalizeLang(code) {
        return String(code || '').toLowerCase().replace(/_/g, '-');
      }
      function pickTrack(tracks) {
        if (!tracks || !tracks.length) return null;
        for (var i = 0; i < tracks.length; i++) {
          var code = normalizeLang(tracks[i].languageCode);
          if (code === 'zh-hans' || code.indexOf('zh-hans-') === 0 || code === 'zh-cn') return tracks[i];
        }
        for (var j = 0; j < tracks.length; j++) {
          if (normalizeLang(tracks[j].languageCode).indexOf('zh') === 0) return tracks[j];
        }
        for (var m = 0; m < tracks.length; m++) {
          if (normalizeLang(tracks[m].languageCode).indexOf('en') === 0) return tracks[m];
        }
        return tracks[0];
      }
      function buildVariants(baseUrl) {
        var out = [];
        var seen = Object.create(null);
        function add(u) {
          if (!u || seen[u]) return;
          seen[u] = true;
          out.push(u);
        }
        add(baseUrl);
        try {
          var url = new URL(baseUrl, document.URL);
          var hasFmt = url.searchParams.has('fmt');
          if (!hasFmt) {
            var xml = new URL(url.toString());
            xml.searchParams.set('fmt', 'xml3');
            add(xml.toString());
            var json = new URL(url.toString());
            json.searchParams.set('fmt', 'json3');
            add(json.toString());
          } else {
            var xml2 = new URL(url.toString());
            xml2.searchParams.set('fmt', 'xml3');
            add(xml2.toString());
            var json2 = new URL(url.toString());
            json2.searchParams.set('fmt', 'json3');
            add(json2.toString());
          }
        } catch (_) {}
        return out;
      }
      function parseJSON3(text) {
        try {
          var root = JSON.parse(text);
          var events = Array.isArray(root.events) ? root.events : [];
          var lines = [];
          for (var i = 0; i < events.length; i++) {
            var ev = events[i] || {};
            var segs = Array.isArray(ev.segs) ? ev.segs : [];
            var secs = Math.floor((Number(ev.tStartMs || 0) || 0) / 1000);
            var mm = String(Math.floor(secs / 60)).padStart(2, '0');
            var ss = String(secs % 60).padStart(2, '0');
            for (var j = 0; j < segs.length; j++) {
              var utf8 = String((segs[j] && segs[j].utf8) || '');
              if (utf8.trim()) lines.push('[' + mm + ':' + ss + '] ' + utf8);
            }
          }
          return lines.join('\n').trim();
        } catch (_) {
          return '';
        }
      }
      function decodeXML(text) {
        return String(text || '')
          .replace(/&amp;/g, '&')
          .replace(/&lt;/g, '<')
          .replace(/&gt;/g, '>')
          .replace(/&quot;/g, '"')
          .replace(/&#39;/g, "'")
          .replace(/&nbsp;/g, ' ');
      }
      function parseXML(text) {
        try {
          var doc = new DOMParser().parseFromString(text, 'text/xml');
          var nodes = Array.prototype.slice.call(doc.getElementsByTagName('text'));
          var lines = [];
          for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            var start = Number(node.getAttribute('start') || '0') || 0;
            var secs = Math.floor(start);
            var mm = String(Math.floor(secs / 60)).padStart(2, '0');
            var ss = String(secs % 60).padStart(2, '0');
            var value = decodeXML(node.textContent || '').replace(/\s+/g, ' ').trim();
            if (value) lines.push('[' + mm + ':' + ss + '] ' + value);
          }
          return lines.join('\n').trim();
        } catch (_) {
          return '';
        }
      }
      function extractPlayerResponse() {
        if (window.ytInitialPlayerResponse && typeof window.ytInitialPlayerResponse === 'object') return window.ytInitialPlayerResponse;
        if (window.ytplayer && window.ytplayer.config && window.ytplayer.config.args) {
          var raw = window.ytplayer.config.args.raw_player_response || window.ytplayer.config.args.player_response;
          if (raw) {
            try { return typeof raw === 'string' ? JSON.parse(raw) : raw; } catch (_) {}
          }
        }
        var scripts = document.scripts || [];
        for (var i = 0; i < scripts.length; i++) {
          var text = String((scripts[i] && scripts[i].textContent) || '');
          var idx = text.indexOf('ytInitialPlayerResponse');
          if (idx === -1) continue;
          var start = text.indexOf('{', idx);
          if (start === -1) continue;
          var depth = 0;
          var inStr = false;
          var esc = false;
          for (var j = start; j < text.length; j++) {
            var ch = text[j];
            if (inStr) {
              if (esc) { esc = false; }
              else if (ch === '\\') { esc = true; }
              else if (ch === '"') { inStr = false; }
            } else {
              if (ch === '"') { inStr = true; }
              else if (ch === '{') { depth += 1; }
              else if (ch === '}') {
                depth -= 1;
                if (depth === 0) {
                  try { return JSON.parse(text.slice(start, j + 1)); } catch (_) { break; }
                }
              }
            }
          }
        }
        return null;
      }
      async function tryTranscriptEndpointJSON() {
        var initialData = extractInitialData();
        var endpoint = extractTranscriptEndpoint(initialData || extractPlayerResponse());
        if (!endpoint || !endpoint.params) {
          return { err: 'no_transcript_endpoint', source: 'transcript_endpoint' };
        }
        var apiKey = ytcfgGet('INNERTUBE_API_KEY');
        var context = ytcfgGet('INNERTUBE_CONTEXT');
        if (!apiKey || !context) {
          return { err: 'no_innertube_context', source: 'transcript_endpoint' };
        }

        var requestURL;
        try {
          requestURL = new URL(String(endpoint.apiUrl || '/youtubei/v1/get_transcript'), document.URL);
          if (!requestURL.searchParams.has('prettyPrint')) requestURL.searchParams.set('prettyPrint', 'false');
          if (!requestURL.searchParams.has('key')) requestURL.searchParams.set('key', String(apiKey));
        } catch (_) {
          return { err: 'bad_transcript_endpoint', source: 'transcript_endpoint' };
        }

        var headers = { 'Content-Type': 'application/json' };
        var clientName = ytcfgGet('INNERTUBE_CONTEXT_CLIENT_NAME');
        var clientVersion = ytcfgGet('INNERTUBE_CONTEXT_CLIENT_VERSION') || (((context || {}).client || {}).clientVersion) || '';
        var visitorData = (((context || {}).client || {}).visitorData) || ytcfgGet('VISITOR_DATA') || '';
        if (clientName !== null && clientName !== undefined && String(clientName) !== '') {
          headers['X-YouTube-Client-Name'] = String(clientName);
        }
        if (clientVersion) headers['X-YouTube-Client-Version'] = String(clientVersion);
        if (visitorData) headers['X-Goog-Visitor-Id'] = String(visitorData);
        headers['X-Origin'] = location.origin;

        try {
          var response = await fetch(requestURL.toString(), {
            method: 'POST',
            credentials: 'include',
            headers: headers,
            body: JSON.stringify({ context: context, params: endpoint.params })
          });
          var bodyText = String(await response.text() || '');
          if (!response.ok) {
            return { err: 'endpoint_http_' + response.status, source: 'transcript_endpoint' };
          }
          var payload = bodyText ? JSON.parse(bodyText) : null;
          var transcript = extractTranscriptFromRendererJSON(payload);
          if (transcript) {
            return {
              transcript: transcript,
              languageCode: extractLanguageCode(payload),
              source: 'transcript_endpoint'
            };
          }
          return { err: 'endpoint_transcript_empty', source: 'transcript_endpoint' };
        } catch (e) {
          return { err: String(e), source: 'transcript_endpoint' };
        }
      }
      function isLikelyTimestamp(text) {
        return /^\d{1,2}:\d{2}(?::\d{2})?$/.test(String(text || '').trim());
      }
      function normalizeTimestamp(text) {
        var raw = String(text || '').trim();
        var match = raw.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/);
        if (!match) return raw;
        var seconds = match[3]
          ? Number(match[1]) * 3600 + Number(match[2]) * 60 + Number(match[3])
          : Number(match[1]) * 60 + Number(match[2]);
        var mm = String(Math.floor(seconds / 60)).padStart(2, '0');
        var ss = String(seconds % 60).padStart(2, '0');
        return mm + ':' + ss;
      }
      function isVisible(el) {
        if (!(el instanceof Element)) return false;
        var rect = el.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      }
      function queryTranscriptPanel() {
        return document.querySelector('ytd-engagement-panel-section-list-renderer[target-id*="engagement-panel-searchable-transcript"]') ||
          document.querySelector('ytd-engagement-panel-section-list-renderer[target-id*="transcript"]') ||
          document.querySelector('ytd-transcript-search-panel-renderer') ||
          null;
      }
      function queryTranscriptSegmentNodes(root) {
        var scope = root || document;
        var nodes = Array.prototype.slice.call(scope.querySelectorAll('ytd-transcript-segment-renderer'));
        if (nodes.length) return nodes;
        return Array.prototype.slice.call(scope.querySelectorAll('[target-id*="transcript"] ytd-transcript-segment-renderer'));
      }
      function uniqueTextsFromNode(node) {
        var seen = Object.create(null);
        var values = [];
        var textNodes = Array.prototype.slice.call(node.querySelectorAll('yt-formatted-string, span, div'));
        for (var i = 0; i < textNodes.length; i++) {
          var value = String(textNodes[i].textContent || '').replace(/\s+/g, ' ').trim();
          if (!value || seen[value]) continue;
          seen[value] = true;
          values.push(value);
        }
        return values;
      }
      function extractTranscriptFromDOM(root) {
        var segmentNodes = queryTranscriptSegmentNodes(root);
        if (!segmentNodes.length) return '';
        var lines = [];
        for (var i = 0; i < segmentNodes.length; i++) {
          var node = segmentNodes[i];
          var timestampNode = node.querySelector('#segment-start-offset, [id*="start-offset"], [class*="timestamp"], [class*="cue-group-start-offset"]');
          var rawTimestamp = timestampNode ? String(timestampNode.textContent || '').replace(/\s+/g, ' ').trim() : '';
          var normalizedTimestamp = normalizeTimestamp(rawTimestamp);
          var texts = uniqueTextsFromNode(node);
          var bodyParts = [];
          for (var j = 0; j < texts.length; j++) {
            var text = texts[j];
            if (text === rawTimestamp || isLikelyTimestamp(text)) continue;
            bodyParts.push(text);
          }
          if (!bodyParts.length) {
            var whole = String(node.textContent || '').replace(/\s+/g, ' ').trim();
            if (whole) bodyParts = [whole];
          }
          var body = bodyParts.join(' ').replace(/\s+/g, ' ').trim();
          if (rawTimestamp && body.indexOf(rawTimestamp) === 0) {
            body = body.slice(rawTimestamp.length).trim();
          }
          if (!body) continue;
          lines.push((normalizedTimestamp ? '[' + normalizedTimestamp + '] ' : '') + body);
        }
        var deduped = [];
        for (var k = 0; k < lines.length; k++) {
          if (!deduped.length || deduped[deduped.length - 1] !== lines[k]) {
            deduped.push(lines[k]);
          }
        }
        return deduped.join('\n').trim();
      }
      function clickTranscriptEntry() {
        var selectors = [
          'ytd-video-description-transcript-section-renderer button',
          'ytd-video-description-transcript-section-renderer',
          'button[aria-controls*="transcript"]',
          'tp-yt-paper-button[aria-controls*="transcript"]',
          '[target-id*="engagement-panel-searchable-transcript"] button',
          '[target-id*="engagement-panel-searchable-transcript"] tp-yt-paper-button',
          'ytd-engagement-panel-section-list-renderer[target-id*="transcript"] button'
        ];
        for (var i = 0; i < selectors.length; i++) {
          var nodes = Array.prototype.slice.call(document.querySelectorAll(selectors[i]));
          for (var j = 0; j < nodes.length; j++) {
            var node = nodes[j];
            if (!isVisible(node) && selectors[i].indexOf('ytd-engagement-panel-section-list-renderer') === -1) continue;
            try {
              node.click();
              return true;
            } catch (_) {}
          }
        }
        return false;
      }
      async function tryCaptionTrackTranscript() {
        var playerResponse = extractPlayerResponse();
        if (!playerResponse) return { err: 'no_player_response', source: 'caption_tracks' };
        var tracks = findCaptionTracks(playerResponse);
        if (!tracks || !tracks.length) return { err: 'no_caption_tracks', source: 'caption_tracks' };
        var chosen = pickTrack(tracks);
        if (!chosen || !chosen.baseUrl) return { err: 'no_caption_base_url', source: 'caption_tracks' };
        var variants = buildVariants(String(chosen.baseUrl));
        for (var x = 0; x < variants.length; x++) {
          try {
            var resp = await fetch(variants[x], { credentials: 'include' });
            if (!resp.ok) continue;
            var body = String(await resp.text() || '').trim();
            if (!body) continue;
            var transcript = body[0] === '{' ? parseJSON3(body) : parseXML(body);
            if (transcript) {
              return {
                transcript: transcript,
                languageCode: String(chosen.languageCode || ''),
                source: 'caption_tracks'
              };
            }
          } catch (_) {}
        }
        return { err: 'page_fetch_failed', source: 'caption_tracks' };
      }
      async function tryTranscriptPanelDOM() {
        var transcript = extractTranscriptFromDOM(queryTranscriptPanel() || document);
        if (transcript) {
          return { transcript: transcript, source: 'dom_existing' };
        }

        clickTranscriptEntry();

        for (var attempt = 0; attempt < 20; attempt++) {
          await wait(250);
          transcript = extractTranscriptFromDOM(queryTranscriptPanel() || document);
          if (transcript) {
            return { transcript: transcript, source: 'dom_panel' };
          }
        }

        return { err: 'dom_transcript_unavailable', source: 'dom_panel' };
      }

      // Wait for YouTube SPA hydration
      for (var _hydrationAttempt = 0; _hydrationAttempt < 12; _hydrationAttempt++) {
        if (typeof window.ytcfg !== 'undefined' && typeof window.ytcfg.get === 'function' && window.ytcfg.get('INNERTUBE_API_KEY')) break;
        await wait(250);
      }

      try {
        var fromEndpoint = await tryTranscriptEndpointJSON();
        if (fromEndpoint && fromEndpoint.transcript) {
          return stringify({
            ok: true,
            transcript: fromEndpoint.transcript,
            languageCode: fromEndpoint.languageCode || '',
            source: fromEndpoint.source
          });
        }

        var fromTracks = await tryCaptionTrackTranscript();
        if (fromTracks && fromTracks.transcript) {
          return stringify({
            ok: true,
            transcript: fromTracks.transcript,
            languageCode: fromTracks.languageCode || '',
            source: fromTracks.source
          });
        }

        var fromDOM = await tryTranscriptPanelDOM();
        if (fromDOM && fromDOM.transcript) {
          return stringify({
            ok: true,
            transcript: fromDOM.transcript,
            languageCode: '',
            source: fromDOM.source
          });
        }

        return stringify({
          ok: false,
          err: (fromDOM && fromDOM.err) || (fromTracks && fromTracks.err) || (fromEndpoint && fromEndpoint.err) || 'transcript_unavailable',
          source: (fromDOM && fromDOM.source) || (fromTracks && fromTracks.source) || (fromEndpoint && fromEndpoint.source) || 'unknown'
        });
      } catch (e) {
        return stringify({ ok: false, err: String(e), source: 'exception' });
      }
    })();
    """#

    static func youtubeTranscriptBootstrapScriptForTesting() -> String {
        youtubeTranscriptBootstrapJS
    }

    static func youtubeFallbackBootstrapScriptForTesting() -> String {
        youtubeFallbackBootstrapJS
    }

    private static func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
