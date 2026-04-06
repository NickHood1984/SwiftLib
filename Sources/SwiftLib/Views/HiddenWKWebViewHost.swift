import SwiftUI
import WebKit

enum HiddenWKWebViewMediaGuard {
    static let suppressPlaybackScript = #"""
    (() => {
      const silence = (media) => {
        if (!(media instanceof HTMLMediaElement)) return;
        try { media.muted = true; } catch {}
        try { media.volume = 0; } catch {}
        try { media.autoplay = false; } catch {}
        try { media.removeAttribute('autoplay'); } catch {}
        try { media.pause(); } catch {}
      };

      const silenceAll = (root) => {
        if (!root || !root.querySelectorAll) return;
        for (const media of root.querySelectorAll('audio,video')) {
          silence(media);
        }
      };

      silenceAll(document);

      document.addEventListener('play', (event) => {
        silence(event.target);
      }, true);

      const observer = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
          for (const node of mutation.addedNodes) {
            if (node instanceof HTMLMediaElement) {
              silence(node);
              continue;
            }
            if (node instanceof Element) {
              silenceAll(node);
            }
          }
        }
      });

      const root = document.documentElement || document;
      if (root) {
        observer.observe(root, { childList: true, subtree: true });
      }
    })();
    """#

    static func configure(_ configuration: WKWebViewConfiguration) {
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: suppressPlaybackScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
    }
}

@MainActor
struct HiddenWKWebViewHost: NSViewRepresentable {
    var configure: (WKWebViewConfiguration) -> Void = { _ in }
    var onCreate: (WKWebView) -> Void

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 4, height: 4))
        container.wantsLayer = true

        let configuration = WKWebViewConfiguration()
        HiddenWKWebViewMediaGuard.configure(configuration)
        configure(configuration)

        let webView = WKWebView(frame: container.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.customUserAgent = ReaderExtractionManager.safariLikeUserAgent
        webView.isHidden = true

        container.addSubview(webView)
        onCreate(webView)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
