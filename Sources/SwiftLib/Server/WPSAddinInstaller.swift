import AppKit
import Foundation

/// Manages WPS Office JS add-in installation / uninstallation on macOS.
///
/// WPS macOS looks for JS add-ins in:
///   ~/Library/Containers/com.kingsoft.wpsoffice.mac/Data/.kingsoft/wps/jsaddons/
///
/// The plugin directory name must be `name_version` (e.g. SwiftLib_1.0).
/// The root `publish.xml` registers add-ins using the <jsplugin> format:
///   <jsplugin name="SwiftLib" enable="enable_dev" url="file://" type="wps" version="1.0"/>
enum WPSAddinInstaller {
    static let pluginName = "SwiftLib"
    static let pluginVersion = "1.0"

    /// Root jsaddons directory where WPS looks for JS add-ins.
    /// Official path confirmed at: https://bbs.wps.cn/topic/47510
    static let jsaddonsDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Containers/com.kingsoft.wpsoffice.mac/Data/.kingsoft/wps/jsaddons")
    }()

    /// This plugin's directory inside jsaddons. Must be named `name_version`.
    static var pluginDir: URL {
        jsaddonsDir.appendingPathComponent("\(pluginName)_\(pluginVersion)")
    }

    /// The publish.xml catalog that WPS reads to enumerate installed add-ins.
    static var publishXML: URL {
        jsaddonsDir.appendingPathComponent("publish.xml")
    }

    static var isInstalled: Bool {
        guard FileManager.default.fileExists(atPath: pluginDir.appendingPathComponent("index.html").path) else {
            return false
        }
        guard let xml = try? String(contentsOf: publishXML, encoding: .utf8) else { return false }
        return xml.contains("name=\"\(pluginName)\"")
    }

    /// Whether WPS appears to be installed on this machine.
    static var isWPSInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.kingsoft.wpsoffice.mac") != nil
            || FileManager.default.fileExists(atPath: "/Applications/wpsoffice.app")
    }

    // MARK: - Install

    static func install() throws {
        guard isWPSInstalled else { return }

        let fm = FileManager.default

        // Remove legacy directory (old installs used plain "SwiftLib" without version suffix)
        let legacyDir = jsaddonsDir.appendingPathComponent(pluginName)
        if fm.fileExists(atPath: legacyDir.path) {
            try? fm.removeItem(at: legacyDir)
        }

        // Ensure jsaddons + plugin dir exist
        if !fm.fileExists(atPath: pluginDir.path) {
            try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        }

        // Copy WPSAddin resource files from SwiftLibCore bundle
        let bundle = Bundle.swiftLibCoreBundle

        let filesToCopy = [
            "index.html",
            "main.js",
            "ribbon.xml",
            "wps-document.js",
            "wps-taskpane.html",
            "wps-taskpane.js",
        ]

        for fileName in filesToCopy {
            let stem = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            if let srcURL = bundle.url(forResource: "Resources/WPSAddin/\(stem)", withExtension: ext) {
                let destURL = pluginDir.appendingPathComponent(fileName)
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(at: srcURL, to: destURL)
            }
        }

        // Ensure publish.xml includes our plugin entry
        try ensurePluginRegistered()

        // Delete authaddin.json so WPS recomputes the security signature for the new files.
        // If stale, WPS silently refuses to load the addon without any error.
        let authAddin = jsaddonsDir.appendingPathComponent("authaddin.json")
        if fm.fileExists(atPath: authAddin.path) {
            try? fm.removeItem(at: authAddin)
        }
    }

    // MARK: - Uninstall

    static func uninstall() {
        let fm = FileManager.default
        if fm.fileExists(atPath: pluginDir.path) {
            try? fm.removeItem(at: pluginDir)
        }
        removePluginRegistration()
    }

    // MARK: - Reveal

    static func revealAddin() {
        if isInstalled {
            NSWorkspace.shared.selectFile(pluginDir.appendingPathComponent("index.html").path,
                                          inFileViewerRootedAtPath: "")
        } else {
            NSWorkspace.shared.open(jsaddonsDir)
        }
    }

    // MARK: - publish.xml management

    /// Make sure publish.xml contains our <jsplugin> entry.
    /// Format confirmed working: <jsplugin name="X" enable="enable_dev" url="file://" type="wps" version="X"/>
    private static func ensurePluginRegistered() throws {
        // url="file://" is a magic value telling WPS to look in the local jsaddons directory.
        // The actual plugin dir is resolved by WPS as jsaddons/name_version/.
        let entry = "<jsplugin name=\"\(pluginName)\" enable=\"enable_dev\" url=\"file://\" type=\"wps\" version=\"\(pluginVersion)\"/>"

        let fm = FileManager.default
        if fm.fileExists(atPath: publishXML.path),
           let existing = try? String(contentsOf: publishXML, encoding: .utf8),
           existing.contains("name=\"\(pluginName)\"") {
            // Already registered — refresh the entry in case the path changed
            let refreshed = rebuildPublishXML(existing: existing, newEntry: entry)
            try refreshed.write(to: publishXML, atomically: true, encoding: .utf8)
            return
        }

        if fm.fileExists(atPath: publishXML.path),
           let existing = try? String(contentsOf: publishXML, encoding: .utf8) {
            // Append our entry before </jsplugins>
            let updated: String
            if existing.contains("</jsplugins>") {
                updated = existing.replacingOccurrences(
                    of: "</jsplugins>",
                    with: "  \(entry)\n</jsplugins>"
                )
            } else {
                updated = existing + "\n" + entry
            }
            try updated.write(to: publishXML, atomically: true, encoding: .utf8)
        } else {
            // Create fresh publish.xml with XML declaration
            let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<jsplugins>\n  \(entry)\n</jsplugins>"
            try xml.write(to: publishXML, atomically: true, encoding: .utf8)
        }
    }

    /// Replace the existing entry for our plugin (path may have changed).
    private static func rebuildPublishXML(existing: String, newEntry: String) -> String {
        // Remove old line containing our plugin name, then append updated entry
        let lines = existing.components(separatedBy: "\n")
        let filtered = lines.filter { !$0.contains("name=\"\(pluginName)\"") }
        var result = filtered.joined(separator: "\n")
        if result.contains("</jsplugins>") {
            result = result.replacingOccurrences(
                of: "</jsplugins>",
                with: "  \(newEntry)\n</jsplugins>"
            )
        } else {
            result += "\n  " + newEntry
        }
        return result
    }

    private static func removePluginRegistration() {
        guard FileManager.default.fileExists(atPath: publishXML.path),
              let existing = try? String(contentsOf: publishXML, encoding: .utf8),
              existing.contains("name=\"\(pluginName)\"") else { return }

        let lines = existing.components(separatedBy: "\n")
        let filtered = lines.filter { !$0.contains("name=\"\(pluginName)\"") }
        let updated = filtered.joined(separator: "\n")
        try? updated.write(to: publishXML, atomically: true, encoding: .utf8)
    }
}
