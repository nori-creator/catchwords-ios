import Foundation

/// One syllable of a recording, measured at the same `ProsodyAnalyzer.points` moments (5 %, 15 %, … 95 % of its voiced
/// part) so syllables of any length compare point by point.
nonisolated struct SyllableProsody: Codable, Sendable, Equatable {
    /// Pitch in semitones above 100 Hz.
    var pitch: [Double]
    /// Loudness in dB below the recording's loudest moment.
    var loudness: [Double]
    /// How long the voiced part lasted, seconds.
    var duration: Double
    /// Its mean loudness, dB below the recording's loudest moment.
    var meanLoudness: Double
    /// Where it starts and ends, seconds from the start of the recording.
    var start: Double
    var end: Double
}

/// What one recording of a word says about its prosody: its syllables, and how its voice spreads (for a speaker's
/// range when only speech is heard — the AI voice, and to compare a native's speech with their glide).
nonisolated struct ProsodyTake: Codable, Sendable, Equatable {
    var syllables: [SyllableProsody]
    /// The 5th, 50th and 95th percentile of every voiced pitch in the recording, semitones above 100 Hz.
    var pitchPercentiles: [Double]
}

/// From samples to syllables: the pitch track cleaned the way a listener hears it, cut into the word's syllables, each
/// measured for pitch, length and loudness. Pure; the same steps for the learner, the natives and the AI voice, so the
/// three are measured alike. The algorithm was tried on synthetic voices first (docs/pronunciation-coach.md §3).
nonisolated enum ProsodyAnalyzer {
    /// Moments measured in each syllable.
    static let points = 10
    /// Seconds between frames.
    static var frameSeconds: Double { Double(PitchTracker.hop) / PitchTracker.sampleRate }

    static func semitones(_ hz: Double) -> Double { 12 * log2(hz / 100) }
    static func hertz(_ semitones: Double) -> Double { 100 * pow(2, semitones / 12) }

    /// A recording of a word with `syllables` syllables; nil when no voice was heard or it cannot be cut that many ways.
    static func analyze(_ samples: [Float], syllables: Int) -> ProsodyTake? {
        analyze(frames: PitchTracker.frames(samples), syllables: syllables)
    }

    static func analyze(frames: [ProsodyFrame], syllables count: Int) -> ProsodyTake? {
        guard count > 0, !frames.isEmpty else { return nil }
        let pitch = track(frames)
        let db = frames.map(\.db)
        let segments = segment(pitch, loudness: db, count: count)
        guard segments.count == count else { return nil }
        let smooth = smoothed(db)
        let peak = smooth.max() ?? 0
        let relative: [Double?] = smooth.map { $0 - peak }
        var out: [SyllableProsody] = []
        for seg in segments {
            guard let p = resample(pitch, seg), let l = resample(relative, seg) else { return nil }
            let mean = seg.map { smooth[$0] - peak }.reduce(0, +) / Double(seg.count)
            out.append(SyllableProsody(
                pitch: p, loudness: l,
                duration: Double(seg.count) * frameSeconds,
                meanLoudness: mean,
                start: frames[seg.lowerBound].time, end: frames[seg.upperBound].time
            ))
        }
        let voiced = pitch.compactMap { $0 }.sorted()
        return ProsodyTake(syllables: out, pitchPercentiles: [
            percentile(voiced, 0.05), percentile(voiced, 0.5), percentile(voiced, 0.95),
        ])
    }

    // MARK: - Pitch track

    /// The pitch of each frame in semitones (nil = no voice): voiced only where the frame is clearly periodic and well
    /// above the background noise; octave slips folded back inside each stretch of voice; a 5-frame median; stretches
    /// shorter than 40 ms dropped.
    static func track(_ frames: [ProsodyFrame]) -> [Double?] {
        guard !frames.isEmpty else { return [] }
        let sortedDb = frames.map(\.db).sorted()
        let floor = sortedDb[Int(0.1 * Double(sortedDb.count - 1))]
        let peak = sortedDb.last ?? 0
        let gate = max(floor + 10, peak - 35)
        var pitch: [Double?] = frames.map { f in
            guard let hz = f.f0, f.aperiodicity < 0.3, f.db > gate else { return nil }
            return semitones(hz)
        }
        // Octave slips: inside one stretch of voice the pitch cannot jump an octave from one frame to the next, so a
        // value about 12 semitones from the stretch's median is folded back. Never across a gap: a new syllable may
        // really start an octave higher (a 4th tone after a low 3rd).
        for run in runs(pitch) {
            let values = run.compactMap { pitch[$0] }.sorted()
            guard !values.isEmpty else { continue }
            let median = values[values.count / 2]
            for k in run {
                guard let p = pitch[k], abs(p - median) > 9 else { continue }
                for octave in [12.0, -12.0] where abs(p - octave - median) < abs(p - median) - 6 {
                    pitch[k] = p - octave
                    break
                }
            }
        }
        // A 5-frame median over the voiced neighbours.
        var smooth = pitch
        for i in pitch.indices where pitch[i] != nil {
            let near = pitch[max(0, i - 2)...min(pitch.count - 1, i + 2)].compactMap { $0 }.sorted()
            smooth[i] = near[near.count / 2]
        }
        // Stretches under 40 ms are clicks or noise, not voice.
        var i = 0
        while i < smooth.count {
            guard smooth[i] != nil else { i += 1; continue }
            var j = i
            while j < smooth.count, smooth[j] != nil { j += 1 }
            if j - i < 4 { for k in i..<j { smooth[k] = nil } }
            i = j
        }
        return smooth
    }

    /// The stretches of voice: voiced frames with gaps of at most `bridge` frames (20 ms) between them.
    static func runs(_ pitch: [Double?], bridge: Int = 2) -> [ClosedRange<Int>] {
        var out: [ClosedRange<Int>] = []
        var i = 0
        let n = pitch.count
        while i < n {
            guard pitch[i] != nil else { i += 1; continue }
            var j = i
            var last = i
            while j < n {
                if pitch[j] != nil {
                    last = j
                    j += 1
                    continue
                }
                var k = j
                while k < n, pitch[k] == nil { k += 1 }
                if k < n, k - j <= bridge {
                    j = k
                    continue
                }
                break
            }
            out.append(i...last)
            i = last + 1
        }
        return out
    }

    // MARK: - Syllables

    /// The word's voice cut into `count` syllables.
    ///
    /// Most syllables are separated by a consonant without voice (a gap). Weak short blips are dropped first; too many
    /// stretches are joined across the shortest gaps; too few are cut where the loudness dips at least 3 dB between two
    /// louder parts (a nasal or a vowel boundary: 媽媽, 銀行), the deepest dips first; what is still missing is cut in the
    /// middle of the longest stretch.
    static func segment(_ pitch: [Double?], loudness db: [Double], count n: Int) -> [ClosedRange<Int>] {
        var parts = runs(pitch).map { [$0.lowerBound, $0.upperBound] }
        guard n > 0, !parts.isEmpty, db.count == pitch.count else { return [] }
        let peak = parts.flatMap { db[$0[0]...$0[1]] }.max() ?? 0
        let strong = parts.filter { p in
            let short = p[1] - p[0] + 1 < 6
            let weak = (db[p[0]...p[1]].max() ?? -200) < peak - 25
            return !(short && weak)
        }
        if !strong.isEmpty { parts = strong }

        while parts.count > n {
            var k = 0
            var smallest = Int.max
            for i in 0..<(parts.count - 1) {
                let gap = parts[i + 1][0] - parts[i][1]
                if gap < smallest { smallest = gap; k = i }
            }
            parts[k] = [parts[k][0], parts[k + 1][1]]
            parts.remove(at: k + 1)
        }

        if parts.count < n {
            let smooth = smoothed(db)
            var dips: [(depth: Double, at: Int)] = []
            for p in parts where p[1] - p[0] >= 12 {
                let (a, b) = (p[0], p[1])
                for i in (a + 6)...(b - 6) {
                    guard smooth[i] < smooth[i - 1], smooth[i] <= smooth[i + 1] else { continue }
                    let left = smooth[a..<i].max() ?? smooth[i]
                    let right = smooth[(i + 1)...b].max() ?? smooth[i]
                    let depth = min(left, right) - smooth[i]
                    if depth >= 3 { dips.append((depth, i)) }
                }
            }
            var cuts: [Int] = []
            for dip in dips.sorted(by: { $0.depth > $1.depth }) where cuts.count < n - parts.count {
                if cuts.allSatisfy({ abs($0 - dip.at) >= 8 }) { cuts.append(dip.at) }
            }
            cuts.sort()
            var split: [[Int]] = []
            for p in parts {
                var start = p[0]
                for c in cuts where c > p[0] && c < p[1] {
                    split.append([start, c - 1])
                    start = c + 1
                }
                split.append([start, p[1]])
            }
            parts = split
            while parts.count < n {
                guard let k = parts.indices.max(by: { parts[$0][1] - parts[$0][0] < parts[$1][1] - parts[$1][0] }),
                      parts[k][1] - parts[k][0] >= 7 else { break }
                let (a, b) = (parts[k][0], parts[k][1])
                let mid = (a + b) / 2
                parts.replaceSubrange(k...k, with: [[a, mid], [mid + 1, b]])
            }
        }
        return parts.map { $0[0]...$0[1] }
    }

    // MARK: - Helpers

    /// The values over `range` at the `points` moments (linear between voiced frames, held at the ends).
    static func resample(_ values: [Double?], _ range: ClosedRange<Int>) -> [Double]? {
        let known = range.compactMap { i in values[i].map { (Double(i), $0) } }
        guard !known.isEmpty else { return nil }
        let a = Double(range.lowerBound), b = Double(range.upperBound)
        return (0..<points).map { k in
            let x = a + (b - a) * (0.05 + 0.9 * Double(k) / Double(points - 1))
            if x <= known[0].0 { return known[0].1 }
            if x >= known[known.count - 1].0 { return known[known.count - 1].1 }
            var j = 1
            while known[j].0 < x { j += 1 }
            let (x0, y0) = known[j - 1], (x1, y1) = known[j]
            return x1 == x0 ? y1 : y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        }
    }

    /// A 5-frame moving average.
    static func smoothed(_ v: [Double]) -> [Double] {
        v.indices.map { i in
            let part = v[max(0, i - 2)...min(v.count - 1, i + 2)]
            return part.reduce(0, +) / Double(part.count)
        }
    }

    static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let pos = q * Double(sorted.count - 1)
        let lo = Int(pos.rounded(.down)), hi = min(sorted.count - 1, lo + 1)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
    }
}
