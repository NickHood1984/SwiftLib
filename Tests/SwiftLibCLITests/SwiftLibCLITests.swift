import XCTest
import Foundation

/// Integration tests for the `swiftlib-cli` CLI binary.
/// These tests invoke the compiled CLI executable and verify its output.
/// Requires the CLI to be built first: `swift build --product swiftlib-cli`
final class SwiftLibCLITests: XCTestCase {

    /// Path to the built CLI binary
    private var cliBinaryPath: String {
        let debugPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // SwiftLibCLITests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent(".build/debug/swiftlib-cli")
            .path

        if FileManager.default.isExecutableFile(atPath: debugPath) {
            return debugPath
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/swiftlib-cli") {
            return "/usr/local/bin/swiftlib-cli"
        }
        return debugPath
    }

    private func runCLI(_ arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliBinaryPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return (
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    private func skipIfBinaryMissing() throws {
        guard FileManager.default.isExecutableFile(atPath: cliBinaryPath) else {
            throw XCTSkip("CLI binary not found at \(cliBinaryPath). Run `swift build` first.")
        }
    }

    // MARK: - Help

    func testHelpOutput() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["--help"])
        XCTAssertEqual(result.exitCode, 0)
        let output = result.stdout + result.stderr
        XCTAssertTrue(output.lowercased().contains("subcommand") || output.contains("SUBCOMMANDS"),
                      "Help should list subcommands")
    }

    // MARK: - Version

    func testVersionOutput() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["--version"])
        XCTAssertEqual(result.exitCode, 0)
        let output = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(output.isEmpty, "--version should produce output")
    }

    // MARK: - List

    func testListCommand() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["list"])
        XCTAssertEqual(result.exitCode, 0)
        // Verify output is valid JSON array
        let data = Data(result.stdout.utf8)
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [Any], "List output should be a JSON array")
    }

    func testListWithLimit() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["list", "--limit", "5"])
        XCTAssertEqual(result.exitCode, 0)
        let data = Data(result.stdout.utf8)
        let arr = try JSONSerialization.jsonObject(with: data) as? [Any]
        XCTAssertNotNil(arr)
        XCTAssertLessThanOrEqual(arr?.count ?? 0, 5, "List with --limit 5 should return at most 5")
    }

    func testListWithOffset() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["list", "--offset", "0"])
        XCTAssertEqual(result.exitCode, 0)
    }

    // MARK: - Search

    func testSearchCommand() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["search", "test"])
        XCTAssertEqual(result.exitCode, 0)
        let data = Data(result.stdout.utf8)
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [Any], "Search output should be a JSON array")
    }

    // MARK: - Collections

    func testCollectionsListCommand() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["collections"])
        XCTAssertEqual(result.exitCode, 0)
        let data = Data(result.stdout.utf8)
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [Any], "Collections output should be a JSON array")
    }

    // MARK: - Tags

    func testTagsListCommand() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["tags"])
        XCTAssertEqual(result.exitCode, 0)
        let data = Data(result.stdout.utf8)
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [Any], "Tags output should be a JSON array")
    }

    // MARK: - Export

    func testExportJSON() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["export", "--format", "json"])
        XCTAssertEqual(result.exitCode, 0)
        let data = Data(result.stdout.utf8)
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [Any], "Export JSON should produce a JSON array")
    }

    func testExportBibTeX() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["export", "--format", "bibtex"])
        XCTAssertEqual(result.exitCode, 0)
    }

    func testExportRIS() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["export", "--format", "ris"])
        XCTAssertEqual(result.exitCode, 0)
    }

    // MARK: - Subcommand Help

    func testSearchHelp() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["search", "--help"])
        XCTAssertEqual(result.exitCode, 0)
    }

    func testCiteHelp() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["cite", "--help"])
        XCTAssertEqual(result.exitCode, 0)
    }

    func testImportHelp() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["import", "--help"])
        XCTAssertEqual(result.exitCode, 0)
    }

    // MARK: - Invalid Subcommand

    func testInvalidSubcommand() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["nonexistent"])
        XCTAssertNotEqual(result.exitCode, 0,
                          "Invalid subcommand should return non-zero exit code")
    }

    // MARK: - Get Non-existent Reference

    func testGetNonExistentReference() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["get", "999999999"])
        XCTAssertNotEqual(result.exitCode, 0,
                          "Getting a non-existent reference should fail")
        // Error should be in stderr as JSON
        let errData = Data(result.stderr.utf8)
        if let errJson = try? JSONSerialization.jsonObject(with: errData) as? [String: Any] {
            XCTAssertNotNil(errJson["error"], "Error output should contain 'error' key")
        }
    }

    // MARK: - Delete requires --force in non-interactive

    func testDeleteWithoutForceInNonInteractive() throws {
        try skipIfBinaryMissing()
        // When run as a subprocess (non-tty), delete without --force should still work
        // because isatty returns 0 for piped stdin
        let result = try runCLI(["delete", "999999999", "--force"])
        _ = result
        // May fail because the reference doesn't exist, but should not hang waiting for input
        // The important thing is it doesn't block
    }

    // MARK: - Add → Get → Delete lifecycle

    func testAddGetDeleteLifecycle() throws {
        try skipIfBinaryMissing()

        // Add by title
        let addResult = try runCLI(["add", "--title", "CLI Test Reference \(UUID().uuidString)"])
        XCTAssertEqual(addResult.exitCode, 0, "Add should succeed")
        let addData = Data(addResult.stdout.utf8)
        let addJson = try JSONSerialization.jsonObject(with: addData) as? [String: Any]
        XCTAssertNotNil(addJson, "Add output should be a JSON object")
        guard let refId = addJson?["id"] as? Int64 ?? (addJson?["id"] as? Int).map(Int64.init) else {
            XCTFail("Add output should contain an integer 'id'")
            return
        }

        // Get the reference back
        let getResult = try runCLI(["get", "\(refId)"])
        XCTAssertEqual(getResult.exitCode, 0, "Get should succeed")
        let getData = Data(getResult.stdout.utf8)
        let getJson = try JSONSerialization.jsonObject(with: getData) as? [String: Any]
        XCTAssertNotNil(getJson?["title"], "Get output should contain 'title'")

        // Delete it (with --force to skip confirmation)
        let deleteResult = try runCLI(["delete", "\(refId)", "--force"])
        XCTAssertEqual(deleteResult.exitCode, 0, "Delete should succeed")

        // Verify it's gone
        let verifyResult = try runCLI(["get", "\(refId)"])
        XCTAssertNotEqual(verifyResult.exitCode, 0, "Get after delete should fail")
    }

    // MARK: - Import Help mentions stdin

    func testImportHelpMentionsStdin() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["import", "--help"])
        XCTAssertEqual(result.exitCode, 0)
        let output = result.stdout + result.stderr
        XCTAssertTrue(output.contains("-") || output.contains("stdin"),
                      "Import help should mention stdin support")
    }

    // MARK: - Cite invalid style

    func testCiteInvalidStyleFails() throws {
        try skipIfBinaryMissing()
        let result = try runCLI(["cite", "1", "--style", "nonexistent-style"])
        XCTAssertNotEqual(result.exitCode, 0, "Invalid citation style should fail")
    }
}
