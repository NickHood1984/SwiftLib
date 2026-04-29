import AppKit
import SwiftUI
import SwiftLibCore

/// Manages an independent NSWindow for the pending metadata queue.
/// Unlike a sheet, this window can be moved, resized, and stays open
/// alongside the main library window.
@MainActor
final class PendingMetadataQueueWindowManager {
    static let shared = PendingMetadataQueueWindowManager()

    private var window: NSWindow?
    private var hostController: NSHostingController<AnyView>?
    private var closeObserver: NSObjectProtocol?

    private let minSize = NSSize(width: 720, height: 520)

    private init() {}

    func present(
        db: AppDatabase,
        resolver: MetadataResolver,
        onPersistResult: @escaping (MetadataResolutionResult, MetadataIntake) -> Void,
        onConfirmManual: @escaping (MetadataIntake) -> Void,
        onDelete: @escaping (MetadataIntake) -> Void
    ) {
        let window = ensureWindow()

        let view = PendingMetadataQueueView(
            db: db,
            resolver: resolver,
            onPersistResult: onPersistResult,
            onConfirmManual: onConfirmManual,
            onDelete: onDelete
        )
        .frame(minWidth: minSize.width, minHeight: minSize.height)

        if let hostController {
            hostController.rootView = AnyView(view)
        } else {
            let hostController = NSHostingController(rootView: AnyView(view))
            window.contentViewController = hostController
            self.hostController = hostController
        }

        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        guard let window else { return }
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        hostController = nil
        window.contentViewController = nil
        window.orderOut(nil)
        self.window = nil
    }

    var isVisible: Bool { window?.isVisible == true }

    private func ensureWindow() -> NSWindow {
        if let window { return window }

        let window = makeWindow()
        self.window = window

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let closeObserver = self.closeObserver {
                    NotificationCenter.default.removeObserver(closeObserver)
                    self.closeObserver = nil
                }
                self.hostController = nil
                self.window = nil
            }
        }

        return window
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: minSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "待确认元数据"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.minSize = minSize
        window.setFrameAutosaveName("SwiftLibPendingQueueWindow-v1")
        if !window.setFrameUsingName("SwiftLibPendingQueueWindow-v1") {
            positionNearMainWindow(window)
        }
        return window
    }

    private func positionNearMainWindow(_ window: NSWindow) {
        guard let mainWindow = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }),
              let screen = mainWindow.screen ?? NSScreen.main else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let windowWidth = window.frame.width
        let windowHeight = window.frame.height
        let rightX = mainWindow.frame.maxX + 20

        if rightX + windowWidth <= visibleFrame.maxX {
            let y = max(
                visibleFrame.minY,
                min(mainWindow.frame.midY - windowHeight / 2, visibleFrame.maxY - windowHeight)
            )
            window.setFrameOrigin(NSPoint(x: rightX, y: y))
        } else {
            window.center()
        }
    }
}
