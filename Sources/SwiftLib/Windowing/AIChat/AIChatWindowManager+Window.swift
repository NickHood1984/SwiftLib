import AppKit

extension AIChatWindowManager {
    // MARK: - Window factory

    func makeWindow() -> NSPanel {
        let size = preferredSize()
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "AI 助手"
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 480, height: 520)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.auxiliary, .moveToActiveSpace]
        panel.setFrameAutosaveName("SwiftLibAIChat-v1")
        if !panel.setFrameUsingName("SwiftLibAIChat-v1") {
            positionNearMainWindow(panel)
        }
        return panel
    }

    func positionNearMainWindow(_ panel: NSPanel) {
        guard let mainWindow = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }),
              let screen = mainWindow.screen ?? NSScreen.main else {
            panel.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height

        let rightX = mainWindow.frame.maxX + 8
        if rightX + panelWidth <= visibleFrame.maxX {
            let y = max(visibleFrame.minY, min(mainWindow.frame.midY - panelHeight / 2, visibleFrame.maxY - panelHeight))
            panel.setFrameOrigin(NSPoint(x: rightX, y: y))
        } else {
            panel.center()
        }
    }

    func preferredSize() -> NSSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 960)
        let width = min(max(560, visibleFrame.width * 0.36), visibleFrame.width - 80)
        let height = min(max(640, visibleFrame.height * 0.72), visibleFrame.height - 80)
        return NSSize(width: width, height: height)
    }
}
