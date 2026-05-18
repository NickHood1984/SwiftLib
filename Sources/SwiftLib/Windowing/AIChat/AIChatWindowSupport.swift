import Foundation

enum AIChatPageLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

enum AIChatStatusTone {
    case info
    case warning
    case error
}

struct AIChatStatusBanner {
    let message: String
    let systemImage: String
    let tone: AIChatStatusTone
    let showsProgress: Bool
}

struct AIChatPageSnapshotScriptPayload: Encodable {
    let inputSel: String
    let sendSel: String
}

struct AIChatInjectScriptPayload: Encodable {
    let inputSel: String
    let text: String
}

struct AIChatSendScriptPayload: Encodable {
    let inputSel: String
    let sendSel: String
}

struct AIChatResponseTrackerScriptPayload: Encodable {
    let selectors: [String]
}

struct AIChatResponseScriptPayload: Encodable {
    let responseSel: String
    let contentSel: String
    let streamingSel: String
    let beforeCount: Int
    let beforeText: String
}

struct AIChatResponseSnapshot: Decodable, Equatable {
    let status: String
    let text: String
    let responseCount: Int
    let pendingRequests: Int
    let requestsStartedSinceMark: Int
    let responseIdleMs: Int
    let networkIdleMs: Int
}

extension AIChatResponseSnapshot {
    var hasTrackedNetworkCompletion: Bool {
        requestsStartedSinceMark > 0
            && pendingRequests == 0
            && responseIdleMs >= 900
            && networkIdleMs >= 300
    }
}

struct AIChatResponseStabilityTracker {
    private(set) var lastText = ""
    private(set) var stablePollCount = 0

    mutating func ingest(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed == lastText {
            stablePollCount += 1
        } else {
            lastText = trimmed
            stablePollCount = 0
        }
    }

    func hasSettled(for status: String) -> Bool {
        let requiredStablePolls = status == "done" ? 2 : 4
        return !lastText.isEmpty && stablePollCount >= requiredStablePolls
    }
}

extension AIDOMServiceConfig {
    var requiresClickableSendButton: Bool {
        let trimmed = sendSelector.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.caseInsensitiveCompare("Enter") != .orderedSame
    }
}

/// Manages a single, shared AI chat browser window backed by WKWebView.
///
/// Provides DOM-based text injection and response extraction using configurable
