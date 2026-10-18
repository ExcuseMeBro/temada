import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import Darwin

// Only this task-owned helper is terminated by the Rust parent. No external apps.
func emit(_ line: String) { print(line); fflush(stdout) }
func fail(_ message: String) -> Never { emit("ERROR: \(message)"); exit(1) }

final class StreamEncoder {
    private var converter: AVAudioConverter?
    private var source: AVAudioFormat?
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    func encode(_ buffer: AVAudioPCMBuffer) -> Data {
        if source != buffer.format {
            source = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { fail("PCM16 converter unavailable") }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { fail("PCM buffer allocation failed") }
        var supplied = false
        var data = Data()
        // Drain all available converter output before the next native callback.
        // Returning after one full output buffer otherwise accumulates resampler backlog.
        for _ in 0..<8 {
            var error: NSError?
            output.frameLength = 0
            let status = converter.convert(to: output, error: &error) { _, result in
                if supplied { result.pointee = .noDataNow; return nil }
                supplied = true; result.pointee = .haveData; return buffer
            }
            guard status != .error, error == nil else { fail("PCM16 resampling failed") }
            if output.frameLength > 0 {
                data.append(Data(bytes: output.int16ChannelData![0], count: Int(output.frameLength) * 2))
            }
            if status != .haveData { return data }
        }
        fail("PCM16 converter failed to drain")
    }
}
final class ChunkWriter: @unchecked Sendable {
    let directory: URL
    private var file: AVAudioFile?
    private var seconds = 0.0
    private var sequence = 0
    private var name = ""
    private let streaming: Bool
    private let encoder = StreamEncoder()
    init(_ directory: URL, streaming: Bool = false) { self.directory = directory; self.streaming = streaming }
    func append(_ buffer: AVAudioPCMBuffer) {
        if streaming {
            let data = encoder.encode(buffer)
            // Bound frames to <= 100ms. Rust drains this pipe asynchronously with backpressure.
            for offset in stride(from: 0, to: data.count, by: 3200) {
                emit("PCM:\(data.subdata(in: offset..<min(offset + 3200, data.count)).base64EncodedString())")
            }
            return
        }
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
        let mode = CommandLine.arguments[2].replacingOccurrences(of: "live-", with: "")
        let streaming = CommandLine.arguments[2].hasPrefix("live-")
        let writer = ChunkWriter(directory, streaming: streaming)
        if mode == "pcm-test" {
            // 48kHz stereo -> mono 16kHz signed LE PCM, without devices or cloud.
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
            buffer.frameLength = 48000
            for channel in 0..<2 { for i in 0..<48000 { buffer.floatChannelData![channel][i] = 0.2 * sin(Float(i) * 0.05) } }
            let encoder = StreamEncoder()
            let first = encoder.encode(buffer)
            let steady = encoder.encode(buffer)
            // Resampler startup retains a filter tail, with block-sized output jitter.
            // Verify sustained sample count too, rather than assuming exact per-call output.
            var total = first.count + steady.count
            for _ in 0..<30 { total += encoder.encode(buffer).count }
            guard first.count > 28000, first.count <= 32000, first.count % 2 == 0,
                  first.contains(where: { $0 != 0 }), abs(steady.count - 32000) <= 64,
                  total > 32 * 32000 - 3000, total <= 32 * 32000 + 64 else {
                fail("PCM16 conversion self-test failed: first=\(first.count), steady=\(steady.count), 32s=\(total)")
            }
            writer.append(buffer)
            writer.append(buffer)
            guard (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true else { fail("Streaming wrote audio to disk") }
            emit("SELFTEST:PCM16-PASS")
            return
        }
        if mode == "self-test" || mode == "overload-test" {
            // Synthetic PCM only: never requests permission or accesses a device.
            let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64000)!
            buffer.frameLength = 64000
            for index in 0..<64000 { buffer.floatChannelData![0][index] = 0.1 * sin(Float(index) * 0.05) }
            let count = mode == "self-test" ? 1 : 5
            for _ in 0..<count { writer.append(buffer) }
            do {
                let file = try AVAudioFile(forReading: directory.appendingPathComponent("audio-0.wav"))
                guard file.length == 64000, file.fileFormat.sampleRate == 16000 else { fail("Synthetic WAV validation failed") }
                emit("SELFTEST:PASS")
            } catch { fail("Synthetic WAV could not be reopened") }
            return
        } else if mode == "microphone" {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else { fail("Microphone permission denied. Enable it in System Settings → Privacy & Security.") }
            let engine = AVAudioEngine()
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1600, format: input.outputFormat(forBus: 0)) { buffer, _ in writer.append(buffer) }
            do { try engine.start() } catch { fail("Microphone could not start.") }
            await CaptureLifetime.shared.wait(retaining: engine)
        } else if mode == "system" {
            let capture = SystemCapture(writer)
            do { try await capture.start() } catch { fail("Cannot capture system audio. Allow Screen & System Audio Recording in System Settings, then restart this app.") }
            await CaptureLifetime.shared.wait(retaining: capture)
        } else { fail("Unknown audio source") }
    }
}
