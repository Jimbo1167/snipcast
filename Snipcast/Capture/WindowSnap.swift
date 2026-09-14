import AppKit

/// An on-screen window the selection overlay can snap to.
struct SnapWindow: Sendable, Equatable {
    /// AppKit coordinates (bottom-left origin): global when listed, view-local once handed to the overlay.
    var frame: CGRect
    var appName: String
}

/// Pure helpers behind "click a window to select it" and magnetic selection edges.
///
/// Window bounds from `CGWindowListCopyWindowInfo` use a top-left origin anchored at the
/// primary display, while the overlay works in AppKit's bottom-left global space, so every
/// frame is flipped against the primary display's height on the way in.
enum WindowSnap {
    /// How close (in points) an edge has to be before it pulls onto a candidate.
    static let threshold: CGFloat = 8

    /// Normal app windows on screen, front to back, excluding `ownPID`.
    static func onScreenWindows(ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> [SnapWindow] {
        guard let primary = NSScreen.screens.first,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return windows(fromWindowInfo: info, ownPID: ownPID, primaryHeight: primary.frame.height)
    }

    static func windows(fromWindowInfo info: [[String: Any]], ownPID: pid_t, primaryHeight: CGFloat) -> [SnapWindow] {
        info.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  RegionMath.isUsableSelection(bounds) else { return nil }
            let name = entry[kCGWindowOwnerName as String] as? String ?? ""
            return SnapWindow(frame: appKitRect(fromCGBounds: bounds, primaryHeight: primaryHeight), appName: name)
        }
    }

    static func appKitRect(fromCGBounds bounds: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    /// The frontmost window under `point`. `windows` must be ordered front to back.
    static func window(at point: CGPoint, in windows: [SnapWindow]) -> SnapWindow? {
        windows.first { $0.frame.contains(point) }
    }

    /// Vertical (`xs`) and horizontal (`ys`) edge lines worth snapping to.
    static func edges(of rects: [CGRect]) -> (xs: [CGFloat], ys: [CGFloat]) {
        (rects.flatMap { [$0.minX, $0.maxX] }, rects.flatMap { [$0.minY, $0.maxY] })
    }

    /// `value` pulled onto the nearest candidate within `threshold`, otherwise unchanged.
    static func snap(_ value: CGFloat, to candidates: [CGFloat], threshold: CGFloat = threshold) -> CGFloat {
        guard let nearest = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
              abs(nearest - value) <= threshold else { return value }
        return nearest
    }

    static func snap(_ point: CGPoint, xs: [CGFloat], ys: [CGFloat], threshold: CGFloat = threshold) -> CGPoint {
        CGPoint(x: snap(point.x, to: xs, threshold: threshold), y: snap(point.y, to: ys, threshold: threshold))
    }

    /// `rect` shifted, without resizing, so whichever of its edges is closest to a candidate lands on it.
    static func snapMove(_ rect: CGRect, xs: [CGFloat], ys: [CGFloat], threshold: CGFloat = threshold) -> CGRect {
        func offset(_ low: CGFloat, _ high: CGFloat, _ candidates: [CGFloat]) -> CGFloat {
            let deltas = [low, high].flatMap { edge in candidates.map { $0 - edge } }
            guard let best = deltas.min(by: { abs($0) < abs($1) }), abs(best) <= threshold else { return 0 }
            return best
        }
        return rect.offsetBy(dx: offset(rect.minX, rect.maxX, xs), dy: offset(rect.minY, rect.maxY, ys))
    }
}
