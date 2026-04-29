import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

private let canvasSize = CGSize(width: 480, height: 480)
private let frameCount = 56
private let frameDelay = 1.0 / 24.0

private struct OceanWaveFrame: View {
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
                FloatingToastPreview(message: "正在导入 PDF…", time: time)
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
    let time: Double

    var body: some View {
        HStack(spacing: 8) {
            IllustratedWaveLoader(time: time)
                .frame(width: 46, height: 24)

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

private struct IllustratedWaveLoader: View {
    let time: Double

    var body: some View {
        let travel = time * 1.65
        let swell = sin(travel * 1.35)
        let drift = cos(travel * 1.05)
        let rearDrift = cos(travel * 1.05 - 0.85)

        ZStack {
            WaveTailShape(swell: rearDrift)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.38, blue: 0.45).opacity(0.44),
                            Color(red: 0.34, green: 0.56, blue: 0.64).opacity(0.70),
                            Color(red: 0.48, green: 0.69, blue: 0.76).opacity(0.84)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(x: -10.5 + rearDrift * 1.3, y: 7.0)

            WaveCrestShape(swell: swell)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.42, blue: 0.55),
                            Color(red: 0.28, green: 0.60, blue: 0.73),
                            Color(red: 0.58, green: 0.80, blue: 0.86)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .offset(x: -0.8 + drift * 0.9, y: 1.3)

            WaveFoamFillShape(swell: swell)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color(red: 0.89, green: 0.96, blue: 0.98).opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .offset(x: 0.2 + drift * 0.7, y: 0.2)

            FoamRidgeShape(swell: swell)
                .stroke(
                    Color.white.opacity(0.94),
                    style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
                )
                .offset(x: 0.1 + drift * 0.5, y: -0.2)

            FoamSprayShape(swell: swell)
                .fill(Color.white.opacity(0.88))
                .offset(x: 0.3 + drift * 0.5, y: -0.2)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.10), radius: 2, y: 1)
    }
}

private struct WaveTailShape: Shape {
    let swell: Double

    func path(in rect: CGRect) -> Path {
        let s = CGFloat(swell)

        return Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.00, y: rect.maxY - rect.height * 0.12))
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.maxY - rect.height * (0.36 + s * 0.02)),
                control1: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.maxY - rect.height * 0.60),
                control2: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.maxY - rect.height * 0.46)
            )
            path.addCurve(
                to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY - rect.height * 0.12),
                control1: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.maxY - rect.height * 0.20),
                control2: CGPoint(x: rect.maxX - rect.width * 0.19, y: rect.maxY - rect.height * 0.28)
            )
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct WaveCrestShape: Shape {
    let swell: Double

    func path(in rect: CGRect) -> Path {
        let s = CGFloat(swell)

        return Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.maxY - rect.height * 0.07))
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.maxY - rect.height * (0.78 + s * 0.03)),
                control1: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.70),
                control2: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.98)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.maxY - rect.height * 0.18),
                control1: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.maxY - rect.height * 0.36),
                control2: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.maxY - rect.height * 0.00)
            )
            path.addCurve(
                to: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.maxY - rect.height * 0.08),
                control1: CGPoint(x: rect.minX + rect.width * 0.79, y: rect.maxY - rect.height * 0.34),
                control2: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.maxY - rect.height * 0.20)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.02),
                control1: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY - rect.height * 0.00),
                control2: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.00)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.maxY - rect.height * 0.07),
                control1: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY - rect.height * 0.04),
                control2: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.maxY - rect.height * 0.05)
            )
            path.closeSubpath()
        }
    }
}

private struct WaveFoamFillShape: Shape {
    let swell: Double

    func path(in rect: CGRect) -> Path {
        let s = CGFloat(swell)

        return Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.23, y: rect.maxY - rect.height * 0.45))
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.47, y: rect.maxY - rect.height * (0.79 + s * 0.02)),
                control1: CGPoint(x: rect.minX + rect.width * 0.29, y: rect.maxY - rect.height * 0.75),
                control2: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.94)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.maxY - rect.height * 0.47),
                control1: CGPoint(x: rect.minX + rect.width * 0.56, y: rect.maxY - rect.height * 0.73),
                control2: CGPoint(x: rect.minX + rect.width * 0.60, y: rect.maxY - rect.height * 0.59)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.maxY - rect.height * 0.21),
                control1: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.maxY - rect.height * 0.33),
                control2: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.maxY - rect.height * 0.23)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.23, y: rect.maxY - rect.height * 0.45),
                control1: CGPoint(x: rect.minX + rect.width * 0.64, y: rect.maxY - rect.height * 0.28),
                control2: CGPoint(x: rect.minX + rect.width * 0.37, y: rect.maxY - rect.height * 0.31)
            )
            path.closeSubpath()
        }
    }
}

private struct FoamRidgeShape: Shape {
    let swell: Double

    func path(in rect: CGRect) -> Path {
        let s = CGFloat(swell)

        return Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.maxY - rect.height * 0.43))
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.47, y: rect.maxY - rect.height * (0.81 + s * 0.02)),
                control1: CGPoint(x: rect.minX + rect.width * 0.31, y: rect.maxY - rect.height * 0.79),
                control2: CGPoint(x: rect.minX + rect.width * 0.39, y: rect.maxY - rect.height * 0.98)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.maxY - rect.height * 0.20),
                control1: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.maxY - rect.height * 0.66),
                control2: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.maxY - rect.height * 0.17)
            )
        }
    }
}

private struct FoamSprayShape: Shape {
    let swell: Double

    func path(in rect: CGRect) -> Path {
        let s = CGFloat(swell)

        return Path { path in
            path.addEllipse(in: CGRect(
                x: rect.minX + rect.width * 0.74,
                y: rect.maxY - rect.height * (0.28 + s * 0.02),
                width: rect.width * 0.05,
                height: rect.height * 0.05
            ))
            path.addEllipse(in: CGRect(
                x: rect.minX + rect.width * 0.81,
                y: rect.maxY - rect.height * 0.17,
                width: rect.width * 0.04,
                height: rect.height * 0.04
            ))
            path.addEllipse(in: CGRect(
                x: rect.minX + rect.width * 0.86,
                y: rect.maxY - rect.height * 0.09,
                width: rect.width * 0.03,
                height: rect.height * 0.03
            ))
        }
    }
}

@MainActor
private func renderFrame(at time: Double) -> CGImage? {
    let renderer = ImageRenderer(content: OceanWaveFrame(time: time))
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
        throw NSError(domain: "render-ocean-wave-loader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create GIF destination"])
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
        throw NSError(domain: "render-ocean-wave-loader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize GIF"])
    }
}

let outputPath = CommandLine.arguments.dropFirst().first ?? "/tmp/ocean-wave-loader.gif"
let outputURL = URL(fileURLWithPath: outputPath)
try await MainActor.run {
    try writeGIF(to: outputURL)
}
print(outputURL.path)
