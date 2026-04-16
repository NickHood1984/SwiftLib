import Foundation
import OSLog
import CryptoKit
import SwiftLibCore

private let log = Logger(subsystem: "SwiftLib", category: "PaddleOCR")

enum PaddleOCRError: LocalizedError {
    case tokenNotConfigured
    case fileNotFound(URL)
    case jobCreationFailed(Int, String)
    case jobFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .tokenNotConfigured:
            return "请先在设置中配置 PaddleOCR Token"
        case .fileNotFound(let url):
            return "文件不存在：\(url.path)"
        case .jobCreationFailed(let code, let body):
            return "创建识别任务失败（\(code)）：\(body)"
        case .jobFailed(let msg):
            return "识别任务失败：\(msg)"
        case .invalidResponse:
            return "识别服务返回了无效的响应"
        }
    }
}

actor PaddleOCRClient {
    static let shared = PaddleOCRClient()

    private let jobURL = "https://paddleocr.aistudio-app.com/api/v2/ocr/jobs"
    private let model = "PaddleOCR-VL-1.5"

    /// Recognize a local PDF file and return the combined Markdown text.
    /// Results are cached on disk keyed by the file's SHA-256 hash.
    func recognize(fileURL: URL) async throws -> String {
        let token = SwiftLibPreferences.paddleOCRToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw PaddleOCRError.tokenNotConfigured
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PaddleOCRError.fileNotFound(fileURL)
        }

        let fileData = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: fileData)
            .map { String(format: "%02x", $0) }.joined()

        // Check cache
        if let cached = loadCache(hash: hash) {
            log.info("OCR cache hit for \(fileURL.lastPathComponent)")
            return cached
        }

        log.info("Submitting OCR job for \(fileURL.lastPathComponent)")

        let jobId = try await createJob(fileURL: fileURL, token: token)
        let jsonlURL = try await pollUntilDone(jobId: jobId, token: token)
        let markdown = try await fetchMarkdown(jsonlURL: jsonlURL)

        saveCache(hash: hash, markdown: markdown)

        return markdown
    }

    // MARK: - Cache

    private static var cacheDirectory: URL {
        let dir = AppDatabase.pdfStorageURL
            .deletingLastPathComponent()
            .appendingPathComponent("OCRCache_v2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private nonisolated func loadCache(hash: String) -> String? {
        let url = Self.cacheDirectory.appendingPathComponent("\(hash).md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private nonisolated func saveCache(hash: String, markdown: String) {
        let url = Self.cacheDirectory.appendingPathComponent("\(hash).md")
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
        log.info("OCR result cached: \(hash.prefix(12))…")
    }

    // MARK: - Private

    private func createJob(fileURL: URL, token: String) async throws -> String {
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: jobURL)!)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let optionalPayload: [String: Any] = [
            "useDocOrientationClassify": false,
            "useDocUnwarping": false,
            "useChartRecognition": true,
        ]
        let optionalJSON = try JSONSerialization.data(withJSONObject: optionalPayload)

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("model", model)
        appendField("optionalPayload", String(data: optionalJSON, encoding: .utf8)!)

        let fileData = try Data(contentsOf: fileURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PaddleOCRError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw PaddleOCRError.jobCreationFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let jobId = dataObj["jobId"] as? String else {
            throw PaddleOCRError.invalidResponse
        }

        log.info("OCR job created: \(jobId)")
        return jobId
    }

    private func pollUntilDone(jobId: String, token: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(jobURL)/\(jobId)")!)
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")

        while true {
            let (data, response) = try await NetworkClient.session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let state = dataObj["state"] as? String else {
                throw PaddleOCRError.invalidResponse
            }

            switch state {
            case "pending", "running":
                if let progress = dataObj["extractProgress"] as? [String: Any],
                   let total = progress["totalPages"] as? Int,
                   let extracted = progress["extractedPages"] as? Int {
                    log.info("OCR progress: \(extracted)/\(total)")
                }
                try await Task.sleep(nanoseconds: 3_000_000_000)
            case "done":
                guard let resultURL = dataObj["resultUrl"] as? [String: Any],
                      let jsonURL = resultURL["jsonUrl"] as? String else {
                    throw PaddleOCRError.invalidResponse
                }
                log.info("OCR job done: \(jobId)")
                return jsonURL
            case "failed":
                let errorMsg = dataObj["errorMsg"] as? String ?? "未知错误"
                throw PaddleOCRError.jobFailed(errorMsg)
            default:
                throw PaddleOCRError.invalidResponse
            }
        }
    }

    private func fetchMarkdown(jsonlURL: String) async throws -> String {
        let (data, _) = try await NetworkClient.session.data(from: URL(string: jsonlURL)!)
        let text = String(data: data, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)

        var pageParts: [String] = []
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let lineJSON = try JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let result = lineJSON["result"] as? [String: Any],
                  let layouts = result["layoutParsingResults"] as? [[String: Any]] else {
                continue
            }
            for layout in layouts {
                let md = layout["markdown"] as? [String: Any]
                let imageMap = md?["images"] as? [String: String] ?? [:]
                var imageKeys = Array(imageMap.keys)

                guard let pruned = layout["prunedResult"] as? [String: Any],
                      let blocks = pruned["parsing_res_list"] as? [[String: Any]] else {
                    // Fallback: use markdown.text if parsing_res_list unavailable
                    if let fallbackText = md?["text"] as? String {
                        pageParts.append(fallbackText)
                    }
                    continue
                }

                var blockParts: [String] = []
                for block in blocks {
                    let label = block["block_label"] as? String ?? ""
                    let content = (block["block_content"] as? String ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if content.isEmpty && label != "image" { continue }

                    switch label {
                    case "doc_title":
                        blockParts.append("# \(content)")
                    case "paragraph_title":
                        blockParts.append("## \(content)")
                    case "abstract":
                        let quoted = content.components(separatedBy: "\n")
                            .map { "> \($0)" }.joined(separator: "\n")
                        blockParts.append(quoted)
                    case "text", "reference", "reference_content", "aside_text", "vertical_text":
                        blockParts.append(content)
                    case "chart", "table":
                        blockParts.append(Self.formatTableContent(content))
                    case "figure_title":
                        blockParts.append("*\(content)*")
                    case "display_formula":
                        blockParts.append("$$\n\(content)\n$$")
                    case "inline_formula":
                        blockParts.append("$\(content)$")
                    case "image":
                        if let key = imageKeys.first {
                            imageKeys.removeFirst()
                            let b64 = imageMap[key] ?? ""
                            blockParts.append("![Image](data:image/jpeg;base64,\(b64))")
                        }
                    case "header", "footer", "number", "footnote", "header_image", "footer_image":
                        break // skip
                    default:
                        if !content.isEmpty { blockParts.append(content) }
                    }
                }
                if !blockParts.isEmpty {
                    pageParts.append(blockParts.joined(separator: "\n\n"))
                }
            }
        }

        return pageParts.joined(separator: "\n\n---\n\n")
    }

    /// Format table content from OCR. Handles both raw HTML tables and pipe-separated text.
    private static func formatTableContent(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // If the OCR engine returned an HTML table, pass it through directly.
        if trimmed.range(of: #"<\s*table[\s>]"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return trimmed
        }
        // Otherwise convert pipe-separated text to a Markdown table.
        return pipeTextToMarkdownTable(trimmed)
    }

    private static func pipeTextToMarkdownTable(_ text: String) -> String {
        let rows = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let header = rows.first else { return text }

        let cols = header.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        var lines: [String] = []
        lines.append("| " + cols.joined(separator: " | ") + " |")
        lines.append("| " + cols.map { _ in "---" }.joined(separator: " | ") + " |")
        for row in rows.dropFirst() {
            let cells = row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }
}
