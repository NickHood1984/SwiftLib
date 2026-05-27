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
    private let glassDriver: GlassUpdateDriver
    private let updater: SPUUpdater
    private static let defaultWindowSize = preferredDefaultWindowSize()

    init() {
        let driver = GlassUpdateDriver()
        let upd = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: driver,
            delegate: nil
        )
        glassDriver = driver
        updater = upd
        // Sparkle requires a valid bundle identifier. When running via `swift run`
        // in development there is no .app bundle, so skip starting the updater.
        guard Bundle.main.bundleIdentifier != nil else { return }
        do {
            try upd.start()
        } catch {
            print("SwiftLib: Failed to start Sparkle updater: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .swiftLibElegantScrollersInSubtree()
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
                CheckForUpdatesView(updater: updater)
            }

            CommandMenu("AI") {
                Button("打开 AI 助手") {
                    AIChatWindowManager.shared.open()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }
        WindowGroup("待确认元数据", for: PendingQueueWindowID.self) { _ in
            PendingMetadataQueueSceneView()
                .swiftLibElegantScrollersInSubtree()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 520)

        WindowGroup("工作区", for: Int64.self) { workspaceID in
            ContentView(initialWorkspaceID: workspaceID.wrappedValue)
                .swiftLibElegantScrollersInSubtree()
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
        Settings {
            SettingsView()
                .swiftLibElegantScrollersInSubtree()
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

        // If persistent storage is unavailable, continue with an in-memory database
        // only after the user explicitly acknowledges the limitation.
        if AppDatabase.sharedStorageMode == .inMemoryFallback {
            let alert = NSAlert()
            alert.messageText = "数据库已切换为临时内存模式"
            let detail = AppDatabase.sharedStartupErrorDescription ?? "未知错误"
            alert.informativeText = "SwiftLib 无法打开持久化数据库，本次会话会改用内存数据库继续运行。你仍可浏览和编辑数据，但重启应用后改动不会保留。\n\n错误详情：\(detail)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "退出")
            alert.addButton(withTitle: "继续")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSApp.terminate(nil)
                return
            }
        }

        // Configure API contact email for CrossRef/OpenAlex polite pool
        MetadataFetcher.contactEmail = SwiftLibPreferences.apiContactEmail

        // Register the WebView executor so that adapter routes with `kind: webView`
        // (subscription-gated sources that need cookie-authenticated sessions)
        // are handled by a hidden WKWebView instead of raw URLSession.
        MetadataFetcher.webViewExecutor = WebViewAdapterExecutorImpl()

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
