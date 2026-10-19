import AppKit

struct ResizeEdges: OptionSet {
    let rawValue: Int
    static let left = Self(rawValue: 1)
    static let right = Self(rawValue: 2)
    static let bottom = Self(rawValue: 4)
    static let top = Self(rawValue: 8)
    static func hit(_ point: NSPoint, size: NSSize, inset: CGFloat = 8) -> Self {
        guard NSRect(origin: .zero, size: size).contains(point) else { return [] }
        // Larger corner targets remain reachable inside the rounded background.
        let corner = inset * 2
        if point.x < corner && point.y < corner { return [.left, .bottom] }
        if point.x >= size.width - corner && point.y < corner { return [.right, .bottom] }
        if point.x < corner && point.y >= size.height - corner { return [.left, .top] }
        if point.x >= size.width - corner && point.y >= size.height - corner { return [.right, .top] }
        var edges: Self = []
        if point.x < inset { edges.insert(.left) }
        if point.x >= size.width - inset { edges.insert(.right) }
        if point.y < inset { edges.insert(.bottom) }
        if point.y >= size.height - inset { edges.insert(.top) }
        return edges
    }
    func frame(from start: NSRect, delta: NSPoint, minimum: NSSize, maximum: NSSize) -> NSRect {
        var frame = start
        func clamp(_ value: CGFloat, _ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat { min(max(value, minValue), maxValue) }
        if contains(.left) {
            frame.size.width = clamp(start.width - delta.x, minimum.width, maximum.width)
            frame.origin.x = start.maxX - frame.width
        } else if contains(.right) { frame.size.width = clamp(start.width + delta.x, minimum.width, maximum.width) }
        if contains(.bottom) {
            frame.size.height = clamp(start.height - delta.y, minimum.height, maximum.height)
            frame.origin.y = start.maxY - frame.height
        } else if contains(.top) { frame.size.height = clamp(start.height + delta.y, minimum.height, maximum.height) }
        return frame
    }
}

// Handle only events belonging to this panel, BEFORE NSHostingView/ScrollView.
// A normal native drag therefore works even when the pointer is over caption text.
@MainActor class CaptionPanel: NSPanel {
    private struct ResizeSession { let edges: ResizeEdges; let frame: NSRect; let pointer: NSPoint }
    private var resizeSession: ResizeSession?
    func dragWindow(with event: NSEvent) { performDrag(with: event) }
    func sendToContent(_ event: NSEvent) { super.sendEvent(event) }
    func isScrollControl(at point: NSPoint) -> Bool {
        var view = contentView?.hitTest(point)
        while let current = view {
            if current is NSScroller { return true }
            view = current.superview
        }
        return false
    }
    override func sendEvent(_ event: NSEvent) {
        guard event.window === self else { super.sendEvent(event); return }
        switch event.type {
        case .leftMouseDown:
            // Keep the outer 3px resize edge, but never turn scrollbar clicks
            // or thumb dragging into window dragging/resizing.
            if event.locationInWindow.x < frame.width - 3 && isScrollControl(at: event.locationInWindow) {
                resizeSession = nil; sendToContent(event); return
            }
            let edges = ResizeEdges.hit(event.locationInWindow, size: frame.size)
            if !edges.isEmpty {
                resizeSession = ResizeSession(edges: edges, frame: frame, pointer: convertPoint(toScreen: event.locationInWindow))
            } else {
                resizeSession = nil
                dragWindow(with: event)
            }
            return
        case .leftMouseDragged:
            if let session = resizeSession {
                let pointer = convertPoint(toScreen: event.locationInWindow)
                let delta = NSPoint(x: pointer.x - session.pointer.x, y: pointer.y - session.pointer.y)
                setFrame(session.edges.frame(from: session.frame, delta: delta, minimum: minSize, maximum: maxSize), display: true)
                return
            }
        case .leftMouseUp:
            if resizeSession != nil { resizeSession = nil; return }
        case .mouseMoved:
            super.sendEvent(event)
            let edges = ResizeEdges.hit(event.locationInWindow, size: frame.size)
            if isScrollControl(at: event.locationInWindow) { NSCursor.arrow.set(); return }
            if edges.intersection([.left, .right]).isEmpty { (edges.isEmpty ? NSCursor.openHand : NSCursor.resizeUpDown).set() }
            else if edges.intersection([.top, .bottom]).isEmpty { NSCursor.resizeLeftRight.set() }
            else { NSCursor.crosshair.set() }
            return
        default: break
        }
        super.sendEvent(event)
    }
    override func resignKey() { resizeSession = nil; super.resignKey() }
    override func orderOut(_ sender: Any?) { resizeSession = nil; super.orderOut(sender) }
}
