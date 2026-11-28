import AVFoundation
import Foundation
import Observation

/// The microphone for the pronunciation coach: records one word (or the range glide), analyses it as it comes in for the
/// live curve, and stops by itself once the speaker has finished. Nothing leaves the phone.
@MainActor @Observable
final class VoiceRecorder {
    enum Phase: Equatable { case idle, recording }

    private(set) var phase: Phase = .idle
    /// The live pitch, one value per 10 ms (semitones above 100 Hz; nil = no voice), for the curve drawn while speaking.
    private(set) var live: [Double?] = []
    /// How loud the input is now, 0…1 (the button's ring).
    private(set) var meter: Double = 0
    /// Seconds since recording began.
    private(set) var elapsed: Double = 0

    /// The longest recording, and how long a silence after the voice ends it.
    var maxSeconds: Double = 6
    var silenceToStop: Double = 0.7

    private var sink: MicSink?
    private var finish: (([Float]) -> Void)?
    private var frames: [ProsodyFrame] = []
    private var noiseFloor: Double = 0
    private var voicedFrames = 0
    private var trailingSilence = 0
    private var startedAt = Date()
    private var clock: Task<Void, Never>?
    private var previous: (category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                           options: AVAudioSession.CategoryOptions)?

    /// Asks once; afterwards answers from the setting.
    static func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    static var permissionDenied: Bool { AVAudioApplication.shared.recordPermission == .denied }

    /// Starts recording; `onFinish` gets the samples (16 kHz mono) once it stops — analyse them off the main thread
    /// (`ProsodyAnalyzer.analyze`, a few tens of milliseconds for a word).
    func start(onFinish: @escaping ([Float]) -> Void) throws {
        guard phase == .idle else { return }
        let session = AVAudioSession.sharedInstance()
        previous = (session.category, session.mode, session.categoryOptions)
        // Measurement mode: no automatic gain or voice processing, so the pitch and loudness are the voice's own.
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)

        let sink = MicSink()
        sink.onFrames = { [weak self] made in
            Task { @MainActor in self?.receive(made) }
        }
        do {
            try sink.start()
        } catch {
            restoreSession()
            throw VoiceRecorderFailure.noInput
        }
        self.sink = sink
        finish = onFinish
        frames = []
        live = []
        meter = 0
        elapsed = 0
        noiseFloor = 0
        voicedFrames = 0
        trailingSilence = 0
        startedAt = Date()
        phase = .recording
        clock = Task { @MainActor [weak self] in
            while let self, self.phase == .recording, !Task.isCancelled {
                self.elapsed = Date().timeIntervalSince(self.startedAt)
                // No voice at all for 5 s, or the longest recording reached.
                if self.elapsed >= self.maxSeconds || (self.voicedFrames == 0 && self.elapsed >= 5) {
                    self.stop()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Stops now and hands over what was recorded.
    func stop() {
        guard phase == .recording, let sink else { return }
        clock?.cancel()
        clock = nil
        let samples = sink.stop()
        self.sink = nil
        phase = .idle
        meter = 0
        restoreSession()
        let done = finish
        finish = nil
        done?(samples)
    }

    /// Stops without handing anything over (the screen closed).
    func cancel() {
        finish = nil
        stop()
    }

    private func receive(_ made: [ProsodyFrame]) {
        guard phase == .recording else { return }
        for f in made {
            frames.append(f)
            // The background: the quietest of the first 300 ms, then the quietest seen.
            noiseFloor = frames.count == 1 ? f.db : min(noiseFloor, f.db)
            let voiced = f.f0 != nil && f.aperiodicity < 0.25 && f.db > noiseFloor + 12
            live.append(voiced ? f.f0.map(ProsodyAnalyzer.semitones) : nil)
            if voiced {
                voicedFrames += 1
                trailingSilence = 0
            } else {
                trailingSilence += 1
            }
            meter = max(0, min(1, (f.db - noiseFloor) / 40))
        }
        let silenceFrames = Int(silenceToStop / ProsodyAnalyzer.frameSeconds)
        if voicedFrames >= 15, trailingSilence >= silenceFrames { stop() }
    }

    private func restoreSession() {
        let session = AVAudioSession.sharedInstance()
        if let previous {
            try? session.setCategory(previous.category, mode: previous.mode, options: previous.options)
        } else {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        previous = nil
    }
}

nonisolated enum VoiceRecorderFailure: Error { case noInput }

/// The microphone's tap: converts each buffer to 16 kHz mono and analyses every complete 10 ms frame. Runs on the audio
/// engine's thread, so it is not tied to the main actor.
nonisolated final class MicSink: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var analysed = 0
    private var converter: AVAudioConverter?
    var onFrames: (@Sendable ([ProsodyFrame]) -> Void)?

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let converter = AVAudioConverter(from: format, to: AudioSamples.format) else {
            throw VoiceRecorderFailure.noInput
        }
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.receive(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    private func receive(_ buffer: AVAudioPCMBuffer) {
        guard let converter, buffer.frameLength > 0 else { return }
        let ratio = PitchTracker.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: AudioSamples.format, frameCapacity: capacity) else { return }
        let feed = AudioSamples.Feed(buffer)
        var error: NSError?
        _ = converter.convert(to: out, error: &error) { _, status in feed.next(status, ending: false) }
        guard let ch = out.floatChannelData, out.frameLength > 0 else { return }
        let new = Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
        lock.lock()
        samples.append(contentsOf: new)
        let made = PitchTracker.frames(samples, from: analysed, upTo: samples.count)
        analysed += made.count * PitchTracker.hop
        lock.unlock()
        if !made.isEmpty { onFrames?(made) }
    }
}
