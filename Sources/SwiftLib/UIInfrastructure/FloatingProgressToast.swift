import SwiftUI
import AppKit

struct FloatingProgressToast: View {
    let message: String
    let isSpinning: Bool
    var onCancel: (() -> Void)?

    var body: some View {
        HStack(spacing: SLDesign.Spacing.lg) {
            if isSpinning {
                NeonBreathingLoader(diameter: 20)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            }

            Text(message)
                .font(.slCaption)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if isSpinning, let onCancel {
                Divider()
                    .frame(height: 12)
                    .padding(.horizontal, SLDesign.Spacing.tiny)
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("取消刷新")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, SLDesign.Spacing.md)
        .background {
            Capsule(style: .continuous)
                .fill(backgroundColor)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .shadow(color: isSpinning ? Color.orange.opacity(0.08) : .clear, radius: 18, y: 0)
        .padding(.top, SLDesign.Spacing.lg)
    }

    private var backgroundColor: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isSpinning {
                return isDark
                    ? NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.06, alpha: 0.94)
                    : NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.90, alpha: 0.96)
            }
            return NSColor.controlBackgroundColor
        })
    }
}
