import AppKit

@MainActor enum StatusIcon {
    static func image(running: Bool) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: running ? "captions.bubble.fill" : "captions.bubble", accessibilityDescription: running ? "Temada — recording" : "Temada") else { return nil }
        let image = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)) ?? symbol
        image.size = NSSize(width: 18, height: 18)
        // AppKit supplies the tint for light/dark menu bars and highlighted menus.
        // Never resize/recolor the full-color application artwork for the tray.
        image.isTemplate = true
        return image
    }
}
