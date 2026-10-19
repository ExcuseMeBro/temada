import Foundation
import Combine

struct Appearance: Codable, Equatable {
    var originalSize = 21.0
    var translationSize = 27.0
    var originalColor = "#F2F4F8"
    var translationColor = "#82E8C1"
    var backgroundColor = "#11151C"
    var opacity = 0.86
    var width = 820.0
    var height = 330.0
    var x: Double?
    var y: Double?
    var visiblePairs = 4
    var animations = true
    var source = "system"
    var target = "uz"
    mutating func clamp() {
        func valid(_ n: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double { n.isFinite ? min(max(n, range.lowerBound), range.upperBound) : fallback }
        originalSize = valid(originalSize, 12...64, 21); translationSize = valid(translationSize, 12...72, 27)
        width = valid(width, 340...1800, 820); height = valid(height, 140...1200, 330)
        opacity = valid(opacity, 0.1...1, 0.86); visiblePairs = min(max(visiblePairs, 1), 12)
        for color in [originalColor, translationColor, backgroundColor] {
            if !Self.isColor(color) { originalColor = "#F2F4F8"; translationColor = "#82E8C1"; backgroundColor = "#11151C"; break }
        }
        if let value = x, !value.isFinite { x = nil }; if let value = y, !value.isFinite { y = nil }
        if !["system", "microphone", "both"].contains(source) { source = "system" }
        if !["uz", "en", "ru"].contains(target) { target = "uz" }
    }
    static func isColor(_ value: String) -> Bool { value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }
}
@MainActor final class Preferences: ObservableObject {
    let defaults: UserDefaults
    @Published var appearance: Appearance { didSet { if let data = try? JSONEncoder().encode(appearance) { defaults.set(data, forKey: "appearance.v1") } } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var value = defaults.data(forKey: "appearance.v1").flatMap { try? JSONDecoder().decode(Appearance.self, from: $0) } ?? Appearance()
        value.clamp(); self.appearance = value
    }
}
struct WireFrame: Decodable {
    var kind: String
    var source: String?
    var original: String?
    var translation: String?
    var interim: String?
    var message: String?
    var inputFinished: Bool?
    var outputFinished: Bool?
}
struct CaptionPair: Identifiable, Equatable {
    let id: String
    let source: String
    var original = ""
    var translation = ""
    var originalFinal = false
    var translationFinal = false
}
// Gemini Live Translate has no cross-stream sentence IDs. Preserve FIFO order per
// source, stable local row IDs, and partial text. Never pair across audio sources.
// Sentence counts can differ semantically: this is ordered display, NOT forced alignment.
struct CaptionTimeline {
    private var inputIndex: [String: Int] = [:]
    private var outputIndex: [String: Int] = [:]
    private(set) var pairs: [CaptionPair] = []
    mutating func clear() { pairs.removeAll(); inputIndex.removeAll(); outputIndex.removeAll() }
    mutating func consume(_ frame: WireFrame) throws {
        guard frame.kind == "text" || frame.kind == "boundary" else { return }
        guard let source = frame.source, ["system", "microphone"].contains(source) else { throw ModelError.invalidSource }
        if let text = frame.original { try append(text, source: source, translated: false) }
        if let text = frame.translation { try append(text, source: source, translated: true) }
        if frame.inputFinished == true { finish(source: source, translated: false) }
        if frame.outputFinished == true { finish(source: source, translated: true) }
        // Retain bounded recent history, never evict a row whose counterpart is pending.
        while pairs.count > 48, let first = pairs.first, first.originalFinal && first.translationFinal { pairs.removeFirst() }
        if pairs.count > 64 { throw ModelError.alignmentBacklog }
    }
    private mutating func row(source: String, index: Int) throws -> Int {
        let id = "\(source)-\(index)"
        if let i = pairs.firstIndex(where: { $0.id == id }) { return i }
        if pairs.count >= 64 { throw ModelError.alignmentBacklog }
        pairs.append(CaptionPair(id: id, source: source)); return pairs.count - 1
    }
    private mutating func finish(source: String, translated: Bool) {
        let index = translated ? outputIndex[source, default: 0] : inputIndex[source, default: 0]
        let id = "\(source)-\(index)"
        guard let i = pairs.firstIndex(where: { $0.id == id }) else { return }
        let text = translated ? pairs[i].translation : pairs[i].original
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if translated { pairs[i].translationFinal = true; outputIndex[source] = index + 1 }
        else { pairs[i].originalFinal = true; inputIndex[source] = index + 1 }
    }
    private mutating func append(_ text: String, source: String, translated: Bool) throws {
        guard text.utf8.count <= 64000 else { throw ModelError.oversize }
        // Delimit on punctuation followed by whitespace; keep decimal points intact.
        // A provider finished event flushes trailing text even without punctuation.
        for char in text {
            let index = translated ? outputIndex[source, default: 0] : inputIndex[source, default: 0]
            let i = try row(source: source, index: index)
            let current = translated ? pairs[i].translation : pairs[i].original
            let stripped = current.trimmingCharacters(in: .whitespaces)
            if char.isWhitespace, let last = stripped.last, ".!?。！？".contains(last), !stripped.isEmpty {
                finish(source: source, translated: translated)
                continue
            }
            if char.isNewline { finish(source: source, translated: translated); continue }
            if current.isEmpty && char.isWhitespace { continue }
            if translated { pairs[i].translation.append(char) } else { pairs[i].original.append(char) }
            if (translated ? pairs[i].translation.utf8.count : pairs[i].original.utf8.count) > 16000 { throw ModelError.oversize }
        }
    }
    enum ModelError: Error { case invalidSource, oversize, alignmentBacklog }
}
@MainActor final class Captions: ObservableObject {
    @Published private(set) var rows: [CaptionPair] = []
    private var timeline = CaptionTimeline()
    private var interims: [String: String] = [:]
    func clear() { timeline.clear(); interims.removeAll(); rows = [] }
    func consume(_ frame: WireFrame) throws {
        try timeline.consume(frame)
        if frame.kind == "text", let source = frame.source {
            if let interim = frame.interim, !interim.isEmpty {
                guard interim.utf8.count <= 16000 else { throw CaptionTimeline.ModelError.oversize }
                interims[source] = interim
            }
            if let original = frame.original, !original.isEmpty { interims.removeValue(forKey: source) }
        }
        var visible = timeline.pairs.filter { !$0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for source in interims.keys.sorted() {
            // Provisional input is not falsely paired with an untagged output.
            var pair = CaptionPair(id: "\(source)-interim", source: source)
            pair.original = interims[source] ?? ""; visible.append(pair)
        }
        rows = visible
    }
}
