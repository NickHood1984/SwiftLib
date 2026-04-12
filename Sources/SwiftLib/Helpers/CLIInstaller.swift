import AppKit
import Foundation

/// Installs / uninstalls the `swiftlib-cli` CLI tool to /usr/local/bin.
///
/// The CLI binary is expected to live alongside the main app executable
/// inside the app bundle's `MacOS/` directory (or as a bundled resource).
enum CLIInstaller {
    static let binaryName = "swiftlib-cli"

    static var installURLOverride: URL?
    static var bundledBinaryURLOverride: (() -> URL?)?
    static var unprivilegedInstallerOverride: ((URL, URL) throws -> Void)?
    static var unprivilegedUninstallerOverride: ((URL) throws -> Void)?
    static var privilegedCommandRunnerOverride: ((String) throws -> Void)?

    static var installURL: URL {
        installURLOverride ?? URL(fileURLWithPath: "/usr/local/bin/\(binaryName)")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installURL.path)
    }

    /// Locate the bundled CLI binary inside the app bundle.
    static var bundledBinaryURL: URL? {
        if let override = bundledBinaryURLOverride {
            return override()
        }

        // 1. Contents/Helpers/swiftlib-cli (standard location, avoids case-insensitive collision with SwiftLib)
        if let bundleURL = Bundle.main.bundleURL as URL? {
            let candidate = bundleURL.appendingPathComponent("Contents/Helpers/\(binaryName)")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        // 2. Contents/MacOS/swiftlib-cli
        if let execURL = Bundle.main.executableURL {
            let candidate = execURL.deletingLastPathComponent().appendingPathComponent(binaryName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        // 3. As a resource
        if let url = Bundle.main.url(forResource: binaryName, withExtension: nil) {
            return url
        }
        // 4. Development: built product in same directory (swift build)
        if let execURL = Bundle.main.executableURL {
            let buildDir = execURL.deletingLastPathComponent()
            let candidate = buildDir.appendingPathComponent(binaryName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func install() throws {
        guard let source = bundledBinaryURL else {
            throw makeError("找不到 swiftlib-cli 可执行文件。请确认 CLI 已包含在 App 中。")
        }

        do {
            try runUnprivilegedInstall(from: source, to: installURL)
        } catch {
            guard requiresAdministratorPrivileges(for: error) else {
                throw normalizedFileOperationError(error, action: "安装")
            }

            do {
                try runPrivilegedCommand(privilegedInstallCommand(from: source, to: installURL))
            } catch {
                throw normalizedPrivilegeError(error, action: "安装")
            }
        }
    }

    static func uninstall() throws {
        guard FileManager.default.fileExists(atPath: installURL.path) else {
            return
        }

        do {
            try runUnprivilegedUninstall(at: installURL)
        } catch {
            guard requiresAdministratorPrivileges(for: error) else {
                throw normalizedFileOperationError(error, action: "卸载")
            }

            do {
                try runPrivilegedCommand(privilegedUninstallCommand(at: installURL))
            } catch {
                throw normalizedPrivilegeError(error, action: "卸载")
            }
        }
    }

    static func revealInFinder() {
        if isInstalled {
            NSWorkspace.shared.selectFile(installURL.path, inFileViewerRootedAtPath: "")
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/usr/local/bin"))
        }
    }

    static func resetOverridesForTesting() {
        installURLOverride = nil
        bundledBinaryURLOverride = nil
        unprivilegedInstallerOverride = nil
        unprivilegedUninstallerOverride = nil
        privilegedCommandRunnerOverride = nil
    }

    static func requiresAdministratorPrivileges(for error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == EACCES || nsError.code == EPERM {
            return true
        }

        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return requiresAdministratorPrivileges(for: underlying)
        }

        return false
    }

    private static func runUnprivilegedInstall(from source: URL, to destination: URL) throws {
        if let override = unprivilegedInstallerOverride {
            try override(source, destination)
            return
        }

        let directory = destination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }

    private static func runUnprivilegedUninstall(at destination: URL) throws {
        if let override = unprivilegedUninstallerOverride {
            try override(destination)
            return
        }

        try FileManager.default.removeItem(at: destination)
    }

    private static func runPrivilegedCommand(_ command: String) throws {
        if let override = privilegedCommandRunnerOverride {
            try override(command)
            return
        }

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"\(escapeForAppleScript(command))\" with administrator privileges"
        ]
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let details = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw makeError(details?.isEmpty == false
                ? details!
                : "管理员命令执行失败（退出码 \(process.terminationStatus)）。")
        }
    }

    private static func privilegedInstallCommand(from source: URL, to destination: URL) -> String {
        let directory = destination.deletingLastPathComponent().path
        return "/bin/mkdir -p \(shellQuote(directory)) && /usr/bin/install -m 755 \(shellQuote(source.path)) \(shellQuote(destination.path))"
    }

    private static func privilegedUninstallCommand(at destination: URL) -> String {
        "/bin/rm -f \(shellQuote(destination.path))"
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func normalizedFileOperationError(_ error: Error, action: String) -> NSError {
        let nsError = error as NSError
        if nsError.domain == "SwiftLib.CLIInstaller" {
            return nsError
        }

        return makeError("\(action) CLI 工具失败：\(nsError.localizedDescription)")
    }

    private static func normalizedPrivilegeError(_ error: Error, action: String) -> NSError {
        let nsError = error as NSError
        let message = nsError.localizedDescription

        if nsError.code == -128 || message.localizedCaseInsensitiveContains("user canceled") || message.contains("(-128)") {
            return makeError("已取消管理员授权，CLI 工具\(action)未完成。")
        }

        return makeError("需要管理员权限才能\(action) CLI 工具，但授权失败：\(message)")
    }

    private static func makeError(_ message: String) -> NSError {
        NSError(
            domain: "SwiftLib.CLIInstaller",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
