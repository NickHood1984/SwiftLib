import AppKit

struct AnnotationColor: Identifiable {
    let id: String
    let name: String
    let nsColor: NSColor

    static let palette: [AnnotationColor] = [
        .init(id: "#FFDE59", name: "黄色", nsColor: NSColor(red: 1.0, green: 0.87, blue: 0.35, alpha: 0.4)),
        .init(id: "#7ED957", name: "绿色", nsColor: NSColor(red: 0.49, green: 0.85, blue: 0.34, alpha: 0.4)),
        .init(id: "#5CE1E6", name: "蓝色", nsColor: NSColor(red: 0.36, green: 0.88, blue: 0.9, alpha: 0.4)),
        .init(id: "#FF66C4", name: "粉色", nsColor: NSColor(red: 1.0, green: 0.4, blue: 0.77, alpha: 0.4)),
        .init(id: "#FF914D", name: "橙色", nsColor: NSColor(red: 1.0, green: 0.57, blue: 0.3, alpha: 0.4)),
        .init(id: "#CB6CE6", name: "紫色", nsColor: NSColor(red: 0.80, green: 0.42, blue: 0.9, alpha: 0.4)),
    ]

    static func nsColor(for hex: String) -> NSColor {
        palette.first { $0.id == hex }?.nsColor ?? palette[0].nsColor
    }
}
