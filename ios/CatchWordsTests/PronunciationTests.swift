import XCTest
@testable import CatchWords

/// 発音チェック (docs/pronunciation-coach.md): the pitch tracker, the syllable cutting, the speaker's own scale and the
/// score, on synthetic voices — a buzz with harmonics whose pitch follows a tone, the way the algorithm was first tried.
final class PronunciationTests: XCTestCase {
    // MARK: - Synthetic voices

    /// One syllable: its pitch from level to level on a speaker's range, how long, how loud, and a voiceless consonant
    /// (noise) before it.
    struct Syl {
        var levels: [Double]
        var seconds: Double
        var gainDb: Double = 0
        var noiseBefore: Double = 0.06
        var gapAfter: Double = 0.03
    }

    static let tones: [Int: [Double]] = [
        1: [4.6, 4.6, 4.5], 2: [2.8, 3.0, 3.8, 4.5], 3: [2.0, 1.4, 1.1, 1.2], 4: [4.8, 4.0, 2.6, 1.4], 5: [2.5, 2.3],
    ]
    static let lengths: [Int: Double] = [1: 0.26, 2: 0.28, 3: 0.33, 4: 0.22, 5: 0.15]
    static let gains: [Int: Double] = [1: 0, 2: 0, 3: -4, 4: 2, 5: -6]

    func word(_ tones: [Int], low: Double, high: Double, slower: Double = 1, seed: UInt64 = 1) -> [Float] {
        synth(tones.map { Syl(levels: Self.tones[$0]!, seconds: Self.lengths[$0]! * slower, gainDb: Self.gains[$0]!) },
              low: low, high: high, seed: seed)
    }

    func synth(_ syllables: [Syl], low: Double, high: Double, seed: UInt64 = 1) -> [Float] {
        var rng = SplitMix(seed: seed)
        let sr = PitchTracker.sampleRate
        let range = SpeakerRange(low: ProsodyAnalyzer.semitones(low), high: ProsodyAnalyzer.semitones(high))
        var out = [Float](repeating: 0, count: Int(0.15 * sr))
        for s in syllables {
            for _ in 0..<Int(s.noiseBefore * sr) { out.append(Float(rng.gaussian() * 0.02)) }
            let n = Int(s.seconds * sr)
            var phase = 0.0
            for i in 0..<n {
                let t = Double(i) / Double(max(1, n - 1))
                let level = Self.interpolate(s.levels, at: t)
                let hz = ProsodyAnalyzer.hertz(range.semitones(atLevel: level))
                phase += 2 * Double.pi * hz / sr
                var v = 0.0
                for h in 1...7 { v += 0.6 / Double(h) * sin(Double(h) * phase) }
                let envelope = pow(sin(Double.pi * t), 0.5) * pow(10, s.gainDb / 20)
                out.append(Float(v * envelope * 0.3))
            }
            out.append(contentsOf: [Float](repeating: 0, count: Int(s.gapAfter * sr)))
        }
        out.append(contentsOf: [Float](repeating: 0, count: Int(0.2 * sr)))
        return out.map { $0 + Float(rng.gaussian() * 0.001) }
    }

    static func interpolate(_ v: [Double], at t: Double) -> Double {
        guard v.count > 1 else { return v[0] }
        let x = t * Double(v.count - 1)
        let i = min(v.count - 2, Int(x))
        return v[i] + (v[i + 1] - v[i]) * (x - Double(i))
    }

    /// A small deterministic generator (the tests must not change from run to run).
    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
        mutating func gaussian() -> Double {
            let u = max(uniform(), 1e-12), v = uniform()
            return (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
        }
    }

    // MARK: - Pitch

    func testTracksASteadyVoice() {
        for hz in [90.0, 150.0, 300.0] {
            let sr = PitchTracker.sampleRate
            let samples: [Float] = (0..<Int(0.5 * sr)).map { i in
                let p = 2 * Double.pi * hz * Double(i) / sr
                return Float(0.3 * (sin(p) + 0.5 * sin(2 * p) + 0.3 * sin(3 * p)))
            }
            let found = PitchTracker.frames(samples).compactMap(\.f0).sorted()
            XCTAssertGreaterThan(found.count, 30)
            XCTAssertEqual(found[found.count / 2], hz, accuracy: hz * 0.02, "\(hz) Hz")
        }
    }

    func testSilenceHasNoPitch() {
        let quiet = [Float](repeating: 0, count: 8000)
        XCTAssertTrue(ProsodyAnalyzer.track(PitchTracker.frames(quiet)).allSatisfy { $0 == nil })
        XCTAssertNil(ProsodyAnalyzer.analyze(quiet, syllables: 1))
    }

    // MARK: - Syllables

    func testCutsARisingThenFallingWordIntoTwo() throws {
        let range = SpeakerRange(low: ProsodyAnalyzer.semitones(100), high: ProsodyAnalyzer.semitones(200))
        let take = try XCTUnwrap(ProsodyAnalyzer.analyze(word([2, 4], low: 100, high: 200), syllables: 2))
        let s = NormalizedSyllable.make(take, range: range)
        XCTAssertEqual(s.count, 2)
        XCTAssertGreaterThan(s[0].slope, 1, "the 2nd tone rises")
        XCTAssertLessThan(s[1].slope, -2, "the 4th tone falls")
        XCTAssertEqual(s[0].levels.first ?? 0, 2.9, accuracy: 0.4)
        XCTAssertEqual(s[1].levels.last ?? 0, 1.5, accuracy: 0.4)
    }

    func testAFourthToneAfterALowThirdIsNotFoldedAnOctave() throws {
        // The jump from a low 3rd to a high 4th is about an octave for a wide voice: across the gap it is real.
        let range = SpeakerRange(low: ProsodyAnalyzer.semitones(80), high: ProsodyAnalyzer.semitones(180))
        let take = try XCTUnwrap(ProsodyAnalyzer.analyze(word([3, 4], low: 85, high: 170), syllables: 2))
        let s = NormalizedSyllable.make(take, range: range)
        XCTAssertGreaterThan(s[1].levels[0], 3.8)
    }

    func testCutsAWordWithoutAGapAtTheLoudnessDip() throws {
        let take = try XCTUnwrap(ProsodyAnalyzer.analyze(
            synth([Syl(levels: [4.6, 4.6], seconds: 0.28, noiseBefore: 0, gapAfter: 0),
                   Syl(levels: [2.4, 2.0], seconds: 0.2, gainDb: -6, noiseBefore: 0)],
                  low: 180, high: 360),
            syllables: 2))
        XCTAssertEqual(take.syllables.count, 2)
        XCTAssertGreaterThan(take.syllables[0].duration, take.syllables[1].duration)
    }

    // MARK: - Speaker's own scale and the score

    func band(_ tones: [Int]) -> ProsodyBand? {
        let speakers: [(Double, Double, Double, Double)] = [(180, 360, 170, 380), (95, 190, 90, 200), (120, 250, 115, 260)]
        let takes = speakers.enumerated().compactMap { i, v -> [NormalizedSyllable]? in
            guard let take = ProsodyAnalyzer.analyze(word(tones, low: v.0, high: v.1, seed: UInt64(10 + i)),
                                                      syllables: tones.count) else { return nil }
            return NormalizedSyllable.make(take, range: SpeakerRange(low: ProsodyAnalyzer.semitones(v.2),
                                                                     high: ProsodyAnalyzer.semitones(v.3)))
        }
        return ProsodyBand(takes)
    }

    func learner(_ tones: [Int], slower: Double = 1) -> [NormalizedSyllable]? {
        // A low male voice, slower than the natives.
        ProsodyAnalyzer.analyze(word(tones, low: 85, high: 170, slower: slower, seed: 99), syllables: tones.count)
            .map { NormalizedSyllable.make($0, range: SpeakerRange(low: ProsodyAnalyzer.semitones(80),
                                                                   high: ProsodyAnalyzer.semitones(180))) }
    }

    func testTheRightTonesScoreInTheNativeRangeWhateverTheVoice() throws {
        let natives = try XCTUnwrap(band([2, 4]))
        let score = try XCTUnwrap(ProsodyScore.score(try XCTUnwrap(learner([2, 4], slower: 1.3)), against: natives))
        XCTAssertGreaterThanOrEqual(score.total, ProsodyScore.good)
        XCTAssertEqual(score.advice, .great)
    }

    func testWrongTonesScoreLowAndSayWhatToFix() throws {
        let natives = try XCTUnwrap(band([2, 4]))
        let fourFour = try XCTUnwrap(ProsodyScore.score(try XCTUnwrap(learner([4, 4])), against: natives))
        XCTAssertLessThan(fourFour.syllables[0].total, ProsodyScore.close)
        XCTAssertGreaterThanOrEqual(fourFour.syllables[1].total, ProsodyScore.good)
        XCTAssertEqual(fourFour.advice.syllable, 0)

        let threeFour = try XCTUnwrap(ProsodyScore.score(try XCTUnwrap(learner([3, 4])), against: natives))
        XCTAssertLessThan(threeFour.syllables[0].total, ProsodyScore.close)
        XCTAssertEqual(threeFour.advice, .higher(0), "a low 3rd where a rising 2nd belongs: higher")

        let twoOne = try XCTUnwrap(ProsodyScore.score(try XCTUnwrap(learner([2, 1])), against: natives))
        XCTAssertLessThan(twoOne.syllables[1].total, ProsodyScore.close)
    }

    func testRangeNeedsARealGlide() {
        XCTAssertNil(SpeakerRange.fromGlide(Array(repeating: 5, count: 200)))
        let glide = (0..<200).map { Double($0) / 199 * 14 - 2 }
        let r = SpeakerRange.fromGlide(glide)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.level(r?.low ?? 0) ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(r?.level(r?.high ?? 0) ?? 0, 5, accuracy: 1e-9)
    }

    // MARK: - Tones from the reading

    func testTonesFromZhuyinAndPinyin() throws {
        let school = try XCTUnwrap(WordTones.make(headword: "學校", zhuyin: "ㄒㄩㄝˊ ㄒㄧㄠˋ", pinyin: nil))
        XCTAssertEqual(school.syllables.map(\.tone), [2, 4])
        XCTAssertEqual(school.pattern, "2-4")
        XCTAssertEqual(school.syllables.map(\.pinyin), ["xué", "xiào"])

        let table = try XCTUnwrap(WordTones.make(headword: "桌子", zhuyin: "ㄓㄨㄛ ˙ㄗ", pinyin: nil))
        XCTAssertEqual(table.syllables.map(\.tone), [1, 5])

        let mango = try XCTUnwrap(WordTones.make(headword: "芒果", zhuyin: nil, pinyin: "mángguǒ"))
        XCTAssertEqual(mango.syllables.map(\.tone), [2, 3])

        XCTAssertNil(WordTones.make(headword: "T恤", zhuyin: nil, pinyin: "T xù"))
        XCTAssertNil(WordTones.make(headword: "一個", zhuyin: "ㄧ ˙ㄍㄜ", pinyin: nil)?.pattern, "一 changes with the next tone")
    }

    func testWaveFileHeader() {
        let wav = AudioSamples.wav([0, 0.5, -0.5, 1])
        XCTAssertEqual(wav.count, 44 + 8)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
    }
}
