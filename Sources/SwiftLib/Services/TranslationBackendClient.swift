import Foundation
import OSLog
import SwiftLibCore

private let translationBackendLog = Logger(subsystem: "SwiftLib", category: "TranslationBackend")

private func translationBackendTrace(_ message: String) {
    guard SwiftLibDebugLogging.metadataVerbose else { return }
    translationBackendLog.notice("\(message, privacy: .public)")
    if let data = "[TranslationBackend] \(message)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

struct TranslationBackendClient {
    private let processManager: TranslationBackendProcessManager

    init(processManager: TranslationBackendProcessManager = .shared) {
        self.processManager = processManager
    }

    func resolve(_ input: TranslationBackendInput) async -> TranslationBackendResult {
        await performResultRequest(
            path: "/resolve",
            body: input,
            context: "resolve inputType=\(input.inputType.rawValue) value=\"\(Self.debugSnippet(input.value))\""
        )
    }

    func resolveSelection(sessionID: String, selectedIDs: [String]) async -> TranslationBackendResult {
        await performResultRequest(
            path: "/resolve-selection",
            body: SelectionRequest(sessionId: sessionID, selectedIds: selectedIDs),
            context: "resolveSelection sessionID=\(sessionID) selectedIDs=\(selectedIDs.joined(separator: ","))"
        )
    }

    func refresh(reference: Reference) async -> TranslationBackendResult {
        await performResultRequest(
            path: "/refresh",
            body: RefreshRequest(reference: reference),
            context: "refresh title=\"\(Self.debugSnippet(reference.title))\" doi=\"\(Self.debugSnippet(reference.doi))\" url=\"\(Self.debugSnippet(reference.url))\""
        )
    }

    func updateTranslators() async -> Result<TranslationBackendMaintenanceResult, NSError> {
        translationBackendTrace("POST /maintenance/update-translators")
        do {
            let connection = try await processManager.currentConnection()
            var request = try buildRequest(
                connection: connection,
                path: "/maintenance/update-translators",
                method: "POST"
            )
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await NetworkClient.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                translationBackendTrace("POST /maintenance/update-translators invalid response")
                return .failure(makeError("本地元数据服务没有返回有效响应。"))
            }

            if http.statusCode == 200 {
                let payload = try JSONDecoder().decode(TranslationBackendMaintenanceResult.self, from: data)
                translationBackendTrace(
                    "POST /maintenance/update-translators -> 200 ok=\(payload.ok) runtimeMode=\(payload.runtimeMode?.rawValue ?? "nil") message=\"\(Self.debugSnippet(payload.message))\""
                )
                await processManager.invalidateConnection()
                return .success(payload)
            }

            let payload = try? JSONDecoder().decode(MessageResponse.self, from: data)
            translationBackendTrace(
                "POST /maintenance/update-translators -> \(http.statusCode) message=\"\(Self.debugSnippet(payload?.message))\""
            )
            return .failure(makeError(payload?.message ?? "更新 translators 失败（HTTP \(http.statusCode)）。"))
        } catch {
            translationBackendTrace(
                "POST /maintenance/update-translators failed error=\"\(Self.debugSnippet(error.localizedDescription))\""
            )
            return .failure(makeError("本地元数据服务未启动：\(error.localizedDescription)"))
        }
    }

    /// 中文文献诊断搜索：通过 Translation Backend 的 /search-cn 接口
    /// 内部依次尝试：百度学术（标题+作者）→ 百度学术（仅标题）→ 知网 Export API
    func searchCN(
        title: String,
        author: String? = nil,
        year: String? = nil,
        fileName: String? = nil,
        cookieHeader: String? = nil
    ) async -> TranslationBackendResult {
        let body = SearchCNRequest(
            title: title,
            author: author,
            year: year,
            fileName: fileName,
            cookieHeader: cookieHeader,
            debug: true
        )
        return await performResultRequest(
            path: "/search-cn",
            body: body,
            context: "searchCN title=\"\(Self.debugSnippet(title))\" author=\"\(Self.debugSnippet(author))\" year=\(year ?? "nil") fileName=\"\(Self.debugSnippet(fileName))\" hasCookie=\((cookieHeader?.isEmpty == false) ? "true" : "false")"
        )
    }

    func capabilities() async -> TranslationBackendCapabilities? {
        translationBackendTrace("GET /capabilities")
        do {
            let connection = try await processManager.currentConnection()
            let request = try buildRequest(connection: connection, path: "/capabilities", method: "GET")
            let (data, response) = try await NetworkClient.session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode
                translationBackendTrace("GET /capabilities -> \(status.map(String.init) ?? "invalid response")")
                return nil
            }
            let capabilities = try JSONDecoder().decode(TranslationBackendCapabilities.self, from: data)
            translationBackendTrace(
                "GET /capabilities -> 200 runtimeMode=\(capabilities.runtimeMode?.rawValue ?? "nil") supportsRefresh=\(capabilities.supportsRefresh)"
            )
            return capabilities
        } catch {
            translationBackendTrace("GET /capabilities failed error=\"\(Self.debugSnippet(error.localizedDescription))\"")
            return nil
        }
    }

    private func performResultRequest<Body: Encodable>(
        path: String,
        body: Body,
        context: String
    ) async -> TranslationBackendResult {
        translationBackendTrace("POST \(path) \(context)")
        do {
            let connection = try await processManager.currentConnection()
            await processManager.trackRequestStart()
            defer { Task { await processManager.trackRequestEnd() } }
            var request = try buildRequest(connection: connection, path: path, method: "POST")
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await NetworkClient.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                translationBackendTrace("POST \(path) invalid response")
                return .unavailable("本地元数据服务没有返回有效响应。")
            }

            switch http.statusCode {
            case 200:
                let payload = try JSONDecoder().decode(ResolvedResponse.self, from: data)
                logDebugLines(path: path, lines: payload.debug)
                let result = TranslationBackendResult.resolved(payload.item.asReference())
                translationBackendTrace("POST \(path) -> 200 \(result.debugLabel)")
                return result
            case 300:
                let payload = try JSONDecoder().decode(CandidatesResponse.self, from: data)
                logDebugLines(path: path, lines: payload.debug)
                let result = TranslationBackendResult.candidates(payload.candidates.map { $0.metadataCandidate() })
                translationBackendTrace("POST \(path) -> 300 \(result.debugLabel)")
                return result
            case 404:
                let payload = try? JSONDecoder().decode(MessageResponse.self, from: data)
                logDebugLines(path: path, lines: payload?.debug)
                let result = TranslationBackendResult.unresolved(payload?.message ?? "后端未返回可用元数据。")
                translationBackendTrace("POST \(path) -> 404 \(result.debugLabel)")
                return result
            default:
                let payload = (try? JSONDecoder().decode(MessageResponse.self, from: data))
                logDebugLines(path: path, lines: payload?.debug)
                let result = TranslationBackendResult.unavailable(
                    payload?.message ?? "本地元数据服务请求失败（HTTP \(http.statusCode)）。"
                )
                translationBackendTrace("POST \(path) -> \(http.statusCode) \(result.debugLabel)")
                return result
            }
        } catch {
            let result = TranslationBackendResult.unavailable("本地元数据服务未启动：\(error.localizedDescription)")
            translationBackendTrace("POST \(path) failed \(result.debugLabel)")
            return result
        }
    }

    private func buildRequest(
        connection: TranslationBackendConnection,
        path: String,
        method: String
    ) throws -> URLRequest {
        let url = connection.baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        if !connection.token.isEmpty {
            request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func debugSnippet(_ value: String?, limit: Int = 120) -> String {
        let normalized = (value ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "(empty)" }
        if normalized.count <= limit {
            return normalized
        }
        let endIndex = normalized.index(normalized.startIndex, offsetBy: limit)
        return "\(normalized[..<endIndex])..."
    }

    private func logDebugLines(path: String, lines: [String]?) {
        guard let lines, !lines.isEmpty else { return }
        for line in lines {
            translationBackendTrace("POST \(path) debug \(line)")
        }
    }
}

private extension TranslationBackendClient {
    struct SearchCNRequest: Codable {
        var title: String
        var author: String?
        var year: String?
        var fileName: String?
        var cookieHeader: String?
        var debug: Bool?
    }

    struct SelectionRequest: Codable {
        var sessionId: String
        var selectedIds: [String]
    }

    struct RefreshRequest: Codable {
        var reference: Reference
    }

    struct ResolvedResponse: Codable {
        var item: ZoteroAPIItem
        var debug: [String]?
    }

    struct CandidatesResponse: Codable {
        var candidates: [TranslationBackendCandidate]
        var debug: [String]?
    }

    struct MessageResponse: Codable {
        var message: String
        var debug: [String]?
    }

    func makeError(_ message: String) -> NSError {
        NSError(
            domain: "SwiftLib.TranslationBackendClient",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
