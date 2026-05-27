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

    // MARK: - AI Abstract Translation

    /// 默认的 AI 摘要翻译目标语言。
    static let abstractTranslationLanguageKey = "SwiftLib.abstractTranslationLanguage"

    static let abstractTranslationLanguageOptions: [(code: String, name: String)] = [
        ("zh", "中文"),
        ("en", "English"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("es", "Español"),
    ]

    static var abstractTranslationLanguage: String {
        get {
            let stored = UserDefaults.standard.string(forKey: abstractTranslationLanguageKey) ?? ""
            let validCodes = Set(abstractTranslationLanguageOptions.map(\.code))
            return validCodes.contains(stored) ? stored : "zh"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: abstractTranslationLanguageKey)
        }
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

    static let ocrDocumentTranslationPromptTemplateKey = "SwiftLib.ocrDocumentTranslationPromptTemplate"
    static let legacyOCRDocumentTranslationPromptTemplates: [String] = [
        """
        你是一名专业的学术翻译助手。请把下面 JSON 数据中的每个 Markdown 段落翻译成 {{target_language}}。

        要求：
        1. 忠实原意，语气自然，保留学术表达。
        2. 如果原文是标题、列表或引用，译文也保持对应结构。
        3. 不要补充解释、注释、总结或前后缀。
        4. 只返回 JSON，不要使用 ``` 代码块。
        5. 返回格式必须严格为：{"translations":[{"id":"block_1","translation":"译文"}]}
        6. 每个 id 都必须原样返回一次；`translation` 字段里只放译文，不要包含原文。

        待翻译数据：
        {{batch_json}}
        """,
        """
        把下面 JSON 里的每个 Markdown 段落翻译成 {{target_language}}。

        只返回：
        {"translations":[{"id":"block_1","translation":"译文"}]}

        要求：
        - 每个 id 原样返回一次
        - `translation` 里只放译文，不要包含原文
        - 保持标题、列表、引用等 Markdown 结构
        - 不要解释，不要代码块

        数据：
        {{batch_json}}
        """,
        """
        把下面 JSON 里的每个 Markdown 段落翻译成 {{target_language}}。

        只返回译文块，不要 JSON，不要代码块，不要解释：
        [[block_1]]
        译文
        [[/block_1]]

        要求：
        - 每个 id 都按同样格式返回一次
        - 标记行必须原样保留
        - 标记中间只放对应译文，不要包含原文
        - 保持标题、列表、引用等 Markdown 结构

        数据：
        {{batch_json}}
        """
    ]

    static let defaultOCRDocumentTranslationPromptTemplate = """
    把下面 JSON 里的每个 Markdown 段落翻译成 {{target_language}}。

    如果数据里只有 1 个 block：只返回译文，不要 JSON，不要标记，不要解释。

    如果数据里有多个 block：只返回下面这种译文块，不要 JSON，不要代码块，不要解释：
    [[block_1]]
    译文
    [[/block_1]]

    要求：
    - 译文里不要包含原文
    - 保持标题、列表、引用等 Markdown 结构
    - 多个 block 时，每个 id 都按上面格式返回一次，标记行必须原样保留

    数据：
    {{batch_json}}
    """

    static var ocrDocumentTranslationPromptTemplate: String {
        get {
            let stored = UserDefaults.standard.string(forKey: ocrDocumentTranslationPromptTemplateKey)
            let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                return defaultOCRDocumentTranslationPromptTemplate
            }

            let normalizedLegacyTemplates = legacyOCRDocumentTranslationPromptTemplates.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if normalizedLegacyTemplates.contains(trimmed) {
                return defaultOCRDocumentTranslationPromptTemplate
            }

            return stored!
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ocrDocumentTranslationPromptTemplateKey)
        }
    }

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

    // MARK: - Site Adapters (站点适配器远程配置)

    static let siteAdaptersRemoteURLKey = "SwiftLib.siteAdaptersRemoteURL"
    static let defaultSiteAdaptersRemoteURL = "https://raw.githubusercontent.com/NickHood1984/SwiftLib/main/Sources/SwiftLib/Resources/site-adapters.json"

    static var siteAdaptersRemoteURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: siteAdaptersRemoteURLKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (stored?.isEmpty == false) ? stored! : defaultSiteAdaptersRemoteURL
        }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: siteAdaptersRemoteURLKey
            )
        }
    }

    static let siteAdaptersLastUpdateKey = "SwiftLib.siteAdaptersLastUpdate"
    static var siteAdaptersLastUpdate: Date {
        get { UserDefaults.standard.object(forKey: siteAdaptersLastUpdateKey) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: siteAdaptersLastUpdateKey) }
    }

    // MARK: - CNKI Selectors (知网选择器远程配置)

    static let cnkiSelectorsRemoteURLKey = "SwiftLib.cnkiSelectorsRemoteURL"
    static let defaultCNKISelectorsRemoteURL = "https://raw.githubusercontent.com/NickHood1984/SwiftLib/main/Sources/SwiftLib/Resources/cnki-selectors.json"

    static var cnkiSelectorsRemoteURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: cnkiSelectorsRemoteURLKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (stored?.isEmpty == false) ? stored! : defaultCNKISelectorsRemoteURL
        }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: cnkiSelectorsRemoteURLKey
            )
        }
    }

    static let cnkiSelectorsLastUpdateKey = "SwiftLib.cnkiSelectorsLastUpdate"
    static var cnkiSelectorsLastUpdate: Date {
        get { UserDefaults.standard.object(forKey: cnkiSelectorsLastUpdateKey) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: cnkiSelectorsLastUpdateKey) }
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

    // MARK: - easyScholar Journal Rank

    static let easyScholarSecretKeyKey = "SwiftLib.easyScholarSecretKey"
    static let easyScholarDisplayRankKey = "SwiftLib.easyScholarDisplayRank"

    static let easyScholarDisplayRankOptions: [(key: String, name: String)] = [
        ("sci", "SCI"),
        ("ssci", "SSCI"),
        ("cssci", "CSSCI"),
        ("pku", "北大核心"),
        ("sciif", "SCI-IF"),
        ("sciif5", "SCI-IF5"),
        ("sciup", "中科院分区"),
        ("scibase", "中科院基础版"),
        ("cscd", "CSCD"),
        ("ccf", "CCF"),
        ("ahci", "A&HCI"),
        ("esi", "ESI"),
    ]

    static var easyScholarSecretKey: String {
        get {
            if let token = KeychainStorage.string(forAccount: easyScholarSecretKeyKey) {
                return token
            }

            let legacyToken = UserDefaults.standard.string(forKey: easyScholarSecretKeyKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !legacyToken.isEmpty else { return "" }

            _ = KeychainStorage.set(legacyToken, forAccount: easyScholarSecretKeyKey)
            UserDefaults.standard.removeObject(forKey: easyScholarSecretKeyKey)
            return legacyToken
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                _ = KeychainStorage.remove(account: easyScholarSecretKeyKey)
            } else {
                _ = KeychainStorage.set(trimmed, forAccount: easyScholarSecretKeyKey)
            }
            UserDefaults.standard.removeObject(forKey: easyScholarSecretKeyKey)
        }
    }

    static var easyScholarDisplayRank: String {
        get {
            let stored = UserDefaults.standard.string(forKey: easyScholarDisplayRankKey) ?? ""
            let validKeys = Set(easyScholarDisplayRankOptions.map(\.key))
            return validKeys.contains(stored) ? stored : "sci"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: easyScholarDisplayRankKey)
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
