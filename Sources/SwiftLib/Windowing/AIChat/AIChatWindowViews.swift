import SwiftUI

// MARK: - SwiftUI host view

struct AIChatHostView: View {
    @ObservedObject var manager: AIChatWindowManager
    @ObservedObject var selectorService = AIDOMSelectorService.shared

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let banner = manager.statusBanner {
                Divider()
                AIChatStatusBannerView(banner: banner)
            }
            Divider()
            chatWebView
        }
        .task {
            await AIDOMSelectorService.shared.autoUpdateIfNeeded()
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 0) {
            AIChatToolbar(
                urlString: $manager.currentURLString,
                onReload: {
                    manager.reloadCurrentPage()
                },
                onGoBack: {
                    NotificationCenter.default.post(name: .aiChatGoBack, object: nil)
                },
                onGoForward: {
                    NotificationCenter.default.post(name: .aiChatGoForward, object: nil)
                },
                onChangeService: { newURL in
                    manager.changeService(to: newURL)
                }
            )

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            Button {
                Task { await AIDOMSelectorService.shared.updateFromRemote() }
            } label: {
                if selectorService.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.borderless)
            .disabled(selectorService.isUpdating)
            .help("更新 DOM 选择器配置（v\(selectorService.config.version)）")
            .padding(.trailing, 8)
        }
    }

    @ViewBuilder
    private var chatWebView: some View {
        if let url = URL(string: manager.currentURLString), !manager.currentURLString.isEmpty {
            AIChatBrowserView(url: url)
        } else {
            VStack {
                Spacer()
                Text("请在设置中配置 AI 服务 URL")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

private struct AIChatStatusBannerView: View {
    let banner: AIChatStatusBanner

    var body: some View {
        HStack(spacing: 8) {
            if banner.showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: banner.systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }

            Text(banner.message)
                .font(.caption)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
    }

    private var foregroundColor: Color {
        switch banner.tone {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch banner.tone {
        case .info:
            return Color.secondary.opacity(0.08)
        case .warning:
            return Color.orange.opacity(0.10)
        case .error:
            return Color.red.opacity(0.10)
        }
    }
}
