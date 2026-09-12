import CoreGraphics

/// Pure geometry for turning an AppKit-space selection into ScreenCaptureKit input.
///
/// AppKit screen coordinates have a bottom-left origin in a global space shared by all
/// displays. ScreenCaptureKit's `SCStreamConfiguration.sourceRect` is expressed in points
/// relative to the captured display, with a top-left origin. Encoders also require even
/// pixel dimensions, so the output size is floored to an even number of pixels and the
/// point size is derived back from that so the two always agree.
enum RegionMath {
    struct CaptureGeometry: Equatable {
        /// Region in the display's own coordinate space, top-left origin, in points.
        var sourceRect: CGRect
        /// Output size in pixels. Both dimensions are even.
        var pixelSize: CGSize
    }

    /// Minimum selection size in points; anything smaller is treated as a click, not a drag.
    static let minimumSelection: CGFloat = 8

    static func captureGeometry(selection: CGRect, displayFrame: CGRect, scale: CGFloat) -> CaptureGeometry {
        let clipped = selection.intersection(displayFrame)
        let originX = clipped.minX.rounded(.down)
        let originYTop = (displayFrame.maxY - clipped.maxY).rounded(.down)

        var pixelWidth = (clipped.width * scale).rounded(.down)
        var pixelHeight = (clipped.height * scale).rounded(.down)
        if pixelWidth.truncatingRemainder(dividingBy: 2) != 0 { pixelWidth -= 1 }
        if pixelHeight.truncatingRemainder(dividingBy: 2) != 0 { pixelHeight -= 1 }
        pixelWidth = max(pixelWidth, 2)
        pixelHeight = max(pixelHeight, 2)

        let sourceRect = CGRect(
            x: originX - displayFrame.minX,
            y: originYTop,
            width: pixelWidth / scale,
            height: pixelHeight / scale
        )
        return CaptureGeometry(sourceRect: sourceRect, pixelSize: CGSize(width: pixelWidth, height: pixelHeight))
    }

    /// Rectangle spanned by a drag between two points, normalized to positive size.
    static func dragRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    static func isUsableSelection(_ rect: CGRect) -> Bool {
        rect.width >= minimumSelection && rect.height >= minimumSelection
    }

    /// Where to place the recording HUD pill relative to the region, staying inside the screen.
    static func hudOrigin(pillSize: CGSize, region: CGRect, visibleFrame: CGRect, gap: CGFloat = 10) -> CGPoint {
        let x = min(max(region.midX - pillSize.width / 2, visibleFrame.minX + gap), visibleFrame.maxX - pillSize.width - gap)
        let below = region.minY - gap - pillSize.height
        let y = below >= visibleFrame.minY ? below : min(region.maxY + gap, visibleFrame.maxY - pillSize.height - gap)
        return CGPoint(x: x, y: y)
    }
}
