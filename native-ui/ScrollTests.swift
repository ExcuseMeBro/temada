import AppKit

@MainActor enum ScrollTests {
    static func run() {
        let scroll = CaptionTextScrollView(frame: NSRect(x: 0, y: 0, width: 620, height: 190))
        scroll.tile(); scroll.layoutSubtreeIfNeeded()
        var rows = (0..<320).map { i in
            CaptionPair(id: "test-\(i)", source: "system", original: "\(i): Salom Hello Привет — " + String(repeating: "original words ", count: 12), translation: "\(i): tarjima translation перевод — " + String(repeating: "translated words ", count: 15))
        }
        var appearance = Appearance()
        scroll.render(rows, appearance: appearance)
        func bottom() -> CGFloat { max(0, scroll.text.frame.height - scroll.contentView.bounds.height) }
        precondition(bottom() > 10000 && abs(scroll.contentView.bounds.minY - bottom()) < 1, "Did not follow exact long document bottom")
        func userScroll(_ y: CGFloat) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y)); scroll.reflectScrolledClipView(scroll.contentView)
            NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        }
        userScroll(500)
        precondition(!scroll.follow.latest)
        let before = scroll.contentView.bounds.minY
        rows[319].translation += String(repeating: " more live text ", count: 100)
        scroll.render(rows, appearance: appearance)
        precondition(abs(scroll.contentView.bounds.minY - before) < 1 && !scroll.follow.latest, "Live partial moved a reader's viewport")
        precondition(scroll.text.string.contains(rows[0].original) && scroll.text.string.contains(rows[319].translation), "Text was truncated")
        userScroll(bottom())
        precondition(scroll.follow.latest)
        rows.append(CaptionPair(id: "next", source: "microphone", original: "New source", translation: "Yangi tarjima"))
        scroll.render(rows, appearance: appearance)
        precondition(abs(scroll.contentView.bounds.minY - bottom()) < 1, "New row left follow stuck above bottom")
        userScroll(700)
        scroll.setFrameSize(NSSize(width: 390, height: 150)); scroll.tile(); scroll.layoutSubtreeIfNeeded()
        appearance.originalSize = 25; appearance.translationSize = 30
        scroll.render(rows, appearance: appearance)
        precondition(!scroll.follow.latest && abs(scroll.contentView.bounds.minY - 700) < 1, "Resize/font change jumped the reader")
        userScroll(bottom()); rows[320].translation += String(repeating: " wraps on resize ", count: 50)
        scroll.render(rows, appearance: appearance)
        precondition(abs(scroll.contentView.bounds.minY - bottom()) < 1)
        scroll.setFrameSize(NSSize(width: 720, height: 400)); scroll.tile(); scroll.layoutSubtreeIfNeeded()
        precondition(scroll.follow.latest && abs(scroll.contentView.bounds.minY - bottom()) < 1, "Resize disabled live following")
        scroll.render([], appearance: appearance)
        precondition(scroll.text.string.isEmpty && scroll.follow.latest && scroll.contentView.bounds.minY == 0)
        scroll.render(Array(rows.prefix(1)), appearance: appearance)
        precondition(scroll.text.string.contains(rows[0].original) && !scroll.text.string.contains(rows[319].original))
        print("SCROLL_SELFTEST: PASS — 320 long mixed-language rows, exact bottom, partial growth, preserved backscroll, resume-follow, resize/font changes, clear, no clipping")
    }
}
