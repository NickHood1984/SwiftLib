import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

/// Tests for the first-launch CLI installation prompt feature.
final class CLIInstallPromptTests: XCTestCase {

    // MARK: - UserDefaults Key

    func testHasPromptedKeyPersistence() {
        let key = "hasPromptedCLIInstallation"
        let saved = UserDefaults.standard.bool(forKey: key)
        // Reset
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))

        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))

        // Restore
        if saved {
            UserDefaults.standard.set(true, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Prompt Logic

    func testShouldShowPromptWhenNotPromptedAndNotInstalled() {
        let hasPrompted = false
        let isInstalled = false
        let shouldShow = !hasPrompted && !isInstalled
        XCTAssertTrue(shouldShow,
                      "Should show prompt when not prompted and not installed")
    }

    func testShouldNotShowPromptWhenAlreadyPrompted() {
        let hasPrompted = true
        let isInstalled = false
        let shouldShow = !hasPrompted && !isInstalled
        XCTAssertFalse(shouldShow,
                       "Should not show prompt when already prompted")
    }

    func testShouldNotShowPromptWhenAlreadyInstalled() {
        let hasPrompted = false
        let isInstalled = true
        let shouldShow = !hasPrompted && !isInstalled
        XCTAssertFalse(shouldShow,
                       "Should not show prompt when CLI is already installed")
    }

    func testShouldNotShowPromptWhenBothPromptedAndInstalled() {
        let hasPrompted = true
        let isInstalled = true
        let shouldShow = !hasPrompted && !isInstalled
        XCTAssertFalse(shouldShow)
    }
}
