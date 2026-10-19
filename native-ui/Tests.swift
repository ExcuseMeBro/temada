import Foundation
import AppKit

@MainActor enum NativeTests {
    static func frame(_ original: String? = nil, _ translation: String? = nil, source: String = "system", inputDone: Bool = false, outputDone: Bool = false) -> WireFrame {
        WireFrame(kind: "text", source: source, original: original, translation: translation, inputFinished: inputDone, outputFinished: outputDone)
    }
    static func run() {
        StatusIconTests.run()
        EditingTests.run()
        HistoryTests.run()
        DictationTests.run()
        PermissionTests.run()
        MeetingFileTests.run()
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
        let older = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(prefs.appearance)) as! [String: Any]
        var olderFields = older; olderFields.removeValue(forKey: "saveMeetings"); olderFields.removeValue(forKey: "meetingFolder"); olderFields.removeValue(forKey: "compactText")
        defaults.set(try! JSONSerialization.data(withJSONObject: olderFields), forKey: "appearance.v1")
        let migrated = Preferences(defaults: defaults)
        precondition(migrated.appearance.originalSize == 30 && migrated.appearance.width == 940 && migrated.appearance.x == 30 && migrated.appearance.saveMeetings && migrated.appearance.meetingFolder.hasSuffix("Temada/Meetings") && migrated.appearance.compactText, "Older appearance lost during new settings migration")
        var bad = Appearance(); bad.width = -20; bad.originalSize = .nan; bad.opacity = 8; bad.originalColor = "bad"; bad.visiblePairs = 999; bad.clamp()
        precondition(bad.width == 340 && bad.originalSize == 17 && bad.opacity == 1 && bad.visiblePairs == 12 && Appearance.isColor(bad.originalColor))
        let json = try! JSONEncoder().encode(prefs.appearance)
        precondition(!String(data: json, encoding: .utf8)!.contains("apiKey"))
        precondition(!String(data: json, encoding: .utf8)!.contains("envPath"))
        let credentials = APICredentials()
        precondition(!credentials.valid)
        credentials.apiKey = "fixture-quote\"-slash\\-only"
        precondition(credentials.valid)
        do { _ = try credentials.bootstrap(consent: false); preconditionFailure("Credential transfer without consent") } catch {}
        let bootstrap = try! credentials.bootstrap(consent: true)
        precondition(bootstrap.count <= 4096 && bootstrap.last == 10)
        let credentialPipe = Pipe()
        try! StreamingWorker.sendBootstrap(bootstrap, to: credentialPipe.fileHandleForWriting)
        precondition(credentialPipe.fileHandleForReading.availableData == bootstrap)
        try! credentialPipe.fileHandleForReading.close()
        do { try StreamingWorker.sendBootstrap(bootstrap, to: credentialPipe.fileHandleForWriting); preconditionFailure("Broken credential pipe accepted") } catch {}
        try! credentialPipe.fileHandleForWriting.close()
        let parsed = try! JSONSerialization.jsonObject(with: bootstrap) as! [String: String]
        precondition(parsed["apiKey"] == credentials.apiKey)
        let arguments = StreamingWorker.arguments(appearance: prefs.appearance)
        precondition(!arguments.contains(credentials.apiKey) && !arguments.contains("--env-file"))
        precondition(!String(data: json, encoding: .utf8)!.contains(credentials.apiKey))
        precondition(APICredentials().apiKey.isEmpty, "Credentials persisted across model construction")
        let gatedWorker = StreamingWorker()
        gatedWorker.start(appearance: prefs.appearance, credentials: credentials, consent: false)
        precondition(!gatedWorker.running && !gatedWorker.status.contains(credentials.apiKey))
        for badKey in ["", "has space", "ключ", "has\nnewline", String(repeating: "x", count: 1025)] {
            credentials.apiKey = badKey; precondition(!credentials.valid)
        }
        credentials.apiKey = String(repeating: "x", count: 1024)
        precondition(credentials.valid && (try! credentials.bootstrap(consent: true)).count <= 4096)
        print("CREDENTIAL_SELFTEST: PASS — memory-only, consent gate, escaped bounded pipe frame, argv/preferences exclusion")
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
        var exitFirst = WorkerCompletionGate(); exitFirst.exitCode = 0
        precondition(exitFirst.takeCompletedStatus() == nil)
        exitFirst.readerEnded = true; precondition(exitFirst.takeCompletedStatus() == 0 && exitFirst.takeCompletedStatus() == nil)
        var eofFirst = WorkerCompletionGate(); eofFirst.readerEnded = true
        precondition(eofFirst.takeCompletedStatus() == nil)
        eofFirst.exitCode = 7; precondition(eofFirst.takeCompletedStatus() == 7 && eofFirst.takeCompletedStatus() == nil)
        var delivered = false, pipeFailed = false, readerEnded = false
        FrameReader(pipe.fileHandleForReading, deliver: { frames in delivered = frames.first?.message == "fixture" }, failed: { pipeFailed = true }, ended: { precondition(delivered); readerEnded = true; CFRunLoopStop(CFRunLoopGetMain()) }).start()
        try! pipe.fileHandleForWriting.write(contentsOf: Data("{\"kind\":\"status\",\"message\":\"fixture\"}\n".utf8))
        // Keep writer OPEN: a short caption must arrive without filling a 16KiB read.
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        precondition(delivered && !pipeFailed && !readerEnded, "Short IPC frame buffered until EOF")
        try! pipe.fileHandleForWriting.close()
        CFRunLoopRunInMode(.defaultMode, 5, false)
        precondition(readerEnded && !pipeFailed, "Reader EOF lost before meeting finalization")
        print("DRAIN_GATE_SELFTEST: PASS — exit/EOF both orders, exactly-once completion, final frame before EOF")
        precondition(panel.frame.width == 820 && panel.frame.height == 330, "Empty SwiftUI content resized caption window")
        let longOriginal = String(repeating: "Original Привет salom ", count: 90)
        let longTranslation = String(repeating: "Translation tarjima перевод ", count: 90)
        try! captions.consume(frame(longOriginal, longTranslation))
        let beforeCompact = captions.rows
        let beforeSettings = prefs.appearance
        prefs.useCompactLayout()
        precondition(prefs.appearance.width == 620 && prefs.appearance.height == 190 && prefs.appearance.originalSize == 17 && prefs.appearance.translationSize == 20 && prefs.appearance.visiblePairs == 1 && prefs.appearance.compactText)
        precondition(prefs.appearance.x == beforeSettings.x && prefs.appearance.originalColor == beforeSettings.originalColor && prefs.appearance.translationColor == beforeSettings.translationColor && prefs.appearance.saveMeetings == beforeSettings.saveMeetings && prefs.appearance.meetingFolder == beforeSettings.meetingFolder && prefs.appearance.source == beforeSettings.source && prefs.appearance.target == beforeSettings.target)
        panel.setFrame(NSRect(x: 0, y: 0, width: 620, height: 190), display: false); hosting.layoutSubtreeIfNeeded()
        precondition(panel.frame.width == 620 && panel.frame.height == 190 && captions.rows == beforeCompact, "Compact presentation resized window or truncated full transcript model")
        let compactReload = Preferences(defaults: defaults)
        precondition(compactReload.appearance.width == 620 && compactReload.appearance.height == 190 && compactReload.appearance.compactText)
        print("COMPACT_OVERLAY_SELFTEST: PASS — 620x190, 17/20pt, full scrollback, long Unicode model intact, persistence and non-layout preferences retained")
        panel.close()
        InteractionTests.run(preferences: prefs)
        print("NATIVE_SELFTEST: PASS — sentence rows, partial/order/source isolation, UTF8/bounds, persistence/clamp, short-frame IPC before EOF")
    }
}
