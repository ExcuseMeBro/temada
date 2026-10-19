import Foundation
import AppKit

@MainActor enum NativeTests {
    static func frame(_ original: String? = nil, _ translation: String? = nil, source: String = "system", inputDone: Bool = false, outputDone: Bool = false) -> WireFrame {
        WireFrame(kind: "text", source: source, original: original, translation: translation, inputFinished: inputDone, outputFinished: outputDone)
    }
    static func run() {
        PermissionTests.run()
        var t = CaptionTimeline()
        try! t.consume(frame("Hello. Next.", "Salom. Keyingi.", inputDone: true, outputDone: true))
        precondition(t.pairs.count == 2 && t.pairs[0].original == "Hello." && t.pairs[0].translation == "Salom.")
        precondition(t.pairs[1].original == "Next." && t.pairs[1].translation == "Keyingi.")
        let id = t.pairs[0].id
        t.clear(); try! t.consume(frame("Привет, ")); try! t.consume(frame("salom!", "Hello!"))
        precondition(t.pairs.count == 1 && t.pairs[0].original == "Привет, salom!")
        precondition(t.pairs[0].id == id)
        t.clear(); try! t.consume(frame(nil, "Salom.", outputDone: true)); try! t.consume(frame("Hello.", inputDone: true))
        precondition(t.pairs.count == 1 && t.pairs[0].translation == "Salom.")
        t.clear(); try! t.consume(frame(nil, "System only", source: "system")); try! t.consume(frame("Mic only", source: "microphone"))
        precondition(t.pairs.count == 2 && t.pairs[0].source != t.pairs[1].source)
        precondition(t.pairs[1].translation.isEmpty)
        t.clear(); try! t.consume(frame("Value 3.14 is valid.", "3.14 to‘g‘ri.", inputDone: true, outputDone: true))
        precondition(t.pairs.count == 1)
        t.clear()
        for _ in 0..<100 { try! t.consume(frame("Hi.", "Salom.", inputDone: true, outputDone: true)) }
        precondition(t.pairs.count <= 48 && t.pairs.last!.translation == "Salom.")
        t.clear()
        do { try t.consume(frame(String(repeating: "Hi. ", count: 70))); preconditionFailure("Unbounded unmatched rows") } catch {}
        precondition(t.pairs.count <= 64)
        t.clear()
        do { try t.consume(frame(String(repeating: "Я", count: 33000))); preconditionFailure("Unbounded text") } catch {}
        do { try t.consume(frame("x", source: "unknown")); preconditionFailure("Unknown source accepted") } catch {}
        let captions = Captions()
        try! captions.consume(WireFrame(kind: "text", source: "system", interim: "Hel…"))
        precondition(captions.rows.count == 1 && captions.rows[0].original == "Hel…" && captions.rows[0].translation.isEmpty)
        try! captions.consume(frame("Hello.", "Salom."))
        precondition(captions.rows.count == 1 && captions.rows[0].original == "Hello.")
        captions.clear(); precondition(captions.rows.isEmpty)
        let name = "MeetingCaptions.NativeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = Preferences(defaults: defaults)
        prefs.appearance.originalSize = 30; prefs.appearance.translationColor = "#AABBCC"
        prefs.appearance.width = 940; prefs.appearance.x = 30
        let loaded = Preferences(defaults: defaults)
        precondition(loaded.appearance.originalSize == 30 && loaded.appearance.width == 940 && loaded.appearance.translationColor == "#AABBCC" && loaded.appearance.x == 30)
        var bad = Appearance(); bad.width = -20; bad.originalSize = .nan; bad.opacity = 8; bad.originalColor = "bad"; bad.visiblePairs = 999; bad.clamp()
        precondition(bad.width == 340 && bad.originalSize == 21 && bad.opacity == 1 && bad.visiblePairs == 12 && Appearance.isColor(bad.originalColor))
        let json = try! JSONEncoder().encode(prefs.appearance)
        precondition(!String(data: json, encoding: .utf8)!.contains("apiKey"))
        let decoded = try! JSONDecoder().decode(WireFrame.self, from: Data("{\"kind\":\"boundary\",\"source\":\"system\",\"inputFinished\":true}".utf8))
        precondition(decoded.inputFinished == true)
        NSApplication.shared.setActivationPolicy(.prohibited)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 820, height: 330), styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let hosting = captionHostingView(preferences: prefs, captions: captions)
        precondition(hosting.sizingOptions.isEmpty)
        panel.contentView = hosting
        panel.setFrame(NSRect(x: 0, y: 0, width: 820, height: 330), display: false)
        hosting.layoutSubtreeIfNeeded()
        let pipe = Pipe()
        var delivered = false, pipeFailed = false
        FrameReader(pipe.fileHandleForReading, deliver: { frames in delivered = frames.first?.message == "fixture" }, failed: { pipeFailed = true }).start()
        try! pipe.fileHandleForWriting.write(contentsOf: Data("{\"kind\":\"status\",\"message\":\"fixture\"}\n".utf8))
        // Keep writer OPEN: a short caption must arrive without filling a 16KiB read.
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        precondition(delivered && !pipeFailed, "Short IPC frame buffered until EOF")
        try! pipe.fileHandleForWriting.close()
        precondition(panel.frame.width == 820 && panel.frame.height == 330, "Empty SwiftUI content resized caption window")
        panel.close()
        InteractionTests.run(preferences: prefs)
        print("NATIVE_SELFTEST: PASS — sentence rows, partial/order/source isolation, UTF8/bounds, persistence/clamp, short-frame IPC before EOF")
    }
}
