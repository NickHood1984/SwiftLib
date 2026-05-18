import Foundation

enum AIChatPageStage: Equatable {
    case waitingForInput
    case waitingForResponseStart
    case waitingForResponseCompletion
}

enum AIChatPageIssue: Equatable {
    case authRequired
    case pageStillLoading
    case inputUnavailable
    case sendUnavailable
    case responseDidNotStart
}

struct AIChatPageDiagnostic: Equatable {
    let issue: AIChatPageIssue
    let message: String
}

struct AIChatPageSnapshot: Decodable, Equatable {
    let href: String
    let title: String
    let readyState: String
    let hasInput: Bool
    let inputVisible: Bool
    let inputEnabled: Bool
    let inputValueLength: Int
    let hasSendButton: Bool
    let sendButtonVisible: Bool
    let sendButtonEnabled: Bool
    let authHintVisible: Bool
    let hasPasswordField: Bool
    let bodyTextSample: String
}

extension AIChatPageSnapshot {
    var hasUsableInput: Bool {
        hasInput && inputVisible && inputEnabled
    }

    var combinedSignalText: String {
        [href, title, bodyTextSample]
            .joined(separator: " ")
            .lowercased()
    }
}

func diagnoseAIChatPage(
    _ snapshot: AIChatPageSnapshot,
    serviceName: String,
    stage: AIChatPageStage,
    requiresClickableSendButton: Bool
) -> AIChatPageDiagnostic? {
    let combinedText = snapshot.combinedSignalText

    // 关键改动：输入框已经可用 ⇒ 用户一定是登录态。
    // 网页 AI 的侧栏/正文里经常出现 "登录"/"验证" 这种词（比如 "退出登录"、"实验验证"、AI 回复里翻译的内容），
    // 不能因为这些词就判定未登录。只有在输入框不可用时才考虑 keyword 兜底信号。
    let hasStrongAuthDOMSignals = snapshot.authHintVisible || snapshot.hasPasswordField
    let hasAuthKeywordSignals = !snapshot.hasUsableInput
        && aiChatContainsAnyKeyword(aiChatAuthKeywords, in: combinedText)
    let hasAuthSignals = hasStrongAuthDOMSignals || hasAuthKeywordSignals

    let hasLoadingSignals = snapshot.readyState == "loading"
        || aiChatContainsAnyKeyword(aiChatLoadingKeywords, in: combinedText)

    if !snapshot.hasUsableInput {
        if hasAuthSignals {
            return AIChatPageDiagnostic(
                issue: .authRequired,
                message: "\(serviceName) 当前页面看起来还没有登录，请先在 AI 窗口完成登录后再试。"
            )
        }

        if hasLoadingSignals {
            return AIChatPageDiagnostic(
                issue: .pageStillLoading,
                message: "\(serviceName) 页面仍在加载或跳转，请等页面稳定后再试。"
            )
        }
    }

    if snapshot.hasInput && !snapshot.inputEnabled {
        // 输入框存在但禁用：只有同时检测到强 DOM 信号（密码框/auth 提示节点）才判定登录问题
        return AIChatPageDiagnostic(
            issue: hasStrongAuthDOMSignals ? .authRequired : .inputUnavailable,
            message: hasStrongAuthDOMSignals
                ? "\(serviceName) 当前页面看起来还没有登录，请先在 AI 窗口完成登录后再试。"
                : "\(serviceName) 的输入框当前不可用，请确认页面已经准备好。"
        )
    }

    if stage == .waitingForResponseStart {
        // 这一阶段输入框已经可用、文本已经注入。如果还报"未登录"，几乎都是误判
        // （比如 AI 部分回复里出现"登录"/"验证"），所以这里只信强 DOM 信号
        if hasStrongAuthDOMSignals {
            return AIChatPageDiagnostic(
                issue: .authRequired,
                message: "\(serviceName) 当前页面看起来还没有登录，请先在 AI 窗口完成登录后再试。"
            )
        }

        if requiresClickableSendButton
            && (!snapshot.hasSendButton || !snapshot.sendButtonVisible || !snapshot.sendButtonEnabled) {
            return AIChatPageDiagnostic(
                issue: .sendUnavailable,
                message: "\(serviceName) 的发送按钮当前不可用，可能页面还没准备好，或者页面没有接管输入。"
            )
        }

        return AIChatPageDiagnostic(
            issue: .responseDidNotStart,
            message: "\(serviceName) 没有开始回复，可能页面仍在加载或发送没有真正触发。"
        )
    }

    if stage == .waitingForResponseCompletion, hasLoadingSignals, !snapshot.hasUsableInput {
        return AIChatPageDiagnostic(
            issue: .pageStillLoading,
            message: "\(serviceName) 页面仍在加载或跳转，请等页面稳定后再试。"
        )
    }

    return nil
}

/// 只保留登录页/未登录态会出现的**具体短语**——不要单独的 "登录" / "验证" / "登入"，
/// 因为这些词在已登录页面的侧栏（"退出登录"）、正文翻译结果（"验证假设"）里常见。
private let aiChatAuthKeywords = [
    "sign in to",
    "sign in with",
    "log in to",
    "log in with",
    "continue with google",
    "continue with apple",
    "verify you are human",
    "you must be logged in",
    "请先登录",
    "需要登录",
    "未登录",
    "去登录",
    "立即登录",
    "请登录",
    "扫码登录",
    "登录后继续",
    "登录后即可",
    "账号登录",
    "请输入密码",
]

private let aiChatLoadingKeywords = [
    "loading",
    "redirecting",
    "just a moment",
    "please wait",
    "加载中",
    "正在加载",
    "跳转中",
    "请稍候"
]

private func aiChatContainsAnyKeyword(_ keywords: [String], in text: String) -> Bool {
    keywords.contains { text.contains($0) }
}
