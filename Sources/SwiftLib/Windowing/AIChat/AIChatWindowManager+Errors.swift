import Foundation

extension AIChatWindowManager {
    func error(for diagnostic: AIChatPageDiagnostic, fallbackSelector: String) -> AIChatError {
        switch diagnostic.issue {
        case .authRequired:
            return .authRequired(diagnostic.message)
        case .pageStillLoading:
            return .pageStillLoading(diagnostic.message)
        case .inputUnavailable:
            return .inputUnavailable(diagnostic.message)
        case .sendUnavailable:
            return .sendUnavailable(diagnostic.message)
        case .responseDidNotStart:
            return .responseDidNotStart(diagnostic.message)
        }
    }

    func normalizeError(_ error: Error) -> AIChatError {
        if let aiError = error as? AIChatError {
            return aiError
        }

        return AIChatError.pageInteractionFailed(error.localizedDescription)
    }

    // MARK: - Errors

    enum AIChatError: LocalizedError {
        case noWebView
        case unknownService(String)
        case inputNotFound(String)
        case inputUnavailable(String)
        case authRequired(String)
        case pageStillLoading(String)
        case pageLoadFailed(String)
        case sendUnavailable(String)
        case responseDidNotStart(String)
        case emptyResponse
        case timeout
        case javaScriptTimedOut
        case pageInteractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .noWebView: return "AI 聊天窗口未就绪"
            case .unknownService(let url): return "未识别的 AI 服务：\(url)\n请更新 DOM 选择器配置"
            case .inputNotFound(let sel): return "找不到聊天输入框（\(sel)）。当前页可能尚未登录或仍在加载，请先确认 AI 页面已准备好。"
            case .inputUnavailable(let message): return message
            case .authRequired(let message): return message
            case .pageStillLoading(let message): return message
            case .pageLoadFailed(let detail): return "AI 页面加载失败：\(detail)"
            case .sendUnavailable(let message): return message
            case .responseDidNotStart(let message): return message
            case .emptyResponse: return "AI 返回了空回复"
            case .timeout: return "等待 AI 回复超时，请稍后再试。"
            case .javaScriptTimedOut: return "AI 页面脚本执行超时，页面可能仍在加载或卡住了。"
            case .pageInteractionFailed(let message): return "AI 页面交互失败：\(message)"
            }
        }
    }
}
