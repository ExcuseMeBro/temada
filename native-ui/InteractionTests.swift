import AppKit

@MainActor private final class TestCaptionPanel: CaptionPanel {
    var dragCalls = 0
    var contentCalls = 0
    override func dragWindow(with event: NSEvent) { dragCalls += 1 }
    // Hidden windows do not dispatch normal AppKit control tracking. Verify
    // routing without activating a window or injecting input into user apps.
    override func sendToContent(_ event: NSEvent) { contentCalls += 1 }
}
@MainActor enum InteractionTests {
    static func run(preferences: Preferences) {
        let start = NSRect(x: -500, y: 100, width: 820, height: 330)
        let minimum = NSSize(width: 340, height: 140), maximum = NSSize(width: 1800, height: 1200)
        let positions: [(NSPoint, ResizeEdges)] = [
            (NSPoint(x: 1, y: 160), .left), (NSPoint(x: 819, y: 160), .right),
            (NSPoint(x: 400, y: 1), .bottom), (NSPoint(x: 400, y: 329), .top),
            (NSPoint(x: 1, y: 1), [.left, .bottom]), (NSPoint(x: 819, y: 1), [.right, .bottom]),
            (NSPoint(x: 1, y: 329), [.left, .top]), (NSPoint(x: 819, y: 329), [.right, .top])
        ]
        for (point, expected) in positions {
            precondition(ResizeEdges.hit(point, size: start.size) == expected)
            let frame = expected.frame(from: start, delta: NSPoint(x: 40, y: 20), minimum: minimum, maximum: maximum)
            precondition(frame.width == (expected.contains(.left) ? 780 : expected.contains(.right) ? 860 : 820))
            precondition(frame.height == (expected.contains(.bottom) ? 310 : expected.contains(.top) ? 350 : 330))
            if expected.contains(.left) { precondition(frame.maxX == start.maxX) }
            if expected.contains(.bottom) { precondition(frame.maxY == start.maxY) }
        }
        precondition(ResizeEdges.hit(NSPoint(x: 12, y: 12), size: start.size) == [.left, .bottom])
        precondition(ResizeEdges.hit(NSPoint(x: 400, y: 100), size: start.size).isEmpty)
        precondition(ResizeEdges.hit(NSPoint(x: -1, y: 100), size: start.size).isEmpty)
        let minFrame = ResizeEdges([.left, .bottom]).frame(from: start, delta: NSPoint(x: 9999, y: 9999), minimum: minimum, maximum: maximum)
        precondition(minFrame.size == minimum && minFrame.maxX == start.maxX && minFrame.maxY == start.maxY)
        let maxFrame = ResizeEdges([.right, .top]).frame(from: start, delta: NSPoint(x: 9999, y: 9999), minimum: minimum, maximum: maximum)
        precondition(maxFrame.size == maximum && maxFrame.origin == start.origin)
        let panel = TestCaptionPanel(contentRect: start, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.minSize = minimum; panel.maxSize = maximum
        let captions = Captions()
        try! captions.consume(WireFrame(kind: "text", source: "system", original: "Drag this caption text", translation: "Matn ustidan ham suring"))
        panel.contentView = captionHostingView(preferences: preferences, captions: captions)
        panel.setFrame(start, display: false)
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        panel.sendEvent(mouse(.leftMouseDown, NSPoint(x: 400, y: 100)))
        precondition(panel.dragCalls == 1, "Caption text swallowed native drag")
        panel.sendEvent(mouse(.leftMouseDown, NSPoint(x: 819, y: 160)))
        panel.sendEvent(mouse(.leftMouseDragged, NSPoint(x: 919, y: 160)))
        precondition(panel.frame.width == 920 && panel.frame.minX == start.minX, "Right-edge event did not resize")
        panel.sendEvent(mouse(.leftMouseUp, NSPoint(x: 919, y: 160)))
        panel.sendEvent(mouse(.leftMouseDragged, NSPoint(x: 1000, y: 160)))
        precondition(panel.frame.width == 920, "Resize continued after mouse up")
        let root = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        let scroller = NSScroller(frame: NSRect(x: panel.frame.width - 20, y: 20, width: 16, height: 200))
        scroller.isEnabled = true
        root.addSubview(scroller); panel.contentView = root
        panel.sendEvent(mouse(.leftMouseDown, NSPoint(x: panel.frame.width - 12, y: 100)))
        precondition(panel.dragCalls == 1 && panel.contentCalls == 1, "Scrollbar mouse-down was swallowed by window drag/resize")
        panel.close()
        print("PANEL_INTERACTIONS: PASS — 8 edges/corners, min/max, opposite anchors, text drag route, resize/up events, scrollbar forwarded")
    }
}
