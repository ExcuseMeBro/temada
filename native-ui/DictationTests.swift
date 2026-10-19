import AppKit

@MainActor enum DictationTests {
    static func run() {
        precondition(CommandSpaceHotkey.accepts(signature: 0x544D4441, id: 1))
        precondition(!CommandSpaceHotkey.accepts(signature: 0, id: 1) && !CommandSpaceHotkey.accepts(signature: 0x544D4441, id: 2))
        var buffer = DictationBuffer()
        try! buffer.consume([NativeTests.frame(nil, "ignored", source: "microphone")])
        precondition(buffer.translation.isEmpty && !buffer.active)
        buffer.begin()
        try! buffer.consume([NativeTests.frame("Salom", "Hello", source: "microphone")])
        buffer.finish()
        try! buffer.consume([NativeTests.frame(" dunyo", " world.", source: "microphone")])
        precondition(buffer.original == "Salom dunyo" && buffer.completed(cleanly: true) == "Hello world.")
        precondition(buffer.completed(cleanly: true) == nil, "Duplicate insertion")
        buffer.begin(); try! buffer.consume([NativeTests.frame(nil, "Draft", source: "microphone")])
        precondition(buffer.completed(cleanly: true) == nil, "Inserted without explicit finish")
        buffer.begin(); buffer.finish(); try! buffer.consume([NativeTests.frame(nil, "Draft", source: "microphone")])
        precondition(buffer.completed(cleanly: false) == nil && buffer.translation == "Draft")
        buffer.begin(); buffer.finish(); buffer.cancel()
        precondition(buffer.completed(cleanly: true) == nil)
        buffer.begin(); buffer.finish()
        try! buffer.consume([WireFrame(kind: "error", message: "fixture")])
        precondition(buffer.completed(cleanly: true) == nil)
        buffer.begin(); buffer.finish(); precondition(buffer.completed(cleanly: true) == nil)
        buffer.begin()
        do { try buffer.consume([NativeTests.frame(nil, "bad", source: "system")]); preconditionFailure("Cross-source dictation") } catch {}
        precondition(buffer.completed(cleanly: true) == nil)
        buffer.begin(); try! buffer.consume([NativeTests.frame(nil, "old", source: "microphone")])
        do { try buffer.consume([NativeTests.frame(nil, String(repeating: "я", count: 8000), source: "microphone")]); preconditionFailure("Dictation bound bypassed") } catch {}
        precondition(buffer.translation == "old" && buffer.completed(cleanly: true) == nil)
        for exitFirst in [true, false] {
            var completion = WorkerCompletionGate()
            if exitFirst { completion.exitCode = 0 } else { completion.readerEnded = true }
            completion.cancelled = true // Stop/error races a successful exit before reader drain.
            if exitFirst { completion.readerEnded = true } else { completion.exitCode = 0 }
            let code = completion.takeCompletedStatus()!
            precondition(!completion.allowsSuccess(code) && completion.takeCompletedStatus() == nil)
        }
        precondition(WorkerCompletionGate().allowsSuccess(0) && !WorkerCompletionGate().allowsSuccess(1))
        precondition(CursorPolicy.safeText("Hello world. Next sentence."))
        for text in ["", "Hi\n", "Hi\r", "Hi\t", "Hi\u{0000}", "Hi\u{2028}", String(repeating: "a", count: 16001)] {
            precondition(!CursorPolicy.safeText(text))
        }
        precondition(!CursorPolicy.safeApplication(nil) && !CursorPolicy.safeApplication("com.apple.Terminal") && !CursorPolicy.safeApplication("com.googlecode.iterm2") && !CursorPolicy.safeApplication("dev.warp.Warp-Stable") && CursorPolicy.safeApplication("com.example.editor"))
        let before = CursorContext(pid: 123, location: 4, length: 0, role: "AXTextArea", secure: false, editable: true)
        func permits(_ after: CursorContext, same: Bool = true, trusted: Bool = true, own: pid_t = 999) -> Bool {
            CursorPolicy.permits(before: before, after: after, sameElement: same, trusted: trusted, ownPID: own)
        }
        precondition(permits(before))
        precondition(!permits(before, same: false) && !permits(before, trusted: false) && !permits(before, own: 123))
        for variant in 0..<7 {
            var changed = before
            switch variant {
            case 0: changed.pid = 456
            case 1: changed.location = 5
            case 2: changed.length = 3
            case 3: changed.role = "AXButton"
            case 4: changed.secure = true
            case 5: changed.editable = false
            default: changed.location = -1
            }
            precondition(!permits(changed))
            precondition(!CursorPolicy.permits(before: changed, after: changed, sameElement: true, trusted: true, ownPID: 999) || variant == 0 || variant == 1)
        }
        var config = Appearance(); config.source = "microphone"; config.target = "en"
        let args = StreamingWorker.arguments(appearance: config, dictation: true)
        precondition(args.contains("--dictation") && !args.contains("--env-file"))
        precondition(!StreamingWorker.arguments(appearance: config).contains("--dictation"))
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("fixture clipboard unchanged", forType: .string)
        let controller = EnglishDictation(); controller.copyDraft(to: board)
        precondition(board.string(forType: .string) == "fixture clipboard unchanged")
        print("DICTATION_SELFTEST: PASS — explicit finish only, late final text, cancel/error/empty/duplicate/bounds/source guards, cursor focus/role/caret/selection/secure/trust/own-app policy, argv isolation; no real AX/hotkey/clipboard access")
    }
}
