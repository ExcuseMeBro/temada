import Foundation
import CoreFoundation

@MainActor enum MeetingFileTests {
    private static func finish(_ journal: MeetingJournal, expected: Bool) {
        var completed = false
        journal.finish { okay in
            precondition(okay == expected); completed = true; CFRunLoopStop(CFRunLoopGetMain())
        }
        CFRunLoopRunInMode(.defaultMode, 5, false)
        precondition(completed, "Meeting file writer did not finish within bounded test deadline")
    }
    static func run() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("temada-file-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var writerFailure = false
        let journal = try! MeetingJournal(parent: root, source: "both", target: "uz") { writerFailure = true }
        let captions = Captions()
        for index in 0..<120 {
            var frame = NativeTests.frame("entry-\(index): Привет, hello, salom. ", "tarjima-\(index): O‘zbekcha / English / Русский. ", source: index.isMultiple(of: 2) ? "system" : "microphone", inputDone: true, outputDone: true)
            frame.message = "fixture-private-excluded"
            try! journal.record([frame]); try! captions.consume(frame)
        }
        precondition(captions.rows.count <= 48 && !captions.rows.contains { $0.original.contains("entry-0:") })
        try! journal.record([WireFrame(kind: "status", message: "fixture-private-excluded"), WireFrame(kind: "error", message: "fixture-private-excluded"), WireFrame(kind: "text", source: "system", interim: "Unfinished provisional input")])
        finish(journal, expected: true)
        precondition(!writerFailure)
        let raw = try! Data(contentsOf: journal.folder.appendingPathComponent("meeting.jsonl"))
        let contents = String(decoding: raw, as: UTF8.self)
        precondition(!contents.contains("fixture-private-excluded"))
        let lines = raw.split(separator: 10)
        precondition(lines.count == 122)
        let first = try! JSONDecoder().decode(MeetingRecord.self, from: Data(lines[1]))
        precondition(first.elapsedSeconds >= 0 && first.frame.source == "system" && first.frame.original!.contains("entry-0:"))
        let text = try! String(contentsOf: journal.folder.appendingPathComponent("meeting.md"), encoding: .utf8)
        for marker in ["entry-0:", "entry-119:", "tarjima-0:", "tarjima-119:", "Привет", "O‘zbekcha", "## System audio", "## Microphone", "Provisional input (not final)", "Unfinished provisional input"] { precondition(text.contains(marker), "Missing complete meeting data: \(marker)") }
        let folderMode = try! FileManager.default.attributesOfItem(atPath: journal.folder.path)[.posixPermissions] as! NSNumber
        precondition(folderMode.intValue == 0o700)
        for name in ["meeting.md", "meeting.jsonl"] {
            let mode = try! FileManager.default.attributesOfItem(atPath: journal.folder.appendingPathComponent(name).path)[.posixPermissions] as! NSNumber
            precondition(mode.intValue == 0o600)
        }
        let separate = try! MeetingJournal(parent: root, source: "system", target: "en") { preconditionFailure("Unexpected file failure") }
        precondition(separate.folder != journal.folder)
        finish(separate, expected: true)
        precondition(try! Data(contentsOf: journal.folder.appendingPathComponent("meeting.jsonl")) == raw, "Previous meeting overwritten")
        let limited = try! MeetingJournal(parent: root, source: "system", target: "uz", maxBytes: 1024) { }
        do { try limited.record([NativeTests.frame(String(repeating: "x", count: 2048))]); preconditionFailure("File limit ignored") } catch {}
        finish(limited, expected: false)
        let queued = try! MeetingJournal(parent: root, source: "microphone", target: "ru", maxPending: 1024) { }
        do { try queued.record([NativeTests.frame(String(repeating: "x", count: 2048))]); preconditionFailure("Queue limit ignored") } catch {}
        finish(queued, expected: false)
        let failedExport = try! MeetingJournal(parent: root, source: "system", target: "uz") { }
        // Simulate an unexpected existing output, without touching a real meeting.
        let export = failedExport.folder.appendingPathComponent("meeting.md")
        try! Data("existing-fixture".utf8).write(to: export)
        finish(failedExport, expected: false)
        precondition(try! String(contentsOf: export, encoding: .utf8) == "existing-fixture", "Export overwrote an existing file")
        let disabled = MeetingFiles()
        var settings = Appearance(); settings.saveMeetings = false; settings.meetingFolder = root.appendingPathComponent("disabled").path
        try! disabled.start(appearance: settings)
        precondition(!disabled.busy && !FileManager.default.fileExists(atPath: settings.meetingFolder))
        print("MEETING_FILES_SELFTEST: PASS — all 120 entries beyond UI eviction, EN/RU/UZ, two sources, provisional labels, private/exclusive files, status exclusion, queue/file bounds, failure/disabled-save paths")
    }
}
