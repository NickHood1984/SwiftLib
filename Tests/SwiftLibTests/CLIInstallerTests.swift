import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class CLIInstallerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CLIInstaller.resetOverridesForTesting()
    }

    override func tearDown() {
        CLIInstaller.resetOverridesForTesting()
        super.tearDown()
    }

    // MARK: - Properties

    func testBinaryNameIsSwiftlibCLI() {
        XCTAssertEqual(CLIInstaller.binaryName, "swiftlib-cli")
    }

    func testInstallURLPointsToUsrLocalBin() {
        let expected = URL(fileURLWithPath: "/usr/local/bin/swiftlib-cli")
        XCTAssertEqual(CLIInstaller.installURL, expected)
    }

    // MARK: - isInstalled

    func testIsInstalledReflectsFileExistence() {
        let exists = FileManager.default.fileExists(atPath: CLIInstaller.installURL.path)
        XCTAssertEqual(CLIInstaller.isInstalled, exists)
    }

    // MARK: - bundledBinaryURL

    func testBundledBinaryURLIsExecutableIfPresent() {
        // In a unit-test host the CLI binary may or may not be present.
        // If found, verify it is executable.
        if let url = CLIInstaller.bundledBinaryURL {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path),
                          "bundledBinaryURL should point to an executable file")
        }
    }

    // MARK: - Install / Uninstall round-trip

    func testInstallAndUninstallRoundTrip() throws {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let source = workingDirectory.appendingPathComponent("swiftlib-cli-source")
        let destination = workingDirectory
            .appendingPathComponent("usr/local/bin", isDirectory: true)
            .appendingPathComponent(CLIInstaller.binaryName)

        try "#!/bin/sh\necho SwiftLib\n".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        CLIInstaller.installURLOverride = destination
        CLIInstaller.bundledBinaryURLOverride = { source }

        try CLIInstaller.install()
        XCTAssertTrue(CLIInstaller.isInstalled, "CLI should be installed after install()")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: CLIInstaller.installURL.path),
                      "Installed CLI should be executable")

        let attrs = try FileManager.default.attributesOfItem(atPath: CLIInstaller.installURL.path)
        if let perms = attrs[.posixPermissions] as? Int {
            XCTAssertEqual(perms, 0o755, "Installed binary should have 755 permissions")
        }

        try CLIInstaller.uninstall()
        XCTAssertFalse(CLIInstaller.isInstalled, "CLI should not be installed after uninstall()")
    }

    // MARK: - Install error when binary missing

    func testInstallThrowsWhenBinaryNotFound() {
        CLIInstaller.bundledBinaryURLOverride = { nil }
        XCTAssertThrowsError(try CLIInstaller.install()) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "SwiftLib.CLIInstaller")
            XCTAssertTrue(nsError.localizedDescription.contains("swiftlib-cli"),
                          "Error should mention the binary name")
        }
    }

    // MARK: - Reinstall overwrites old version

    func testReinstallOverwritesExistingBinary() throws {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let source = workingDirectory.appendingPathComponent("swiftlib-cli-source")
        let destination = workingDirectory
            .appendingPathComponent("usr/local/bin", isDirectory: true)
            .appendingPathComponent(CLIInstaller.binaryName)

        try "#!/bin/sh\necho SwiftLib\n".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        CLIInstaller.installURLOverride = destination
        CLIInstaller.bundledBinaryURLOverride = { source }

        try CLIInstaller.install()
        XCTAssertNoThrow(try CLIInstaller.install(), "Reinstalling should not throw")
        XCTAssertTrue(CLIInstaller.isInstalled)
        try CLIInstaller.uninstall()
    }

    // MARK: - Uninstall is idempotent

    func testUninstallWhenNotInstalledDoesNotThrow() throws {
        try CLIInstaller.uninstall()
        try CLIInstaller.uninstall()
        XCTAssertFalse(CLIInstaller.isInstalled)
    }

    func testInstallFallsBackToAdministratorPrivilegesWhenCopyIsDenied() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("swiftlib-cli-source-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: source) }
        try "#!/bin/sh\necho SwiftLib\n".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLI Installer Tests", isDirectory: true)
            .appendingPathComponent("swiftlib-cli")
        let permissionError = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        var receivedCommand: String?

        CLIInstaller.installURLOverride = destination
        CLIInstaller.bundledBinaryURLOverride = { source }
        CLIInstaller.unprivilegedInstallerOverride = { _, _ in throw permissionError }
        CLIInstaller.privilegedCommandRunnerOverride = { command in
            receivedCommand = command
        }

        try CLIInstaller.install()

        XCTAssertNotNil(receivedCommand)
        XCTAssertTrue(receivedCommand?.contains("/usr/bin/install -m 755") == true)
        XCTAssertTrue(receivedCommand?.contains("/bin/mkdir -p") == true)
        XCTAssertTrue(receivedCommand?.contains("'\(source.path)'") == true)
        XCTAssertTrue(receivedCommand?.contains("'\(destination.path)'") == true)
    }

    func testUninstallFallsBackToAdministratorPrivilegesWhenRemovalIsDenied() throws {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let destination = workingDirectory.appendingPathComponent(CLIInstaller.binaryName)
        try Data("SwiftLib".utf8).write(to: destination)

        let permissionError = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        var receivedCommand: String?

        CLIInstaller.installURLOverride = destination
        CLIInstaller.unprivilegedUninstallerOverride = { _ in throw permissionError }
        CLIInstaller.privilegedCommandRunnerOverride = { command in
            receivedCommand = command
        }

        try CLIInstaller.uninstall()

        XCTAssertEqual(receivedCommand, "/bin/rm -f '\(destination.path)'")
    }

    func testInstallReportsCanceledAdministratorAuthorization() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("swiftlib-cli-source-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: source) }
        try "#!/bin/sh\necho SwiftLib\n".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)

        CLIInstaller.installURLOverride = FileManager.default.temporaryDirectory.appendingPathComponent("swiftlib-cli-dest-\(UUID().uuidString)")
        CLIInstaller.bundledBinaryURLOverride = { source }
        CLIInstaller.unprivilegedInstallerOverride = { _, _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        }
        CLIInstaller.privilegedCommandRunnerOverride = { _ in
            throw NSError(
                domain: "SwiftLib.CLIInstaller",
                code: -128,
                userInfo: [NSLocalizedDescriptionKey: "User canceled. (-128)"]
            )
        }

        XCTAssertThrowsError(try CLIInstaller.install()) { error in
            XCTAssertTrue(error.localizedDescription.contains("已取消管理员授权"))
        }
    }
}
