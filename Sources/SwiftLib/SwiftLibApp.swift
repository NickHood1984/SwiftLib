import AppKit
import Sparkle
import SwiftUI
import SwiftLibCore

// MARK: - Sparkle Update Support

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("检查更新…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

// MARK: - App

@main
struct SwiftLibApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var addinToast: AddinToastPayload?
    @AppStorage(SwiftLibPreferences.appendYouTubeTranscriptOnClipKey) private var appendYouTubeTranscriptOnClip = false
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )
    private static let defaultWindowSize = preferredDefaultWindowSize()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay(alignment: .top) {
                    if let toast = addinToast {
                        AddinToast(message: toast.message, tone: toast.tone)
                            .padding(.top, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .swiftLibClipImported)) { note in
                    let title = (note.userInfo?[SwiftLibClipImportedKeys.title] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let message = title.flatMap { !$0.isEmpty ? "已保存网页剪藏：\($0)" : nil } ?? "已保存网页剪藏"
                    showToast(message, tone: .success)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: Self.defaultWindowSize.width, height: Self.defaultWindowSize.height)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }

            CommandGroup(after: .appSettings) {
                Toggle("剪藏 YouTube 时在笔记中追加字幕", isOn: $appendYouTubeTranscriptOnClip)

                Divider()

                Button(CLIInstaller.isInstalled ? "重新安装 CLI 工具" : "安装 CLI 工具") {
                    do {
                        try CLIInstaller.install()
                        showToast("CLI 已安装到 \(CLIInstaller.installURL.path)", tone: .success)
                    } catch {
                        showToast("安装失败：\(error.localizedDescription)", tone: .error, hideAfter: 5)
                    }
                }

                Button("卸载 CLI 工具") {
                    CLIInstaller.uninstall()
                    showToast("CLI 工具已卸载", tone: .info, hideAfter: 2.5)
                }
                .disabled(!CLIInstaller.isInstalled)

                Button("在 Finder 中显示") {
                    CLIInstaller.revealInFinder()
                }

                Divider()

                let installed = CLIInstaller.isInstalled
                Text("状态：\(installed ? "✅ 已安装" : "❌ 未安装")  路径：\(CLIInstaller.installURL.path)")

                Divider()

                Button(WordAddinInstaller.isInstalled ? "重新安装 Word 插件" : "安装 Word 插件") {
                    do {
                        try WordAddinInstaller.install()
                        showToast("Word 插件已安装", tone: .success)
                    } catch {
                        showToast("Word 插件安装失败：\(error.localizedDescription)", tone: .error, hideAfter: 5)
                    }
                }

                Button("卸载 Word 插件") {
                    WordAddinInstaller.uninstall()
                    showToast("Word 插件已卸载", tone: .info, hideAfter: 2.5)
                }
                .disabled(!WordAddinInstaller.isInstalled)

                Button("在 Finder 中显示插件清单") {
                    WordAddinInstaller.revealManifest()
                }

                Divider()

                let addinInstalled = WordAddinInstaller.isInstalled
                Text("Word 插件：\(addinInstalled ? "✅ 已安装" : "❌ 未安装")  服务：\(WordAddinServer.shared.isRunning ? "🟢 运行中" : "⚪ 已停止")")

                if WPSAddinInstaller.isWPSInstalled {
                    Divider()

                    Button(WPSAddinInstaller.isInstalled ? "重新安装 WPS 插件" : "安装 WPS 插件") {
                        do {
                            try WPSAddinInstaller.install()
                            showToast("WPS 插件已安装", tone: .success)
                        } catch {
                            showToast("WPS 插件安装失败：\(error.localizedDescription)", tone: .error, hideAfter: 5)
                        }
                    }

                    Button("卸载 WPS 插件") {
                        WPSAddinInstaller.uninstall()
                        showToast("WPS 插件已卸载", tone: .info, hideAfter: 2.5)
                    }
                    .disabled(!WPSAddinInstaller.isInstalled)

                    Button("在 Finder 中显示 WPS 插件") {
                        WPSAddinInstaller.revealAddin()
                    }

                    let wpsInstalled = WPSAddinInstaller.isInstalled
                    Text("WPS 插件：\(wpsInstalled ? "✅ 已安装" : "❌ 未安装")")
                }
            }

        }
        Settings {
            EmptyView()
        }
    }

    private func showToast(_ message: String, tone: AddinToastTone, hideAfter delay: TimeInterval = 3) {
        let toast = AddinToastPayload(message: message, tone: tone)
        withAnimation(.easeInOut(duration: 0.3)) {
            addinToast = toast
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeInOut(duration: 0.3)) {
                if addinToast?.id == toast.id { addinToast = nil }
            }
        }
    }

    private static func preferredDefaultWindowSize() -> CGSize {
        let fallback = CGSize(width: 1440, height: 920)
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return fallback }

        let width = min(visibleFrame.width - 80, max(1280, visibleFrame.width * 0.84))
        let height = min(visibleFrame.height - 80, max(820, visibleFrame.height * 0.84))
        return CGSize(width: width, height: height)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Configure API contact email for CrossRef/OpenAlex polite pool
        MetadataFetcher.contactEmail = SwiftLibPreferences.apiContactEmail

        // Pre-warm the JSCore engine for the style used in the last session,
        // so the first Word Add-in render request doesn't pay the cold-start cost.
        CiteprocJSCorePool.shared.warmUpLastUsed()

        // Auto-install Word Add-in manifest (idempotent) and start HTTP server
        try? WordAddinInstaller.install()
        try? WPSAddinInstaller.install()
        WordAddinServer.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        WordAddinServer.shared.stop()
        ReaderWindowManager.shared.closeAll()
        TranslationBackendProcessManager.shared.shutdownSync()
    }
}

// MARK: - Toast

private struct AddinToastPayload: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let tone: AddinToastTone
}

private enum AddinToastTone: Equatable {
    case success, error, info

    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .secondary
        }
    }
}

private struct AddinToast: View {
    let message: String
    let tone: AddinToastTone

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                toastContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
            } else {
                toastContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
        }
        .padding(.horizontal, 16)
        .lineLimit(3)
        .allowsHitTesting(false)
    }

    private var toastContent: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tone.color)
                .frame(width: 10, height: 10)
            Text(message)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
        }
    }
}
