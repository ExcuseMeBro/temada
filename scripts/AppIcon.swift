import AppKit

// Vector-drawn local brand artwork. No network, stock assets or model download.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(size) / 1024); transform.concat()
        let plate = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 206, yRadius: 206)
        NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.18, blue: 0.33, alpha: 1), ending: NSColor(srgbRed: 0.08, green: 0.38, blue: 0.46, alpha: 1))!.draw(in: plate, angle: 45)
        let rear = NSBezierPath(roundedRect: NSRect(x: 205, y: 398, width: 532, height: 320), xRadius: 68, yRadius: 68)
        NSColor.white.setFill(); rear.fill()
        let rearTail = NSBezierPath(); rearTail.move(to: NSPoint(x: 256, y: 425)); rearTail.line(to: NSPoint(x: 256, y: 346)); rearTail.line(to: NSPoint(x: 352, y: 425)); rearTail.close(); rearTail.fill()
        let front = NSBezierPath(roundedRect: NSRect(x: 348, y: 248, width: 488, height: 292), xRadius: 64, yRadius: 64)
        NSColor(srgbRed: 0.27, green: 0.91, blue: 0.75, alpha: 1).setFill(); front.fill()
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: 702, y: 275)); tail.line(to: NSPoint(x: 781, y: 196)); tail.line(to: NSPoint(x: 781, y: 275)); tail.close(); tail.fill()
        NSColor(srgbRed: 0.10, green: 0.24, blue: 0.34, alpha: 1).setFill()
        for rect in [NSRect(x: 276, y: 611, width: 328, height: 28), NSRect(x: 276, y: 555, width: 214, height: 28), NSRect(x: 412, y: 428, width: 342, height: 28), NSRect(x: 412, y: 368, width: 244, height: 28)] {
            NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
