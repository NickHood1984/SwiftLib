import Foundation
import SwiftLibCore
import WebKit

@MainActor
final class CNKIMetadataProvider: NSObject, ObservableObject {
    enum CNKIError: LocalizedError {
        case webViewNotReady
        case busy
        case timedOut
        case navigationFailed(String)
        case blockedByVerification
        case verificationCancelled
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .webViewNotReady:
                return "知网抓取组件尚未就绪，请稍后再试。"
            case .busy:
                return "已有进行中的知网抓取任务。"
            case .timedOut:
                return "知网页面加载超时。"
            case .navigationFailed(let message):
                return "无法打开知网页面：\(message)"
            case .blockedByVerification:
                return "知网页面进入安全验证或登录拦截，暂时无法自动抓取。"
            case .verificationCancelled:
                return "已取消知网验证。"
            case .parseFailed(let message):
                return "知网页面解析失败：\(message)"
            }
        }
    }

    struct VerificationSession: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let title: String
        let message: String
        let continueLabel: String
    }

    @Published var isWorking = false
    @Published var verificationSession: VerificationSession?
    /// Set to `true` before any operation so the hosting view can lazily create the hidden WKWebView.
    @Published var needsWebView = false

    static let sharedDataStore = WKWebsiteDataStore.default()
    static let mainlandCNKIHomeURL = URL(string: "https://kns.cnki.net/kns8s/defaultresult/index")!
    static let mainlandCNKISearchURL = URL(string: "https://kns.cnki.net/kns8s/brief/grid")!

    enum PendingOperation {
        case search(MetadataResolutionSeed)
        case resolve(MetadataCandidate)
    }

    enum OperationOutput {
        case search([MetadataCandidate])
        case resolve(AuthoritativeMetadataRecord)
    }

    enum HiddenSearchBootstrapResult {
        case candidates([MetadataCandidate])
        case noResult
        case blockedByVerification
    }

    struct SearchPayload: Decodable {
        struct Candidate: Decodable {
            let title: String
            let detailURL: String
            let metaText: String
            let snippet: String?
            let exportID: String?
            let dbname: String?
            let filename: String?
        }

        let blocked: Bool
        let emptyState: Bool
        let candidates: [Candidate]
    }

    struct DetailPayload: Decodable {
        let blocked: Bool
        let blockedReason: String?
        let title: String?
        let authors: [String]
        let authorSource: String?
        let journal: String?
        let doi: String?
        let abstract: String?
        let volume: String?
        let issue: String?
        let firstPage: String?
        let lastPage: String?
        let yearText: String?
        let bodyText: String?
        let url: String?
    }

    struct PageAssessmentPayload: Decodable {
        let markerBlocked: Bool
        let searchRowCount: Int
        let hasSearchEmptyState: Bool
        let hasDetailTitle: Bool
        let hasDetailAuthors: Bool
        let hasDetailSummary: Bool
        let hasVisibleDetailScaffold: Bool?
        let blockedReason: String?

        init(
            markerBlocked: Bool,
            searchRowCount: Int,
            hasSearchEmptyState: Bool = false,
            hasDetailTitle: Bool,
            hasDetailAuthors: Bool,
            hasDetailSummary: Bool,
            hasVisibleDetailScaffold: Bool? = nil,
            blockedReason: String? = nil
        ) {
            self.markerBlocked = markerBlocked
            self.searchRowCount = searchRowCount
            self.hasSearchEmptyState = hasSearchEmptyState
            self.hasDetailTitle = hasDetailTitle
            self.hasDetailAuthors = hasDetailAuthors
            self.hasDetailSummary = hasDetailSummary
            self.hasVisibleDetailScaffold = hasVisibleDetailScaffold
            self.blockedReason = blockedReason
        }
    }

    enum PageResolutionState: Equatable {
        case resolvedSearch
        case resolvedDetail
        case blocked
        case loadingOrUnknown

        var isReady: Bool {
            switch self {
            case .resolvedSearch, .resolvedDetail:
                return true
            case .blocked, .loadingOrUnknown:
                return false
            }
        }
    }

    weak var webView: WKWebView?
    let parserPool = CNKIParserWebViewPool()
    var pendingOperation: PendingOperation?
    var pendingContinuation: CheckedContinuation<OperationOutput, Error>?
    var verificationContinuation: CheckedContinuation<Void, Error>?
    var timeoutTask: Task<Void, Never>?
    var inspectionTask: Task<Void, Never>?
    var lastNavigationStatusCode: Int?
    var verificationOperation: PendingOperation?
    var verificationPreparedOutput: OperationOutput?

    func configureWebView(_ configuration: WKWebViewConfiguration) {
        configuration.websiteDataStore = Self.sharedDataStore
    }

    func registerWebView(_ webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self
    }

    func continueVerification() {
        let continuation = verificationContinuation
        verificationContinuation = nil
        verificationSession = nil
        continuation?.resume()
    }

    func cancelVerification() {
        let continuation = verificationContinuation
        verificationContinuation = nil
        verificationSession = nil
        verificationOperation = nil
        verificationPreparedOutput = nil
        continuation?.resume(throwing: CNKIError.verificationCancelled)
    }

    func prepareVerificationResultIfPossible(from webView: WKWebView) async -> Bool {
        guard verificationPreparedOutput == nil, let operation = verificationOperation else {
            return verificationPreparedOutput != nil
        }

        do {
            switch operation {
            case .search(let seed):
                do {
                    let candidates = try await extractSearchCandidates(seed: seed, in: webView)
                    if !candidates.isEmpty {
                        verificationPreparedOutput = .search(candidates)
                    } else if await pageResolutionState(in: webView) == .resolvedSearch {
                        verificationPreparedOutput = .search([])
                    }
                } catch {
                    if await pageResolutionState(in: webView) == .resolvedSearch {
                        verificationPreparedOutput = .search([])
                    } else {
                        throw error
                    }
                }
            case .resolve(let candidate):
                let record = try await extractReference(candidate: candidate, in: webView)
                verificationPreparedOutput = .resolve(record)
            }
        } catch {
            // Ignore parse failures here and fall back to the normal retry path.
        }
        return verificationPreparedOutput != nil
    }

    func pageResolutionState(in webView: WKWebView) async -> PageResolutionState {
        do {
            let payload: PageAssessmentPayload = try await evaluateJSONScript(Self.pageAssessmentScript, in: webView)
            let state = Self.pageResolutionState(from: payload)
            cnkiDebugTrace(
                "pageState url=\(webView.url?.absoluteString ?? "nil") state=\(String(describing: state)) blocked=\(payload.markerBlocked) reason=\(payload.blockedReason ?? "nil") searchRows=\(payload.searchRowCount) detailTitle=\(payload.hasDetailTitle) detailAuthors=\(payload.hasDetailAuthors) detailSummary=\(payload.hasDetailSummary) scaffold=\(payload.hasVisibleDetailScaffold ?? false)"
            )
            return state
        } catch {
            cnkiDebugTrace(
                "pageState evaluate failed url=\(webView.url?.absoluteString ?? "nil") error=\(error.localizedDescription)"
            )
            return .loadingOrUnknown
        }
    }

    nonisolated static func pageResolutionState(from payload: PageAssessmentPayload) -> PageResolutionState {
        if payload.searchRowCount > 0 || payload.hasSearchEmptyState {
            return .resolvedSearch
        }
        let hasVisibleDetailScaffold = payload.hasVisibleDetailScaffold
            ?? (payload.hasDetailTitle && (payload.hasDetailAuthors || payload.hasDetailSummary))
        if hasVisibleDetailScaffold || payload.hasDetailTitle {
            return .resolvedDetail
        }
        if payload.markerBlocked {
            return .blocked
        }
        return .loadingOrUnknown
    }

    func search(seed: MetadataResolutionSeed) async throws -> [MetadataCandidate] {
        try await searchViaGridRequest(seed: seed)
    }

    func fetchAuthoritativeRecord(candidate: MetadataCandidate) async throws -> AuthoritativeMetadataRecord {
        do {
            let result = try await runOperation(.resolve(candidate))
            guard case .resolve(let record) = result else {
                throw CNKIError.parseFailed("知网详情返回了意外结果。")
            }
            return record
        } catch {
            guard shouldAttemptExportFallback(after: error),
                  let record = try await resolveViaExportFallback(candidate: candidate) else {
                throw error
            }
            return record
        }
    }

    func resolve(candidate: MetadataCandidate) async throws -> Reference {
        try await fetchAuthoritativeRecord(candidate: candidate).reference
    }

    func fetchAuthoritativeRecord(detailURL: URL) async throws -> AuthoritativeMetadataRecord {
        try await fetchAuthoritativeRecord(
            candidate: MetadataCandidate(
                source: .cnki,
                title: detailURL.lastPathComponent,
                detailURL: detailURL.absoluteString,
                score: 1
            )
        )
    }

    func resolve(detailURL: URL) async throws -> Reference {
        try await fetchAuthoritativeRecord(detailURL: detailURL).reference
    }

}
