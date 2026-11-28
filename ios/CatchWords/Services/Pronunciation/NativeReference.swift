import Foundation

/// A native speaker's recording as the server keeps it: who (a code, never a name), their range from their own glide,
/// and the measured syllables. The audio stays on the server; only these numbers come to the app.
nonisolated struct NativeProsodyRecording: Codable, Sendable, Equatable {
    let speaker: String
    let range: SpeakerRange
    let take: ProsodyTake
    let headword: String
}

/// `getNativeProsody`: the natives' recordings of the word itself, and of other words with the same tones.
nonisolated struct NativeProsodyAnswer: Decodable, Sendable {
    let word: [NativeProsodyRecording]
    let pattern: [NativeProsodyRecording]
}

/// Where the band came from, said on the screen so the learner knows what they are compared with.
nonisolated enum ReferenceSource: Equatable, Sendable {
    /// Natives' recordings: `speakers` people, `recordings` takes; `sameWord` = of this very word (else of words with
    /// the same tones).
    case natives(speakers: Int, recordings: Int, sameWord: Bool)
    /// The app's AI voice (Taiwan), measured on the phone until natives have recorded this word or its tones.
    case aiVoice
}

nonisolated struct NativeReference: Sendable {
    let band: ProsodyBand
    let source: ReferenceSource
}

/// Finds the band for a word: natives first (their recordings of the word, then of words with the same tones), else the
/// AI voice measured on the phone.
@MainActor
enum NativeReferenceLoader {
    private static var cache: [String: NativeReference] = [:]

    static func load(_ word: WordTones) async -> NativeReference? {
        if let hit = cache[word.headword] { return hit }
        let made = await fromNatives(word) ?? fromAIVoice(word)
        if let made { cache[word.headword] = made }
        return made
    }

    /// The server's recordings. Any failure (no network, a server without the function yet) is just "none".
    private static func fromNatives(_ word: WordTones) async -> NativeReference? {
        var input: [String: Any] = ["headword": word.headword, "syllables": word.syllables.count]
        if let p = word.pattern { input["pattern"] = p }
        guard let answer = try? await NativeAPI.call("getNativeProsody", input, as: NativeProsodyAnswer.self, timeout: 12) else {
            return nil
        }
        let n = word.syllables.count
        let own = answer.word.filter { $0.take.syllables.count == n }
        let others = answer.pattern.filter { $0.take.syllables.count == n && $0.headword != word.headword }
        let chosen: [NativeProsodyRecording]
        if own.count >= 3 {
            chosen = own
        } else if own.count + others.count >= 2 {
            chosen = own + others.prefix(24)
        } else if own.count == 1 {
            chosen = own
        } else {
            return nil
        }
        guard let band = ProsodyBand(chosen.map { NormalizedSyllable.make($0.take, range: $0.range) }) else { return nil }
        let speakers = Set(chosen.map(\.speaker)).count
        return NativeReference(band: band, source: .natives(speakers: speakers, recordings: chosen.count,
                                                              sameWord: !own.isEmpty))
    }

    /// The AI voice's recording of the word, on the AI voice's own scale (`AIVoiceRange`).
    private static func fromAIVoice(_ word: WordTones) async -> NativeReference? {
        guard let data = await SoundService.shared.pronunciationAudio(for: word.headword) else { return nil }
        let n = word.syllables.count
        let take: ProsodyTake? = await Task.detached(priority: .userInitiated) {
            guard let samples = AudioSamples.decode(data) else { return nil }
            return ProsodyAnalyzer.analyze(samples, syllables: n)
        }.value
        guard let take else { return nil }
        let range = await AIVoiceRange.current()
            ?? SpeakerRange.fromSpeech(p05: take.pitchPercentiles[0] - 3, p95: take.pitchPercentiles[2] + 3)
        guard let range, let band = ProsodyBand([NormalizedSyllable.make(take, range: range)]) else { return nil }
        return NativeReference(band: band, source: .aiVoice)
    }

    static func forget(_ headword: String) { cache[headword] = nil }
}

/// The AI voice's range: measured once from it reading the four tones twice (媽麻馬罵 八拔把爸), kept two weeks (the
/// developer may change the voice).
@MainActor
enum AIVoiceRange {
    private static let key = "pron.aiVoiceRange"
    private static let maxAge: TimeInterval = 14 * 86_400
    private static let phrase = "媽、麻、馬、罵。八、拔、把、爸。" // l10n-ignore

    nonisolated private struct Saved: Codable {
        let range: SpeakerRange
        let at: Date
    }

    static func current() async -> SpeakerRange? {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data),
           Date().timeIntervalSince(saved.at) < maxAge {
            return saved.range
        }
        guard let audio = await SoundService.shared.pronunciationAudio(for: phrase) else { return nil }
        let range: SpeakerRange? = await Task.detached(priority: .userInitiated) {
            guard let samples = AudioSamples.decode(audio) else { return nil }
            let voiced = ProsodyAnalyzer.track(PitchTracker.frames(samples)).compactMap { $0 }.sorted()
            guard voiced.count >= 40 else { return nil }
            return SpeakerRange.fromSpeech(p05: ProsodyAnalyzer.percentile(voiced, 0.05),
                                           p95: ProsodyAnalyzer.percentile(voiced, 0.95))
        }.value
        if let range, let data = try? JSONEncoder().encode(Saved(range: range, at: Date())) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return range
    }
}
