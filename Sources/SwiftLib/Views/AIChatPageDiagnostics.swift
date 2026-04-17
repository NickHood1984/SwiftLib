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
    let hasAuthSignals = snapshot.authHintVisible
        || snapshot.hasPasswordField
        || aiChatContainsAnyKeyword(aiChatAuthKeywords, in: combinedText)

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
        return AIChatPageDiagnostic(
            issue: hasAuthSignals ? .authRequired : .inputUnavailable,
            message: hasAuthSignals
                ? "\(serviceName) 当前页面看起来还没有登录，请先在 AI 窗口完成登录后再试。"
                : "\(serviceName) 的输入框当前不可用，请确认页面已经准备好。"
        )
    }

    if stage == .waitingForResponseStart {
        if requiresClickableSendButton
            && (!snapshot.hasSendButton || !snapshot.sendButtonVisible || !snapshot.sendButtonEnabled) {
            return AIChatPageDiagnostic(
                issue: .sendUnavailable,
                message: "\(serviceName) 的发送按钮当前不可用，可能页面还没准备好，或者页面没有接管输入。"
            )
        }

        return AIChatPageDiagnostic(
            issue: .responseDidNotStart,
            message: "\(serviceName) 没有开始回复，可能尚未登录、页面仍在加载，或发送没有真正触发。"
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

private let aiChatAuthKeywords = [
    "sign in",
    "signin",
    "log in",
    "login",
    "continue with",
    "password",
    "verify you are human",
    "authentication",
    "登录",
    "扫码登录",
    "验证码",
    "验证",
    "继续使用",
    "账号登录"
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