import CoreGraphics

enum ReaderActionBarContext {
    case pdf
    case web
}

enum ReaderActionBarHorizontalAnchor {
    case center
    case trailing
}

struct ReaderActionBarMetrics: Equatable {
    let toolbarWidth: CGFloat
    let buttonWidth: CGFloat
    let buttonHeight: CGFloat
    let buttonIconSize: CGFloat
    let colorDotSize: CGFloat
    let colorButtonWidth: CGFloat
    let topRowSpacing: CGFloat
    let topRowHorizontalPadding: CGFloat
    let topRowVerticalPadding: CGFloat
    let dividerHorizontalPadding: CGFloat
    let separatorHeight: CGFloat
    let separatorHorizontalPadding: CGFloat
    let editorHorizontalPadding: CGFloat
    let editorTopPadding: CGFloat
    let editorVerticalPadding: CGFloat
    let editorCornerRadius: CGFloat
    let actionRowSpacing: CGFloat
    let actionRowHorizontalPadding: CGFloat
    let actionRowVerticalPadding: CGFloat
    let secondaryFontSize: CGFloat
    let placeholderFontSize: CGFloat
    let placeholderIconSize: CGFloat
    let saveButtonHorizontalPadding: CGFloat
    let saveButtonVerticalPadding: CGFloat
    let toolbarCornerRadius: CGFloat
    let buttonCornerRadius: CGFloat
    let selectionEditorMaxHeight: CGFloat
    let annotationEditorMaxHeight: CGFloat
    let placementGap: CGFloat
    let edgeMargin: CGFloat

    var topRowHeight: CGFloat {
        buttonHeight + (topRowVerticalPadding * 2)
    }

    static func resolve(for context: ReaderActionBarContext, viewportWidth: CGFloat) -> ReaderActionBarMetrics {
        let isCompact = viewportWidth > 0 && viewportWidth < 720
        let edgeMargin: CGFloat = context == .pdf ? 8 : 6
        let baseWidth: CGFloat = isCompact ? 296 : 340
        let maxAllowedWidth = viewportWidth > 0
            ? max(252, viewportWidth - (edgeMargin * 2) - 12)
            : baseWidth

        return ReaderActionBarMetrics(
            toolbarWidth: min(baseWidth, maxAllowedWidth),
            buttonWidth: isCompact ? 26 : 30,
            buttonHeight: isCompact ? 24 : 28,
            buttonIconSize: isCompact ? 12 : 13,
            colorDotSize: isCompact ? 14 : 16,
            colorButtonWidth: isCompact ? 20 : 22,
            topRowSpacing: 2,
            topRowHorizontalPadding: isCompact ? 4 : 5,
            topRowVerticalPadding: isCompact ? 2 : 3,
            dividerHorizontalPadding: isCompact ? 6 : 8,
            separatorHeight: isCompact ? 14 : 16,
            separatorHorizontalPadding: isCompact ? 1.5 : 2,
            editorHorizontalPadding: isCompact ? 6 : 8,
            editorTopPadding: isCompact ? 5 : 6,
            editorVerticalPadding: isCompact ? 5 : 6,
            editorCornerRadius: isCompact ? 5 : 6,
            actionRowSpacing: isCompact ? 6 : 8,
            actionRowHorizontalPadding: isCompact ? 8 : 10,
            actionRowVerticalPadding: isCompact ? 5 : 6,
            secondaryFontSize: isCompact ? 10 : 11,
            placeholderFontSize: isCompact ? 10 : 11,
            placeholderIconSize: isCompact ? 9 : 10,
            saveButtonHorizontalPadding: isCompact ? 10 : 12,
            saveButtonVerticalPadding: isCompact ? 3 : 4,
            toolbarCornerRadius: isCompact ? 7 : 9,
            buttonCornerRadius: isCompact ? 4 : 5,
            selectionEditorMaxHeight: isCompact ? 150 : 180,
            annotationEditorMaxHeight: isCompact ? 136 : 160,
            placementGap: {
                switch context {
                case .pdf:
                    return isCompact ? 3 : 4
                case .web:
                    return isCompact ? 14 : 20
                }
            }(),
            edgeMargin: edgeMargin
        )
    }
}

struct SelectionToolbarLayout: Equatable {
    var origin: CGPoint
    var visible: Bool
    var metrics: ReaderActionBarMetrics

    static func anchored(
        to selectionRect: CGRect?,
        overlaySize: CGSize,
        metrics: ReaderActionBarMetrics,
        horizontalAnchor: ReaderActionBarHorizontalAnchor,
        fallbackToTop: Bool = false
    ) -> SelectionToolbarLayout? {
        guard overlaySize.width > 0, overlaySize.height > 0 else {
            return nil
        }

        let edgeMargin = metrics.edgeMargin
        let maxOriginX = max(edgeMargin, overlaySize.width - metrics.toolbarWidth - edgeMargin)
        let centeredOriginX = min(
            max((overlaySize.width - metrics.toolbarWidth) / 2, edgeMargin),
            maxOriginX
        )

        guard let selectionRect, selectionRect.width >= 1, selectionRect.height >= 1 else {
            return SelectionToolbarLayout(
                origin: CGPoint(x: centeredOriginX, y: edgeMargin),
                visible: fallbackToTop,
                metrics: metrics
            )
        }

        let visibleRect = CGRect(origin: .zero, size: overlaySize)
        guard selectionRect.intersects(visibleRect) else {
            return SelectionToolbarLayout(origin: .zero, visible: false, metrics: metrics)
        }

        let anchorX: CGFloat
        switch horizontalAnchor {
        case .center:
            anchorX = selectionRect.midX
        case .trailing:
            anchorX = selectionRect.maxX
        }

        let desiredOriginX = anchorX - (metrics.toolbarWidth / 2)
        let originX = min(max(desiredOriginX, edgeMargin), maxOriginX)
        let maxOriginY = max(edgeMargin, overlaySize.height - metrics.topRowHeight - edgeMargin)

        let belowOriginY = selectionRect.maxY + metrics.placementGap
        let aboveOriginY = selectionRect.minY - metrics.placementGap - metrics.topRowHeight

        let originY: CGFloat
        if belowOriginY + metrics.topRowHeight <= overlaySize.height - edgeMargin {
            originY = belowOriginY
        } else if aboveOriginY >= edgeMargin {
            originY = aboveOriginY
        } else {
            originY = min(max(belowOriginY, edgeMargin), maxOriginY)
        }

        return SelectionToolbarLayout(
            origin: CGPoint(x: originX, y: originY),
            visible: true,
            metrics: metrics
        )
    }
}