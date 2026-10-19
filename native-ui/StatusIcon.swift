import AppKit

@MainActor enum StatusIcon {
    // Flat silhouette traced from assets/Temada.png: two interlocking speech
    // bubbles and their separate tails. No rounded app tile, gradients or badge.
    // Keep the same brand mark while recording; status remains in the tooltip.
    static func image(running: Bool) -> NSImage? {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState(); defer { context.restoreGState() }
            context.translateBy(x: 0.5, y: 15.25)
            context.scaleBy(x: 17 / 600, y: -17 / 600)
            context.translateBy(x: -212, y: -292)
            NSColor.black.setFill()
            let left = NSBezierPath()
            left.move(to: NSPoint(x: 496, y: 316))
            left.curve(to: NSPoint(x: 214, y: 490), controlPoint1: NSPoint(x: 350, y: 240), controlPoint2: NSPoint(x: 210, y: 350))
            left.curve(to: NSPoint(x: 283, y: 637), controlPoint1: NSPoint(x: 210, y: 550), controlPoint2: NSPoint(x: 238, y: 600))
            left.line(to: NSPoint(x: 283, y: 709))
            left.curve(to: NSPoint(x: 310, y: 726), controlPoint1: NSPoint(x: 283, y: 732), controlPoint2: NSPoint(x: 296, y: 736))
            left.line(to: NSPoint(x: 376, y: 681))
            left.curve(to: NSPoint(x: 598, y: 522), controlPoint1: NSPoint(x: 490, y: 704), controlPoint2: NSPoint(x: 588, y: 630))
            left.curve(to: NSPoint(x: 570, y: 382), controlPoint1: NSPoint(x: 607, y: 470), controlPoint2: NSPoint(x: 587, y: 404))
            left.curve(to: NSPoint(x: 533, y: 452), controlPoint1: NSPoint(x: 527, y: 397), controlPoint2: NSPoint(x: 526, y: 422))
            left.curve(to: NSPoint(x: 463, y: 606), controlPoint1: NSPoint(x: 568, y: 553), controlPoint2: NSPoint(x: 493, y: 602))
            left.curve(to: NSPoint(x: 443, y: 604), controlPoint1: NSPoint(x: 455, y: 614), controlPoint2: NSPoint(x: 448, y: 614))
            left.curve(to: NSPoint(x: 408, y: 490), controlPoint1: NSPoint(x: 418, y: 572), controlPoint2: NSPoint(x: 407, y: 539))
            left.curve(to: NSPoint(x: 496, y: 316), controlPoint1: NSPoint(x: 404, y: 417), controlPoint2: NSPoint(x: 441, y: 364))
            left.close(); left.fill()
            let right = NSBezierPath()
            right.move(to: NSPoint(x: 454, y: 596))
            right.curve(to: NSPoint(x: 423, y: 490), controlPoint1: NSPoint(x: 435, y: 565), controlPoint2: NSPoint(x: 423, y: 530))
            right.curve(to: NSPoint(x: 617, y: 294), controlPoint1: NSPoint(x: 423, y: 382), controlPoint2: NSPoint(x: 510, y: 294))
            right.curve(to: NSPoint(x: 811, y: 490), controlPoint1: NSPoint(x: 725, y: 294), controlPoint2: NSPoint(x: 811, y: 382))
            right.curve(to: NSPoint(x: 742, y: 637), controlPoint1: NSPoint(x: 811, y: 550), controlPoint2: NSPoint(x: 781, y: 607))
            right.line(to: NSPoint(x: 742, y: 709))
            right.curve(to: NSPoint(x: 715, y: 726), controlPoint1: NSPoint(x: 742, y: 732), controlPoint2: NSPoint(x: 729, y: 737))
            right.line(to: NSPoint(x: 648, y: 681))
            right.curve(to: NSPoint(x: 513, y: 652), controlPoint1: NSPoint(x: 602, y: 688), controlPoint2: NSPoint(x: 557, y: 675))
            right.curve(to: NSPoint(x: 611, y: 490), controlPoint1: NSPoint(x: 577, y: 620), controlPoint2: NSPoint(x: 611, y: 568))
            right.curve(to: NSPoint(x: 579, y: 369), controlPoint1: NSPoint(x: 615, y: 439), controlPoint2: NSPoint(x: 595, y: 392))
            right.curve(to: NSPoint(x: 565, y: 365), controlPoint1: NSPoint(x: 575, y: 363), controlPoint2: NSPoint(x: 570, y: 362))
            right.curve(to: NSPoint(x: 476, y: 490), controlPoint1: NSPoint(x: 515, y: 383), controlPoint2: NSPoint(x: 470, y: 426))
            right.curve(to: NSPoint(x: 477, y: 564), controlPoint1: NSPoint(x: 476, y: 511), controlPoint2: NSPoint(x: 480, y: 535))
            right.curve(to: NSPoint(x: 454, y: 596), controlPoint1: NSPoint(x: 474, y: 582), controlPoint2: NSPoint(x: 464, y: 592))
            right.close(); right.fill()
            return true
        }
        image.isTemplate = true // AppKit chooses light/dark/highlight tint.
        image.accessibilityDescription = running ? "Temada — recording" : "Temada"
        return image
    }
}
