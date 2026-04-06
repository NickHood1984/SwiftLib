import Foundation

enum SwiftLibPreferences {
    /// 剪藏 YouTube 网页时，是否在后台拉取字幕并追加到 `notes`（默认关闭，避免额外请求与隐私顾虑）。
    static let appendYouTubeTranscriptOnClipKey = "SwiftLib.appendYouTubeTranscriptOnClip"

    static var appendYouTubeTranscriptOnClip: Bool {
        get { UserDefaults.standard.bool(forKey: appendYouTubeTranscriptOnClipKey) }
        set { UserDefaults.standard.set(newValue, forKey: appendYouTubeTranscriptOnClipKey) }
    }

    /// 用于 CrossRef / OpenAlex API polite pool 的联系邮箱。
    /// CrossRef 要求提供真实 mailto 才能进入 polite pool（更快速率限制）。
    static let apiContactEmailKey = "SwiftLib.apiContactEmail"

    static var apiContactEmail: String {
        get { UserDefaults.standard.string(forKey: apiContactEmailKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: apiContactEmailKey) }
    }
}
