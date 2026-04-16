import AppKit
import Sparkle
import SwiftUI

// MARK: - Driver

/// Custom Sparkle user driver that displays update UI with a frosted-glass style.
@MainActor
final class GlassUpdateDriver: NSObject, SPUUserDriver {

    private var panel: GlassUpdatePanel?

    // Download tracking
    private var downloadExpected: UInt64 = 0
    private var downloadReceived: UInt64 = 0
    private var downloadCancel: (() -> Void)?

    // MARK: Permission

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        // Auto-grant: enable automatic update checks by default.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    // MARK: Checking

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        present(GlassCheckingView {
            cancellation()
            self.dismiss()
        }, size: CGSize(width: 320, height: 130))
    }

    // MARK: Update Found

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        present(GlassUpdateFoundView(item: appcastItem, state: state) { choice in
            reply(choice)
            // Keep panel open for install (→ transitions to download); close otherwise.
            if choice != .install { self.dismiss() }
        }, size: CGSize(width: 440, height: 330))
    }

    // Release notes are linked externally; no inline handling needed.
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    // MARK: No Update Found (async)

    func showUpdateNotFoundWithError(_ error: Error) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            present(GlassAlertView(
                symbol: "checkmark.circle.fill",
                symbolColor: .green,
                title: "已是最新版本",
                message: noUpdateMessage(from: error),
                primary: "好"
            ) {
                self.dismiss()
                cont.resume()
            }, size: CGSize(width: 320, height: 200))
        }
    }

    // MARK: Error (async)

    func showUpdaterError(_ error: Error) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            present(GlassAlertView(
                symbol: "exclamationmark.triangle.fill",
                symbolColor: .orange,
                title: "更新出错",
                message: error.localizedDescription,
                primary: "好"
            ) {
                self.dismiss()
                cont.resume()
            }, size: CGSize(width: 320, height: 200))
        }
    }

    // MARK: Download

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        downloadExpected = 0
        downloadReceived = 0
        downloadCancel = cancellation
        refreshDownloadUI()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        downloadExpected = expectedContentLength
        refreshDownloadUI()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        downloadReceived = min(downloadReceived + length, downloadExpected > 0 ? downloadExpected : .max)
        refreshDownloadUI()
    }

    private func refreshDownloadUI() {
        let exp = downloadExpected
        let recv = downloadReceived
        let progress: Double? = exp > 0 ? Double(recv) / Double(exp) : nil
        let status = formatDownloadStatus(received: recv, expected: exp)
        let cancel = downloadCancel
        present(GlassProgressView(
            title: "正在下载更新…",
            status: status,
            progress: progress,
            onCancel: cancel.map { action in { action(); self.dismiss() } }
        ), size: CGSize(width: 340, height: 155))
    }

    // MARK: Extracting

    func showDownloadDidStartExtractingUpdate() {
        present(GlassSpinnerView(title: "正在解压更新包…"), size: CGSize(width: 340, height: 120))
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        present(GlassProgressView(
            title: "正在解压更新包…",
            status: "\(Int(progress * 100))%",
            progress: progress,
            onCancel: nil
        ), size: CGSize(width: 340, height: 130))
    }

    // MARK: Ready to Install

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        present(GlassAlertView(
            symbol: "arrow.down.circle.fill",
            symbolColor: Color.accentColor,
            title: "更新准备就绪",
            message: "点击「安装并重启」以完成安装。",
            primary: "安装并重启",
            secondary: "稍后",
            onPrimary: { reply(.install) },
            onSecondary: { reply(.dismiss); self.dismiss() }
        ), size: CGSize(width: 340, height: 225))
    }

    // MARK: Installing

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        present(GlassSpinnerView(title: "正在安装更新…"), size: CGSize(width: 340, height: 120))
    }

    // MARK: Installed (async)

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        dismiss()
    }

    // MARK: Dismiss

    func dismissUpdateInstallation() {
        dismiss()
    }

    func showUpdateInFocus() {
        panel?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Panel helpers

    private func present<V: View>(_ view: V, size: CGSize) {
        let wrapped = AnyView(view)
        if let p = panel {
            p.swap(to: wrapped, size: size)
        } else {
            let p = GlassUpdatePanel(view: wrapped, size: size)
            p.center()
            p.makeKeyAndOrderFront(nil)
            panel = p
        }
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Utilities

    private func noUpdateMessage(from error: Error) -> String {
        let ns = error as NSError
        if let reason = ns.userInfo["SPUNoUpdateFoundReasonKey"] as? Int, reason == 0 {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            return version.isEmpty ? "您已安装最新版本。" : "当前版本 \(version) 已是最新版本。"
        }
        return error.localizedDescription
    }

    private func formatDownloadStatus(received: UInt64, expected: UInt64) -> String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        let r = fmt.string(fromByteCount: Int64(received))
        guard expected > 0 else { return r }
        let e = fmt.string(fromByteCount: Int64(expected))
        return "\(r) / \(e)"
    }
}

// MARK: - Hosting Panel

@MainActor
private final class GlassUpdatePanel: NSPanel {

    private let hosting: NSHostingController<AnyView>

    init(view: AnyView, size: CGSize) {
        hosting = NSHostingController(rootView: view)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .modalPanel
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        contentViewController = hosting
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear
    }

    func swap(to view: AnyView, size: CGSize) {
        hosting.rootView = view
        guard frame.size != size else { return }
        var f = frame
        f.origin.x += (f.width - size.width) / 2
        f.origin.y += (f.height - size.height) / 2
        f.size = size
        setFrame(f, display: true, animate: false)
    }
}

// MARK: - Glass Container Style

private struct GlassContainer: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Button Styles

private struct GlassPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor)
                    .opacity(configuration.isPressed ? 0.75 : 1)
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct GlassSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(configuration.isPressed ? 0.5 : 1)
            )
            .foregroundStyle(.primary)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Views

/// "Checking for updates…"
private struct GlassCheckingView: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
            Text("正在检查更新…")
                .font(.headline)
            Button("取消", action: onCancel)
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 320, height: 130)
        .modifier(GlassContainer())
    }
}

/// Indeterminate spinner (extracting / installing)
private struct GlassSpinnerView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text(title)
                .font(.headline)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .modifier(GlassContainer())
    }
}

/// Determinate or indeterminate download/extraction progress
private struct GlassProgressView: View {
    let title: String
    let status: String
    let progress: Double?
    let onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)

            if let p = progress {
                SwiftUI.ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .frame(width: 270)
            } else {
                SwiftUI.ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 270)
            }

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)

            if let cancel = onCancel {
                Button("取消", action: cancel)
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .modifier(GlassContainer())
    }
}

/// Reusable icon + title + message + button(s) alert
private struct GlassAlertView: View {
    let symbol: String
    let symbolColor: Color
    let title: String
    let message: String
    let primary: String
    var secondary: String? = nil
    let onPrimary: () -> Void
    var onSecondary: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 44))
                .foregroundStyle(symbolColor)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if let sec = secondary, let secAction = onSecondary {
                    Button(sec, action: secAction)
                        .buttonStyle(GlassSecondaryButton())
                }
                Button(primary, action: onPrimary)
                    .buttonStyle(GlassPrimaryButton())
            }
            .padding(.top, 2)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .modifier(GlassContainer())
    }
}

/// Main "update available" dialog
private struct GlassUpdateFoundView: View {
    let item: SUAppcastItem
    let state: SPUUserUpdateState
    let onChoice: (SPUUserUpdateChoice) -> Void

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "SwiftLib"
    }

    private var installLabel: String {
        state.stage == .notDownloaded ? "安装更新" : "安装并重启"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 14) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 56, height: 56)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("发现新版本")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if item.isCriticalUpdate {
                            Text("重要更新")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.18), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }

                    Text("\(appName) \(item.displayVersionString)")
                        .font(.title3.weight(.semibold))
                }

                Spacer()
            }
            .padding(.bottom, 16)

            Divider()
                .padding(.bottom, 14)

            // ── Release notes link ───────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("更新内容")
                    .font(.caption.weight(.medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)

                let notesURL = item.fullReleaseNotesURL ?? item.releaseNotesURL ?? item.infoURL
                if let url = notesURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 4) {
                            Text("查看完整发布说明")
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                } else {
                    Text("暂无发布说明")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 20)

            Divider()
                .padding(.bottom, 14)

            // ── Actions ──────────────────────────────────────────────────
            HStack(spacing: 8) {
                Button("跳过此版本") { onChoice(.skip) }
                    .buttonStyle(GlassSecondaryButton())

                Spacer()

                Button("稍后提醒") { onChoice(.dismiss) }
                    .buttonStyle(GlassSecondaryButton())

                Button(installLabel) { onChoice(.install) }
                    .buttonStyle(GlassPrimaryButton())
            }
        }
        .padding(24)
        .modifier(GlassContainer())
    }
}
