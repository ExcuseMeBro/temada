import AppKit
import Combine
import Carbon
import ApplicationServices

@MainActor final class CommandSpaceHotkey {
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var triggered: (() -> Void)?
    private var lastPress = -Double.infinity
    nonisolated static func accepts(signature: OSType, id: UInt32) -> Bool { signature == 0x544D4441 && id == 1 }
    func register() -> Bool {
        guard hotkey == nil, handler == nil else { return false }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let code = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  CommandSpaceHotkey.accepts(signature: id.signature, id: id.id) else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<CommandSpaceHotkey>.fromOpaque(context).takeUnretainedValue()
                let now = ProcessInfo.processInfo.systemUptime
                if now - owner.lastPress >= 0.5 { owner.lastPress = now; owner.triggered?() }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard code == noErr, RegisterEventHotKey(49, UInt32(cmdKey), EventHotKeyID(signature: 0x544D4441, id: 1), GetApplicationEventTarget(), 0, &hotkey) == noErr else { unregister(); return false }
        return true
    }
    func unregister() {
        if let hotkey { UnregisterEventHotKey(hotkey) }; hotkey = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
    }
}
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
    private let hotkey = CommandSpaceHotkey()
    var onHotkey: (() -> Void)?
    var onCancel: (() -> Void)?
    func requestAccessibility() {
        guard AppIdentity.certificateSigned else { status = "Use the signed Temada app."; return }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
    func arm(consent: Bool, credentialsValid: Bool, microphoneReady: Bool) {
        guard consent, credentialsValid, microphoneReady, AppIdentity.certificateSigned, AXIsProcessTrusted() else {
            status = "Need API key, cloud/cost consent, Microphone and Accessibility access."; return
        }
        hotkey.triggered = { [weak self] in self?.onHotkey?() }
        guard hotkey.register() else { status = "⌘Space is unavailable. Check Spotlight shortcut in Keyboard Settings."; return }
        armed = true; status = "Ready · focus a text caret, ⌘Space to speak, ⌘Space again to finish."
    }
    func disarm() { hotkey.unregister(); armed = false; cancel() }
    func begin() -> Bool {
        guard armed, !active else { return false }
        do { cursor = try FocusedCursor.capture() }
        catch { status = "Use an editable, non-password text caret with no selection. No audio sent."; return false }
        buffer.begin(); active = true; draft = ""; status = "Connecting · wait for microphone indicator before speaking (then ⌘Space to finish)."
        return true
    }
    func consume(_ frames: [WireFrame]) throws {
        try buffer.consume(frames); draft = buffer.translation
        if buffer.phase == .listening, frames.contains(where: { $0.kind == "status" && $0.message?.hasPrefix("Live connected") == true }) {
            status = "Listening · Uzbek → English · ⌘Space to finish (60s max)."
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
        do { try cursor.insert(text); status = "English inserted at the same caret. No Send/Return event. ⌘Space for next phrase." }
        catch { status = "Focus/caret changed or field unsupported. Nothing inserted; draft retained for explicit Copy." }
    }
    func copyDraft(to pasteboard: NSPasteboard) {
        guard !draft.isEmpty else { return }
        pasteboard.clearContents(); pasteboard.setString(draft, forType: .string)
    }
}
