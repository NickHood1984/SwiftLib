import AppKit
import SwiftUI

struct IdleStandbyHost<Content: View>: View {
    @StateObject private var controller = IdleStandbyController()
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            BlossomStandbyBackdrop(isPaused: controller.revealAmount < 0.01)
                .opacity(controller.revealAmount)
                .allowsHitTesting(false)

            content
                .opacity(max(0, 1 - controller.revealAmount * 1.35))
                .saturation(max(0, 1 - controller.revealAmount * 0.42))
                .blur(radius: controller.revealAmount * 2.8)
                .allowsHitTesting(controller.revealAmount < 0.02)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            StandbyMouseActivityBridge {
                controller.registerActivity()
            }
        }
        .background {
            StandbyWindowChromeBridge(isStandbyVisible: controller.revealAmount > 0.02)
        }
        .onAppear {
            controller.start()
        }
        .onDisappear {
            controller.stop()
        }
    }
}

@MainActor
final class IdleStandbyController: ObservableObject {
    @Published private(set) var revealAmount: Double = 0

    private let idleDelay: TimeInterval = 16
    private let revealDuration: TimeInterval = 1.6
    private let wakeDuration: TimeInterval = 0.35

    private var lastActivity = Date()
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var pollingTask: Task<Void, Never>?
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastActivity = Date()
        installEventMonitor()
        installObservers()
        startPollingLoop()
    }

    func stop() {
        isRunning = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        pollingTask?.cancel()
        pollingTask = nil
    }

    func registerActivity() {
        lastActivity = Date()
        updateReveal(target: 0, animation: .easeOut(duration: wakeDuration))
    }

    private func installEventMonitor() {
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .scrollWheel,
            .keyDown,
            .flagsChanged,
            .gesture,
            .magnify,
            .rotate,
            .swipe,
            .smartMagnify
        ]

        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.registerActivity()
            }
            return event
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.registerActivity()
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.registerActivity()
                }
            }
        )
    }

    private func startPollingLoop() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                self.refreshStandbyState()
            }
        }
    }

    private func refreshStandbyState() {
        guard NSApp.isActive else {
            updateReveal(target: 0, animation: .easeOut(duration: wakeDuration))
            return
        }

        if NSApp.modalWindow != nil {
            updateReveal(target: 0, animation: .easeOut(duration: wakeDuration))
            return
        }

        let idleTime = Date().timeIntervalSince(lastActivity)
        if idleTime >= idleDelay {
            updateReveal(target: 1, animation: .linear(duration: revealDuration))
        } else {
            updateReveal(target: 0, animation: .easeOut(duration: wakeDuration))
        }
    }

    private func updateReveal(target: Double, animation: Animation) {
        guard abs(revealAmount - target) > 0.001 else { return }
        withAnimation(animation) {
            revealAmount = target
        }
    }
}

private struct BlossomStandbyBackdrop: View {
    let isPaused: Bool

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let wind = StandbyWind.sample(at: time)
                let size = proxy.size

                ZStack {
                    wallBackground(size: size)
                    branchShadowLayer(size: size, wind: wind)
                    petalLayer(size: size, time: time, wind: wind)
                    foregroundLight(size: size, wind: wind)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
        .ignoresSafeArea()
    }

    private func wallBackground(size: CGSize) -> some View {
        ZStack {
            Color(red: 0.70, green: 0.71, blue: 0.73)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.14),
                    Color.white.opacity(0.04),
                    Color.black.opacity(0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.18),
                    .clear,
                ],
                center: UnitPoint(x: 0.72, y: 0.14),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.65
            )
            .blendMode(.screen)

            Rectangle()
                .fill(Color.black.opacity(0.035))
                .blendMode(.multiply)
        }
    }

    private func foregroundLight(size: CGSize, wind: StandbyWind) -> some View {
        RadialGradient(
            colors: [
                Color.white.opacity(0.12),
                Color.white.opacity(0.04),
                .clear,
            ],
            center: UnitPoint(x: 0.78 + wind.lightX * 0.01, y: 0.10 + wind.lightY * 0.01),
            startRadius: 0,
            endRadius: min(size.width, size.height) * 0.42
        )
        .blendMode(.screen)
    }

    @ViewBuilder
    private func branchShadowLayer(size: CGSize, wind: StandbyWind) -> some View {
        let branchWidth = min(max(size.width * 0.56, 560), 900)
        let baseX = min(size.width * 0.21, 160)
        let baseY = -min(size.height * 0.18, 120)
        let driftX = wind.branchDriftX * 14
        let driftY = wind.branchLift * 10
        let rotation = -2.0 + wind.branchRoll * 1.6
        let scale = 1.0 + wind.branchScale * 0.012

        ZStack {
            branchPass(
                width: branchWidth,
                x: baseX - 42 + driftX * 0.42,
                y: baseY + 26 + driftY * 0.46,
                blur: 26,
                opacity: 0.10,
                rotation: rotation - 0.9,
                scale: scale * 1.02
            )

            branchPass(
                width: branchWidth,
                x: baseX - 16 + driftX * 0.72,
                y: baseY + 10 + driftY * 0.74,
                blur: 12,
                opacity: 0.15,
                rotation: rotation,
                scale: scale
            )

            branchPass(
                width: branchWidth,
                x: baseX + driftX,
                y: baseY + driftY,
                blur: 6,
                opacity: 0.08,
                rotation: rotation + 0.35,
                scale: scale * 0.996
            )
        }
        .mask(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.34),
                    .init(color: .black.opacity(0.88), location: 0.52),
                    .init(color: .clear, location: 0.86),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private func branchPass(
        width: CGFloat,
        x: CGFloat,
        y: CGFloat,
        blur: CGFloat,
        opacity: Double,
        rotation: Double,
        scale: CGFloat
    ) -> some View {
        if let image = StandbySceneAssets.branchShadow {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: width)
                .scaleEffect(scale, anchor: .topTrailing)
                .rotationEffect(.degrees(rotation), anchor: .topTrailing)
                .offset(x: x, y: y)
                .blur(radius: blur)
                .opacity(opacity)
                .blendMode(.multiply)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        } else {
            fallbackBranchShadow(
                width: width,
                x: x,
                y: y,
                blur: blur,
                opacity: opacity
            )
        }
    }

    private func fallbackBranchShadow(
        width: CGFloat,
        x: CGFloat,
        y: CGFloat,
        blur: CGFloat,
        opacity: Double
    ) -> some View {
        FallbackStandbyBranchShape()
            .stroke(
                Color.black.opacity(opacity),
                style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
            )
            .frame(width: width, height: width * 0.5)
            .offset(x: x, y: y)
            .blur(radius: blur)
            .blendMode(.multiply)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func petalLayer(size: CGSize, time: TimeInterval, wind: StandbyWind) -> some View {
        ZStack {
            ForEach(StandbyPetalSeed.catalog) { seed in
                if let snapshot = snapshot(for: seed, size: size, time: time, wind: wind) {
                    standbyPetalShadow(snapshot)
                    standbyPetal(snapshot)
                }
            }
        }
    }

    private func snapshot(
        for seed: StandbyPetalSeed,
        size: CGSize,
        time: TimeInterval,
        wind: StandbyWind
    ) -> StandbyPetalSnapshot? {
        let cycle = cycleProgress(time: time, duration: seed.duration, phase: seed.phase)
        guard cycle < seed.activeSpan else { return nil }

        let progress = cycle / seed.activeSpan
        let eased = 0.08 * progress + 0.92 * pow(progress, 1.26)
        let swing = sin(progress * .pi * 2 + seed.phase * 7.2)
        let flutter = sin(progress * .pi * 4.6 + seed.phase * 3.8)

        let x = size.width * seed.start.x
            + size.width * seed.windX * eased
            + size.width * seed.swing * swing * (1 - progress * 0.45)
            + size.width * seed.swing * 0.32 * flutter
            + wind.petalDriftX * 18
        let y = size.height * seed.start.y
            + size.height * 0.88 * eased
            + size.height * 0.016 * cos(progress * .pi * 3.4 + seed.phase * 2.1)
            + wind.petalLift * 8

        let depth = 0.36 + 0.64 * ((sin(time * 0.58 + seed.phase * 5.3) + 1) * 0.5)
        let rotation = seed.baseRotation
            + eased * 122
            + swing * 12
            + wind.petalRotation * 4.2

        return StandbyPetalSnapshot(
            position: CGPoint(x: x, y: y),
            rotation: rotation,
            scale: seed.scale * (1 + CGFloat(depth) * 0.08),
            opacity: petalOpacity(progress: progress) * seed.opacity,
            size: seed.size,
            shadowOffset: CGSize(
                width: -12 - depth * 10,
                height: 10 + depth * 9
            ),
            shadowBlur: 4 + depth * 5,
            shadowOpacity: (0.12 + (1 - depth) * 0.08) * seed.opacity
        )
    }

    private func standbyPetalShadow(_ snapshot: StandbyPetalSnapshot) -> some View {
        StandbyPetalShape()
            .fill(Color.black.opacity(snapshot.shadowOpacity))
            .frame(width: snapshot.size.width, height: snapshot.size.height)
            .scaleEffect(x: snapshot.scale * 1.08, y: snapshot.scale * 0.84)
            .rotationEffect(.degrees(snapshot.rotation - 10))
            .blur(radius: snapshot.shadowBlur)
            .position(
                x: snapshot.position.x + snapshot.shadowOffset.width,
                y: snapshot.position.y + snapshot.shadowOffset.height
            )
            .blendMode(.multiply)
    }

    private func standbyPetal(_ snapshot: StandbyPetalSnapshot) -> some View {
        StandbyPetalShape()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.96),
                        Color(red: 0.98, green: 0.90, blue: 0.94),
                        Color(red: 0.94, green: 0.76, blue: 0.84),
                    ],
                    startPoint: UnitPoint(x: 0.42, y: 0.02),
                    endPoint: UnitPoint(x: 0.58, y: 1.0)
                )
            )
            .overlay {
                StandbyPetalShape()
                    .stroke(Color.white.opacity(0.32), lineWidth: 0.7)
            }
            .overlay {
                StandbyPetalCreaseShape()
                    .stroke(
                        Color(red: 0.84, green: 0.58, blue: 0.70).opacity(0.22),
                        style: StrokeStyle(lineWidth: 0.7, lineCap: .round)
                    )
            }
            .frame(width: snapshot.size.width, height: snapshot.size.height)
            .scaleEffect(snapshot.scale)
            .rotationEffect(.degrees(snapshot.rotation))
            .opacity(snapshot.opacity)
            .position(snapshot.position)
    }

    private func cycleProgress(time: TimeInterval, duration: Double, phase: Double) -> Double {
        let raw = time / duration + phase
        return raw - floor(raw)
    }

    private func petalOpacity(progress: Double) -> Double {
        if progress < 0.12 {
            return progress / 0.12
        }

        if progress > 0.90 {
            return max(0, (1 - progress) / 0.10)
        }

        return 1
    }
}

private enum StandbySceneAssets {
    static let branchShadow = loadImage(named: "real-blossom-shadow-mask-low", ext: "png")

    private static func loadImage(named name: String, ext: String) -> NSImage? {
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        if let url = Bundle.module.url(forResource: name, withExtension: ext),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return nil
    }
}

private struct StandbyWind {
    let branchDriftX: CGFloat
    let branchLift: CGFloat
    let branchRoll: Double
    let branchScale: CGFloat
    let petalDriftX: CGFloat
    let petalLift: CGFloat
    let petalRotation: Double
    let lightX: CGFloat
    let lightY: CGFloat

    static func sample(at time: TimeInterval) -> StandbyWind {
        let base = sin(time * (.pi * 2 * 0.28))
        let branch = sin(time * (.pi * 2 * 0.54) + 0.9)
        let flutter = sin(time * (.pi * 2 * 0.92) + 1.7)
        let gust = 0.76 + 0.24 * ((sin(time * (.pi * 2 * 0.07)) + 1) * 0.5)

        return StandbyWind(
            branchDriftX: CGFloat((base * 0.56 + branch * 0.18) * gust),
            branchLift: CGFloat((cos(time * (.pi * 2 * 0.28) + 0.3) * 0.46 + branch * 0.14) * gust),
            branchRoll: (base * 0.84 + branch * 0.22 + flutter * 0.08) * gust,
            branchScale: CGFloat((base * 0.24 + branch * 0.12) * gust),
            petalDriftX: CGFloat((base * -0.62 + flutter * -0.20) * gust),
            petalLift: CGFloat((branch * 0.16 + flutter * 0.12) * gust),
            petalRotation: (base * 0.90 + flutter * 0.22) * gust,
            lightX: CGFloat(base * 0.8),
            lightY: CGFloat(branch * 0.6)
        )
    }
}

private struct StandbyPetalSeed: Identifiable {
    let id: Int
    let start: CGPoint
    let windX: CGFloat
    let swing: CGFloat
    let duration: Double
    let activeSpan: Double
    let phase: Double
    let baseRotation: Double
    let opacity: Double
    let scale: CGFloat
    let size: CGSize

    static let catalog: [StandbyPetalSeed] = [
        StandbyPetalSeed(
            id: 0,
            start: CGPoint(x: 0.82, y: 0.18),
            windX: -0.12,
            swing: 0.020,
            duration: 11.8,
            activeSpan: 0.17,
            phase: 0.08,
            baseRotation: -18,
            opacity: 0.90,
            scale: 0.92,
            size: CGSize(width: 18, height: 24)
        ),
        StandbyPetalSeed(
            id: 1,
            start: CGPoint(x: 0.78, y: 0.12),
            windX: -0.14,
            swing: 0.022,
            duration: 13.2,
            activeSpan: 0.14,
            phase: 0.36,
            baseRotation: 10,
            opacity: 0.82,
            scale: 0.88,
            size: CGSize(width: 16, height: 22)
        ),
        StandbyPetalSeed(
            id: 2,
            start: CGPoint(x: 0.86, y: 0.09),
            windX: -0.11,
            swing: 0.018,
            duration: 14.0,
            activeSpan: 0.12,
            phase: 0.64,
            baseRotation: -8,
            opacity: 0.76,
            scale: 0.84,
            size: CGSize(width: 15, height: 20)
        ),
    ]
}

private struct StandbyPetalSnapshot {
    let position: CGPoint
    let rotation: Double
    let scale: CGFloat
    let opacity: Double
    let size: CGSize
    let shadowOffset: CGSize
    let shadowBlur: CGFloat
    let shadowOpacity: Double
}

private struct StandbyMouseActivityBridge: NSViewRepresentable {
    let onActivity: () -> Void

    func makeNSView(context: Context) -> StandbyActivityTrackingView {
        let view = StandbyActivityTrackingView()
        view.onActivity = onActivity
        return view
    }

    func updateNSView(_ nsView: StandbyActivityTrackingView, context: Context) {
        nsView.onActivity = onActivity
    }
}

private final class StandbyActivityTrackingView: NSView {
    var onActivity: (() -> Void)?
    private var trackingAreaRef: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        refreshTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        onActivity?()
    }

    override func mouseMoved(with event: NSEvent) {
        onActivity?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func refreshTrackingArea() {
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingAreaRef = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaRef)
        self.trackingAreaRef = trackingAreaRef
    }
}

private struct StandbyWindowChromeBridge: NSViewRepresentable {
    let isStandbyVisible: Bool

    func makeCoordinator() -> StandbyWindowChromeCoordinator {
        StandbyWindowChromeCoordinator()
    }

    func makeNSView(context: Context) -> StandbyWindowChromeView {
        let view = StandbyWindowChromeView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: StandbyWindowChromeView, context: Context) {
        nsView.coordinator = context.coordinator
        nsView.isStandbyVisible = isStandbyVisible
        nsView.applyWindowStateIfPossible()
    }

    static func dismantleNSView(_ nsView: StandbyWindowChromeView, coordinator: StandbyWindowChromeCoordinator) {
        coordinator.restoreWindowIfNeeded()
    }
}

private final class StandbyWindowChromeView: NSView {
    weak var coordinator: StandbyWindowChromeCoordinator?
    var isStandbyVisible = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.attach(to: window)
        applyWindowStateIfPossible()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            coordinator?.restoreWindowIfNeeded()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func applyWindowStateIfPossible() {
        coordinator?.setStandbyVisible(isStandbyVisible, for: window)
    }
}

private final class StandbyWindowChromeCoordinator {
    private struct SavedState {
        let titleVisibility: NSWindow.TitleVisibility
        let titlebarAppearsTransparent: Bool
        let toolbarVisible: Bool?
        let hasFullSizeContentView: Bool
        let closeHidden: Bool
        let miniaturizeHidden: Bool
        let zoomHidden: Bool
    }

    private weak var window: NSWindow?
    private var savedState: SavedState?
    private var isApplied = false

    func attach(to window: NSWindow?) {
        guard self.window !== window else { return }
        restoreWindowIfNeeded()
        self.window = window
    }

    func setStandbyVisible(_ visible: Bool, for window: NSWindow?) {
        guard let window else { return }
        attach(to: window)
        if visible {
            applyStandbyAppearance(to: window)
        } else {
            restoreWindowIfNeeded()
        }
    }

    func restoreWindowIfNeeded() {
        guard isApplied, let window, let savedState else { return }

        window.titleVisibility = savedState.titleVisibility
        window.titlebarAppearsTransparent = savedState.titlebarAppearsTransparent
        if let toolbarVisible = savedState.toolbarVisible {
            window.toolbar?.isVisible = toolbarVisible
        }
        if !savedState.hasFullSizeContentView {
            window.styleMask.remove(.fullSizeContentView)
        }

        window.standardWindowButton(.closeButton)?.isHidden = savedState.closeHidden
        window.standardWindowButton(.miniaturizeButton)?.isHidden = savedState.miniaturizeHidden
        window.standardWindowButton(.zoomButton)?.isHidden = savedState.zoomHidden

        self.savedState = nil
        isApplied = false
    }

    private func applyStandbyAppearance(to window: NSWindow) {
        if !isApplied {
            savedState = SavedState(
                titleVisibility: window.titleVisibility,
                titlebarAppearsTransparent: window.titlebarAppearsTransparent,
                toolbarVisible: window.toolbar?.isVisible,
                hasFullSizeContentView: window.styleMask.contains(.fullSizeContentView),
                closeHidden: window.standardWindowButton(.closeButton)?.isHidden ?? false,
                miniaturizeHidden: window.standardWindowButton(.miniaturizeButton)?.isHidden ?? false,
                zoomHidden: window.standardWindowButton(.zoomButton)?.isHidden ?? false
            )
        }

        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar?.isVisible = false
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        isApplied = true
    }
}

private struct StandbyPetalShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notch = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.14)
        let leftTip = CGPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.03)
        let leftShoulder = CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.30)
        let leftWaist = CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.76)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        let rightWaist = CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.76)
        let rightShoulder = CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.30)
        let rightTip = CGPoint(x: rect.maxX - rect.width * 0.27, y: rect.minY + rect.height * 0.03)

        var path = Path()
        path.move(to: notch)
        path.addCurve(
            to: leftTip,
            control1: CGPoint(x: rect.midX - rect.width * 0.08, y: rect.minY),
            control2: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.02)
        )
        path.addCurve(
            to: leftShoulder,
            control1: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.07),
            control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.16)
        )
        path.addCurve(
            to: leftWaist,
            control1: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.48),
            control2: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.66)
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: rect.minX + rect.width * 0.31, y: rect.minY + rect.height * 0.98),
            control2: CGPoint(x: rect.midX - rect.width * 0.11, y: rect.maxY)
        )
        path.addCurve(
            to: rightWaist,
            control1: CGPoint(x: rect.midX + rect.width * 0.11, y: rect.maxY),
            control2: CGPoint(x: rect.maxX - rect.width * 0.31, y: rect.minY + rect.height * 0.98)
        )
        path.addCurve(
            to: rightShoulder,
            control1: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.66),
            control2: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.48)
        )
        path.addCurve(
            to: rightTip,
            control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.16),
            control2: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY + rect.height * 0.07)
        )
        path.addCurve(
            to: notch,
            control1: CGPoint(x: rect.maxX - rect.width * 0.34, y: rect.minY + rect.height * 0.02),
            control2: CGPoint(x: rect.midX + rect.width * 0.08, y: rect.minY)
        )
        return path
    }
}

private struct StandbyPetalCreaseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.18))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.10),
            control1: CGPoint(x: rect.midX - rect.width * 0.02, y: rect.minY + rect.height * 0.38),
            control2: CGPoint(x: rect.midX + rect.width * 0.02, y: rect.minY + rect.height * 0.74)
        )
        return path
    }
}

private struct FallbackStandbyBranchShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY - rect.height * 0.08))
            path.addCurve(
                to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.10),
                control1: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.maxY - rect.height * 0.22),
                control2: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.30)
            )
        }
    }
}
