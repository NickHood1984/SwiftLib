import Foundation
import OSLog
import CryptoKit
import SwiftLibCore

private let log = Logger(subsystem: "SwiftLib", category: "OCRTranslationCache")

/// 双语翻译结果磁盘缓存，键 = SHA-256(原文 markdown ‖ 目标语言)。
/// 与 OCR 结果缓存目录同级，避免又新增一棵目录树。
enum OCRTranslationCache {
    private static var cacheDirectory: URL {
        let dir = AppDatabase.pdfStorageURL
            .deletingLastPathComponent()
            .appendingPathComponent("OCRTranslationCache_v1", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cacheKey(sourceMarkdown: String, targetLanguage: String) -> String {
        let payload = "\(targetLanguage)\u{1F}\(sourceMarkdown)".data(using: .utf8) ?? Data()
        return SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func load(sourceMarkdown: String, targetLanguage: String) -> String? {
        let key = cacheKey(sourceMarkdown: sourceMarkdown, targetLanguage: targetLanguage)
        let url = cacheDirectory.appendingPathComponent("\(key).md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func save(sourceMarkdown: String, targetLanguage: String, translatedMarkdown: String) {
        let key = cacheKey(sourceMarkdown: sourceMarkdown, targetLanguage: targetLanguage)
        let url = cacheDirectory.appendingPathComponent("\(key).md")
        do {
            try translatedMarkdown.write(to: url, atomically: true, encoding: .utf8)
            log.info("Translation cached: \(key.prefix(12))… [\(targetLanguage)]")
        } catch {
            log.error("Failed to cache translation: \(error.localizedDescription)")
        }
    }
}
