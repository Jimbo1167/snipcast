import AppKit

struct RegionSelection: Sendable {
    /// AppKit global coordinates.
    var rect: CGRect
    var displayID: CGDirectDisplayID
}

/// Full-screen overlays on every display that let the user drag out a rectangle.
/// Escape cancels; Return (or a plain click) accepts the suggested region if one is shown.
@MainActor
final class RegionSelector {
    private var windows: [SelectionWindow] = []
    private var continuation: CheckedContinuation<RegionSelection?, Never>?

    var isActive: Bool { continuation != nil }

    func select(suggested: StoredRegion?) async -> RegionSelection? {
        if isActive { cancel() }
        return await withCheckedContinuation { cont in
            continuation = cont
            for screen in NSScreen.screens {
                let suggestion = suggested.flatMap { s -> CGRect? in
                    guard s.displayID == screen.displayID, screen.frame.intersects(s.rect) else { return nil }
                    return s.rect
                }
                let window = SelectionWindow(screen: screen, suggested: suggestion) { [weak self] result in
                    self?.finish(result)
                }
                windows.append(window)
                window.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)
            windows.first { $0.suggestedRect != nil }?.makeKey()
            if NSApp.keyWindow == nil { windows.first?.makeKey() }
        }
    }

    func cancel() { finish(nil) }

    /// Starts recording with whatever region is currently shown, if any; otherwise cancels.
    func confirm() {
        if let view = windows.compactMap({ $0.contentView as? SelectionView }).first(where: { $0.region != nil }) {
            view.confirm()
        } else {
            cancel()
        }
    }

    private func finish(_ result: RegionSelection?) {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        let cont = continuation
        continuation = nil
        cont?.resume(returning: result)
    }
}

final class SelectionWindow: NSWindow {
    let suggestedRect: CGRect?

    init(screen: NSScreen, suggested: CGRect?, onComplete: @escaping @MainActor (RegionSelection?) -> Void) {
        suggestedRect = suggested
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.displayID = screen.displayID ?? 0
        view.suggested = suggested.map { convertFromScreen($0) }
        view.onComplete = onComplete
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SelectionView: NSView {
    var displayID: CGDirectDisplayID = 0
    var suggested: CGRect? { didSet { region = suggested } }
    var onComplete: (@MainActor (RegionSelection?) -> Void)?

    /// The editable rectangle, in view coordinates. Nil until the user drags one out.
    private(set) var region: CGRect?

    private enum Drag {
        case create(start: CGPoint)
        case move(grab: CGPoint, original: CGRect)
        case resize(RegionMath.Handle, anchor: CGRect)
    }
    private var drag: Drag?
    private var trackingArea: NSTrackingArea?

    private let buttonSize = CGSize(width: 96, height: 26)
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: Confirm / cancel

    func confirm() {
        guard let region, RegionMath.isUsableSelection(region), let window else { return }
        onComplete?(RegionSelection(rect: window.convertToScreen(region), displayID: displayID))
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let p = convert(event.locationInWindow, from: nil)
        if let region {
            if recordButtonRect(for: region).contains(p) {
                confirm(); return
            }
            if let handle = RegionMath.handle(at: p, in: region) {
                drag = .resize(handle, anchor: region)
            } else if region.contains(p) {
                if event.clickCount == 2 { confirm(); return }
                drag = .move(grab: p, original: region)
            } else {
                drag = .create(start: p)
                self.region = nil
            }
        } else {
            drag = .create(start: p)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .create(let start):
            region = RegionMath.dragRect(from: start, to: p).intersection(bounds)
        case .move(let grab, let original):
            region = RegionMath.move(original, by: CGPoint(x: p.x - grab.x, y: p.y - grab.y), within: bounds)
        case .resize(let handle, let anchor):
            region = RegionMath.resize(anchor, handle: handle, to: p).intersection(bounds)
        case nil:
            return
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil; needsDisplay = true; updateCursor(at: convert(event.locationInWindow, from: nil)) }
        if case .create = drag, let region, !RegionMath.isUsableSelection(region) {
            // A plain click on empty space clears the selection rather than leaving a sliver.
            self.region = nil
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let step: CGFloat = shift ? 10 : 1
        switch event.keyCode {
        case 53: onComplete?(nil)                            // Escape
        case 36, 76: confirm()                               // Return / Enter
        case 123: nudge(dx: -step, dy: 0)                    // ←
        case 124: nudge(dx: step, dy: 0)                     // →
        case 125: nudge(dx: 0, dy: -step)                    // ↓
        case 126: nudge(dx: 0, dy: step)                     // ↑
        default: super.keyDown(with: event)
        }
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        guard let region else { return }
        self.region = RegionMath.move(region, by: CGPoint(x: dx, y: dy), within: bounds)
        needsDisplay = true
    }

    // MARK: Cursor

    private func updateCursor(at p: CGPoint) {
        guard let region else { NSCursor.crosshair.set(); return }
        if recordButtonRect(for: region).contains(p) { NSCursor.pointingHand.set(); return }
        switch RegionMath.handle(at: p, in: region) {
        case .left, .right: NSCursor.resizeLeftRight.set()
        case .top, .bottom: NSCursor.resizeUpDown.set()
        case .some: NSCursor.crosshair.set()
        case nil:
            if region.contains(p) {
                if case .move = drag { NSCursor.closedHand.set() } else { NSCursor.openHand.set() }
            } else {
                NSCursor.crosshair.set()
            }
        }
    }

    // MARK: Layout

    private func recordButtonRect(for rect: CGRect) -> CGRect {
        let gap: CGFloat = 8
        var origin = CGPoint(x: rect.maxX - buttonSize.width, y: rect.minY - gap - buttonSize.height)
        if origin.y < bounds.minY + 4 { origin.y = rect.maxY + gap }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - buttonSize.width - 4)
        return CGRect(origin: origin, size: buttonSize)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let region, region.width > 0, region.height > 0 else {
            drawHint("Drag to select an area  ·  Esc to cancel")
            return
        }

        NSColor.clear.setFill()
        region.fill(using: .copy)

        let border = NSBezierPath(rect: region.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        NSColor.white.setStroke()
        border.stroke()

        let usable = RegionMath.isUsableSelection(region)
        let isDragging = drag != nil
        if usable && !isDragging {
            for h in RegionMath.Handle.allCases {
                let c = h.point(in: region)
                let r = CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
                NSColor.white.setFill()
                NSBezierPath(ovalIn: r).fill()
                NSColor.black.withAlphaComponent(0.6).setStroke()
                NSBezierPath(ovalIn: r).stroke()
            }
            drawRecordButton(recordButtonRect(for: region))
        }

        let label = "\(Int(region.width)) × \(Int(region.height))"
        drawLabel(usable ? label : "\(label)  ·  too small", near: region)
    }

    private func drawRecordButton(_ rect: CGRect) {
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: "Record  ⏎", attributes: attrs)
        let size = str.size()
        str.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    private func drawLabel(_ text: String, near rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.white]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let pad: CGFloat = 6
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - pad * 2 - 8)
        if origin.y < bounds.minY + 4 { origin.y = rect.maxY + 8 }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - pad * 2 - 4)
        let box = CGRect(x: origin.x, y: origin.y, width: size.width + pad * 2, height: size.height + pad * 2)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        str.draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad))
    }

    private func drawHint(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let pad: CGFloat = 12
        let box = CGRect(x: bounds.midX - size.width / 2 - pad, y: bounds.maxY - 120,
                         width: size.width + pad * 2, height: size.height + pad * 2)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        str.draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad))
    }
}
