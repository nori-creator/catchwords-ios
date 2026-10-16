import AVFoundation

/// Recorded cinematic SFX from the web app (`public/sfx/el-*.mp3`) with the same per-file trims.
enum SFX: String, CaseIterable {
    case impact = "el-catch-impact"
    case bookOpen = "el-book-open"
    case slide = "el-gallery-slide"
    case sting = "el-celebrate-sting"
    case analyzeLoop = "el-analyze-loop"
    // ElevenLabs SFX (eleven_text_to_sound_v2), trimmed and normalized for these moments:
    case jarCork = "el-jar-cork"        // cork lands in the glass jar: soft pop + bright clink
    case cutTrace = "el-cut-trace"      // scissors round the outline (cut-out mode)
    case stickerLift = "el-sticker-lift" // the cut sticker peels up off the page
    case landBounce = "el-land-bounce"  // a word lands: a light ball-like bounce (pon-pon-pon), no coin clink
    // The owner's pick from the web prototype ("bubble pon"): a page opening / going back.
    case ponOpen = "pon-bubble-open"
    case ponBack = "pon-bubble-back"
    // The card-catch prototype's synthesized SFX (docs/prototype/cardcatch-src.html `SFX`), rendered offline by
    // scripts/render_cardcatch_sfx.py. The candidate and light sounds reuse the pop and the twinkle (owner 2026-10-04).
    case ccShutter = "cc-shutter"
    case ccTick = "cc-tick"
    case ccScanStart = "cc-scan-start"
    case ccFound = "cc-found"
    case ccPop = "cc-pop"
    case ccReveal = "cc-reveal"
    case ccTwinkle = "cc-twinkle"
    case ccLand = "cc-land"
    // Concept film v6's catch → GET → 図鑑 (scratchpad catchfilm audio/kit3, loudness-matched by role there; the
    // catch jingle and the stage pad rendered with the film's own synth, mix6.py `catch_jingle` / `soft_pad`).
    case c6Choose = "cc6-choose"
    case c6StagePad = "cc6-stage-pad"
    case c6CatchJingle = "cc6-catch-jingle"
    case c6DexOpen = "cc6-dex-open"
    case c6Riser = "cc6-riser-300"
    case c6LandImpact = "cc6-land-impact"
    case c6NewBadge = "cc6-new-badge"
    case c6Tick1 = "cc6-count-tick-1"
    case c6Tick2 = "cc6-count-tick-2"
    case c6Tick3 = "cc6-count-tick-3"
    case c6Refill = "cc6-refill"
    case c6GoalOneMore = "cc6-goal-one-more"
    // The small UI ticks (owner 2026-10-15, scripts/render_ui_ticks.py, −26 LUFS like the kit's `ui` role): three
    // alternatives each, chosen in 設定 › 開発者 (`DevChoices`) — the map's timeline passing a word, a Settings picker.
    case c6ScrollTick1 = "cc6-scroll-tick-1"
    case c6ScrollTick2 = "cc6-scroll-tick-2"
    case c6ScrollTick3 = "cc6-scroll-tick-3"
    case c6PickTick1 = "cc6-pick-tick-1"
    case c6PickTick2 = "cc6-pick-tick-2"
    case c6PickTick3 = "cc6-pick-tick-3"

    var gain: Float {
        switch self {
        case .impact: 1.4
        case .bookOpen: 1.6
        case .slide: 1.2
        case .sting: 1.1
        case .analyzeLoop: 0.9
        case .jarCork: 0.9
        case .cutTrace: 0.7
        case .stickerLift: 0.8
        case .landBounce: 1.0
        case .ponOpen: 0.9
        case .ponBack: 0.8
        // Rendered at the prototype's loudness relative to the pon (same 0.9); two files were turned down
        // in rendering to avoid clipping and get that back here (render report: ×2.803 and ×1.640; cc-land ×1.590).
        case .ccShutter: 0.9 * 2.803
        case .ccReveal: 0.9 * 1.640
        case .ccLand: 0.9 * 1.590
        case .ccTick, .ccScanStart, .ccFound, .ccPop, .ccTwinkle: 0.9
        // The v6 kit is balanced within itself (ui −26, motion −24, earcon −21, reward −19 LUFS), the earcons as
        // loud as the pop and the land above (−22 LUFS at 0.9).
        case .c6Choose, .c6StagePad, .c6CatchJingle, .c6DexOpen, .c6Riser, .c6LandImpact, .c6NewBadge,
             .c6Tick1, .c6Tick2, .c6Tick3, .c6Refill, .c6GoalOneMore: 1.0
        // Rendered at the kit's `ui` loudness already; kept low (they can come several times a second).
        case .c6ScrollTick1, .c6ScrollTick2, .c6ScrollTick3, .c6PickTick1, .c6PickTick2, .c6PickTick3: 0.9
        }
    }

    /// The card-catch sounds can overlap themselves (the prototype starts a new WebAudio voice each time).
    var isCardCatch: Bool { rawValue.hasPrefix("cc-") }

    /// The v6 film's kit (16-bit PCM .caf: no encoder delay on the short ticks).
    var isFilm6: Bool { rawValue.hasPrefix("cc6-") }

    /// The pon and card-catch files are AAC (.m4a); everything else is the web's mp3.
    var fileExtension: String {
        if isCardCatch { return "m4a" }
        if isFilm6 { return "caf" }
        switch self {
        case .ponOpen, .ponBack: return "m4a"
        default: return "mp3"
        }
    }

    var offset: TimeInterval {
        switch self {
        case .bookOpen: 0.6
        case .slide: 0.05
        default: 0
        }
    }
}

final class SoundService {
    static let shared = SoundService()

    private var players: [SFX: AVAudioPlayer] = [:]
    /// The device voice, made the first time it speaks (making one at launch held the main thread while the app opened).
    private var synthesizer: AVSpeechSynthesizer?
    private var voiceCache: [String: AVSpeechSynthesisVoice?] = [:]
    /// The device voice for a language (zh-TW / en / ja), picked once — off the main thread: the system's list of
    /// voices can take seconds to come the first time (it held the main thread right as a word's page opened and read
    /// its word with the device voice).
    private func voice(for lang: String) async -> AVSpeechSynthesisVoice? {
        if let v = voiceCache[lang] { return v }
        let code = Self.bcp47(lang)
        let picked = await Task.detached(priority: .userInitiated) { VoiceBox(voice: Self.pickVoice(code)) }.value
        voiceCache[lang] = picked.voice
        return picked.voice
    }

    /// A voice handed from the thread that picked it (the voice itself is only read afterwards).
    nonisolated private struct VoiceBox: @unchecked Sendable {
        let voice: AVSpeechSynthesisVoice?
    }

    /// The language a text is read in — from the text itself, so a word is never read in another
    /// language's voice (R6): kana → Japanese, Latin only → English, Han → the learning language
    /// (Japanese learners read kanji in Japanese, everyone else in Taiwan Mandarin).
    static func language(of text: String) -> String {
        let c = LanguageRules.counts(text)
        if c.kana > 0 { return "ja" }
        if c.han == 0, c.latin > 0 { return "en" }
        return NativeAPI.targetLanguage == "ja" ? "ja" : "zh-TW"
    }

    static func bcp47(_ lang: String) -> String {
        switch lang {
        case "en": "en-US"
        case "ja": "ja-JP"
        default: "zh-TW"
        }
    }

    private var levelMultiplier: Float {
        // Same values and default as the web (cw-sound-level: off / subtle / full, default subtle).
        switch UserDefaults.standard.string(forKey: "sound.level") ?? "subtle" {
        case "off": 0
        case "full": 0.8
        default: 0.45   // "subtle" (and the old iOS value "soft")
        }
    }

    /// 設定 › 効果音 is off (the sound level "off").
    var isMuted: Bool { levelMultiplier == 0 }

    /// At launch: the audio session and every sound's player, made off the main thread (about forty players, each a
    /// file read and an audio setup, used to run on the main thread before the first screen could be drawn). A sound
    /// asked for before its player is ready makes it there and then, as before.
    func configure() {
        let files: [(sfx: SFX, url: URL)] = SFX.allCases.compactMap { sfx in
            Bundle.main.url(forResource: sfx.rawValue, withExtension: sfx.fileExtension).map { (sfx, $0) }
        }
        Task.detached(priority: .utility) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
            var made: [(sfx: SFX, player: AVAudioPlayer)] = []
            for f in files {
                guard let player = try? AVAudioPlayer(contentsOf: f.url) else { continue }
                player.prepareToPlay()
                made.append((f.sfx, player))
            }
            let batch = PlayerBatch(items: made)
            await MainActor.run {
                let service = SoundService.shared
                for m in batch.items where service.players[m.sfx] == nil { service.players[m.sfx] = m.player }
            }
            // The system's list of voices answers slowly the first time: asked once now, behind the first screen, so
            // a word read with the device voice later does not wait for it.
            _ = AVSpeechSynthesisVoice.speechVoices()
        }
    }

    /// The players made off the main thread, handed over once (nothing else touches them meanwhile).
    nonisolated private struct PlayerBatch: @unchecked Sendable {
        let items: [(sfx: SFX, player: AVAudioPlayer)]
    }

    func play(_ sfx: SFX, volume: Float = 1) {
        let level = levelMultiplier
        guard level > 0, let player = player(for: sfx) else { return }
        player.stop()
        player.currentTime = sfx.offset
        player.numberOfLoops = 0
        player.volume = min(1, sfx.gain * volume * level)
        player.play()
    }

    /// Plays `sfx` on a fresh player so it can overlap an earlier play of the same sound (the prototype's
    /// pops come 130 ms apart and each rings out). Same level rules as `play`.
    func playLayered(_ sfx: SFX, volume: Float = 1) {
        let level = levelMultiplier
        guard level > 0,
              let url = Bundle.main.url(forResource: sfx.rawValue, withExtension: sfx.fileExtension),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        layered.removeAll { !$0.isPlaying }
        player.currentTime = sfx.offset
        player.volume = min(1, sfx.gain * volume * level)
        player.play()
        layered.append(player)
    }

    private var layered: [AVAudioPlayer] = []

    /// A page opening (dex, word detail, tab) or going back: the bubble pon plus its matching tap.
    /// The sound follows the sound level ("off" is silent); the tap follows the vibration switch.
    func pon(open: Bool) {
        play(open ? .ponOpen : .ponBack)
        Haptics.pon(open: open)
    }

    /// Where a small tick is heard (owner 2026-10-15).
    enum Tick {
        /// A word passing the reading line of the Collection map's timeline while scrolling.
        case timeline
        /// A Settings pill chosen (off unless chosen in 設定 › 開発者, owner 2026-10-16). The wheels click on their own
        /// (`wheelTick`).
        case picker
    }

    /// The small tick for `kind`: the alternative chosen in 設定 › 開発者 (`DevChoices`, 1–3, or none), on the same
    /// rules as every SFX — the sound level (控えめ / しっかり / オフ) scales it, and the device's own switches apply as
    /// they do to the pon. A tick restarts the one before it (a fast scroll never piles them up). `number` plays that
    /// alternative instead of the chosen one (the developer card's preview of each).
    func tick(_ kind: Tick, number: Int? = nil) {
        let key = kind == .timeline ? DevChoices.timelineTickKey : DevChoices.pickerTickKey
        guard let n = number ?? DevChoices.tick(key), (1...3).contains(n) else { return }
        let files: [SFX] = kind == .timeline
            ? [.c6ScrollTick1, .c6ScrollTick2, .c6ScrollTick3]
            : [.c6PickTick1, .c6PickTick2, .c6PickTick3]
        play(files[n - 1])
    }

    /// A Settings wheel passing a row while it turns (`TickingWheel`): the picker tick chosen in 設定 › 開発者, or the
    /// first one when none is chosen there — the wheel always clicks (owner 2026-10-16: 「カチカチ音がスクロールに
    /// 追従するように」). Same level rules as every SFX; a click restarts the one before it.
    func wheelTick() {
        let n = DevChoices.tick(DevChoices.pickerTickKey) ?? 1
        play([SFX.c6PickTick1, .c6PickTick2, .c6PickTick3][n - 1])
    }

    func startAnalyzeLoop() {
        let level = levelMultiplier
        guard level > 0, let player = player(for: .analyzeLoop) else { return }
        player.numberOfLoops = -1
        player.currentTime = 0
        player.volume = 0
        player.play()
        player.setVolume(min(1, SFX.analyzeLoop.gain * 0.5 * level), fadeDuration: 0.6)
    }

    func stopAnalyzeLoop() {
        guard let player = players[.analyzeLoop], player.isPlaying else { return }
        player.setVolume(0, fadeDuration: 0.3)
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            player.stop()
        }
    }

    // MARK: - Pronunciation (the web's server voice)

    /// The same voice as the web (`synthesizeSpeech`: the developer-chosen TTS provider, cached in the
    /// `tts` bucket). Each text is fetched once and kept on the device, so repeats are instant and offline.
    /// Only when the server is slow (>2.5 s) or unreachable does the device voice speak instead —
    /// pressing the button must never be silent.
    private var voicePlayer: AVAudioPlayer?
    private var inflight: [String: Task<Data?, Never>] = [:]
    private var speakToken = 0

    private static let ttsDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("tts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Caches/tts keeps at most this many files and bytes (the OS may also clear it when space runs low). Room for
    /// every word of a large dex and its review choices: a voice heard once plays at once from then on (owner
    /// 2026-10-11: 「端末に画像や発音を保存し…ラグなしで」).
    nonisolated private static let ttsMaxFiles = 3000
    nonisolated private static let ttsMaxBytes = 150 * 1024 * 1024

    /// Deletes the least recently used pronunciations (oldest modification date first; a replay touches
    /// the file) until the cache is within both limits. File work only, so it runs off the main actor.
    nonisolated private static func trimTTSCache(_ dir: URL) {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys),
                                                      options: [.skipsHiddenFiles]) else { return }
        var entries: [(url: URL, date: Date, size: Int)] = []
        for url in files {
            guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            entries.append((url: url, date: v.contentModificationDate ?? .distantPast, size: v.fileSize ?? 0))
        }
        var count = entries.count
        var total = entries.reduce(0) { $0 + $1.size }
        guard count > ttsMaxFiles || total > ttsMaxBytes else { return }
        entries.sort { $0.date < $1.date }
        for e in entries {
            guard count > ttsMaxFiles || total > ttsMaxBytes else { break }
            if (try? fm.removeItem(at: e.url)) != nil {
                count -= 1
                total -= e.size
            }
        }
    }

    private static func cacheURL(for text: String) -> URL {
        let key = text.unicodeScalars.reduce(into: UInt64(1469598103934665603)) { h, c in
            h = (h ^ UInt64(c.value)) &* 1099511628211
        }
        return ttsDir.appendingPathComponent("\(language(of: text))-\(String(key, radix: 16)).mp3")
    }

    /// Warm the cache (e.g. when candidates appear) so the first tap plays at once.
    func prefetch(_ text: String) {
        guard !text.isEmpty else { return }
        _ = audio(for: text)
    }

    private func audio(for text: String) -> Task<Data?, Never> {
        if let t = inflight[text] { return t }
        let file = Self.cacheURL(for: text)
        let task = Task<Data?, Never> {
            if let d = try? Data(contentsOf: file) {
                // Used again: newest for the cache limit (`trimTTSCache` drops the least recently used).
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
                return d
            }
            struct Res: Decodable {
                let audioURL: String?
                let locked: Bool?
                enum CodingKeys: String, CodingKey { case locked, audioURL = "audio_url" }
            }
            guard let res = try? await NativeAPI.call(
                "synthesizeSpeech", ["text": String(text.prefix(400)), "language": Self.language(of: text)],
                as: Res.self, timeout: 20
            ), res.locked != true, let raw = res.audioURL else { return nil }
            let data: Data?
            if raw.hasPrefix("data:"), let comma = raw.firstIndex(of: ",") {
                data = Data(base64Encoded: String(raw[raw.index(after: comma)...]))
            } else if let url = URL(string: raw) {
                // Only a real answer is kept: an error page (expired link, 403) cached as the word's
                // audio would make that word silent for good.
                if let (body, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20)),
                   (response as? HTTPURLResponse)?.statusCode == 200 {
                    data = body
                } else {
                    data = nil
                }
            } else {
                data = nil
            }
            if let data, !data.isEmpty {
                try? data.write(to: file, options: .atomic)
                let dir = Self.ttsDir
                Task.detached(priority: .utility) { Self.trimTTSCache(dir) }
            }
            return data
        }
        inflight[text] = task
        Task {
            _ = await task.value
            inflight[text] = nil
        }
        return task
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        speakToken += 1
        let token = speakToken
        voicePlayer?.stop()
        if let synthesizer, synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let task = audio(for: text)
        Task {
            // Whichever comes first: the audio, or 2.5 s of waiting (then the device voice speaks,
            // and the fetch keeps going so the next tap is instant).
            let data: Data? = await withTaskGroup(of: Data?.self) { group in
                group.addTask { await task.value }
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(2500))
                    return nil
                }
                let first: Data?? = await group.next()
                group.cancelAll()
                return first ?? nil
            }
            guard token == speakToken else { return }
            ensurePlayback()
            if let data, let player = try? AVAudioPlayer(data: data) {
                voicePlayer = player
                player.volume = 1
                player.play()
            } else {
                speakOnDevice(text)
            }
        }
    }

    /// A pronunciation is always heard (it ignores 効果音オフ and the silent switch): the session is put back to
    /// playback if something left it elsewhere, and reactivated after an interruption (a call, Siri, another
    /// app) deactivated it. A recording in progress (play-and-record) is left alone.
    private func ensurePlayback() {
        let session = AVAudioSession.sharedInstance()
        if session.category == .playAndRecord { return }
        if session.category != .playback {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try? session.setActive(true)
    }

    /// Device voice fallback: always the text's own language's voice (never a "close" language).
    private func speakOnDevice(_ text: String) {
        let token = speakToken
        Task {
            guard let voice = await voice(for: Self.language(of: text)), token == speakToken else { return }
            say(text, voice: voice)
        }
    }

    private func say(_ text: String, voice: AVSpeechSynthesisVoice) {
        let synthesizer = self.synthesizer ?? AVSpeechSynthesizer()
        self.synthesizer = synthesizer
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = 0.42
        utterance.pitchMultiplier = 1.02
        synthesizer.speak(utterance)
    }

    private func player(for sfx: SFX) -> AVAudioPlayer? {
        if let existing = players[sfx] { return existing }
        guard let url = Bundle.main.url(forResource: sfx.rawValue, withExtension: sfx.fileExtension),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[sfx] = player
        return player
    }

    nonisolated private static func pickVoice(_ lang: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == lang }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.identifier < rhs.identifier
            }
        return voices.first ?? AVSpeechSynthesisVoice(language: lang)
    }
}
