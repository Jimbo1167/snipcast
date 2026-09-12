import CoreGraphics
import Testing
@testable import Snipcast

struct RegionMathTests {
    @Test func convertsAppKitRectToTopLeftDisplaySpace() {
        // A 1440×900 point display at the AppKit origin, 2× Retina.
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let selection = CGRect(x: 100, y: 700, width: 200, height: 100) // top edge at y=800 → 100pt from the top
        let g = RegionMath.captureGeometry(selection: selection, displayFrame: display, scale: 2)
        #expect(g.sourceRect == CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(g.pixelSize == CGSize(width: 400, height: 200))
    }

    @Test func offsetsForSecondaryDisplay() {
        // Secondary display to the right of the primary and shifted up 200 points.
        let display = CGRect(x: 1440, y: 200, width: 1920, height: 1080)
        let selection = CGRect(x: 1540, y: 300, width: 300, height: 200)
        let g = RegionMath.captureGeometry(selection: selection, displayFrame: display, scale: 1)
        #expect(g.sourceRect.origin == CGPoint(x: 100, y: 1280 - 500))
        #expect(g.pixelSize == CGSize(width: 300, height: 200))
    }

    @Test func floorsToEvenPixels() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let selection = CGRect(x: 0, y: 0, width: 201.5, height: 99.5)
        let g = RegionMath.captureGeometry(selection: selection, displayFrame: display, scale: 2)
        #expect(g.pixelSize == CGSize(width: 402, height: 198))
        #expect(g.sourceRect.size == CGSize(width: 201, height: 99))
    }

    @Test func clipsSelectionToDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let selection = CGRect(x: 900, y: -50, width: 300, height: 200)
        let g = RegionMath.captureGeometry(selection: selection, displayFrame: display, scale: 1)
        #expect(g.sourceRect == CGRect(x: 900, y: 850, width: 100, height: 150))
    }

    @Test func dragRectNormalizesDirection() {
        let r = RegionMath.dragRect(from: CGPoint(x: 50, y: 60), to: CGPoint(x: 10, y: 20))
        #expect(r == CGRect(x: 10, y: 20, width: 40, height: 40))
        #expect(RegionMath.isUsableSelection(r))
        #expect(!RegionMath.isUsableSelection(CGRect(x: 0, y: 0, width: 3, height: 40)))
    }

    @Test func hudPrefersBelowRegionAndFlipsAboveNearBottom() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let pill = CGSize(width: 150, height: 34)
        let mid = RegionMath.hudOrigin(pillSize: pill, region: CGRect(x: 400, y: 300, width: 200, height: 100), visibleFrame: visible)
        #expect(mid == CGPoint(x: 425, y: 256))
        let low = RegionMath.hudOrigin(pillSize: pill, region: CGRect(x: 400, y: 10, width: 200, height: 100), visibleFrame: visible)
        #expect(low.y == 120)
        let edge = RegionMath.hudOrigin(pillSize: pill, region: CGRect(x: 950, y: 300, width: 40, height: 100), visibleFrame: visible)
        #expect(edge == CGPoint(x: 840, y: 256))
    }
}

struct EditableRegionTests {
    let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test func handlesSitOnEdgesAndCorners() {
        #expect(RegionMath.Handle.topLeft.point(in: rect) == CGPoint(x: 100, y: 200))
        #expect(RegionMath.Handle.bottom.point(in: rect) == CGPoint(x: 200, y: 100))
        #expect(RegionMath.handle(at: CGPoint(x: 305, y: 150), in: rect) == .right)
        #expect(RegionMath.handle(at: CGPoint(x: 200, y: 150), in: rect) == nil)
    }

    @Test func resizeKeepsOppositeEdgesFixed() {
        let r = RegionMath.resize(rect, handle: .right, to: CGPoint(x: 350, y: 999))
        #expect(r == CGRect(x: 100, y: 100, width: 250, height: 100))
        let c = RegionMath.resize(rect, handle: .topLeft, to: CGPoint(x: 50, y: 250))
        #expect(c == CGRect(x: 50, y: 100, width: 250, height: 150))
    }

    @Test func resizePastFarEdgeFlipsInsteadOfGoingNegative() {
        let r = RegionMath.resize(rect, handle: .left, to: CGPoint(x: 340, y: 0))
        #expect(r == CGRect(x: 300, y: 100, width: 40, height: 100))
    }

    @Test func moveStaysInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let r = RegionMath.move(rect, by: CGPoint(x: 500, y: -500), within: bounds)
        #expect(r == CGRect(x: 200, y: 0, width: 200, height: 100))
    }
}
