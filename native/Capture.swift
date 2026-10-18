import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import Darwin

// Only this task-owned helper is terminated by the Rust parent. No external apps.
func emit(_ line: String) { print(line); fflush(stdout) }
func fail(_ message: String) -> Never { emit("ERROR: \(message)"); exit(1) }

final class ChunkWriter: @unchecked Sendable {
    let directory: URL
    private var file: AVAudioFile?
    private var seconds = 0.0
    private var sequence = 0
    private var name = ""
    init(_ directory: URL) { self.directory = directory }
    func append(_ buffer: AVAudioPCMBuffer) {
        do {
            if file == nil {
                let waiting = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".wav") }.count
                if waiting >= 4 { emit("OVERLOAD"); exit(2) }
                name = "audio-\(sequence).wav"
                sequence += 1
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: buffer.format.sampleRate,
                    AVNumberOfChannelsKey: Int(buffer.format.channelCount),
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
                file = try AVAudioFile(forWriting: directory.appendingPathComponent(name), settings: settings, commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
                seconds = 0
            }
            try file?.write(from: buffer)
            seconds += Double(buffer.frameLength) / buffer.format.sampleRate
            if seconds >= 4 {
                file = nil // close WAV header before publishing filename
                emit("CHUNK:\(name)")
            }
        } catch { fail("Audio encoding failed. Check available disk space.") }
    }
}

final class SystemCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let writer: ChunkWriter
    var stream: SCStream?
    init(_ writer: ChunkWriter) { self.writer = writer }
    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw NSError(domain: "No display available", code: 1) }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000
        config.channelCount = 1
        config.width = 2; config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "meeting.audio"))
        self.stream = stream
        try await stream.startCapture()
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { fail("System audio capture stopped; check Screen & System Audio Recording permission.") }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let description = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd) else { return }
        let count = CMSampleBufferGetNumSamples(sampleBuffer)
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(count), into: buffer.mutableAudioBufferList)
        if status != noErr { fail("System audio PCM conversion failed.") }
        writer.append(buffer)
    }
}

actor CaptureLifetime {
    static let shared = CaptureLifetime()
    private var resource: AnyObject?
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(retaining resource: AnyObject) async {
        self.resource = resource
        await withCheckedContinuation { continuation = $0 }
    }
}

@main struct CaptureMain {
    static func main() async {
        guard CommandLine.arguments.count == 3 else { fail("Expected private output directory and system|microphone") }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let writer = ChunkWriter(directory)
        if CommandLine.arguments[2] == "self-test" || CommandLine.arguments[2] == "overload-test" {
            // Synthetic PCM only: never requests permission or accesses a device.
            let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64000)!
            buffer.frameLength = 64000
            for index in 0..<64000 { buffer.floatChannelData![0][index] = 0.1 * sin(Float(index) * 0.05) }
            let count = CommandLine.arguments[2] == "self-test" ? 1 : 5
            for _ in 0..<count { writer.append(buffer) }
            do {
                let file = try AVAudioFile(forReading: directory.appendingPathComponent("audio-0.wav"))
                guard file.length == 64000, file.fileFormat.sampleRate == 16000 else { fail("Synthetic WAV validation failed") }
                emit("SELFTEST:PASS")
            } catch { fail("Synthetic WAV could not be reopened") }
            return
        } else if CommandLine.arguments[2] == "microphone" {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else { fail("Microphone permission denied. Enable it in System Settings → Privacy & Security.") }
            let engine = AVAudioEngine()
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1600, format: input.outputFormat(forBus: 0)) { buffer, _ in writer.append(buffer) }
            do { try engine.start() } catch { fail("Microphone could not start.") }
            await CaptureLifetime.shared.wait(retaining: engine)
        } else if CommandLine.arguments[2] == "system" {
            let capture = SystemCapture(writer)
            do { try await capture.start() } catch { fail("Cannot capture system audio. Allow Screen & System Audio Recording in System Settings, then restart this app.") }
            await CaptureLifetime.shared.wait(retaining: capture)
        } else { fail("Unknown audio source") }
    }
}
