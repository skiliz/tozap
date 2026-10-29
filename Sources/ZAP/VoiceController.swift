import AVFoundation
import AppKit
import ZAPKit
import Observation
import Speech
import os

/// Push-to-talk voice control. The microphone runs only while the button/shortcut is held.
/// Nothing is recorded or stored: audio goes straight to the recognizer (Mode A) or to the
/// Fire TV's Alexa channel (Mode B) and is discarded.
@MainActor
@Observable
final class VoiceController {
    enum Mode: String, CaseIterable {
        /// Apple Speech on this Mac (on-device when available) -> verified remote actions.
        case local
        /// Relay to the Fire TV's Alexa voice channel; Alexa (Amazon's cloud) interprets it.
        case alexa
    }

    enum State: Equatable {
        case idle, starting, listening, processing
        case done(String), failed(String)
    }

    var mode: Mode {
        didSet { AppDefaults.store.set(mode.rawValue, forKey: "voiceMode") }
    }
    /// Only used when on-device Italian recognition is unavailable; off by default.
    var allowServerRecognition: Bool {
        didSet { AppDefaults.store.set(allowServerRecognition, forKey: "allowServerRecognition") }
    }
    private(set) var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            log.notice("voice state: \(String(describing: self.state), privacy: .private)")
            switch state {
            case .done(let text): model?.voiceFinished(text, failed: false)
            case .failed(let text): model?.voiceFinished(text, failed: true)
            default: break
            }
        }
    }
    private(set) var transcript = ""
    private(set) var level: Float = 0
    private(set) var onDeviceItalian = false

    var isActive: Bool { state == .starting || state == .listening }
    /// The microphone is actually recording (red indicators only then).
    var isCapturing: Bool { state == .listening }
    /// Voice is starting or being recognised: the mode can't change now.
    var isBusy: Bool { state == .starting || state == .listening || state == .processing }
    /// Shown in the capsule while the microphone starts or speech is being recognised.
    var busyDescription: String? {
        switch state {
        case .starting: return "Starting microphone…"
        case .processing: return sessionMode == .local ? "Recognising…" : "Sending to Alexa…"
        default: return nil
        }
    }

    /// The Voice button's action: keyboard activation (Full Keyboard Access, VoiceOver) toggles listening;
    /// a pointer press already started and stopped it.
    func keyboardActivated() {
        guard !held, Date().timeIntervalSince(lastPointerEnd) > 0.4 else { return }
        if isActive { pushToTalkEnded() } else { pushToTalkBegan() }
    }

    /// The real system permission states, read without asking (no prompt is ever triggered by Settings).
    enum Permission {
        case allowed, notAsked, denied, restricted
    }

    var microphonePermission: Permission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .allowed
        case .notDetermined: return .notAsked
        case .restricted: return .restricted
        default: return .denied
        }
    }

    var speechPermission: Permission {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .allowed
        case .notDetermined: return .notAsked
        case .restricted: return .restricted
        default: return .denied
        }
    }

    @ObservationIgnored weak var model: RemoteModel?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var relay: AlexaVoiceRelay?
    @ObservationIgnored private var held = false
    @ObservationIgnored private var lastPointerEnd = Date.distantPast
    /// The mode this listening session started in; switching modes mid-session can't strand the other path.
    @ObservationIgnored private var sessionMode: Mode = .local
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var capturing = false
    @ObservationIgnored private var session = 0
    @ObservationIgnored private var finalized = false
    /// Hard stop even if a release event is lost (e.g. the panel closed mid-press).
    static let maxListeningSeconds: UInt64 = 15
    @ObservationIgnored private var configObserver: NSObjectProtocol?
    @ObservationIgnored private let log = Logger(subsystem: "local.fireremote.app", category: "voice")

    static let vocabulary = ["MaxPlayer", "Home", "Indietro", "Conferma", "Vai a destra", "Vai a sinistra",
                             "Su", "Giù", "Pausa", "Riprendi", "Menu", "Apri"]

    init() {
        mode = Mode(rawValue: AppDefaults.store.string(forKey: "voiceMode") ?? "") ?? .local
        allowServerRecognition = AppDefaults.store.bool(forKey: "allowServerRecognition")
        onDeviceItalian = recognizer?.supportsOnDeviceRecognition ?? false
    }

    var modeDescription: String {
        switch mode {
        case .local:
            if onDeviceItalian { return "Recognised on this Mac (on-device)" }
            return allowServerRecognition ? "Recognised by Apple's servers (you allowed this in Settings)"
                : "On-device Italian isn't available: allow Apple server recognition in Settings → Voice to use it"
        case .alexa:
            return "Sent to Alexa through the Fire TV (Amazon cloud)"
        }
    }

    // MARK: Push-to-talk

    func pushToTalkBegan() {
        log.notice("push-to-talk pressed (held=\(self.held), starting=\(self.starting), state=\(String(describing: self.state), privacy: .private))")
        guard !held, !starting, !isActive, state != .processing else { return }
        guard !RemoteModel.offlinePreview else {  // the preview never opens the microphone
            state = .failed("Offline preview — microphone stays off")
            return
        }
        held = true
        starting = true
        Task {
            await begin()
            starting = false
        }
    }

    /// If setup is still running, `begin()` sees `held == false` and tears down itself, so a
    /// half-open Alexa session is never left behind.
    func pushToTalkEnded() {
        guard held else { return }
        held = false
        lastPointerEnd = Date()
        if !starting { Task { await end() } }
    }

    private func begin() async {
        transcript = ""
        state = .starting
        guard await ensurePermissions() else { return }
        guard held else {
            state = .idle  // released while a permission prompt was up
            return
        }
        do {
            sessionMode = mode
            switch sessionMode {
            case .local: try startLocalRecognition()
            case .alexa: try await startAlexaRelay()
            }
            guard held else {
                await end()  // released during setup: close what was opened, send no audio
                return
            }
            try startCapture()
            state = .listening
            session += 1
            let current = session
            log.notice("listening (\(self.sessionMode.rawValue, privacy: .public))")
            Task {
                try? await Task.sleep(nanoseconds: Self.maxListeningSeconds * 1_000_000_000)
                if self.session == current, self.state == .listening {
                    self.log.notice("push-to-talk watchdog stopped the microphone")
                    self.held = false
                    await self.end()
                }
            }
        } catch {
            await stopEverything(abort: true)
            state = .failed(error.localizedDescription)
        }
    }

    private func end() async {
        guard state == .listening || state == .starting else { return }
        stopCapture()
        switch sessionMode {
        case .local:
            state = .processing
            request?.endAudio()
            // wait briefly for the final result, then fall back to the best partial transcript
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            finalize(transcript)
        case .alexa:
            await relay?.finish()
            relay = nil
            state = .done("Sent to Alexa — the answer appears on the TV")
        }
    }

    private func stopEverything(abort: Bool) async {
        stopCapture()
        task?.cancel()
        task = nil
        request = nil
        if abort { await relay?.abort() }
        relay = nil
    }

    // MARK: Mode A — local recognition

    private func startLocalRecognition() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw FireTVError.unsupported("Italian speech recognition isn't available right now")
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = Self.vocabulary
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else if !allowServerRecognition {
            throw FireTVError.unsupported("On-device Italian recognition isn't available. Allow Apple server recognition in Settings to continue.")
        }
        finalized = false
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if isFinal { self.finalize(text ?? self.transcript) }
                if error != nil, !isFinal, self.state == .processing { self.finalize(self.transcript) }
            }
        }
    }

    private func finalize(_ text: String) {
        guard !finalized else { return }
        finalized = true
        task?.cancel()
        task = nil
        request = nil
        let heard = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else {
            state = .done("Didn't hear anything")
            return
        }
        switch ItalianCommands.parse(heard, apps: model?.apps ?? []) {
        case .action(let action, let times):
            for _ in 0..<times { model?.send(action, source: .voice) }
            let suffix = times > 1 ? " ×\(times)" : ""
            let partial = action.verification == .partial ? " (play/pause toggle)" : ""
            state = .done("«\(heard)» → \(action.summary)\(suffix)\(partial)")
        case .unsupported(let why):
            state = .done("«\(heard)» — \(why)")
        case .unknown:
            state = .done("«\(heard)» — not a supported command")
        }
        log.notice("voice result: \(String(describing: self.state), privacy: .private)")
    }

#if ZAP_DEVTOOLS
    /// Developer builds: recognise an audio file (no microphone) and optionally execute the command.
    func recognizeFile(_ url: URL, execute: Bool) {
        Task {
            guard await requestSpeechPermission() else {
                state = .failed("Speech recognition permission denied")
                return
            }
            guard let recognizer, recognizer.isAvailable else {
                state = .failed("Italian speech recognition unavailable")
                return
            }
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.contextualStrings = Self.vocabulary
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            state = .processing
            recognizer.recognitionTask(with: request) { result, error in
                guard let result, result.isFinal else {
                    if let error {
                        Task { @MainActor in
                            self.log.notice("file test failed: \(error.localizedDescription, privacy: .public)")
                            self.state = .failed(error.localizedDescription)
                        }
                    }
                    return
                }
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.transcript = text
                    let intent = ItalianCommands.parse(text, apps: self.model?.apps ?? [])
                    self.log.notice("file test heard «\(text, privacy: .private)» -> \(String(describing: intent), privacy: .public) onDevice=\(request.requiresOnDeviceRecognition)")
                    if execute {
                        self.finalized = false
                        self.finalize(text)
                    } else {
                        self.state = .done("«\(text)» → \(intent) (dry run)")
                    }
                }
            }
        }
    }
#endif

    // MARK: Mode B — Alexa relay

    private func startAlexaRelay() async throws {
        guard let client = model?.client else { throw FireTVError.notPaired }
        let relay = AlexaVoiceRelay(client: client)
        try await relay.open()
        self.relay = relay
    }

    // MARK: Audio capture

    private func startCapture() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let request = self.request
        let relay = self.relay
        let converter = PCM16kConverter()
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            if let request {
                request.append(buffer)
            } else if let relay {
                relay.append(converter.convert(buffer))
                if relay.failure != nil {
                    Task { @MainActor in self?.relayFailed() }
                }
            }
            let level = Self.rms(buffer)
            Task { @MainActor in self?.level = level }
        }
        engine.prepare()
        try engine.start()
        capturing = true
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                                object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.interrupted() }
        }
    }

    private func stopCapture() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        level = 0
        guard capturing else { return }
        capturing = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func relayFailed() {
        guard relay != nil else { return }
        held = false
        Task {
            await stopEverything(abort: true)
            state = .failed("Connection to the Fire TV voice channel failed — stopped")
        }
    }

    private func interrupted() {
        guard isActive else { return }
        held = false
        Task {
            await stopEverything(abort: true)
            state = .failed("Audio input changed — stopped")
        }
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        return min(1, sqrt(sum / Float(buffer.frameLength)) * 8)
    }

    // MARK: Permissions

    private func ensurePermissions() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                state = .failed("Microphone access denied")
                return false
            }
        default:
            state = .failed("Microphone access is off — enable it in Privacy & Security")
            return false
        }
        if mode == .local, !(await requestSpeechPermission()) {
            state = .failed("Speech recognition is off — enable it in Privacy & Security")
            return false
        }
        return true
    }

    private func requestSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
