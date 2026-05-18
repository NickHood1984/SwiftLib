import SwiftUI
import SwiftLibCore

struct WebReaderView: View {
    @StateObject private var viewModel: WebReaderViewModel
    @StateObject private var transcriptPageFetcher = YouTubeTranscriptPageFetcher()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAnnotationSidebar = true
    private let onClose: (() -> Void)?

    init(reference: Reference, onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: WebReaderViewModel(reference: reference))
    }

    var body: some View {
        HSplitView {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if usesPinnedYouTubeHeader {
                        pinnedYouTubeHeader
                    }
                    youTubeInlineHeader
                    GeometryReader { proxy in
                        WebReaderContentView(viewModel: viewModel)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .overlay {
                                webSelectionToolbarOverlay
                            }
                            .overlay {
                                webAnnotationToolbarOverlay
                            }
                            .onAppear {
                                viewModel.updateViewportSize(proxy.size)
                            }
                            .onChange(of: proxy.size) { _, newSize in
                                viewModel.updateViewportSize(newSize)
                            }
                    }
                }

                if viewModel.isRendering || viewModel.isLiveReadableBusy {
                    ProgressView(viewModel.isLiveReadableBusy ? "正在加载并提取正文…" : "正在渲染 Markdown…")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 14)
                }
            }
            .frame(minWidth: 540)

            if showAnnotationSidebar {
                WebAnnotationSidebarView(viewModel: viewModel)
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 400)
                    .overlay(alignment: .leading) {
                        LinearGradient(
                            colors: [Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 6)
                        .allowsHitTesting(false)
                    }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .onDisappear {
            viewModel.collapseYouTubeInlinePlayer()
        }
        .background {
            if viewModel.reference.isLikelyYouTubeWatchURL {
                HiddenWKWebViewHost(
                    onCreate: { webView in
                        transcriptPageFetcher.registerWebView(webView)
                    }
                )
                .frame(width: 4, height: 4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .animation(
            .spring(response: 0.3, dampingFraction: 0.82),
            value: viewModel.hasSelection && viewModel.selectionToolbarLayout?.visible == true
        )
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if viewModel.allowsDisplayModeSwitching {
                    Picker("阅读模式", selection: Binding(
                        get: { viewModel.displayMode },
                        set: { viewModel.setDisplayMode($0) }
                    )) {
                        ForEach(WebReaderDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }

                if !usesPinnedYouTubeHeader {
                    fontControls
                    widthControls
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation { showAnnotationSidebar.toggle() }
                } label: {
                    Label("侧边栏", systemImage: "sidebar.right")
                }
            }
        }
        .onAppear {
            NoteEditorPool.shared.warmUp()
        }
        .onChange(of: viewModel.sidebarSummaryScrollToken) { _, new in
            if new > 0, viewModel.hasSidebarSummary {
                showAnnotationSidebar = true
            }
        }
        .task {
            viewModel.fetchTranscriptFromOriginalPage = { [transcriptPageFetcher] urlString in
                await transcriptPageFetcher.fetchTranscript(urlString: urlString)
            }
        }
        .navigationTitle(viewModel.reference.title)
        .alert("在线阅读", isPresented: Binding(
            get: { viewModel.liveReadableUserMessage != nil },
            set: { if !$0 { viewModel.liveReadableUserMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.liveReadableUserMessage ?? "")
        }
    }

    private var usesPinnedYouTubeHeader: Bool {
        viewModel.reference.youTubeVideoId != nil
    }

    private var pinnedYouTubeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Label("YouTube", systemImage: "play.rectangle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)

                Spacer()

                if let urlString = viewModel.reference.resolvedWebReaderURLString(),
                   let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("原视频", systemImage: "arrow.up.right")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
            }

            Text(viewModel.reference.title)
                .font(.system(size: 24, weight: .bold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let site = viewModel.reference.siteName ?? viewModel.reference.journal,
               !site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(site)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    @ViewBuilder
    private var youTubeInlineHeader: some View {
        if let vid = viewModel.reference.youTubeVideoId {
            let externalURL = viewModel.reference.resolvedWebReaderURLString().flatMap { URL(string: $0) }
                ?? URL(string: "https://www.youtube.com/watch?v=\(vid)")
            Group {
                if viewModel.youTubeInlineWatchURL != nil {
                    ZStack(alignment: .topTrailing) {
                        YouTubeWatchInlineWebView(viewModel: viewModel)
                        Button {
                            viewModel.collapseYouTubeInlinePlayer()
                        } label: {
                            Label("收起视频", systemImage: "xmark")
                                .labelStyle(.iconOnly)
                                .padding(9)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                    }
                } else {
                    YouTubeWatchPlayPlaceholder(videoId: vid, externalWatchURL: externalURL) {
                        viewModel.activateYouTubeInlinePlayer()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipped()
        }
    }

    @ViewBuilder
    private var webSelectionToolbarOverlay: some View {
        let shouldShow = viewModel.hasSelection
            && viewModel.selectionToolbarLayout?.visible == true
        if shouldShow, let layout = viewModel.selectionToolbarLayout {
            WebSelectionActionBar(viewModel: viewModel, metrics: layout.metrics)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: layout.origin.x, y: layout.origin.y)
                .allowsHitTesting(true)
                .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                .animation(.spring(response: 0.25, dampingFraction: 0.82), value: layout.origin)
        }
    }

    @ViewBuilder
    private var webAnnotationToolbarOverlay: some View {
        if viewModel.clickedAnnotationRecord != nil,
           let layout = viewModel.annotationToolbarLayout, layout.visible {
            WebAnnotationActionBar(viewModel: viewModel, metrics: layout.metrics)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: layout.origin.x, y: layout.origin.y)
                .allowsHitTesting(true)
                .transition(.opacity)
        }
    }

    private var fontControls: some View {
        HStack(spacing: 3) {
            Button { viewModel.decreaseFontSize() } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)

            Button { viewModel.increaseFontSize() } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private var widthControls: some View {
        HStack(spacing: 3) {
            Button { viewModel.narrowContent() } label: {
                Image(systemName: "arrow.left.and.line.vertical.and.arrow.right")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)

            Button { viewModel.widenContent() } label: {
                Image(systemName: "arrow.left.and.line.vertical.and.arrow.right.circle")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}

