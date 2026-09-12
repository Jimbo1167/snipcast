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
    var suggested: CGRect?
    var onComplete: (@MainActor (RegionSelection?) -> Void)?

    private var dragStart: CGPoint?
    private var current: CGRect?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .cursorUpdate, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        dragStart = convert(event.locationInWindow, from: nil)
        current = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        current = RegionMath.dragRect(from: dragStart, to: p).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; current = nil; needsDisplay = true }
        if let current, RegionMath.isUsableSelection(current) {
            complete(current)
        } else if let suggested, let dragStart, suggested.contains(dragStart) {
            complete(suggested)
        } else {
            onComplete?(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onComplete?(nil)                       // Escape
        case 36, 76: if let suggested { complete(suggested) } // Return / Enter
        default: super.keyDown(with: event)
        }
    }

    private func complete(_ localRect: CGRect) {
        guard let window else { return }
        let screenRect = window.convertToScreen(localRect)
        onComplete?(RegionSelection(rect: screenRect, displayID: displayID))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        if let current, RegionMath.isUsableSelection(current) {
            drawSelection(current, color: .white, dashed: false, label: sizeLabel(current))
        } else if let suggested {
            drawSelection(suggested, color: .white, dashed: true, label: "\(sizeLabel(suggested))  ·  Return to reuse, drag to change")
        } else {
            drawHint("Drag to select an area  ·  Esc to cancel")
        }
    }

    private func drawSelection(_ rect: CGRect, color: NSColor, dashed: Bool, label: String) {
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        let path = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        path.lineWidth = 1
        if dashed { path.setLineDash([6, 4], count: 2, phase: 0) }
        color.setStroke()
        path.stroke()
        drawLabel(label, near: rect)
    }

    private func sizeLabel(_ rect: CGRect) -> String {
        "\(Int(rect.width)) × \(Int(rect.height))"
    }

    private func drawLabel(_ text: String, near rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let pad: CGFloat = 6
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - pad * 2 - 4)
        if origin.y < bounds.minY { origin.y = rect.maxY + 4 }
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
