import SwiftUI

struct NeonBreathingLoader: View {
    let diameter: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let phase = time * 3.2
            let spacing = max(2, diameter * 0.09)
            let beadSize = max(3, floor((diameter - spacing * 2) / 3.0))

            VStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { column in
                            glowingBead(
                                row: row,
                                column: column,
                                phase: phase,
                                size: beadSize
                            )
                        }
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            .compositingGroup()
        }
    }

    private func glowingBead(
        row: Int,
        column: Int,
        phase: Double,
        size: CGFloat
    ) -> some View {
        let index = Double(row * 3 + column)
        let localPhase = phase - index * 0.36
        let pulse = max(0, sin(localPhase))
        let trailing = max(0, sin(localPhase - 0.58)) * 0.34
        let intensity = min(1, pow(pulse, 1.7) + trailing)
        let scale = 0.72 + intensity * 0.34

        return Circle()
            .fill(beadFill(intensity: intensity))
            .frame(width: size, height: size)
            .opacity(intensity > 0.05 ? 1 : 0)
            .scaleEffect(scale)
            .shadow(
                color: Color(red: 1.0, green: 0.58, blue: 0.16).opacity(intensity * 0.85),
                radius: size * (0.24 + intensity * 1.10)
            )
            .overlay {
                Circle()
                    .fill(Color.white.opacity(intensity * 0.32))
                    .frame(width: size * 0.42, height: size * 0.42)
                    .offset(x: -size * 0.12, y: -size * 0.12)
            }
            .overlay {
                Circle()
                    .fill(Color(red: 1.0, green: 0.62, blue: 0.18).opacity(intensity * 0.14))
                    .blur(radius: size * 0.36)
                    .scaleEffect(1.0 + intensity * 0.38)
            }
    }

    private func beadFill(intensity: Double) -> RadialGradient {
        RadialGradient(
            colors: [
                Color(red: 1.00, green: 0.84, blue: 0.58).opacity(intensity * 0.95),
                Color(red: 1.00, green: 0.60, blue: 0.18).opacity(intensity),
                Color(red: 0.92, green: 0.32, blue: 0.06).opacity(intensity * 0.92)
            ],
            center: .center,
            startRadius: 0,
            endRadius: sizeAwareRadius(for: diameter)
        )
    }

    private func sizeAwareRadius(for diameter: CGFloat) -> CGFloat {
        max(4, diameter * 0.22)
    }
}
