import SwiftUI

enum CoachMarkStep: Hashable {
    case citationStyle
    case toolbarImport
    case sidebarCollections
    case sidebarTags
}

struct CoachMarkAnchorKey: PreferenceKey {
    static var defaultValue: [CoachMarkStep: Anchor<CGRect>] = [:]

    static func reduce(value: inout [CoachMarkStep: Anchor<CGRect>], nextValue: () -> [CoachMarkStep: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct CoachMarkAnchorModifier: ViewModifier {
    let step: CoachMarkStep

    func body(content: Content) -> some View {
        content.anchorPreference(key: CoachMarkAnchorKey.self, value: .bounds) {
            [step: $0]
        }
    }
}

extension View {
    func coachMarkAnchor(_ step: CoachMarkStep) -> some View {
        modifier(CoachMarkAnchorModifier(step: step))
    }
}

final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    @Published var showWelcomeWizard = false
    @Published var activeCoachMark: CoachMarkStep?

    private init() {}

    func triggerOnboardingIfNeeded() {}

    func advanceCoachMarks() {}

    func completeCurrentCoachMark() {
        activeCoachMark = nil
    }

    func skipAll() {
        activeCoachMark = nil
        showWelcomeWizard = false
        SwiftLibPreferences.onboardingCompleted = true
    }
}

struct WelcomeWizardView: View {
    @ObservedObject var onboarding: OnboardingManager

    var body: some View {
        EmptyView()
    }
}

struct CoachMarkOverlay: View {
    let step: CoachMarkStep
    let anchors: [CoachMarkStep: Anchor<CGRect>]
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        EmptyView()
    }
}