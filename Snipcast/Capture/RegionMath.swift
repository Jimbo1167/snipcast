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

// MARK: - Editable region

extension RegionMath {
    enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var movesLeft: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
        var movesRight: Bool { [.topRight, .right, .bottomRight].contains(self) }
        var movesTop: Bool { [.topLeft, .top, .topRight].contains(self) }
        var movesBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }

        /// Handle centre for `rect` in AppKit (bottom-left origin) coordinates.
        func point(in rect: CGRect) -> CGPoint {
            let x: CGFloat = movesLeft ? rect.minX : movesRight ? rect.maxX : rect.midX
            let y: CGFloat = movesBottom ? rect.minY : movesTop ? rect.maxY : rect.midY
            return CGPoint(x: x, y: y)
        }
    }

    static let handleHitRadius: CGFloat = 7

    static func handle(at point: CGPoint, in rect: CGRect) -> Handle? {
        Handle.allCases.first { h in
            let c = h.point(in: rect)
            return abs(c.x - point.x) <= handleHitRadius && abs(c.y - point.y) <= handleHitRadius
        }
    }

    /// `anchor` resized so that `handle` follows `point`; the opposite edges stay put.
    /// Dragging past the far edge flips the rectangle rather than producing negative size.
    static func resize(_ anchor: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        var minX = anchor.minX, maxX = anchor.maxX, minY = anchor.minY, maxY = anchor.maxY
        if handle.movesLeft { minX = point.x }
        if handle.movesRight { maxX = point.x }
        if handle.movesBottom { minY = point.y }
        if handle.movesTop { maxY = point.y }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    /// `rect` shifted by `delta`, kept fully inside `bounds`.
    static func move(_ rect: CGRect, by delta: CGPoint, within bounds: CGRect) -> CGRect {
        var r = rect.offsetBy(dx: delta.x, dy: delta.y)
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r
    }
}
