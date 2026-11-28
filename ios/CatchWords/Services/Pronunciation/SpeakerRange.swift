import Foundation

/// A speaker's own pitch range, so every voice is compared on its own scale (話者正規化): the lowest comfortable pitch
/// is level 1 and the highest is level 5, the five levels tones are written in (Chao's 五度). A low male voice and a high
/// female voice saying the same tone then draw the same curve.
nonisolated struct SpeakerRange: Codable, Sendable, Equatable {
    /// Semitones above 100 Hz.
    var low: Double
    var high: Double

    /// A range is never narrower than this many semitones (a flat glide would make every wobble look like a tone).
    static let minimumSpan: Double = 6

    /// The 1…5 level of a pitch (may fall outside 1…5).
    func level(_ semitones: Double) -> Double {
        1 + 4 * (semitones - low) / max(high - low, Self.minimumSpan)
    }

    /// The pitch (semitones) at a level.
    func semitones(atLevel level: Double) -> Double {
        low + (level - 1) / 4 * max(high - low, Self.minimumSpan)
    }

    var lowHz: Double { ProsodyAnalyzer.hertz(low) }
    var highHz: Double { ProsodyAnalyzer.hertz(high) }

    /// From a glide from the lowest to the highest comfortable 「あー」: its 5th and 95th percentile. nil when too little
    /// voice was heard (under 0.6 s) or it hardly moved (under `minimumSpan`).
    static func fromGlide(_ pitch: [Double]) -> SpeakerRange? {
        let sorted = pitch.sorted()
        guard sorted.count >= 60 else { return nil }
        let low = ProsodyAnalyzer.percentile(sorted, 0.05)
        let high = ProsodyAnalyzer.percentile(sorted, 0.95)
        guard high - low >= minimumSpan else { return nil }
        return SpeakerRange(low: low, high: high)
    }

    /// A voice heard only speaking (the AI voice cannot glide): the spread of its speech (5th…95th percentile) widened by
    /// `speechToGlide` around its middle, to the size a glide gives. 1.25 is a first estimate; the natives' recordings
    /// keep both their glide and their speech, so the real ratio replaces it once they are in (docs/pronunciation-coach.md §4).
    static let speechToGlide: Double = 1.25

    static func fromSpeech(p05: Double, p95: Double) -> SpeakerRange? {
        guard p95 > p05 else { return nil }
        let middle = (p05 + p95) / 2
        let half = max((p95 - p05) / 2 * speechToGlide, minimumSpan / 2)
        return SpeakerRange(low: middle - half, high: middle + half)
    }
}

/// The learner's range on this device (measured once, measured again whenever they like), per account.
@MainActor
enum LearnerVoiceRange {
    nonisolated private static func key(_ userId: String?) -> String { "pron.range.\(userId ?? "-")" }

    static var current: SpeakerRange? {
        guard let data = UserDefaults.standard.data(forKey: key(SupabaseClient.shared.userId)) else { return nil }
        return try? JSONDecoder().decode(SpeakerRange.self, from: data)
    }

    static func save(_ range: SpeakerRange) {
        guard let data = try? JSONEncoder().encode(range) else { return }
        UserDefaults.standard.set(data, forKey: key(SupabaseClient.shared.userId))
    }

    nonisolated static func removeRecords(userId: String?) {
        UserDefaults.standard.removeObject(forKey: key(userId))
    }
}
