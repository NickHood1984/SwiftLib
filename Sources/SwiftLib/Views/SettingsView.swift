import SwiftUI

// MARK: - Settings Root

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .plugins

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Text(tab.title)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 200)
        } detail: {
            selectedTab.content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar(.hidden)
        .frame(width: 620, height: 440)
    }
}

// MARK: - Tab Enum

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, plugins, ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:  return "通用"
        case .plugins:  return "插件与工具"
        case .ai:       return "AI 助手"
        }
    }

    var icon: String {
        switch self {
        case .general:  return "gearshape"
        case .plugins:  return "puzzlepiece.extension"
        case .ai:       return "sparkles"
        }
    }

    @ViewBuilder var content: some View {
        switch self {
        case .general:  GeneralSettingsTab()
        case .plugins:  PluginsSettingsTab()
        case .ai:       AISettingsTab()
        }
    }
}

// MARK: - 通用

private struct GeneralSettingsTab: View {
    @AppStorage(SwiftLibPreferences.appendYouTubeTranscriptOnClipKey)
    private var appendTranscript = false

    @State private var apiEmail: String = SwiftLibPreferences.apiContactEmail
    @State private var paddleOCRToken: String = SwiftLibPreferences.paddleOCRToken

    var body: some View {
        Form {
            Section("YouTube 剪藏") {
                Toggle("剪藏时自动追加字幕到笔记", isOn: $appendTranscript)
            }

            Section("学术 API") {
                TextField("联系邮箱（CrossRef / OpenAlex）", text: $apiEmail)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiEmail) { _, newValue in
                        SwiftLibPreferences.apiContactEmail = newValue
                    }
                Text("提供邮箱可接入 CrossRef polite pool，获得更高速率限制。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("PDF 智能识别（PaddleOCR）") {
                SecureField("Token", text: $paddleOCRToken)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: paddleOCRToken) { _, newValue in
                        SwiftLibPreferences.paddleOCRToken = newValue
                    }
                Text("用于 PDF OCR 识别，将扫描版 PDF 转换为可阅读的 Markdown。Token 会安全存储在系统 Keychain。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 插件与工具

private struct PluginsSettingsTab: View {
    @State private var toast: PluginToastData?
    // Force view refresh after install/uninstall
    @State private var refreshToken = UUID()

    var body: some View {
        Form {
            Section {
                PluginRow(
                    icon: "terminal",
                    name: "CLI 工具",
                    description: "命令行工具，安装到 \(CLIInstaller.installURL.path)",
                    isInstalled: CLIInstaller.isInstalled,
                    onInstall: {
                        do {
                            try CLIInstaller.install()
                            showToast("CLI 已安装到 \(CLIInstaller.installURL.path)", tone: .success)
                        } catch {
                            showToast("安装失败：\(error.localizedDescription)", tone: .error)
                        }
                    },
                    onUninstall: {
                        do {
                            try CLIInstaller.uninstall()
                            showToast("CLI 工具已卸载", tone: .info)
                        } catch {
                            showToast("卸载失败：\(error.localizedDescription)", tone: .error)
                        }
                    },
                    onReveal: { CLIInstaller.revealInFinder() }
                )
            }

            Section {
                PluginRow(
                    icon: "doc.richtext",
                    name: "Word 插件",
                    description: "Microsoft Word 引用管理插件",
                    isInstalled: WordAddinInstaller.isInstalled,
                    onInstall: {
                        do {
                            try WordAddinInstaller.install()
                            showToast("Word 插件已安装", tone: .success)
                        } catch {
                            showToast("安装失败：\(error.localizedDescription)", tone: .error)
                        }
                    },
                    onUninstall: {
                        WordAddinInstaller.uninstall()
                        showToast("Word 插件已卸载", tone: .info)
                    },
                    onReveal: { WordAddinInstaller.revealManifest() }
                )

                if WordAddinServer.shared.isRunning {
                    LabeledContent("插件服务") {
                        Text("运行中 · 端口 \(WordAddinServer.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if WPSAddinInstaller.isWPSInstalled {
                Section {
                    PluginRow(
                        icon: "doc.text",
                        name: "WPS 插件",
                        description: "WPS Office 引用管理插件",
                        isInstalled: WPSAddinInstaller.isInstalled,
                        onInstall: {
                            do {
                                try WPSAddinInstaller.install()
                                showToast("WPS 插件已安装", tone: .success)
                            } catch {
                                showToast("安装失败：\(error.localizedDescription)", tone: .error)
                            }
                        },
                        onUninstall: {
                            WPSAddinInstaller.uninstall()
                            showToast("WPS 插件已卸载", tone: .info)
                        },
                        onReveal: { WPSAddinInstaller.revealAddin() }
                    )
                }
            }
        }
        .formStyle(.grouped)
        .id(refreshToken)
        .overlay(alignment: .bottom) {
            if let toast {
                PluginToast(data: toast)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ message: String, tone: PluginToastTone) {
        let data = PluginToastData(message: message, tone: tone)
        withAnimation(.easeInOut(duration: 0.25)) {
            toast = data
        }
        refreshToken = UUID()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.25)) {
                if toast?.id == data.id { toast = nil }
            }
        }
    }
}

// MARK: - AI 助手

private struct AISettingsTab: View {
    @State private var selectedURL: String = SwiftLibPreferences.aiChatURL
    @State private var customURL: String = ""

    private var isCustom: Bool {
        !SwiftLibPreferences.aiChatPresets.contains(where: { $0.url == selectedURL })
    }

    var body: some View {
        Form {
            Section("AI 服务") {
                Picker("默认服务", selection: $selectedURL) {
                    ForEach(SwiftLibPreferences.aiChatPresets, id: \.url) { preset in
                        Text(preset.name).tag(preset.url)
                    }
                    Divider()
                    Text("自定义").tag("__custom__")
                }
                .onChange(of: selectedURL) { _, newValue in
                    if newValue == "__custom__" {
                        customURL = ""
                    } else {
                        SwiftLibPreferences.aiChatURL = newValue
                    }
                }

                if selectedURL == "__custom__" || isCustom {
                    TextField("自定义 URL", text: $customURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            guard !customURL.isEmpty else { return }
                            SwiftLibPreferences.aiChatURL = customURL
                            selectedURL = customURL
                        }
                        .onAppear {
                            if isCustom { customURL = selectedURL }
                        }
                }
            }

            Section("快捷键") {
                LabeledContent("打开 AI 助手") {
                    Text("⇧⌘A")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Plugin Row Component

private struct PluginRow: View {
    let icon: String
    let name: String
    let description: String
    let isInstalled: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(.body.weight(.medium))
                    Text(isInstalled ? "已安装" : "未安装")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            isInstalled
                                ? Color.green.opacity(0.15)
                                : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                        .foregroundStyle(isInstalled ? .green : .secondary)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(isInstalled ? "重新安装" : "安装") {
                    onInstall()
                }
                .controlSize(.small)

                if isInstalled {
                    Button("卸载") { onUninstall() }
                        .controlSize(.small)
                    Button {
                        onReveal()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .controlSize(.small)
                    .help("在 Finder 中显示")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Plugin Toast

private struct PluginToastData: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let tone: PluginToastTone
}

private enum PluginToastTone {
    case success, error, info

    var color: Color {
        switch self {
        case .success: return .green
        case .error:   return .red
        case .info:    return .secondary
        }
    }
}

private struct PluginToast: View {
    let data: PluginToastData

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(data.tone.color).frame(width: 8, height: 8)
            Text(data.message).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
    }
}
