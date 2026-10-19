import AppKit
import Combine
import Darwin

struct MeetingRecord: Codable {
    let elapsedSeconds: Double
    let frame: WireFrame
}
// One private serial writer, bounded reserved bytes and outstanding queue. Never
// archives status/error messages or credentials; independent of the alignment cache/UI.
final class MeetingJournal: @unchecked Sendable {
    let folder: URL
    private let journal: URL
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "Temada.meeting-files", qos: .utility)
    private let lock = NSLock()
    private var total = 0, pending = 0
    private var accepting = true, failed = false
    private let maxBytes: Int
    private let maxPending: Int
    private let started = ProcessInfo.processInfo.systemUptime
    private let target: String
    private let failure: @MainActor () -> Void
    init(parent: URL, source: String, target: String, maxBytes: Int = 16_777_216, maxPending: Int = 1_048_576, failure: @escaping @MainActor () -> Void) throws {
        self.maxBytes = maxBytes; self.maxPending = maxPending; self.target = target; self.failure = failure
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        folder = parent.appendingPathComponent("Meeting-\(stamp)-\(UUID().uuidString)", isDirectory: true)
        // mkdir is exclusive. Never reuse/overwrite a previous meeting directory.
        guard mkdir(folder.path, 0o700) == 0 else { throw FileError.create }
        journal = folder.appendingPathComponent("meeting.jsonl")
        handle = try Self.privateFile(journal)
        let metadata: [String: String] = ["format": "temada-meeting-v1", "startedAt": ISO8601DateFormatter().string(from: Date()), "source": source, "target": target, "notice": "Plaintext transcript and translation only. No audio. Provisional segments may change."]
        var header = try JSONSerialization.data(withJSONObject: metadata); header.append(10)
        try append(header)
    }
    private static func privateFile(_ url: URL) throws -> FileHandle {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw FileError.create }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    func record(_ frames: [WireFrame]) throws {
        for frame in frames where frame.kind == "text" || frame.kind == "boundary" {
            guard let source = frame.source, ["system", "microphone"].contains(source) else { throw FileError.source }
            var archived = frame; archived.message = nil
            var data = try JSONEncoder().encode(MeetingRecord(elapsedSeconds: max(0, ProcessInfo.processInfo.systemUptime - started), frame: archived))
            data.append(10); try append(data)
        }
    }
    private func append(_ data: Data) throws {
        lock.lock()
        guard accepting, !failed, data.count <= maxBytes - total, data.count <= maxPending - pending else {
            failed = true; lock.unlock(); throw FileError.limit
        }
        total += data.count; pending += data.count
        queue.async { [self] in
            do { try handle.write(contentsOf: data) }
            catch {
                lock.lock(); let first = !failed; failed = true; lock.unlock()
                if first { DispatchQueue.main.async { self.failure() } }
            }
            lock.lock(); pending -= data.count; lock.unlock()
        }
        lock.unlock()
    }
    func finish(_ completion: @escaping @MainActor (Bool) -> Void) {
        lock.lock()
        guard accepting else { lock.unlock(); return }
        accepting = false
        queue.async { [self] in
            var okay = true
            do {
                try handle.synchronize(); try handle.close()
                try exportMarkdown()
            } catch { okay = false; try? handle.close() }
            lock.lock(); okay = okay && !failed; lock.unlock()
            let result = okay
            DispatchQueue.main.async { completion(result) }
        }
        lock.unlock()
    }
    private func exportMarkdown() throws {
        let bytes = try Data(contentsOf: journal)
        guard bytes.count <= maxBytes else { throw FileError.limit }
        var originals: [String: String] = [:], translations: [String: String] = [:], provisional: [String: String] = [:]
        for (index, line) in bytes.split(separator: 10).enumerated() where index > 0 {
            let record = try JSONDecoder().decode(MeetingRecord.self, from: Data(line))
            guard let source = record.frame.source else { throw FileError.source }
            if let original = record.frame.original { originals[source, default: ""] += original; if !original.isEmpty { provisional.removeValue(forKey: source) } }
            if let translation = record.frame.translation { translations[source, default: ""] += translation }
            if let interim = record.frame.interim, !interim.isEmpty { provisional[source] = interim }
            if record.frame.inputFinished == true { originals[source, default: ""] += "\n" }
            if record.frame.outputFinished == true { translations[source, default: ""] += "\n" }
        }
        var text = "# Temada meeting\n\nTranslation target: \(target)\n\nOriginal and translation are separate streams, not guaranteed sentence-aligned. Last segments may be incomplete. No audio recorded.\n"
        for source in ["system", "microphone"] where originals[source] != nil || translations[source] != nil || provisional[source] != nil {
            text += "\n## \(source == "system" ? "System audio" : "Microphone")\n\n### Original\n\n\(originals[source] ?? "")\n\n### Translation\n\n\(translations[source] ?? "")\n"
            if let interim = provisional[source] { text += "\n### Provisional input (not final)\n\n\(interim)\n" }
        }
        let output = try Self.privateFile(folder.appendingPathComponent("meeting.md"))
        defer { try? output.close() }
        try output.write(contentsOf: Data(text.utf8)); try output.synchronize()
    }
    enum FileError: Error { case create, limit, source }
}
@MainActor final class MeetingFiles: ObservableObject {
    @Published private(set) var status = "Transcripts and translations only; no audio recording."
    @Published private(set) var busy = false
    @Published private(set) var finishing = false
    @Published private(set) var lastFolder: URL?
    private var journal: MeetingJournal?
    var onFailure: (() -> Void)?
    func start(appearance: Appearance) throws {
        guard !busy else { throw MeetingJournal.FileError.create }
        guard appearance.saveMeetings else { status = "Saving is off for this meeting."; return }
        guard appearance.meetingFolder.hasPrefix("/") else { throw MeetingJournal.FileError.create }
        let value = try MeetingJournal(parent: URL(fileURLWithPath: appearance.meetingFolder, isDirectory: true), source: appearance.source, target: appearance.target) { [weak self] in
            self?.status = "File write failed. Partial journal retained; stopping capture."; self?.onFailure?()
        }
        journal = value; lastFolder = value.folder; busy = true; status = "Saving meeting privately as JSONL; Markdown is exported on Stop."
    }
    func record(_ frames: [WireFrame]) throws { try journal?.record(frames) }
    func finish(_ completion: @escaping (Bool) -> Void) {
        guard !finishing else { return }
        guard let journal else { completion(true); return }
        finishing = true; status = "Finishing meeting files…"
        journal.finish { [weak self] okay in
            guard let self else { return }
            self.journal = nil; self.busy = false; self.finishing = false
            self.status = okay ? "Meeting saved: meeting.md + meeting.jsonl" : "Save incomplete. Partial files retained; inspect them before relying on this meeting."
            completion(okay)
        }
    }
    func reveal() { if let lastFolder { NSWorkspace.shared.open(lastFolder) } }
}
