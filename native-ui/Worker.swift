import Foundation
import Combine
import Darwin

// Bounded blocking pipe reader lives off the UI thread. Main-thread delivery is
// synchronous so a busy UI backpressures the pipe, not an unbounded Task queue.
final class FrameReader: @unchecked Sendable {
    let handle: FileHandle
    let deliver: @MainActor ([WireFrame]) -> Void
    let failed: @MainActor () -> Void
    let ended: @MainActor () -> Void
    init(_ handle: FileHandle, deliver: @escaping @MainActor ([WireFrame]) -> Void, failed: @escaping @MainActor () -> Void, ended: @escaping @MainActor () -> Void = {}) {
        self.handle = handle; self.deliver = deliver; self.failed = failed; self.ended = ended
    }
    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer {
                try? handle.close()
                DispatchQueue.main.async { MainActor.assumeIsolated { self.ended() } }
            }
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
// A child may exit before its final stdout frames reach the UI/journal.
// Finalize only after BOTH process exit and fully drained reader (in either order).
struct WorkerCompletionGate {
    var exitCode: Int32?
    var readerEnded = false
    mutating func takeCompletedStatus() -> Int32? {
        guard readerEnded, let code = exitCode else { return nil }
        exitCode = nil; return code
    }
}
@MainActor final class StreamingWorker: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var status = "Ready — choose audio, consent, then Start."
    private var process: Process?
    private var input: FileHandle?
    private var generation = UUID()
    private var completion = WorkerCompletionGate()
    var onFrames: (([WireFrame]) -> Void)?
    var onStopped: (() -> Void)?
    static func arguments(appearance: Appearance) -> [String] {
        ["--native-worker", "--cloud-consent", "--source", appearance.source, "--target", appearance.target]
    }
    static func sendBootstrap(_ data: Data, to handle: FileHandle) throws {
        // A failed child must not SIGPIPE-kill the UI while credentials are sent.
        guard fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { throw BootstrapError.pipe }
        try handle.write(contentsOf: data)
    }
    private enum BootstrapError: Error { case pipe }
    func start(appearance: Appearance, credentials: APICredentials, consent: Bool) {
        guard !running else { return }
        guard consent else { status = "Cloud/cost consent is required."; return }
        guard let bootstrap = try? credentials.bootstrap(consent: consent) else { status = "Enter a valid Gemini API key before Start."; return }
        guard let folder = Bundle.main.executableURL?.deletingLastPathComponent() else { status = "App bundle unavailable."; return }
        let task = Process(), stdin = Pipe(), stdout = Pipe()
        task.executableURL = folder.appendingPathComponent("meeting-captions")
        task.arguments = Self.arguments(appearance: appearance)
        task.standardInput = stdin; task.standardOutput = stdout; task.standardError = FileHandle.nullDevice
        let id = UUID(); generation = id; completion = WorkerCompletionGate()
        task.terminationHandler = { [weak self] task in
            let code = task.terminationStatus
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == id else { return }
                self.completion.exitCode = code; self.finishIfDrained()
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
            }, ended: { [weak self] in
                guard let self, self.generation == id else { return }
                self.completion.readerEnded = true; self.finishIfDrained()
            }).start()
            do { try Self.sendBootstrap(bootstrap, to: stdin.fileHandleForWriting) }
            catch { fail("Cannot send API credentials to owned worker; stopped.") }
        } catch {
            try? stdin.fileHandleForWriting.close(); try? stdout.fileHandleForReading.close()
            status = "Cannot start bundled worker. Rebuild the native app."; running = false
        }
    }
    private func finishIfDrained() {
        guard let code = completion.takeCompletedStatus() else { return }
        running = false; process = nil
        try? input?.close(); input = nil
        if code != 0 && !status.hasPrefix("Error:") { status = "Worker stopped (\(code)); check API key, quota and permissions." }
        else if !status.hasPrefix("Error:") { status = "Stopped. Pending audio/text may have been discarded." }
        onStopped?()
    }
    func stop() {
        guard running else { return }
        if !status.hasPrefix("Error:") { status = "Stopping…" }
        try? input?.close(); input = nil
        // EOF cancels only the owned worker; never signal another app/session.
    }
    func fail(_ message: String) { status = "Error: \(message)"; stop() }
}
