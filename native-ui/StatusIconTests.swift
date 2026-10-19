import AppKit

@MainActor enum StatusIconTests {
    static func require(_ value: Bool, _ message: String) {
        if !value { fputs("STATUS_ICON_SELFTEST: FAIL — \(message)\n", stderr); exit(1) }
    }
    static func run() {
        // Reproduce the real bundle's colored logo even in an unsigned test binary.
        // This is process-local image-cache state, never a user asset/disk edit.
        let name = NSImage.Name("Temada")
        let savedLogo = NSImage(named: name)
        _ = savedLogo?.setName(nil)
        let logo = NSImage(size: NSSize(width: 20, height: 20))
        logo.lockFocus(); NSColor.systemTeal.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 20, height: 20)).fill(); logo.unlockFocus()
        require(logo.setName(name), "Fixture logo could not be registered")
        defer { _ = logo.setName(nil); _ = savedLogo?.setName(name) }
        for running in [false, true] {
            guard let image = StatusIcon.image(running: running) else { require(false, "Missing tray symbol"); return }
            require(image.isTemplate, "Idle/running tray icon must use AppKit template tinting")
            require(image.size == NSSize(width: 18, height: 18), "Tray symbol must fit menu-bar height")
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                    NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: 36, height: 36).fill(using: .copy)
                    image.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36))
                    NSGraphicsContext.restoreGraphicsState()
                    var visible = 0, transparent = 0
                    for y in 0..<36 { for x in 0..<36 {
                        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        if color.alphaComponent > 0.05 {
                            visible += 1
                            require(abs(color.redComponent - color.greenComponent) < 0.02 && abs(color.greenComponent - color.blueComponent) < 0.02, "Colored logo/badge leaked into tray")
                        } else { transparent += 1 }
                    } }
                    require(visible > 10 && transparent > 100, "Empty symbol or opaque square background")
                }
            }
        }
        require(!logo.isTemplate, "Application logo was mutated into a template")
        print("STATUS_ICON_SELFTEST: PASS — idle/running18pt template, light/dark monochrome pixels, transparent background; full-color app logo untouched")
    }
}
