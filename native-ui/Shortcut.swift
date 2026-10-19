import AppKit
import Carbon
import SwiftUI

struct ShortcutBinding: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String
    static let allowedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    static let functionKeys: Set<UInt32> = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
    static let defaultBinding = ShortcutBinding(keyCode: 49, modifiers: UInt32(cmdKey | shiftKey), keyLabel: "Space")
    var valid: Bool {
        keyCode <= 127 && ![54,55,56,57,58,59,60,61,62,63].contains(keyCode) &&
        modifiers & ~Self.allowedModifiers == 0 &&
        (modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 || Self.functionKeys.contains(keyCode)) &&
        !keyLabel.isEmpty && keyLabel.utf8.count <= 48 && !keyLabel.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    var display: String {
        [(controlKey,"⌃"),(optionKey,"⌥"),(shiftKey,"⇧"),(cmdKey,"⌘")].reduce("") { $0 + (modifiers & UInt32($1.0) != 0 ? $1.1 : "") } + keyLabel
    }
    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) { self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel }
    init?(event: NSEvent) {
        var bits: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.command,cmdKey),(.control,controlKey),(.option,optionKey),(.shift,shiftKey)] {
            if event.modifierFlags.contains(flag) { bits |= UInt32(carbon) }
        }
        let code = UInt32(event.keyCode)
        let names: [UInt32:String] = [49:"Space",36:"Return",48:"Tab",51:"Delete",53:"Escape",117:"⌦",123:"←",124:"→",125:"↓",126:"↑",115:"Home",119:"End",116:"Page Up",121:"Page Down"]
        let fOrder: [UInt32] = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
        let label = names[code] ?? fOrder.firstIndex(of: code).map { "F\($0 + 1)" } ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(code)"
        self.init(keyCode: code, modifiers: bits, keyLabel: label)
        if !valid { return nil }
    }
}
struct HotkeyPressGate {
    private var held = false
    mutating func accept(pressed: Bool) -> Bool {
        if !pressed { held = false; return false }
        guard !held else { return false }; held = true; return true
    }
}
@MainActor protocol HotkeyRegistering: AnyObject {
    var triggered: (() -> Void)? { get set }
    func register(_ binding: ShortcutBinding) -> OSStatus
    func unregister()
}
@MainActor final class GlobalDictationHotkey: HotkeyRegistering {
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var gate = HotkeyPressGate()
    var triggered: (() -> Void)?
    nonisolated static func accepts(signature: OSType, id: UInt32) -> Bool { signature == 0x544D4441 && id == 1 }
    func register(_ binding: ShortcutBinding) -> OSStatus {
        guard binding.valid, hotkey == nil, handler == nil else { return OSStatus(paramErr) }
        let specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let result = specs.withUnsafeBufferPointer { types in
            InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let context, let event else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                      GlobalDictationHotkey.accepts(signature: id.signature, id: id.id) else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    let owner = Unmanaged<GlobalDictationHotkey>.fromOpaque(context).takeUnretainedValue()
                    if owner.gate.accept(pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed)) { owner.triggered?() }
                }
                return noErr
            }, types.count, types.baseAddress, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        guard result == noErr else { unregister(); return result }
        let code = RegisterEventHotKey(binding.keyCode, binding.modifiers, EventHotKeyID(signature: 0x544D4441, id: 1), GetApplicationEventTarget(), 0, &hotkey)
        if code != noErr { unregister() }
        return code
    }
    func unregister() {
        if let hotkey { UnregisterEventHotKey(hotkey) }; hotkey = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
        gate = HotkeyPressGate()
    }
}
// Only a focused, explicitly clicked button consumes keys. A temporary local
// monitor protects menu equivalents; no global monitor/event tap, Input
// Monitoring permission, clipboard access or synthetic keyboard events.
@MainActor final class ShortcutRecorderButton: NSButton {
    var changed: ((ShortcutBinding) -> Void)?
    var began: (() -> Void)?
    var current = ShortcutBinding.defaultBinding
    private(set) var recording = false
    private var localMonitor: Any?
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero); bezelStyle = .rounded; target = self; action = #selector(toggleRecording)
        refreshTitle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refreshTitle() { if !recording { title = "Record shortcut…  \(current.display)" } }
    @objc func toggleRecording() {
        if recording { stop(); return }
        began?(); recording = true; title = "Press shortcut · Esc to cancel"
        if window?.makeFirstResponder(self) != true { stop(); return }
        // Scoped to Temada's own focused recorder; intercept menu equivalents
        // such as Command-Q before they can invoke an application action.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return false }
                return self.capture(event)
            }
            return consumed ? nil : event
        }
    }
    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        recording = false; refreshTitle()
    }
    override func resignFirstResponder() -> Bool { stop(); return super.resignFirstResponder() }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow !== window { stop() }; super.viewWillMove(toWindow: newWindow) }
    override func keyDown(with event: NSEvent) { if !capture(event) { super.keyDown(with: event) } }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { capture(event) || super.performKeyEquivalent(with: event) }
    @discardableResult func capture(_ event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return false }
        if event.isARepeat { return true }
        if event.keyCode == 53 && event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty { stop(); return true }
        guard let binding = ShortcutBinding(event: event) else { title = "Use ⌘ / ⌃ / ⌥ + key, or F1–F20 · Esc cancels"; return true }
        current = binding; stop(); changed?(binding); return true
    }
}
struct ShortcutRecorder: NSViewRepresentable {
    let binding: ShortcutBinding
    var began: () -> Void
    var changed: (ShortcutBinding) -> Void
    func makeNSView(context: Context) -> ShortcutRecorderButton { ShortcutRecorderButton() }
    func updateNSView(_ view: ShortcutRecorderButton, context: Context) {
        view.current = binding; view.began = began; view.changed = changed; view.refreshTitle()
    }
}
