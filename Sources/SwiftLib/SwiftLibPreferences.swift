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
