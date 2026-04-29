import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

private let canvasSize = CGSize(width: 480, height: 480)
private let frameCount = 48
private let frameDelay = 1.0 / 24.0

private struct NeonLoaderFrame: View {
    let time: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.08),
                    Color(red: 0.05, green: 0.07, blue: 0.12),
                    Color(red: 0.03, green: 0.03, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ZStack(alignment: .top) {
                pageShell
                FloatingToastPreview(message: "正在导入 PDF…", isSpinning: true, time: time)
                    .padding(.top, 18)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private var pageShell: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 11) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 78, height: 18)

                ForEach(0..<7, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(index == 0 ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                        .frame(width: 102, height: 22)
                }

                Spacer()
            }
            .padding(14)
            .frame(width: 130)
            .background(Color.white.opacity(0.03))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.09))
                        .frame(width: 110, height: 20)
                    Spacer()
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 68, height: 20)
                }

                ForEach(0..<5, id: \.self) { row in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(row == 0 ? 0.08 : 0.05))
                        .frame(height: row == 0 ? 42 : 34)
                }

                Spacer()
            }
            .padding(16)
        }
        .frame(width: 430, height: 300)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.10, green: 0.11, blue: 0.15).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 30, y: 16)
    }
}

private struct FloatingToastPreview: View {
    let message: String
    let isSpinning: Bool
    let time: Double

    var body: some View {
        HStack(spacing: 10) {
            if isSpinning {
                NeonLoaderShape(diameter: 20, time: time)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            }

            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            Capsule(style: .continuous)
                .fill(Color(red: 0.10, green: 0.08, blue: 0.06).opacity(0.96))
                .shadow(color: Color.black.opacity(0.16), radius: 10, y: 4)
                .shadow(color: Color.orange.opacity(0.08), radius: 18, y: 0)
        }
    }
}

private struct NeonLoaderShape: View {
    let diameter: CGFloat
    let time: Double

    var body: some View {
        let phase = time * 4.2
        let gap = max(1, diameter * 0.07)
        let pixelSize = floor((diameter - gap * 2) / 3.0)

        return VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { column in
                        wavePixel(
                            row: row,
                            column: column,
                            phase: phase,
                            size: pixelSize
                        )
                    }
                }
            }
        }
        .compositingGroup()
    }

    private func wavePixel(
        row: Int,
        column: Int,
        phase: Double,
        size: CGFloat
    ) -> some View {
        let rowBias = Double(2 - row) * 0.34
        let columnDelay = Double(column) * 0.72
        let localPhase = phase - columnDelay - rowBias
        let crest = max(0, sin(localPhase))
        let body = max(0, sin(localPhase - 0.55)) * 0.42
        let brightness = pow(crest, 1.45) + body
        let clamped = min(1, brightness)
        let verticalFloat = -sin(localPhase) * size * 0.12

        return Rectangle()
            .fill(AnyShapeStyle(pixelFill(brightness: clamped)))
            .frame(width: size, height: size)
            .opacity(clamped > 0.03 ? 1 : 0)
            .offset(y: verticalFloat)
            .shadow(color: Color(red: 1.0, green: 0.52, blue: 0.08).opacity(clamped * 0.92), radius: size * (0.14 + clamped * 0.72))
            .overlay {
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.62, blue: 0.16).opacity(clamped * 0.12))
                    .blur(radius: size * 0.16)
                    .scaleEffect(1.02 + clamped * 0.22)
            }
    }

    private func pixelFill(brightness: Double) -> LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.40, blue: 0.06).opacity(brightness * 0.82),
                Color(red: 1.00, green: 0.54, blue: 0.08).opacity(brightness),
                Color(red: 1.00, green: 0.66, blue: 0.16).opacity(brightness * 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

@MainActor
private func renderFrame(at time: Double) -> CGImage? {
    let renderer = ImageRenderer(content: NeonLoaderFrame(time: time))
    renderer.proposedSize = ProposedViewSize(canvasSize)
    renderer.scale = 2
    return renderer.cgImage
}

@MainActor
private func writeGIF(to outputURL: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.gif.identifier as CFString,
        frameCount,
        nil
    ) else {
        throw NSError(domain: "render-neon-loader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create GIF destination"])
    }

    let gifProperties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFLoopCount: 0
        ]
    ]
    CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

    for index in 0..<frameCount {
        let time = Double(index) * frameDelay
        guard let image = renderFrame(at: time) else { continue }
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay
            ]
        ]
        CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
    }

    if !CGImageDestinationFinalize(destination) {
        throw NSError(domain: "render-neon-loader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize GIF"])
    }
}

let outputPath = CommandLine.arguments.dropFirst().first ?? "/tmp/neon-loader-preview.gif"
let outputURL = URL(fileURLWithPath: outputPath)
try await MainActor.run {
    try writeGIF(to: outputURL)
}
print(outputURL.path)
