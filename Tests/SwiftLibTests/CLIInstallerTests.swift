import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class CLIInstallerTests: XCTestCase {

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
        guard CLIInstaller.bundledBinaryURL != nil else {
            throw XCTSkip("CLI binary not found in bundle; skipping install round-trip test")
        }

        // Install
        try CLIInstaller.install()
        XCTAssertTrue(CLIInstaller.isInstalled, "CLI should be installed after install()")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: CLIInstaller.installURL.path),
                      "Installed CLI should be executable")

        // Verify permissions (0o755)
        let attrs = try FileManager.default.attributesOfItem(atPath: CLIInstaller.installURL.path)
        if let perms = attrs[.posixPermissions] as? Int {
            XCTAssertEqual(perms, 0o755, "Installed binary should have 755 permissions")
        }

        // Uninstall
        CLIInstaller.uninstall()
        XCTAssertFalse(CLIInstaller.isInstalled, "CLI should not be installed after uninstall()")
    }

    // MARK: - Install error when binary missing

    func testInstallThrowsWhenBinaryNotFound() {
        guard CLIInstaller.bundledBinaryURL == nil else { return }
        XCTAssertThrowsError(try CLIInstaller.install()) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "SwiftLib.CLIInstaller")
            XCTAssertTrue(nsError.localizedDescription.contains("swiftlib-cli"),
                          "Error should mention the binary name")
        }
    }

    // MARK: - Reinstall overwrites old version

    func testReinstallOverwritesExistingBinary() throws {
        guard CLIInstaller.bundledBinaryURL != nil else {
            throw XCTSkip("CLI binary not found in bundle")
        }
        try CLIInstaller.install()
        XCTAssertNoThrow(try CLIInstaller.install(), "Reinstalling should not throw")
        XCTAssertTrue(CLIInstaller.isInstalled)
        CLIInstaller.uninstall()
    }

    // MARK: - Uninstall is idempotent

    func testUninstallWhenNotInstalledDoesNotThrow() {
        CLIInstaller.uninstall()
        CLIInstaller.uninstall()
        XCTAssertFalse(CLIInstaller.isInstalled)
    }
}
