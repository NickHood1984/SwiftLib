import AppKit
import SwiftUI
import WebKit

@MainActor
final class AIChatWindowManager: ObservableObject {
    static let shared = AIChatWindowManager()

    private var window: NSPanel?
    private var closeObserver: NSObjectProtocol?

    @Published var currentURLString: String = SwiftLibPreferences.aiChatURL
    @Published var isLoading = false
    @Published var pageLoadState: AIChatPageLoadState = .idle
    @Published var lastOperationErrorMessage: String?

    /// Reference to the active WKWebView for JS evaluation.
    var webView: WKWebView?

    private init() {}

    var statusBanner: AIChatStatusBanner? {
        if let message = lastOperationErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            return AIChatStatusBanner(
                message: message,
                systemImage: "exclamationmark.triangle.fill",
                tone: .error,
                showsProgress: false
            )
        }

        switch pageLoadState {
        case .loading:
            return AIChatStatusBanner(
                message: "AI 页面加载中，页面未就绪时不会自动发送。",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .info,
                showsProgress: true
            )
        case .failed(let detail):
            return AIChatStatusBanner(
                message: "AI 页面加载失败：\(detail)",
                systemImage: "wifi.exclamationmark",
                tone: .warning,
                showsProgress: false
            )
        case .idle, .ready:
            return nil
        }
    }

    // MARK: - Public API

    /// Show the AI chat browser window.
    func open() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            existing.deminiaturize(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = makeWindow()
        let hostView = AIChatHostView(manager: self)
            .swiftLibElegantScrollersInSubtree()
        win.contentViewController = NSHostingController(rootView: hostView)
        window = win

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pageLoadState = .idle
                self?.lastOperationErrorMessage = nil
            }
        }

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Release the WKWebView and free memory.
    func destroyWindow() {
        if let obs = closeObserver {
            NotificationCenter.default.removeObserver(obs)
            closeObserver = nil
        }
        webView = nil
        pageLoadState = .idle
        lastOperationErrorMessage = nil
        window?.close()
        window = nil
    }

    // MARK: - Internals

    func changeService(to urlString: String) {
        lastOperationErrorMessage = nil
        pageLoadState = .loading
        currentURLString = urlString
        SwiftLibPreferences.aiChatURL = urlString
    }

    func reloadCurrentPage() {
        lastOperationErrorMessage = nil
        pageLoadState = .loading
        if let webView {
            webView.reload()
            return
        }

        let current = currentURLString
        currentURLString = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.currentURLString = current
        }
    }

    // MARK: - DOM interaction helpers

    func handleNavigationStarted() {
        pageLoadState = .loading
        if !isLoading {
            lastOperationErrorMessage = nil
        }
    }

    func handleNavigationFinished() {
        pageLoadState = .ready
    }

    func handleNavigationFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == URLError.cancelled.rawValue {
            return
        }
        pageLoadState = .failed(error.localizedDescription)
    }

}
