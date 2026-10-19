import AppKit
import Carbon

@MainActor private final class FixtureHotkey: HotkeyRegistering {
    var triggered: (() -> Void)?
    var code: OSStatus = noErr
    var registrations: [ShortcutBinding] = []
    var removals = 0
    func register(_ binding: ShortcutBinding) -> OSStatus { registrations.append(binding); return code }
    func unregister() { removals += 1 }
}
@MainActor enum ShortcutTests {
    static func run() {
        let suite = "Temada.ShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = FixtureHotkey()
        let controller = EnglishDictation(defaults: defaults, hotkey: fake, signed: { true }, trusted: { true }, conflict: { _ in nil })
        precondition(controller.shortcut == .defaultBinding && !controller.armed)
        guard ShortcutBinding.defaultBinding.display == "⌃Space" else {
            fputs("SHORTCUT_SELFTEST: FAIL — expected Control+Space, not Command+Space\n", stderr)
            exit(1)
        }
        let custom = ShortcutBinding(keyCode: 40, modifiers: UInt32(controlKey | optionKey), keyLabel: "K")
        precondition(custom.valid && custom.display == "⌃⌥K")
        controller.setShortcut(custom)
        precondition(controller.shortcut == custom && !controller.armed && fake.registrations.isEmpty)
        let restored = EnglishDictation(defaults: defaults, hotkey: FixtureHotkey(), signed: { true }, trusted: { true })
        precondition(restored.shortcut == custom && !restored.armed)
        controller.arm(consent: false, credentialsValid: true, microphoneReady: true)
        precondition(!controller.armed && fake.registrations.isEmpty && controller.status.contains("cloud/cost consent") && !controller.status.contains("API key"))
        controller.checkAccess(consent: true, credentialsValid: true, microphoneReady: true)
        precondition(fake.registrations.isEmpty && !controller.armed, "Check access silently armed a shortcut")
        fake.code = OSStatus(eventHotKeyExistsErr)
        controller.arm(consent: true, credentialsValid: true, microphoneReady: true)
        precondition(!controller.armed && fake.registrations == [custom] && controller.status.contains("\(eventHotKeyExistsErr)") && controller.status.contains(custom.display))
        fake.code = noErr
        controller.arm(consent: true, credentialsValid: true, microphoneReady: true)
        precondition(controller.armed)
        var fires = 0; controller.onHotkey = { fires += 1 }; fake.triggered?(); precondition(fires == 1)
        let beforeRemove = fake.removals
        controller.prepareShortcutRecording()
        precondition(!controller.armed && fake.removals > beforeRemove)
        let missing = EnglishDictation.missing(consent: false, credentialsValid: false, microphoneReady: false, signed: false, trusted: false)
        precondition(missing.count == 5 && missing.joined().contains("Accessibility") && missing.joined().contains("API key"))
        for bad in [ShortcutBinding(keyCode: 0, modifiers: 0, keyLabel: "A"), ShortcutBinding(keyCode: 0, modifiers: UInt32(shiftKey), keyLabel: "A"), ShortcutBinding(keyCode: 55, modifiers: UInt32(cmdKey), keyLabel: "Command"), ShortcutBinding(keyCode: 999, modifiers: UInt32(cmdKey), keyLabel: "Bad"), ShortcutBinding(keyCode: 0, modifiers: UInt32(cmdKey), keyLabel: "bad\n"), ShortcutBinding(keyCode: 0, modifiers: UInt32(cmdKey) | 1, keyLabel: "A")] {
            precondition(!bad.valid); controller.setShortcut(bad); precondition(controller.shortcut == custom)
        }
        defaults.set(Data("{\"keyCode\":999,\"modifiers\":0,\"keyLabel\":\"Bad\"}".utf8), forKey: "dictation.shortcut.v1")
        precondition(EnglishDictation(defaults: defaults, hotkey: FixtureHotkey()).shortcut == .defaultBinding)
        defaults.set(Data("not JSON".utf8), forKey: "dictation.shortcut.v1")
        precondition(EnglishDictation(defaults: defaults, hotkey: FixtureHotkey()).shortcut == .defaultBinding)
        // Read-only symbolic preference parsing uses Cocoa modifier bits, not Carbon bits.
        precondition(GlobalDictationHotkey.accepts(signature: 0x544D4441, id: 2, expectedID: 2))
        precondition(!GlobalDictationHotkey.accepts(signature: 0x544D4441, id: 1, expectedID: 2), "Queued event from audio-free test could start dictation after rearming")
        precondition(!GlobalDictationHotkey.accepts(signature: 0, id: 2, expectedID: 2))
        let space = ShortcutBinding.defaultBinding
        let reserved: [String: Any] = ["60": ["enabled": true, "value": ["parameters": [32, 49, Int(NSEvent.ModifierFlags.control.rawValue)]]]]
        precondition(SystemShortcutConflict.reason(for: space, entries: reserved)?.contains("Input Sources") == true)
        precondition(SystemShortcutConflict.reason(for: custom, entries: reserved) == nil)
        precondition(SystemShortcutConflict.reason(for: space, entries: ["60": ["enabled": false, "value": ["parameters": [32, 49, Int(NSEvent.ModifierFlags.control.rawValue)]]]]) == nil)
        precondition(SystemShortcutConflict.reason(for: space, entries: ["60": ["enabled": true, "value": ["parameters": [32]]]]) == nil)
        let testFake = FixtureHotkey(); var axChecks = 0; var dictationCalls = 0
        let tester = EnglishDictation(defaults: defaults, hotkey: testFake, signed: { true }, trusted: { axChecks += 1; return true }, conflict: { _ in nil })
        tester.onHotkey = { dictationCalls += 1 }
        tester.testShortcut()
        precondition(tester.testingShortcut && !tester.armed && !tester.active && axChecks == 0)
        let stale = testFake.triggered!
        testFake.triggered?()
        precondition(tester.status.contains("Received ⌃Space") && dictationCalls == 0 && tester.draft.isEmpty)
        tester.stopShortcutTest(); let stopped = tester.status; stale()
        precondition(!tester.testingShortcut && testFake.triggered == nil && tester.status == stopped)
        tester.testShortcut(); let fresh = tester.status; stale()
        precondition(tester.status == fresh, "Stale test callback affected a new test")
        tester.expireShortcutTest(UUID()); precondition(tester.testingShortcut)
        tester.arm(consent: true, credentialsValid: true, microphoneReady: true)
        tester.expireShortcutTest(UUID()); stale()
        precondition(tester.armed && !tester.testingShortcut && axChecks == 1 && dictationCalls == 0)
        testFake.triggered?(); precondition(dictationCalls == 1)
        tester.disarm(); testFake.code = OSStatus(eventHotKeyExistsErr); tester.testShortcut()
        precondition(!tester.testingShortcut && !tester.armed && testFake.triggered == nil && tester.status.contains("Cannot test"))
        let blockedFake = FixtureHotkey()
        let blocked = EnglishDictation(defaults: defaults, hotkey: blockedFake, signed: { true }, trusted: { true }, conflict: { SystemShortcutConflict.reason(for: $0, entries: reserved) })
        blocked.testShortcut(); precondition(!blocked.testingShortcut && blockedFake.registrations.isEmpty && blocked.status.contains("Input Sources"))
        blocked.arm(consent: true, credentialsValid: true, microphoneReady: true)
        precondition(!blocked.armed && blockedFake.registrations.isEmpty)
        let unsigned = EnglishDictation(defaults: defaults, hotkey: FixtureHotkey(), signed: { false }, trusted: { preconditionFailure("Audio-free test queried AX trust") }, conflict: { _ in nil })
        unsigned.testShortcut(); precondition(!unsigned.testingShortcut && unsigned.status.contains("certificate-signed"))
        tester.setShortcut(.defaultBinding)
        precondition(EnglishDictation(defaults: defaults, hotkey: FixtureHotkey()).shortcut.display == "⌃Space")
        precondition(!tester.armed && !tester.testingShortcut && tester.draft.isEmpty)
        var gate = HotkeyPressGate()
        precondition(gate.accept(pressed: true) && !gate.accept(pressed: true) && !gate.accept(pressed: false) && gate.accept(pressed: true))
        // Private hidden window, direct method calls only; no events posted to the OS.
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let button = ShortcutRecorderButton(); window.contentView = button
        var selected: [ShortcutBinding] = []; var begins = 0
        button.changed = { selected.append($0) }; button.began = { begins += 1 }
        func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags, _ chars: String, repeating: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: repeating, keyCode: code)!
        }
        let cmdK = event(40, [.command,.shift,.capsLock], "k")
        precondition(!button.capture(cmdK))
        button.toggleRecording(); precondition(button.recording && begins == 1)
        precondition(button.capture(event(40, [.command], "k", repeating: true)) && selected.isEmpty)
        precondition(button.capture(event(0, [], "a")) && button.recording && selected.isEmpty)
        precondition(button.performKeyEquivalent(with: cmdK) && !button.recording)
        precondition(selected.last == ShortcutBinding(keyCode: 40, modifiers: UInt32(cmdKey | shiftKey), keyLabel: "K"))
        button.toggleRecording(); precondition(button.capture(event(53, [], "\u{1b}")) && !button.recording && selected.count == 1)
        button.toggleRecording(); _ = window.makeFirstResponder(nil)
        precondition(!button.recording && !button.capture(cmdK))
        button.toggleRecording(); precondition(button.capture(event(122, [.function], "\u{f704}")))
        precondition(selected.last?.display == "F1" && selected.last!.valid)
        button.toggleRecording(); window.contentView = NSView(); precondition(!button.recording)
        window.close(); controller.disarm()
        print("SHORTCUT_SELFTEST: PASS — Control+Space default/explicit preset, read-only Input Sources conflict parsing, audio-free test/cancel/stale callbacks/signing gates, configurable modifiers/keycodes, persistence/invalid defaults, conflict codes/cleanup, exact missing gates, explicit arm only, press-release/no repeat, focused recorder/cancel/resign/removal/F-key/menu-equivalent routing; no real global registration or OS event injection")
    }
}
