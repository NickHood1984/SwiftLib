import Foundation
import OSLog

private let ytDlpTranscriptLog = Logger(subsystem: "SwiftLib", category: "YtDlpTranscript")

protocol YtDlpCommandRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?
    ) async throws -> YtDlpCommandResult
}

protocol YtDlpBinaryDownloading {
    func download(from remoteURL: URL, to localURL: URL) async throws
}

struct YtDlpCommandResult {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

enum YtDlpTranscriptError: Error, LocalizedError {
    case invalidVideoId
    case executableUnavailable(String)
    case commandFailed(String)
    case transcriptFileMissing
    case transcriptParseFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidVideoId:
            return "无效的视频 ID"
        case .executableUnavailable(let detail):
            return "yt-dlp 不可用：\(detail)"
        case .commandFailed(let detail):
            return "yt-dlp 抓取失败：\(detail)"
        case .transcriptFileMissing:
            return "yt-dlp 未产出字幕文件"
        case .transcriptParseFailed(let detail):
            return "yt-dlp 字幕解析失败：\(detail)"
        }
    }
}

actor YtDlpBinaryLocator {
    static let shared = YtDlpBinaryLocator()

    private let fileManager = FileManager.default
    private let latestDownloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    private let managedExecutableName = "yt-dlp_macos"
    private var prepareTask: Task<URL, Error>?
    private var rejectedExecutablePaths = Set<String>()

    func executableURL(
        runner: any YtDlpCommandRunning,
        downloader: any YtDlpBinaryDownloading
    ) async throws -> URL {
        if let existing = await firstUsablePreferredExecutable(runner: runner) {
            return existing
        }

        if let fallback = await firstUsableSystemExecutable(runner: runner) {
            return fallback
        }

        #if DEBUG
        // 在开发模式下，如果本地和系统都没有找到，则允许下载最新版
        if let prepareTask {
            return try await prepareTask.value
        }

        let task = Task { [self] in
            try await downloadManagedExecutable(runner: runner, downloader: downloader)
        }
        prepareTask = task

        do {
            let executableURL = try await task.value
            prepareTask = nil
            return executableURL
        } catch {
            prepareTask = nil
            if let fallback = await firstUsableSystemExecutable(runner: runner) {
                return fallback
            }
            throw YtDlpTranscriptError.executableUnavailable(error.localizedDescription)
        }
        #else
        // 出于安全防范（避免下载并执行未知签名的可执行代码导致沙盒被破坏或审核被拒），正式版禁止运行时热更新第三方二进制。
        // 请确保打包时在 Resources 目录中带上了 yt-dlp_macos。
        throw YtDlpTranscriptError.executableUnavailable("未找到 yt-dlp。如需使用字幕提取功能，请通过 Homebrew 安装：brew install yt-dlp")
        #endif
    }

    private func firstUsablePreferredExecutable(runner: any YtDlpCommandRunning) async -> URL? {
        for candidate in preferredExecutableCandidates() {
            if await isUsable(candidate, runner: runner) {
                return candidate
            }
        }
        return nil
    }

    private func firstUsableSystemExecutable(runner: any YtDlpCommandRunning) async -> URL? {
        for candidate in systemExecutableCandidates() {
            if await isUsable(candidate, runner: runner) {
                return candidate
            }
        }
        return nil
    }

    private func downloadManagedExecutable(
        runner: any YtDlpCommandRunning,
        downloader: any YtDlpBinaryDownloading
    ) async throws -> URL {
        let managedURL = try managedExecutableURL()
        let directoryURL = managedURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let stagingURL = directoryURL.appendingPathComponent("\(managedExecutableName).download")
        try? fileManager.removeItem(at: stagingURL)
        try? fileManager.removeItem(at: managedURL)

        ytDlpTranscriptLog.notice("开始下载最新 yt-dlp macOS 二进制")
        try await downloader.download(from: latestDownloadURL, to: stagingURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagingURL.path)
        try fileManager.moveItem(at: stagingURL, to: managedURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: managedURL.path)

        guard await isUsable(managedURL, runner: runner) else {
            try? fileManager.removeItem(at: managedURL)
            throw YtDlpTranscriptError.executableUnavailable("下载后的 yt-dlp 无法执行")
        }

        ytDlpTranscriptLog.notice("最新 yt-dlp 已准备完成 path=\(managedURL.path, privacy: .public)")
        return managedURL
    }

    private func preferredExecutableCandidates() -> [URL] {
        var out: [URL] = []
        var seen = Set<String>()

        func add(_ url: URL?) {
            guard let url else { return }
            let path = url.path
            guard !path.isEmpty, seen.insert(path).inserted else { return }
            out.append(url)
        }

        if let overridePath = ProcessInfo.processInfo.environment["SWIFTLIB_YTDLP_PATH"], !overridePath.isEmpty {
            add(URL(fileURLWithPath: overridePath))
        }

        add(try? managedExecutableURL())

        return out
    }

    private func systemExecutableCandidates() -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        var directories = pathDirectories
        directories.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ])

        var out: [URL] = []
        var seen = Set<String>()
        for directory in directories where !directory.isEmpty {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("yt-dlp", isDirectory: false)
            let path = url.path
            if seen.insert(path).inserted {
                out.append(url)
            }
        }
        return out
    }

    private func managedExecutableURL() throws -> URL {
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupportURL
            .appendingPathComponent("SwiftLib/Tools", isDirectory: true)
            .appendingPathComponent(managedExecutableName, isDirectory: false)
    }

    private func isUsable(
        _ executableURL: URL,
        runner: any YtDlpCommandRunning
    ) async -> Bool {
        let path = executableURL.path
        guard !rejectedExecutablePaths.contains(path) else { return false }
        guard fileManager.fileExists(atPath: path) else { return false }
        guard fileManager.isExecutableFile(atPath: path) else { return false }

        if let version = await quickProbeVersion(executableURL) {
            rejectedExecutablePaths.remove(path)
            ytDlpTranscriptLog.notice(
                "发现可用 yt-dlp path=\(path, privacy: .public) version=\(version, privacy: .public)"
            )
            return true
        }

        rejectedExecutablePaths.insert(path)
        ytDlpTranscriptLog.notice(
            "yt-dlp 快速探测失败 path=\(path, privacy: .public)"
        )
        return false
    }

    private func quickProbeVersion(_ executableURL: URL) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = ["--version"]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let resumeBox = ResumeOnceBox()

            @Sendable func finish(_ version: String?) {
                if resumeBox.markResumed() {
                    continuation.resume(returning: version)
                }
            }

            process.terminationHandler = { process in
                let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let version = Self.cleanText(from: stdout)
                if process.terminationStatus == 0, !version.isEmpty {
                    finish(version)
                } else {
                    finish(nil)
                }
            }

            do {
                try process.run()
                Task.detached {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard resumeBox.markResumed() else { return }
                    if process.isRunning {
                        process.terminate()
                    }
                    continuation.resume(returning: nil)
                }
            } catch {
                finish(nil)
            }
        }
    }

    private static func cleanText(from data: Data) -> String {
        String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DefaultYtDlpBinaryDownloader: YtDlpBinaryDownloading {
    func download(from remoteURL: URL, to localURL: URL) async throws {
        let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            throw YtDlpTranscriptError.executableUnavailable("下载最新 yt-dlp 失败：HTTP \(httpResponse.statusCode)")
        }

        let fileManager = FileManager.default
        let directoryURL = localURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: localURL)
        try fileManager.moveItem(at: temporaryURL, to: localURL)
    }
}

struct ProcessYtDlpCommandRunner: YtDlpCommandRunning {
    private let commandTimeoutNanoseconds: UInt64

    init(commandTimeout: TimeInterval = 30) {
        let seconds = max(commandTimeout, 1)
        commandTimeoutNanoseconds = UInt64(seconds * 1_000_000_000)
    }

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?
    ) async throws -> YtDlpCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let resumeBox = ResumeOnceBox()

            @Sendable func resume(_ result: Result<YtDlpCommandResult, Error>) {
                if resumeBox.markResumed() {
                    continuation.resume(with: result)
                }
            }

            process.terminationHandler = { process in
                let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                resume(.success(.init(
                    exitCode: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                )))
            }

            do {
                try process.run()
                Task.detached {
                    try? await Task.sleep(nanoseconds: commandTimeoutNanoseconds)
                    guard resumeBox.markResumed() else { return }
                    if process.isRunning {
                        process.terminate()
                    }
                    continuation.resume(throwing: YtDlpTranscriptError.commandFailed("调用超时"))
                }
            } catch {
                resume(.failure(error))
            }
        }
    }
}

private final class ResumeOnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func markResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}

final class YtDlpTranscriptFetcher: YouTubeTranscriptExternalFetcher {
    static let shared = YtDlpTranscriptFetcher()

    private static let supportedSubtitleExtensions: Set<String> = [
        "json3", "srv1", "srv2", "srv3", "xml", "ttml", "vtt", "srt"
    ]

    enum SubtitleSource: Equatable {
        case manual
        case automatic
    }

    struct SubtitleSelection {
        let languageCode: String
        let source: SubtitleSource
    }

    private let locator: YtDlpBinaryLocator
    private let runner: any YtDlpCommandRunning
    private let downloader: any YtDlpBinaryDownloading
    private let fileManager: FileManager

    init(
        locator: YtDlpBinaryLocator = .shared,
        runner: any YtDlpCommandRunning = ProcessYtDlpCommandRunner(),
        downloader: any YtDlpBinaryDownloading = DefaultYtDlpBinaryDownloader(),
        fileManager: FileManager = .default
    ) {
        self.locator = locator
        self.runner = runner
        self.downloader = downloader
        self.fileManager = fileManager
    }

    func fetchPlainText(videoId: String) async throws -> String {
        let trimmed = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw YtDlpTranscriptError.invalidVideoId
        }

        let executableURL = try await locator.executableURL(runner: runner, downloader: downloader)
        let workingDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("SwiftLib-yt-dlp-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workingDirectoryURL) }

        let watchURL = "https://www.youtube.com/watch?v=\(trimmed)"
        let selection = try await fetchSubtitleSelection(
            executableURL: executableURL,
            watchURL: watchURL,
            workingDirectoryURL: workingDirectoryURL
        )

        var arguments = [
            "--ignore-config",
            "--skip-download",
            "--sub-langs", selection.languageCode,
            "--sub-format", "json3/srv3/vtt/best",
            "--extractor-args", "youtube:player_client=default,-web;skip=translated_subs",
            "--output", "%(id)s",
            "--paths", workingDirectoryURL.path,
            "--no-warnings",
            "--no-progress",
            "--no-playlist",
            watchURL
        ]
        switch selection.source {
        case .manual:
            arguments.insert("--write-subs", at: 2)
        case .automatic:
            arguments.insert("--write-auto-subs", at: 2)
        }

        ytDlpTranscriptLog.notice(
            "调用 yt-dlp 抓取字幕 vid=\(trimmed, privacy: .public) lang=\(selection.languageCode, privacy: .public) source=\(String(describing: selection.source), privacy: .public)"
        )
        let commandResult = try await runner.run(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: workingDirectoryURL
        )

        let subtitleFiles = try Self.subtitleFiles(in: workingDirectoryURL, fileManager: fileManager)
        if let subtitleFile = Self.selectSubtitleFile(from: subtitleFiles) {
            let transcript = try Self.parseTranscriptFile(at: subtitleFile)
            if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ytDlpTranscriptLog.notice(
                    "yt-dlp 字幕抓取成功 vid=\(trimmed, privacy: .public) file=\(subtitleFile.lastPathComponent, privacy: .public) length=\(transcript.count, privacy: .public)"
                )
                return transcript
            }
        }

        let stderr = Self.cleanText(from: commandResult.stderr)
        let stdout = Self.cleanText(from: commandResult.stdout)
        if commandResult.exitCode != 0 {
            let detail = stderr.isEmpty ? (stdout.isEmpty ? "退出码 \(commandResult.exitCode)" : stdout) : stderr
            throw YtDlpTranscriptError.commandFailed(detail)
        }
        throw YtDlpTranscriptError.transcriptFileMissing
    }

    private func fetchSubtitleSelection(
        executableURL: URL,
        watchURL: String,
        workingDirectoryURL: URL
    ) async throws -> SubtitleSelection {
        let metadataArguments = [
            "--ignore-config",
            "--skip-download",
            "--dump-single-json",
            "--extractor-args", "youtube:player_client=default,-web;skip=translated_subs",
            "--no-warnings",
            "--no-progress",
            "--no-playlist",
            watchURL
        ]

        let result = try await runner.run(
            executableURL: executableURL,
            arguments: metadataArguments,
            currentDirectoryURL: workingDirectoryURL
        )

        let stderr = Self.cleanText(from: result.stderr)
        if result.exitCode != 0 {
            let stdout = Self.cleanText(from: result.stdout)
            let detail = stderr.isEmpty ? (stdout.isEmpty ? "退出码 \(result.exitCode)" : stdout) : stderr
            throw YtDlpTranscriptError.commandFailed(detail)
        }

        guard let root = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] else {
            throw YtDlpTranscriptError.transcriptParseFailed("字幕元数据 JSON 解析失败")
        }

        guard let selection = Self.selectSubtitleSelection(
            subtitles: root["subtitles"] as? [String: Any],
            automaticCaptions: root["automatic_captions"] as? [String: Any]
        ) else {
            throw YtDlpTranscriptError.commandFailed("yt-dlp 未发现可用字幕语言")
        }

        return selection
    }

    static func selectSubtitleSelection(
        subtitles: [String: Any]?,
        automaticCaptions: [String: Any]?
    ) -> SubtitleSelection? {
        var candidates: [SubtitleSelection] = []

        if let subtitles {
            candidates.append(contentsOf: subtitles.keys.map {
                SubtitleSelection(languageCode: $0, source: .manual)
            })
        }
        if let automaticCaptions {
            candidates.append(contentsOf: automaticCaptions.keys.map {
                SubtitleSelection(languageCode: $0, source: .automatic)
            })
        }

        let availableCodes = Set(candidates.map {
            $0.languageCode
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
        })

        candidates = candidates.filter { candidate in
            !isProbablyTranslatedLanguageCode(candidate.languageCode, availableCodes: availableCodes)
        }

        return candidates.sorted { lhs, rhs in
            let lhsLanguageRank = languageRank(lhs.languageCode)
            let rhsLanguageRank = languageRank(rhs.languageCode)
            if lhsLanguageRank != rhsLanguageRank {
                return lhsLanguageRank < rhsLanguageRank
            }

            let lhsSourceRank = sourceRank(lhs.source)
            let rhsSourceRank = sourceRank(rhs.source)
            if lhsSourceRank != rhsSourceRank {
                return lhsSourceRank < rhsSourceRank
            }

            return lhs.languageCode < rhs.languageCode
        }.first
    }

    static func selectSubtitleFile(from files: [URL]) -> URL? {
        files.sorted { lhs, rhs in
            let lhsLanguageRank = languageRank(languageCode(from: lhs))
            let rhsLanguageRank = languageRank(languageCode(from: rhs))
            if lhsLanguageRank != rhsLanguageRank {
                return lhsLanguageRank < rhsLanguageRank
            }

            let lhsExtensionRank = extensionRank(lhs.pathExtension)
            let rhsExtensionRank = extensionRank(rhs.pathExtension)
            if lhsExtensionRank != rhsExtensionRank {
                return lhsExtensionRank < rhsExtensionRank
            }

            return lhs.lastPathComponent < rhs.lastPathComponent
        }.first
    }

    private static func subtitleFiles(in directoryURL: URL, fileManager: FileManager) throws -> [URL] {
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                return false
            }
            return supportedSubtitleExtensions.contains(url.pathExtension.lowercased())
        }
    }

    private static func parseTranscriptFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let ext = url.pathExtension.lowercased()

        let transcript: String?
        switch ext {
        case "json3":
            transcript = YouTubeTranscriptFetcher.parseYouTubeCaptionJSON3(text)
        case "srv1", "srv2", "srv3", "xml", "ttml":
            transcript = YouTubeTranscriptFetcher.parseTimedTextXMLToPlain(text)
        case "vtt":
            transcript = parseWebVTTToPlain(text)
        case "srt":
            transcript = parseSRTToPlain(text)
        default:
            transcript = nil
        }

        let trimmed = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw YtDlpTranscriptError.transcriptParseFailed(url.lastPathComponent)
        }
        return trimmed
    }

    private static func parseWebVTTToPlain(_ text: String) -> String? {
        parseTimestampedBlocks(
            text,
            timestampSeparator: "-->",
            textLineFilter: { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                if trimmed == "WEBVTT" || trimmed.hasPrefix("NOTE") {
                    return nil
                }
                return decodeEntities(stripTags(from: trimmed))
            }
        )
    }

    private static func parseSRTToPlain(_ text: String) -> String? {
        parseTimestampedBlocks(
            text,
            timestampSeparator: "-->",
            textLineFilter: { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                if Int(trimmed) != nil {
                    return nil
                }
                return decodeEntities(stripTags(from: trimmed))
            }
        )
    }

    private static func parseTimestampedBlocks(
        _ text: String,
        timestampSeparator: String,
        textLineFilter: (String) -> String?
    ) -> String? {
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var index = 0

        while index < lines.count {
            let currentLine = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard currentLine.contains(timestampSeparator) else {
                index += 1
                continue
            }

            let startRaw = currentLine.components(separatedBy: timestampSeparator).first ?? ""
            let timestamp = formatTimestampLabel(startRaw)
            index += 1

            var textLines: [String] = []
            while index < lines.count {
                let line = lines[index]
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    break
                }
                if let filtered = textLineFilter(line), !filtered.isEmpty {
                    textLines.append(filtered)
                }
                index += 1
            }

            let body = textLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                output.append("[\(timestamp)] \(body)")
            }

            index += 1
        }

        guard !output.isEmpty else { return nil }
        return output.joined(separator: "\n")
    }

    private static func formatTimestampLabel(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: ":")
        guard !parts.isEmpty else { return "00:00" }

        let hours: Int
        let minutes: Int
        let seconds: Int

        if parts.count == 3 {
            hours = Int(parts[0]) ?? 0
            minutes = Int(parts[1]) ?? 0
            seconds = Int(Double(parts[2]) ?? 0)
        } else if parts.count == 2 {
            hours = 0
            minutes = Int(parts[0]) ?? 0
            seconds = Int(Double(parts[1]) ?? 0)
        } else {
            hours = 0
            minutes = 0
            seconds = Int(Double(parts[0]) ?? 0)
        }

        let totalSeconds = (hours * 3600) + (minutes * 60) + seconds
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private static func stripTags(from text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private static func decodeEntities(_ text: String) -> String {
        var value = text
        let replacements = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " "
        ]
        for (from, to) in replacements {
            value = value.replacingOccurrences(of: from, with: to)
        }
        return value
    }

    private static func extensionRank(_ ext: String) -> Int {
        switch ext.lowercased() {
        case "json3": return 0
        case "srv3", "srv2", "srv1", "xml", "ttml": return 1
        case "vtt": return 2
        case "srt": return 3
        default: return 9
        }
    }

    private static func languageCode(from fileURL: URL) -> String {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: ".")
        guard parts.count >= 2 else { return "" }
        return String(parts.last ?? "")
    }

    private static func languageRank(_ languageCode: String) -> Int {
        let normalized = languageCode
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        if normalized == "zh-hans" || normalized.hasPrefix("zh-hans-") || normalized == "zh-cn" {
            return 0
        }
        if normalized.hasPrefix("zh") {
            return 1
        }
        if normalized.hasPrefix("en") {
            return 2
        }
        return normalized.isEmpty ? 9 : 3
    }

    private static func sourceRank(_ source: SubtitleSource) -> Int {
        switch source {
        case .manual:
            return 0
        case .automatic:
            return 1
        }
    }

    private static func isProbablyTranslatedLanguageCode(
        _ languageCode: String,
        availableCodes: Set<String>
    ) -> Bool {
        let normalized = languageCode
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        let parts = normalized.split(separator: "-").map(String.init)
        guard parts.count >= 3 else { return false }
        if parts.last == "orig" {
            return true
        }

        for suffixLength in 1 ..< parts.count {
            let suffix = parts.suffix(suffixLength).joined(separator: "-")
            if availableCodes.contains(suffix) {
                return true
            }
        }
        return false
    }

    private static func cleanText(from data: Data) -> String {
        String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
