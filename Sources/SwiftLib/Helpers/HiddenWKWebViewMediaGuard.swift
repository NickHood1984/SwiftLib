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
