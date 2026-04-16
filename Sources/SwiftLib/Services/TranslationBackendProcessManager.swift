import Foundation
import OSLog

private let pmLog = Logger(subsystem: "SwiftLib", category: "TranslationBackendPM")

private final class HandshakeReadState {
    private let lock = NSLock()
    private var buffer = Data()
    private var resumed = false
    private let newline = Data("\n".utf8)

    func resumeIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }

    func appendAndExtractLine(from chunk: Data) -> (line: Data, remaining: Data)? {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(chunk)
        guard let newlineRange = buffer.range(of: newline) else { return nil }

        let line = Data(buffer[..<newlineRange.lowerBound])
        let remaining = Data(buffer[newlineRange.upperBound...])
        return (line, remaining)
    }
}

actor TranslationBackendProcessManager {
    static let shared = TranslationBackendProcessManager()

    private var connection: TranslationBackendConnection?
    private var process: Process?
    private var activeRequestCount: Int = 0
    private var idleTask: Task<Void, Never>?
    private static let idleTimeout: UInt64 = 5 * 60 * 1_000_000_000 // 5 minutes

    func currentConnection() async throws -> TranslationBackendConnection {
        if let connection {
            return connection
        }
        let conn = try await launchBackend()
        self.connection = conn
        return conn
    }

    func invalidateConnection() {
        connection = nil
    }

    func trackRequestStart() {
        activeRequestCount += 1
        idleTask?.cancel()
        idleTask = nil
    }

    func trackRequestEnd() {
        activeRequestCount = max(0, activeRequestCount - 1)
        if activeRequestCount == 0 {
            scheduleIdleShutdown()
        }
    }

    nonisolated func shutdownSync() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await self.shutdown()
            semaphore.signal()
        }
        semaphore.wait()
    }

    private func shutdown() {
        guard let proc = process, proc.isRunning else {
            terminateProcess()
            return
        }
        proc.terminate()
        proc.waitUntilExit()
        terminateProcess()
    }

    private func terminateProcess() {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        connection = nil
        idleTask?.cancel()
        idleTask = nil
        activeRequestCount = 0
    }

    private func scheduleIdleShutdown() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.idleTimeout)
            } catch {
                return // cancelled
            }
            await self?.performIdleShutdown()
        }
    }

    private func performIdleShutdown() {
        guard activeRequestCount == 0 else { return }
        pmLog.notice("Translation backend idle timeout — shutting down process")
        terminateProcess()
    }

    // MARK: - Launch

    private func launchBackend() async throws -> TranslationBackendConnection {
        // Kill any existing process
        if let proc = process, proc.isRunning {
            proc.terminate()
            process = nil
        }

        let nodeURL = try findNodeExecutable()
        let serverEntry = findServerEntry()

        guard let serverEntry else {
            throw NSError(
                domain: "TranslationBackendProcessManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "找不到 translation backend 的 server.js 文件。"]
            )
        }

        let proc = Process()
        proc.executableURL = nodeURL
        proc.arguments = [serverEntry.path]
        proc.currentDirectoryURL = serverEntry.deletingLastPathComponent()

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["SWIFTLIB_TRANSLATION_RUNTIME_MODE"] = determineLaunchMode(serverEntry: serverEntry)
        env["SWIFTLIB_TRANSLATION_RUNTIME_ROOT"] = serverEntry.deletingLastPathComponent().path
        env["SWIFTLIB_TRANSLATION_SEED_ROOT"] = serverEntry.deletingLastPathComponent().path
        proc.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr

        // Forward stderr to our stderr for debug visibility
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                FileHandle.standardError.write(data)
            }
        }

        try proc.run()
        process = proc

        pmLog.notice("Translation backend process launched (pid=\(proc.processIdentifier))")

        // Read handshake JSON from stdout (first line)
        let handshake = try await readHandshake(from: stdout, process: proc)

        let baseURL = URL(string: "http://127.0.0.1:\(handshake.port)")!
        return TranslationBackendConnection(
            baseURL: baseURL,
            token: handshake.token
        )
    }

    private func readHandshake(from pipe: Pipe, process proc: Process) async throws -> TranslationBackendHandshake {
        try await withCheckedThrowingContinuation { continuation in
            let handle = pipe.fileHandleForReading
            let state = HandshakeReadState()

            // Timeout after 30 seconds
            let deadlineWorkItem = DispatchWorkItem {
                guard state.resumeIfNeeded() else { return }
                handle.readabilityHandler = nil
                continuation.resume(throwing: NSError(
                    domain: "TranslationBackendProcessManager",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Translation backend 握手超时（30 秒）。"]
                ))
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 30, execute: deadlineWorkItem)

            handle.readabilityHandler = { [weak proc] h in
                let chunk = h.availableData
                if chunk.isEmpty {
                    // EOF — process exited
                    if !(proc?.isRunning ?? false) {
                        guard state.resumeIfNeeded() else { return }
                        deadlineWorkItem.cancel()
                        h.readabilityHandler = nil
                        continuation.resume(throwing: NSError(
                            domain: "TranslationBackendProcessManager",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Translation backend 进程意外退出，无法读取握手信息。"]
                        ))
                    }
                    return
                }

                // Look for first newline — handshake is a single JSON line
                if let extracted = state.appendAndExtractLine(from: chunk) {
                    guard state.resumeIfNeeded() else { return }
                    deadlineWorkItem.cancel()

                    do {
                        let handshake = try JSONDecoder().decode(
                            TranslationBackendHandshake.self,
                            from: extracted.line
                        )
                        // Set up ongoing stdout forwarding after handshake
                        if !extracted.remaining.isEmpty {
                            FileHandle.standardError.write(extracted.remaining)
                        }
                        h.readabilityHandler = { fh in
                            let data = fh.availableData
                            if !data.isEmpty {
                                FileHandle.standardError.write(data)
                            }
                        }
                        continuation.resume(returning: handshake)
                    } catch {
                        h.readabilityHandler = nil
                        continuation.resume(throwing: NSError(
                            domain: "TranslationBackendProcessManager",
                            code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "无法解析 Translation backend 握手数据：\(error.localizedDescription)"]
                        ))
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func findNodeExecutable() throws -> URL {
        // 1. Check bundled node in app bundle
        if let bundledNode = Bundle.main.url(forAuxiliaryExecutable: "node") {
            return bundledNode
        }

        // 2. Check Helpers directory in app bundle
        if let helpersURL = Bundle.main.privateFrameworksURL?
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers")
            .appendingPathComponent("node") {
            if FileManager.default.isExecutableFile(atPath: helpersURL.path) {
                return helpersURL
            }
        }

        // 3. Try common node paths
        let commonPaths = [
            "/usr/local/bin/node",
            "/opt/homebrew/bin/node",
            "/usr/bin/node",
        ]
        for nodePath in commonPaths {
            if FileManager.default.isExecutableFile(atPath: nodePath) {
                return URL(fileURLWithPath: nodePath)
            }
        }

        // 4. Try `which node` via PATH
        let whichProc = Process()
        whichProc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProc.arguments = ["node"]
        let whichPipe = Pipe()
        whichProc.standardOutput = whichPipe
        whichProc.standardError = FileHandle.nullDevice
        try? whichProc.run()
        whichProc.waitUntilExit()
        if whichProc.terminationStatus == 0 {
            let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        throw NSError(
            domain: "TranslationBackendProcessManager",
            code: -5,
            userInfo: [NSLocalizedDescriptionKey: "找不到 Node.js 可执行文件。请确保已安装 Node.js。"]
        )
    }

    private func findServerEntry() -> URL? {
        // 1. Check app bundle Resources
        if let bundled = Bundle.main.url(forResource: "server", withExtension: "js", subdirectory: "swiftlib-translation-backend") {
            return bundled
        }

        // 2. Check relative to Bundle.main (for development)
        let mainBundlePath = Bundle.main.bundleURL
        let devServer = mainBundlePath
            .deletingLastPathComponent()
            .appendingPathComponent("swiftlib-translation-backend")
            .appendingPathComponent("server.js")
        if FileManager.default.fileExists(atPath: devServer.path) {
            return devServer
        }

        // 3. Check relative to executable (SPM development layout)
        if let execURL = Bundle.main.executableURL {
            // SPM puts executable in .build/debug/SwiftLib
            // server.js is at project root/swiftlib-translation-backend/server.js
            var dir = execURL.deletingLastPathComponent()
            // Walk up looking for swiftlib-translation-backend/server.js
            for _ in 0..<6 {
                let candidate = dir
                    .appendingPathComponent("swiftlib-translation-backend")
                    .appendingPathComponent("server.js")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
                dir = dir.deletingLastPathComponent()
            }
        }

        // 4. Check current working directory
        let cwdServer = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("swiftlib-translation-backend")
            .appendingPathComponent("server.js")
        if FileManager.default.fileExists(atPath: cwdServer.path) {
            return cwdServer
        }

        return nil
    }

    private func determineLaunchMode(serverEntry: URL) -> String {
        let parentDir = serverEntry.deletingLastPathComponent()
        let gitDir = parentDir.appendingPathComponent(".git")
        let nodeModules = parentDir.appendingPathComponent("node_modules")

        // If parent has .git or node_modules, it's a development checkout
        if FileManager.default.fileExists(atPath: gitDir.path) ||
            FileManager.default.fileExists(atPath: nodeModules.path) {
            return "development"
        }

        // If inside an app bundle, it's bundled
        if parentDir.path.contains(".app/") {
            return "bundled"
        }

        return "external"
    }
}
