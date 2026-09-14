import CoreGraphics
import Testing
@testable import Snipcast

struct WindowSnapTests {
    @Test func flipsCGWindowBoundsIntoAppKitSpace() {
        // 400×300 window 50pt below the top of a 900pt-tall primary display.
        let r = WindowSnap.appKitRect(fromCGBounds: CGRect(x: 100, y: 50, width: 400, height: 300), primaryHeight: 900)
        #expect(r == CGRect(x: 100, y: 550, width: 400, height: 300))
    }

    @Test func keepsOnlyVisibleNormalWindowsFromOtherApps() {
        func entry(pid: pid_t, layer: Int = 0, alpha: Double = 1, bounds: CGRect, name: String) -> [String: Any] {
            [
                kCGWindowOwnerPID as String: pid,
                kCGWindowLayer as String: layer,
                kCGWindowAlpha as String: alpha,
                kCGWindowBounds as String: bounds.dictionaryRepresentation,
                kCGWindowOwnerName as String: name,
            ]
        }
        let info = [
            entry(pid: 10, bounds: CGRect(x: 0, y: 0, width: 800, height: 600), name: "Safari"),
            entry(pid: 99, bounds: CGRect(x: 0, y: 0, width: 800, height: 600), name: "Snipcast"),
            entry(pid: 11, layer: 25, bounds: CGRect(x: 0, y: 0, width: 1440, height: 30), name: "Menubar"),
            entry(pid: 12, alpha: 0, bounds: CGRect(x: 0, y: 0, width: 300, height: 300), name: "Ghost"),
            entry(pid: 13, bounds: CGRect(x: 0, y: 0, width: 4, height: 4), name: "Speck"),
            entry(pid: 14, bounds: CGRect(x: 200, y: 100, width: 500, height: 400), name: "Notes"),
        ]
        let windows = WindowSnap.windows(fromWindowInfo: info, ownPID: 99, primaryHeight: 900)
        #expect(windows.map(\.appName) == ["Safari", "Notes"])
        #expect(windows[1].frame == CGRect(x: 200, y: 400, width: 500, height: 400))
    }

    @Test func picksFrontmostWindowUnderPoint() {
        let front = SnapWindow(frame: CGRect(x: 100, y: 100, width: 200, height: 200), appName: "Front")
        let back = SnapWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), appName: "Back")
        #expect(WindowSnap.window(at: CGPoint(x: 150, y: 150), in: [front, back]) == front)
        #expect(WindowSnap.window(at: CGPoint(x: 500, y: 500), in: [front, back]) == back)
        #expect(WindowSnap.window(at: CGPoint(x: 5000, y: 5000), in: [front, back]) == nil)
    }

    @Test func snapsOnlyWithinThreshold() {
        #expect(WindowSnap.snap(105, to: [0, 100, 200]) == 100)
        #expect(WindowSnap.snap(120, to: [0, 100, 200]) == 120)
        #expect(WindowSnap.snap(CGPoint(x: 197, y: 43), xs: [200], ys: [60]) == CGPoint(x: 200, y: 43))
    }

    @Test func moveSnapsNearestEdgeWithoutResizing() {
        let rect = CGRect(x: 100, y: 100, width: 50, height: 50)
        // Left edge is 5pt from 95, right edge is 3pt from 153: the right edge wins.
        #expect(WindowSnap.snapMove(rect, xs: [95, 153], ys: [0]) == CGRect(x: 103, y: 100, width: 50, height: 50))
        // An edge already on a line stays put even if the other edge is near another line.
        #expect(WindowSnap.snapMove(rect, xs: [100, 147], ys: []) == rect)
    }
}
