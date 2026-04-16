import Foundation

enum SwiftLibPreferences {
    /// 剪藏 YouTube 网页时，是否在后台拉取字幕并追加到 `notes`（默认关闭，避免额外请求与隐私顾虑）。
    static let appendYouTubeTranscriptOnClipKey = "SwiftLib.appendYouTubeTranscriptOnClip"

    static let onboardingCompletedKey = "SwiftLib.onboardingCompleted"

    static var appendYouTubeTranscriptOnClip: Bool {
        get { UserDefaults.standard.bool(forKey: appendYouTubeTranscriptOnClipKey) }
        set { UserDefaults.standard.set(newValue, forKey: appendYouTubeTranscriptOnClipKey) }
    }

    static var onboardingCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingCompletedKey) }
    }

    /// 用于 CrossRef / OpenAlex API polite pool 的联系邮箱。
    /// CrossRef 要求提供真实 mailto 才能进入 polite pool（更快速率限制）。
    static let apiContactEmailKey = "SwiftLib.apiContactEmail"

    static var apiContactEmail: String {
        get { UserDefaults.standard.string(forKey: apiContactEmailKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: apiContactEmailKey) }
    }

    // MARK: - AI Chat

    /// AI 聊天网页的 URL（默认为 ChatGPT）。
    static let aiChatURLKey = "SwiftLib.aiChatURL"

    static var aiChatURL: String {
        get { UserDefaults.standard.string(forKey: aiChatURLKey) ?? "https://chatgpt.com" }
        set { UserDefaults.standard.set(newValue, forKey: aiChatURLKey) }
    }

    /// 预设的 AI 服务列表。
    static let aiChatPresets: [(name: String, url: String)] = [
        ("ChatGPT", "https://chatgpt.com"),
        ("豆包", "https://www.doubao.com/chat/"),
        ("Kimi", "https://kimi.moonshot.cn"),
        ("DeepSeek", "https://chat.deepseek.com"),
    ]

    // MARK: - AI DOM Selectors (远程配置更新)

    /// DOM 选择器配置的远程更新 URL（GitHub raw）。
    static let aiDOMSelectorsRemoteURLKey = "SwiftLib.aiDOMSelectorsRemoteURL"
    static let defaultAIDOMSelectorsRemoteURL = "https://raw.githubusercontent.com/NickHood1984/SwiftLib/main/Sources/SwiftLib/Resources/ai-dom-selectors.json"

    static var aiDOMSelectorsRemoteURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: aiDOMSelectorsRemoteURLKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (stored?.isEmpty == false) ? stored! : defaultAIDOMSelectorsRemoteURL
        }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: aiDOMSelectorsRemoteURLKey
            )
        }
    }

    /// 上次成功更新 DOM 选择器配置的时间。
    static let aiDOMSelectorsLastUpdateKey = "SwiftLib.aiDOMSelectorsLastUpdate"
    static var aiDOMSelectorsLastUpdate: Date {
        get { UserDefaults.standard.object(forKey: aiDOMSelectorsLastUpdateKey) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: aiDOMSelectorsLastUpdateKey) }
    }

    // MARK: - PaddleOCR

    static let paddleOCRTokenKey = "SwiftLib.paddleOCRToken"

    static var paddleOCRToken: String {
        get {
            if let token = KeychainStorage.string(forAccount: paddleOCRTokenKey) {
                return token
            }

            // Migrate any legacy token stored in UserDefaults into Keychain.
            let legacyToken = UserDefaults.standard.string(forKey: paddleOCRTokenKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !legacyToken.isEmpty else { return "" }

            _ = KeychainStorage.set(legacyToken, forAccount: paddleOCRTokenKey)
            UserDefaults.standard.removeObject(forKey: paddleOCRTokenKey)
            return legacyToken
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                _ = KeychainStorage.remove(account: paddleOCRTokenKey)
            } else {
                _ = KeychainStorage.set(trimmed, forAccount: paddleOCRTokenKey)
            }
            UserDefaults.standard.removeObject(forKey: paddleOCRTokenKey)
        }
    }

    // MARK: - WPS Add-in

    /// 是否启用 WPS 插件自动安装（默认为 true，当检测到 WPS 时自动安装）。
    static let enableWPSAddinKey = "SwiftLib.enableWPSAddin"

    static var enableWPSAddin: Bool {
        get {
            // Defaults to true if the key has never been set
            if UserDefaults.standard.object(forKey: enableWPSAddinKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enableWPSAddinKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enableWPSAddinKey) }
    }
}
