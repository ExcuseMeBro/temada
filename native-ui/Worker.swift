import Foundation
import Combine

// Bounded blocking pipe reader lives off the UI thread. Main-thread delivery is
// synchronous so a busy UI backpressures the pipe, not an unbounded Task queue.
final class FrameReader: @unchecked Sendable {
    let handle: FileHandle
    let deliver: @MainActor ([WireFrame]) -> Void
    let failed: @MainActor () -> Void
    init(_ handle: FileHandle, deliver: @escaping @MainActor ([WireFrame]) -> Void, failed: @escaping @MainActor () -> Void) {
        self.handle = handle; self.deliver = deliver; self.failed = failed
    }
    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer { try? handle.close() }
            do {
                var buffer = Data()
                while true {
                    // FileHandle.read(upToCount:) may wait to fill its requested
                    // length on a pipe. availableData returns the next short frame.
                    let data = handle.availableData
                    if data.isEmpty { break }
                    buffer.append(data)
                    guard buffer.count <= 262144 else { throw ReaderError.oversize }
                    var frames: [WireFrame] = []
                    while let end = buffer.firstIndex(of: 10) {
                        let line = buffer[..<end]
                        guard line.count <= 200000 else { throw ReaderError.oversize }
                        let frame = try JSONDecoder().decode(WireFrame.self, from: line)
                        guard ["text", "boundary", "status", "error", "stopped"].contains(frame.kind) else { throw ReaderError.protocolError }
                        frames.append(frame); buffer.removeSubrange(...end)
                    }
                    if !frames.isEmpty {
                        DispatchQueue.main.sync { MainActor.assumeIsolated { deliver(frames) } }
                    }
                }
                if !buffer.isEmpty { throw ReaderError.protocolError }
            } catch {
                DispatchQueue.main.async { MainActor.assumeIsolated { self.failed() } }
            }
        }
    }
    enum ReaderError: Error { case oversize, protocolError }
}
@MainActor final class StreamingWorker: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var status = "Ready — choose audio, consent, then Start."
    private var process: Process?
    private var input: FileHandle?
    private var generation = UUID()
    var onFrames: (([WireFrame]) -> Void)?
    var onStopped: (() -> Void)?
    func start(appearance: Appearance, consent: Bool) {
        guard !running else { return }
        guard consent else { status = "Cloud/cost consent is required."; return }
        guard !appearance.envPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "Choose an existing .env file."; return }
        guard let folder = Bundle.main.executableURL?.deletingLastPathComponent() else { status = "App bundle unavailable."; return }
        let task = Process(), stdin = Pipe(), stdout = Pipe()
        task.executableURL = folder.appendingPathComponent("meeting-captions")
        task.arguments = ["--native-worker", "--cloud-consent", "--env-file", appearance.envPath, "--source", appearance.source, "--target", appearance.target]
        task.standardInput = stdin; task.standardOutput = stdout; task.standardError = FileHandle.nullDevice
        let id = UUID(); generation = id
        task.terminationHandler = { [weak self] task in
            let code = task.terminationStatus
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == id else { return }
                self.running = false; self.process = nil
                try? self.input?.close(); self.input = nil
                if code != 0 && !self.status.hasPrefix("Error:") { self.status = "Worker stopped (\(code)); check .env, quota and permissions." }
                else if !self.status.hasPrefix("Error:") { self.status = "Stopped. Pending audio/text may have been discarded." }
                self.onStopped?()
            }
        }
        do {
            try task.run()
            try? stdin.fileHandleForReading.close(); try? stdout.fileHandleForWriting.close()
            process = task; input = stdin.fileHandleForWriting; running = true
            status = "Connecting to Gemini Live…"
            FrameReader(stdout.fileHandleForReading, deliver: { [weak self] frames in
                guard let self, self.generation == id else { return }
                for frame in frames {
                    if frame.kind == "error" { self.status = "Error: \(frame.message ?? "Streaming failed")" }
                    else if frame.kind == "status" { self.status = frame.message ?? "Streaming" }
                }
                self.onFrames?(frames)
            }, failed: { [weak self] in
                guard let self, self.generation == id else { return }
                self.fail("Invalid or oversized worker response; stopped.")
            }).start()
        } catch {
            try? stdin.fileHandleForWriting.close(); try? stdout.fileHandleForReading.close()
            status = "Cannot start bundled worker. Rebuild the native app."; running = false
        }
    }
    func stop() {
        guard running else { return }
        if !status.hasPrefix("Error:") { status = "Stopping…" }
        try? input?.close(); input = nil
        // EOF cancels only the owned worker; never signal another app/session.
    }
    func fail(_ message: String) { status = "Error: \(message)"; stop() }
}
