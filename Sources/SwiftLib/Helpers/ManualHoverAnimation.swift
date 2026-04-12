import SwiftUI
import Combine
import QuartzCore

@MainActor
final class ManualHoverProgressController: ObservableObject {
    struct Configuration {
        let expandDuration: TimeInterval
        let collapseDuration: TimeInterval
        let framesPerSecond: Double

        static let annotationCard = Configuration(
            expandDuration: 0.18,
            collapseDuration: 0.12,
            framesPerSecond: 120
        )
    }

    @Published private(set) var progress: CGFloat

    private let configuration: Configuration
    private var timer: Timer?
    private var collapseTask: Task<Void, Never>?
    private var startTime: CFTimeInterval = 0
    private var startProgress: CGFloat = 0
    private var targetProgress: CGFloat = 0
    private var duration: TimeInterval = 0

    /// Delay before starting collapse animation.
    /// Bridges momentary hover-state loss caused by SwiftUI tracking-area rebuilds
    /// during frame changes.  Uses a cancellable Task so that a subsequent
    /// `setVisible(true)` can reliably abort the pending collapse.
    private let collapseDelay: TimeInterval = 0.25

    init(initialProgress: CGFloat = 0, configuration: Configuration = .annotationCard) {
        self.progress = ManualHoverMotion.clamp(initialProgress)
        self.configuration = configuration
        self.targetProgress = ManualHoverMotion.clamp(initialProgress)
    }

    deinit {
        timer?.invalidate()
        collapseTask?.cancel()
    }

    func setVisible(_ visible: Bool) {
        collapseTask?.cancel()
        collapseTask = nil

        if visible {
            animate(to: 1)
        } else {
            let delay = collapseDelay
            collapseTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.collapseTask = nil
                self?.animate(to: 0)
            }
        }
    }

    func sync(to visible: Bool) {
        timer?.invalidate()
        timer = nil
        collapseTask?.cancel()
        collapseTask = nil
        let resolved = visible ? CGFloat(1) : CGFloat(0)
        progress = resolved
        startProgress = resolved
        targetProgress = resolved
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func animate(to target: CGFloat) {
        let clampedTarget = ManualHoverMotion.clamp(target)
        if abs(clampedTarget - targetProgress) < 0.0001, timer != nil {
            return
        }

        if abs(clampedTarget - progress) < 0.0001 {
            sync(to: clampedTarget > 0.5)
            return
        }

        timer?.invalidate()
        timer = nil

        startProgress = progress
        targetProgress = clampedTarget
        startTime = CACurrentMediaTime()
        duration = clampedTarget > startProgress
            ? configuration.expandDuration
            : configuration.collapseDuration

        let interval = 1.0 / max(configuration.framesPerSecond, 30)
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                self?.tick(timer: timer)
            }
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    private func tick(timer: Timer) {
        let elapsed = CACurrentMediaTime() - startTime
        let linear = duration <= 0 ? 1 : min(max(CGFloat(elapsed / duration), 0), 1)
        let curved = ManualHoverMotion.primaryCurve(linear)
        progress = startProgress + (targetProgress - startProgress) * curved

        if linear >= 1 {
            progress = targetProgress
            timer.invalidate()
            self.timer = nil
        }
    }
}

enum ManualHoverMotion {
    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    static func primaryCurve(_ progress: CGFloat) -> CGFloat {
        let clamped = clamp(progress)
        if clamped < 0.42 {
            let segment = clamped / 0.42
            return 0.28 * pow(segment, 1.85)
        }

        let segment = (clamped - 0.42) / 0.58
        return 0.28 + (0.72 * (1 - pow(1 - segment, 2.35)))
    }

    static func footerReserve(progress: CGFloat, maxHeight: CGFloat) -> CGFloat {
        maxHeight * primaryCurve(progress)
    }

    static func footerOpacity(progress: CGFloat) -> CGFloat {
        let shifted = remap(progress, from: 0.34, to: 0.88)
        return shifted * shifted * (3 - 2 * shifted)
    }

    static func footerOffset(progress: CGFloat, maxOffset: CGFloat) -> CGFloat {
        maxOffset * (1 - primaryCurve(progress))
    }

    static func hoverFill(progress: CGFloat, maxOpacity: CGFloat) -> CGFloat {
        maxOpacity * remap(progress, from: 0.08, to: 0.72)
    }

    private static func remap(_ progress: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
        guard end > start else { return clamp(progress) }
        return clamp((progress - start) / (end - start))
    }
}