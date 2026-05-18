import SwiftUI

struct DraggableSegmentedControl<T: Hashable>: View {
    @Binding var selection: T
    let items: [(label: String, value: T)]

    @State private var dragIndex: Int?

    private var selectedIndex: Int {
        items.firstIndex(where: { $0.value == selection }) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let segmentWidth = geo.size.width / CGFloat(items.count)
            let activeIndex = dragIndex ?? selectedIndex

            ZStack(alignment: .leading) {
                // Sliding indicator
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: segmentWidth - 4, height: 24)
                    .offset(x: CGFloat(activeIndex) * segmentWidth + 2)
                    .animation(.easeInOut(duration: 0.2), value: activeIndex)

                // Labels
                HStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { index in
                        Text(items[index].label)
                            .font(.caption)
                            .fontWeight(activeIndex == index ? .medium : .regular)
                            .foregroundStyle(activeIndex == index ? Color.accentColor : .secondary)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .animation(.easeInOut(duration: 0.15), value: activeIndex)
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let index = Int(value.location.x / segmentWidth)
                        let clamped = max(0, min(items.count - 1, index))
                        if dragIndex != clamped {
                            dragIndex = clamped
                        }
                    }
                    .onEnded { _ in
                        if let idx = dragIndex {
                            selection = items[idx].value
                        }
                        dragIndex = nil
                    }
            )
        }
        .frame(height: 28)
    }
}
