import SwiftUI
import AppKit

struct CaptionFollowState {
    var latest = true
    mutating func userScrolling() { latest = false }
    mutating func settled(offset: Double, viewport: Double, content: Double) {
        latest = offset + viewport >= content - 6
    }
}

// Native text layout has an exact document height, unlike estimated LazyVStack
// geometry. Update only the changed suffix; never animate a scroll while reading.
struct CaptionScrollText: NSViewRepresentable {
    var rows: [CaptionPair]
    var appearance: Appearance
    func makeNSView(context: Context) -> CaptionTextScrollView { CaptionTextScrollView() }
    func updateNSView(_ view: CaptionTextScrollView, context: Context) { view.render(rows, appearance: appearance) }
}

@MainActor final class CaptionTextScrollView: NSScrollView {
    let text = NSTextView(frame: .zero)
    private(set) var follow = CaptionFollowState()
    private var rendered: [CaptionPair] = []
    private var starts: [Int] = []
    private var styling: Appearance?
    private var updating = false
    private var boundsObserver: NSObjectProtocol?
    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false; contentView.drawsBackground = false; borderType = .noBorder
        hasVerticalScroller = true; hasHorizontalScroller = false
        // Always reachable; do not let an overlay scroller compete with resizing.
        scrollerStyle = .legacy; autohidesScrollers = false
        text.isEditable = false; text.isSelectable = false; text.drawsBackground = false
        text.isRichText = false; text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.minSize = .zero; text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.heightTracksTextView = false
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        documentView = text
        contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.userBoundsChanged() }
        }
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("Not archived") }
    deinit { if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) } }
    private func userBoundsChanged() {
        guard !updating else { return }
        follow.settled(offset: contentView.bounds.minY, viewport: contentView.bounds.height, content: text.frame.height)
    }
    override func scrollWheel(with event: NSEvent) {
        follow.userScrolling()
        super.scrollWheel(with: event)
        userBoundsChanged()
    }
    override func layout() {
        guard !updating else { super.layout(); return }
        updating = true
        super.layout()
        updating = false
        relayout()
    }
    private func relayout() {
        guard !updating, contentView.bounds.width > 0, let manager = text.layoutManager, let container = text.textContainer else { return }
        updating = true
        defer { updating = false }
        let previousOffset = contentView.bounds.origin
        text.setFrameSize(NSSize(width: contentView.bounds.width, height: text.frame.height))
        container.containerSize = NSSize(width: max(1, contentView.bounds.width - 24), height: CGFloat.greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let height = max(contentView.bounds.height, ceil(manager.usedRect(for: container).maxY) + 24)
        text.setFrameSize(NSSize(width: contentView.bounds.width, height: height))
        let bottom = max(0, height - contentView.bounds.height)
        contentView.scroll(to: NSPoint(x: 0, y: follow.latest ? bottom : min(previousOffset.y, bottom)))
        reflectScrolledClipView(contentView)
    }
    func render(_ rows: [CaptionPair], appearance: Appearance) {
        guard let storage = text.textStorage else { return }
        let sameStyle = styling.map { $0.originalSize == appearance.originalSize && $0.translationSize == appearance.translationSize && $0.originalColor == appearance.originalColor && $0.translationColor == appearance.translationColor } ?? false
        var common = 0
        if sameStyle {
            while common < min(rendered.count, rows.count), rendered[common] == rows[common] { common += 1 }
            if common == rendered.count && common == rows.count { return }
        }
        updating = true
        let start = common < starts.count ? starts[common] : storage.length
        starts = Array(starts.prefix(common))
        let suffix = NSMutableAttributedString(string: "")
        for row in rows.dropFirst(common) {
            starts.append(start + suffix.length)
            func append(_ string: String, size: Double, color: String, weight: NSFont.Weight, spacing: CGFloat) {
                guard !string.isEmpty else { return }
                let paragraph = NSMutableParagraphStyle(); paragraph.paragraphSpacing = spacing; paragraph.lineBreakMode = .byWordWrapping
                let nsColor = NSColor(Color(hex: color))
                suffix.append(NSAttributedString(string: string + "\n", attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: nsColor, .paragraphStyle: paragraph]))
            }
            append(row.original, size: appearance.originalSize, color: appearance.originalColor, weight: .regular, spacing: row.translation.isEmpty ? 8 : 3)
            append(row.translation, size: appearance.translationSize, color: appearance.translationColor, weight: .medium, spacing: 8)
        }
        storage.replaceCharacters(in: NSRange(location: start, length: storage.length - start), with: suffix)
        rendered = rows; styling = appearance
        if rows.isEmpty { follow.latest = true }
        updating = false
        relayout()
    }
}
