import AppKit
import SwiftUI

@MainActor
enum MetadataVerificationPanels {
    static let cnki = MetadataVerificationPanelManager(
        defaultTitle: "知网验证",
        autosaveName: "SwiftLibCNKIVerificationPanel-v1"
    )
    static let baidu = MetadataVerificationPanelManager(
        defaultTitle: "百度学术验证",
        autosaveName: "SwiftLibBaiduVerificationPanel-v1"
    )
}

@MainActor
final class MetadataVerificationPanelManager {
    private let defaultTitle: String
    private let autosaveName: String
    private let minSize = NSSize(width: 760, height: 560)

    private var panel: NSPanel?
    private var hostController: NSHostingController<AnyView>?
    private var closeObserver: NSObjectProtocol?
    private var onClose: (() -> Void)?

    init(defaultTitle: String, autosaveName: String) {
        self.defaultTitle = defaultTitle
        self.autosaveName = autosaveName
    }

    func present<Content: View>(
        title: String? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        let panel = ensurePanel()
        let view = AnyView(content())

        if let hostController {
            hostController.rootView = view
        } else {
            let hostController = NSHostingController(rootView: view)
            panel.contentViewController = hostController
            self.hostController = hostController
        }

        self.onClose = onClose
        panel.title = title ?? defaultTitle
        panel.deminiaturize(nil)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        guard let panel else { return }
        onClose = nil
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        hostController = nil
        panel.contentViewController = nil
        panel.orderOut(nil)
        self.panel = nil
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = makePanel()
        self.panel = panel

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let callback = self.onClose
                self.onClose = nil
                self.hostController = nil
                self.panel = nil
                if let closeObserver = self.closeObserver {
                    NotificationCenter.default.removeObserver(closeObserver)
                    self.closeObserver = nil
                }
                callback?()
            }
        }

        return panel
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: preferredSize()),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = defaultTitle
        panel.isReleasedWhenClosed = false
        panel.minSize = minSize
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.auxiliary, .moveToActiveSpace]
        panel.hidesOnDeactivate = false
        panel.setFrameAutosaveName(autosaveName)
        if !panel.setFrameUsingName(autosaveName) {
            positionNearMainWindow(panel)
        }
        return panel
    }

    private func positionNearMainWindow(_ panel: NSPanel) {
        guard let mainWindow = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }),
              let screen = mainWindow.screen ?? NSScreen.main else {
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height
        let rightX = mainWindow.frame.maxX + 12

        if rightX + panelWidth <= visibleFrame.maxX {
            let y = max(
                visibleFrame.minY,
                min(mainWindow.frame.midY - panelHeight / 2, visibleFrame.maxY - panelHeight)
            )
            panel.setFrameOrigin(NSPoint(x: rightX, y: y))
        } else {
            panel.center()
        }
    }

    private func preferredSize() -> NSSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 960)
        let width = min(max(820, visibleFrame.width * 0.48), visibleFrame.width - 88)
        let height = min(max(620, visibleFrame.height * 0.68), visibleFrame.height - 88)
        return NSSize(width: width, height: height)
    }
}
