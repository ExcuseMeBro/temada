import AppKit

// Render checked-in Temada artwork locally; no build-time network/model access.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets/Temada.png")
guard let artwork = NSImage(contentsOf: source) else { fatalError("Temada icon asset missing") }
// Generated PNG has 300dpi metadata: 1024 pixels but 245.76 AppKit points.
// Normalize logical coordinates before cropping, otherwise almost all is blank.
artwork.size = NSSize(width: 1024, height: 1024)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current!.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(size) / 1024); transform.concat()
        // Remove the generated white outer margin, preserving transparent corners.
        NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 206, yRadius: 206).addClip()
        artwork.draw(in: NSRect(x: 56, y: 56, width: 912, height: 912), from: NSRect(x: 85, y: 85, width: 854, height: 854), operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let center = bitmap.colorAt(x: size / 2, y: size / 2), center.alphaComponent > 0.99,
              let corner = bitmap.colorAt(x: 0, y: 0), corner.alphaComponent < 0.01 else {
            fputs("Invalid Temada icon: center must be opaque and corners transparent\n", stderr); exit(1)
        }
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
