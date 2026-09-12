import AppKit
import SwiftUI

/// While recording: a thin red frame around the region plus a small stop pill with the elapsed time.
/// Both windows belong to this app, which the content filter excludes from capture.
@MainActor
final class RecordingHUD {
    private var frameWindow: NSWindow?
    private var pillWindow: NSPanel?

    func show(region: CGRect, on screen: NSScreen, startedAt: Date, onStop: @escaping @MainActor () -> Void) {
        hide()

        let inset: CGFloat = 3
        let frameRect = region.insetBy(dx: -inset, dy: -inset)
        let frame = NSWindow(contentRect: frameRect, styleMask: .borderless, backing: .buffered, defer: false)
        frame.level = .statusBar
        frame.isOpaque = false
        frame.backgroundColor = .clear
        frame.hasShadow = false
        frame.ignoresMouseEvents = true
        frame.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        frame.isReleasedWhenClosed = false
        frame.contentView = RecordingFrameView(frame: NSRect(origin: .zero, size: frameRect.size))
        frame.orderFrontRegardless()
        frameWindow = frame

        let pillSize = CGSize(width: 150, height: 34)
        let origin = RegionMath.hudOrigin(pillSize: pillSize, region: region, visibleFrame: screen.visibleFrame)
        let pill = NSPanel(contentRect: CGRect(origin: origin, size: pillSize),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        pill.level = .statusBar
        pill.isOpaque = false
        pill.backgroundColor = .clear
        pill.hasShadow = true
        pill.isMovableByWindowBackground = true
        pill.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        pill.isReleasedWhenClosed = false
        pill.contentView = NSHostingView(rootView: RecordingPill(startedAt: startedAt, onStop: onStop))
        pill.orderFrontRegardless()
        pillWindow = pill
    }

    func hide() {
        frameWindow?.orderOut(nil)
        pillWindow?.orderOut(nil)
        frameWindow = nil
        pillWindow = nil
    }
}

final class RecordingFrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
        path.lineWidth = 2
        NSColor.systemRed.setStroke()
        path.stroke()
    }
}

struct RecordingPill: View {
    let startedAt: Date
    let onStop: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 9, height: 9)
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Text(elapsed(context.date))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            Spacer(minLength: 0)
            Button(action: onStop) {
                Text("Stop")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(width: 150, height: 34)
        .background(.black.opacity(0.85), in: Capsule())
        .foregroundStyle(.white)
    }

    private func elapsed(_ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
