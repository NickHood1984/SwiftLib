import AppKit
import SwiftUI
import SwiftLibCore

// MARK: - ReaderWindowManager

/// Manages independent reader windows (PDF / Web) so the main library window
/// stays in place and multiple documents can be read side-by-side.
///
/// Design goals:
/// - One window per reference (re-activates if already open).
/// - Each window hosts the full `PDFReaderView` or `WebReaderView` with all
///   existing annotation/toolbar functionality intact.
/// - Zero coupling to `ContentView` reader-mode state — the main window never
///   enters reader mode when using this manager.
/// - Deterministic cleanup: windows are removed from the registry on close.
@MainActor
final class ReaderWindowManager {
    static let shared = ReaderWindowManager()

    // MARK: - Storage

    /// Open reader windows keyed by reference ID.
    private var windows: [Int64: NSWindow] = [:]
    /// Close-notification observers, keyed by reference ID.
    private var closeObservers: [Int64: NSObjectProtocol] = [:]

    private init() {}

    // MARK: - Public API

    /// Open (or re-activate) a PDF reader window for the given reference.
    func openPDFReader(for reference: Reference) {
        guard let refId = reference.id, reference.pdfPath != nil else { return }

        // Already open → bring to front
        if let existing = windows[refId], existing.isVisible || existing.isMiniaturized {
            existing.deminiaturize(nil)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeWindow(
            title: windowTitle(for: reference, suffix: "PDF"),
            autosaveName: "SwiftLibPDFReader-\(refId)",
            minSize: NSSize(width: 800, height: 600)
        )

        let readerView = PDFReaderView(reference: reference) { [weak self] in
            self?.closeWindow(forReferenceId: refId)
        }
        .frame(minWidth: 800, minHeight: 600)

        window.contentViewController = NSHostingController(rootView: readerView)
        registerWindow(window, forReferenceId: refId)
    }

    /// Open (or re-activate) a Web reader window for the given reference.
    func openWebReader(for reference: Reference) {
        guard let refId = reference.id, reference.canOpenWebReader else { return }

        if let existing = windows[refId], existing.isVisible || existing.isMiniaturized {
            existing.deminiaturize(nil)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeWindow(
            title: windowTitle(for: reference, suffix: "Web"),
            autosaveName: "SwiftLibWebReader-\(refId)",
            minSize: NSSize(width: 800, height: 600)
        )

        let readerView = WebReaderView(reference: reference) { [weak self] in
            self?.closeWindow(forReferenceId: refId)
        }
        .frame(minWidth: 800, minHeight: 600)

        window.contentViewController = NSHostingController(rootView: readerView)
        registerWindow(window, forReferenceId: refId)
    }

    /// Returns true if a reader window is currently open for the given reference.
    func isOpen(referenceId: Int64) -> Bool {
        windows[referenceId]?.isVisible == true
    }

    /// Close all reader windows (e.g. on app termination).
    func closeAll() {
        for (refId, window) in windows {
            window.close()
            removeObserver(forReferenceId: refId)
        }
        windows.removeAll()
    }

    // MARK: - Private helpers

    private func makeWindow(title: String, autosaveName: String, minSize: NSSize) -> NSWindow {
        let preferredSize = preferredWindowSize(minSize: minSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: preferredSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = minSize
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.setFrameAutosaveName(autosaveName)

        // Restore saved frame; if none, use preferred size centered on screen
        if !window.setFrameUsingName(autosaveName) {
            window.center()
        }

        return window
    }

    private func registerWindow(_ window: NSWindow, forReferenceId refId: Int64) {
        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Store reference
        windows[refId] = window

        // Observe close to clean up
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.windows.removeValue(forKey: refId)
                self.removeObserver(forReferenceId: refId)
            }
        }
        closeObservers[refId] = observer
    }

    private func closeWindow(forReferenceId refId: Int64) {
        windows[refId]?.close()
        // Observer callback handles cleanup
    }

    private func removeObserver(forReferenceId refId: Int64) {
        if let observer = closeObservers.removeValue(forKey: refId) {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func windowTitle(for reference: Reference, suffix: String) -> String {
        let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Reader — \(suffix)" : title
    }

    private func preferredWindowSize(minSize: NSSize) -> NSSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 960)
        let width = min(max(minSize.width, 1000), visibleFrame.width - 100)
        let height = min(max(minSize.height, 800), visibleFrame.height - 100)
        return NSSize(width: width, height: height)
    }
}
