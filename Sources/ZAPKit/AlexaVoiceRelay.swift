import AVFoundation
import Foundation
import os

/// The Fire TV app's Alexa voice channel (protocol from hms-firetv and LibreControl/fire-tv):
/// `POST /v1/FireTV/voiceCommand?action=start`, then `wss://<tv>:9090/` carrying raw PCM
/// (16 kHz, mono, signed 16-bit little-endian) in binary frames; closing the socket ends the
/// utterance, then `action=stop`. The Fire TV forwards the audio to Alexa, i.e. Amazon's cloud.
///
/// The TLS chain on :9090 must verify to the same pinned Amazon root as :8080 — verification is
/// never turned off. Audio is only sent between `open()` and `finish()`/`abort()`.
public final class AlexaVoiceRelay: @unchecked Sendable {
    public static let frameBytes = 3200  // 100 ms at 16 kHz mono s16le

    private let client: FireTVClient
    private let lock = NSLock()
    private var socket: URLSessionWebSocketTask?
    private var buffer = Data()
    private var sendError: Error?
    private let log = Logger(subsystem: "local.zap.app", category: "voice-relay")

    public init(client: FireTVClient) {
        self.client = client
    }

    /// Set when a frame could not be sent; the caller must stop capturing and call `abort()`.
    public var failure: Error? { lock.withLock { sendError } }

    public func open() async throws {
        try await client.rest("POST", "/v1/FireTV/voiceCommand?action=start")
        do {
            let task = try await client.openVoiceSocket()
            lock.withLock { socket = task; buffer.removeAll(); sendError = nil }
            log.notice("voice socket open")
        } catch {
            _ = try? await client.rest("POST", "/v1/FireTV/voiceCommand?action=stop", wakeIfNeeded: false)
            throw error
        }
    }

    /// Queues 16 kHz mono s16le audio; sends every complete 100 ms frame in order.
    public func append(_ pcm: Data) {
        let (task, frames): (URLSessionWebSocketTask?, [Data]) = lock.withLock {
            guard socket != nil, sendError == nil else { return (nil, []) }
            buffer.append(pcm)
            var out: [Data] = []
            while buffer.count >= Self.frameBytes {
                out.append(buffer.prefix(Self.frameBytes))
                buffer.removeFirst(Self.frameBytes)
            }
            return (socket, out)
        }
        guard let task else { return }
        for frame in frames { send(frame, on: task) }
    }

    /// Ends the utterance: flushes the last partial frame, closes the socket (code 1000) and,
    /// at the same time, sends `action=stop` (some receivers only finish the close after it).
    public func finish() async {
        let (task, rest): (URLSessionWebSocketTask?, Data) = lock.withLock {
            defer { socket = nil; buffer.removeAll() }
            return (socket, buffer)
        }
        guard let task else { return }
        if !rest.isEmpty { send(rest, on: task) }
        task.cancel(with: .normalClosure, reason: nil)
        _ = try? await client.rest("POST", "/v1/FireTV/voiceCommand?action=stop", wakeIfNeeded: false, retries: 1)
        log.notice("voice socket closed, session stopped")
    }

    /// Stops immediately (release, interruption or failure); unsent audio is dropped.
    public func abort() async {
        let task: URLSessionWebSocketTask? = lock.withLock {
            defer { socket = nil; buffer.removeAll() }
            return socket
        }
        task?.cancel(with: .goingAway, reason: nil)
        _ = try? await client.rest("POST", "/v1/FireTV/voiceCommand?action=stop", wakeIfNeeded: false, retries: 1)
        log.notice("voice relay aborted")
    }

    private func send(_ frame: Data, on task: URLSessionWebSocketTask) {
        task.send(.data(frame)) { [weak self] error in
            guard let self, let error else { return }
            self.lock.withLock { if self.sendError == nil { self.sendError = error } }
            self.log.error("voice frame failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Converts any capture format to 16 kHz mono signed 16-bit PCM, keeping resampler state between buffers.
public final class PCM16kConverter {
    public static let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                             channels: 1, interleaved: true)!
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    public init() {}

    public func convert(_ input: AVAudioPCMBuffer) -> Data {
        if converter == nil || inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: Self.format)
            inputFormat = input.format
        }
        guard let converter else { return Data() }
        let ratio = Self.format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 64)
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity) else { return Data() }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, let samples = output.int16ChannelData else { return Data() }
        return Data(bytes: samples[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }
}
