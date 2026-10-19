import AppKit
import Combine
import Carbon
import ApplicationServices

struct DictationBuffer {
    enum Phase { case idle, listening, finishing, cancelled }
    private(set) var phase = Phase.idle
    private(set) var translation = ""
    private(set) var original = ""
    var active: Bool { phase != .idle }
    mutating func begin() { phase = .listening; translation = ""; original = "" }
    mutating func finish() { if phase == .listening { phase = .finishing } }
    mutating func cancel() { if active { phase = .cancelled } }
    mutating func consume(_ frames: [WireFrame]) throws {
        guard active else { return }
        for frame in frames {
            if frame.kind == "error" { phase = .cancelled }
            guard frame.kind == "text" else { continue }
            guard frame.source == "microphone" else { phase = .cancelled; throw Failure.invalid }
            let next = translation + (frame.translation ?? ""), nextOriginal = original + (frame.original ?? "")
            guard next.utf8.count <= 16000, nextOriginal.utf8.count <= 16000 else { phase = .cancelled; throw Failure.invalid }
            translation = next; original = nextOriginal
        }
    }
    mutating func completed(cleanly: Bool) -> String? {
        let result = phase == .finishing && cleanly ? translation.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        phase = .idle
        return result.isEmpty ? nil : result
    }
    enum Failure: Error { case invalid }
}
@MainActor final class EnglishDictation: ObservableObject {
    @Published private(set) var armed = false
    @Published private(set) var active = false
    @Published private(set) var status = "Off — enable for this launch after cloud/microphone/Accessibility consent."
    @Published private(set) var draft = ""
    private var buffer = DictationBuffer()
    private var cursor: FocusedCursor?
    @Published private(set) var shortcut: ShortcutBinding
    private let defaults: UserDefaults
    private let hotkey: any HotkeyRegistering
    private let signed: () -> Bool
    private let trusted: () -> Bool
    init(defaults: UserDefaults = .standard, hotkey: (any HotkeyRegistering)? = nil, signed: @escaping () -> Bool = { AppIdentity.certificateSigned }, trusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.defaults = defaults; self.hotkey = hotkey ?? GlobalDictationHotkey(); self.signed = signed; self.trusted = trusted
        if let data = defaults.data(forKey: "dictation.shortcut.v1"), let saved = try? JSONDecoder().decode(ShortcutBinding.self, from: data), saved.valid { shortcut = saved }
        else { shortcut = .defaultBinding }
    }
    func prepareShortcutRecording() { if !active { disarm(); status = "Recording shortcut in Settings only · Escape cancels." } }
    func setShortcut(_ value: ShortcutBinding) {
        guard !active, value.valid else { return }
        disarm(); shortcut = value
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "dictation.shortcut.v1") }
        status = "Saved \(value.display). Enable dictation below; this does not start recording."
    }
    static func missing(consent: Bool, credentialsValid: Bool, microphoneReady: Bool, signed: Bool, trusted: Bool) -> [String] {
        [(credentialsValid,"API key"),(consent,"cloud/cost consent"),(microphoneReady,"Microphone access"),(trusted,"Accessibility access (then Check access; macOS may require app reopen)"),(signed,"certificate-signed Temada app")].compactMap { $0.0 ? nil : $0.1 }
    }
    var onHotkey: (() -> Void)?
    var onCancel: (() -> Void)?
    func requestAccessibility() {
        guard AppIdentity.certificateSigned else { status = "Use the signed Temada app."; return }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
    func checkAccess(consent: Bool, credentialsValid: Bool, microphoneReady: Bool) {
        let needs = Self.missing(consent: consent, credentialsValid: credentialsValid, microphoneReady: microphoneReady, signed: signed(), trusted: trusted())
        if needs.isEmpty { status = armed ? "Ready · \(shortcut.display)." : "Access ready. Click Enable \(shortcut.display) to register the shortcut." }
        else { if armed { disarm() }; status = "Missing: " + needs.joined(separator: "; ") + ". Nothing recorded." }
    }
    func arm(consent: Bool, credentialsValid: Bool, microphoneReady: Bool) {
        guard !active else { return }
        hotkey.unregister(); armed = false
        let needs = Self.missing(consent: consent, credentialsValid: credentialsValid, microphoneReady: microphoneReady, signed: signed(), trusted: trusted())
        guard needs.isEmpty else { status = "Missing: " + needs.joined(separator: "; ") + ". Nothing registered or recorded."; return }
        hotkey.triggered = { [weak self] in self?.onHotkey?() }
        let code = hotkey.register(shortcut)
        guard code == noErr else { hotkey.unregister(); status = "Cannot register \(shortcut.display) (macOS code \(code)). Another app or macOS may own it. Record a different shortcut; check Keyboard → Keyboard Shortcuts. No recording started."; return }
        armed = true; status = "Ready · focus a text caret, \(shortcut.display) to speak, again to finish."
    }
    func disarm() { hotkey.unregister(); armed = false; cancel() }
    func begin() -> Bool {
        guard armed, !active else { return false }
        do { cursor = try FocusedCursor.capture() }
        catch { status = "Use an editable, non-password text caret with no selection. No audio sent."; return false }
        buffer.begin(); active = true; draft = ""; status = "Connecting · wait for microphone indicator before speaking (then \(shortcut.display) to finish)."
        return true
    }
    func consume(_ frames: [WireFrame]) throws {
        try buffer.consume(frames); draft = buffer.translation
        if buffer.phase == .listening, frames.contains(where: { $0.kind == "status" && $0.message?.hasPrefix("Live connected") == true }) {
            status = "Listening · Uzbek → English · \(shortcut.display) to finish (60s max)."
        }
    }
    func requestFinish() -> Bool {
        guard buffer.phase == .listening else { return false }
        buffer.finish(); status = "Finishing translation · microphone stopping · up to 15s for final turn."
        return true
    }
    func cancel() {
        buffer.cancel(); cursor = nil
        if active { onCancel?() }
        status = active ? "Cancelled — draft only, nothing will be inserted." : "Off."
    }
    func completed(cleanly: Bool) {
        let text = buffer.completed(cleanly: cleanly)
        defer { active = false; cursor = nil }
        guard let text, let cursor else { status = "Nothing inserted. Draft retained; check worker status."; return }
        do { try cursor.insert(text); status = "English inserted at the same caret. No Send/Return event. \(shortcut.display) for next phrase." }
        catch { status = "Focus/caret changed or field unsupported. Nothing inserted; draft retained for explicit Copy." }
    }
    func copyDraft(to pasteboard: NSPasteboard) {
        guard !draft.isEmpty else { return }
        pasteboard.clearContents(); pasteboard.setString(draft, forType: .string)
    }
}
