import AppKit
import Foundation

/// Installs / uninstalls the `swiftlib-cli` CLI tool to /usr/local/bin.
///
/// The CLI binary is expected to live alongside the main app executable
/// inside the app bundle's `MacOS/` directory (or as a bundled resource).
enum CLIInstaller {
    static let binaryName = "swiftlib-cli"

    static var installURL: URL {
        URL(fileURLWithPath: "/usr/local/bin/\(binaryName)")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installURL.path)
    }

    /// Locate the bundled CLI binary inside the app bundle.
    static var bundledBinaryURL: URL? {
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

        let dest = installURL
        let dir = dest.deletingLastPathComponent()

        // Ensure /usr/local/bin exists
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Remove old version if present
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }

        try FileManager.default.copyItem(at: source, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
    }

    static func uninstall() {
        try? FileManager.default.removeItem(at: installURL)
    }

    static func revealInFinder() {
        if isInstalled {
            NSWorkspace.shared.selectFile(installURL.path, inFileViewerRootedAtPath: "")
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/usr/local/bin"))
        }
    }

    private static func makeError(_ message: String) -> NSError {
        NSError(
            domain: "SwiftLib.CLIInstaller",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
