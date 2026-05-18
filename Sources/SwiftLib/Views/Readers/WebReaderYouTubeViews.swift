import SwiftUI
import WebKit

struct YouTubeWatchInlineWebView: NSViewRepresentable {
    @ObservedObject var viewModel: WebReaderViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = ReaderExtractionManager.safariLikeUserAgent
        webView.setValue(false, forKey: "drawsBackground")
        DispatchQueue.main.async {
            webView.applySwiftLibElegantScrollersRecursively(forceVerticalScroller: true)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        DispatchQueue.main.async {
            webView.applySwiftLibElegantScrollersRecursively(forceVerticalScroller: true)
        }
        guard let url = viewModel.youTubeInlineWatchURL else { return }
        if context.coordinator.lastLoadedURL != url {
            context.coordinator.lastLoadedURL = url
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator {
        var lastLoadedURL: URL?
    }
}

struct YouTubeWatchPlayPlaceholder: View {
    let videoId: String
    let externalWatchURL: URL?
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)

            AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    .black.opacity(0.08),
                                    .black.opacity(0.18),
                                    .black.opacity(0.52)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                case .failure:
                    LinearGradient(
                        colors: [Color.black.opacity(0.86), Color.gray.opacity(0.56)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                case .empty:
                    ZStack {
                        LinearGradient(
                            colors: [Color.black.opacity(0.86), Color.gray.opacity(0.56)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        ProgressView()
                            .controlSize(.regular)
                    }
                @unknown default:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("点击播放在线视频")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("默认保留封面，避免阅读区和网页播放器同时展开。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(18)

            VStack {
                Button(action: onPlay) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("播放在线视频")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.58), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放 YouTube 视频")
            }
        }

    }
}

