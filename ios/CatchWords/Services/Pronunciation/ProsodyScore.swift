import Foundation

/// One syllable put on its speaker's own scale: pitch as levels 1…5, its share of the word's length, loudness relative
/// to the word's loudest moment. Two speakers' syllables compare directly in this form.
nonisolated struct NormalizedSyllable: Codable, Sendable, Equatable {
    var levels: [Double]
    var loudness: [Double]
    /// Its part of the word's voiced length (1 for a word of one syllable).
    var share: Double
    var duration: Double
    var meanLoudness: Double

    /// Rise (+) or fall (−) from its start to its end, levels (the mean of the first two and last two moments).
    var slope: Double {
        guard levels.count >= 4 else { return 0 }
        return (levels[levels.count - 2] + levels[levels.count - 1]) / 2 - (levels[0] + levels[1]) / 2
    }

    static func make(_ take: ProsodyTake, range: SpeakerRange) -> [NormalizedSyllable] {
        let total = max(take.syllables.reduce(0) { $0 + $1.duration }, 1e-6)
        return take.syllables.map { s in
            NormalizedSyllable(levels: s.pitch.map(range.level), loudness: s.loudness,
                               share: s.duration / total, duration: s.duration, meanLoudness: s.meanLoudness)
        }
    }
}

/// What natives do with each syllable of a word: the mean and the spread of each measure across their recordings.
/// Inside mean ± spread is 「ネイティブの範囲」. With few recordings the spread has a floor, so one voice is never
/// taken as the only right way.
nonisolated struct ProsodyBand: Sendable, Equatable {
    nonisolated struct Syllable: Sendable, Equatable {
        var levels: [Double]
        var levelSD: [Double]
        var loudness: [Double]
        var loudnessSD: [Double]
        var share: Double
        var shareSD: Double
        var duration: Double
        var meanLoudness: Double
        var meanLoudnessSD: Double
        var slope: Double
        var slopeSD: Double

        /// The band drawn on the chart: mean ± this, never thinner than half a level.
        func halfWidth(_ k: Int) -> Double { max(0.5, 1.5 * levelSD[k]) }
    }

    var syllables: [Syllable]
    /// How many recordings it was made from.
    var takes: Int

    static let levelSDFloor = 0.35
    static let levelSDSingle = 0.5
    static let shareSDFloor = 0.06
    static let loudnessSDFloor = 3.0

    /// nil when there is no recording, or the recordings have different numbers of syllables.
    init?(_ takes: [[NormalizedSyllable]]) {
        guard let first = takes.first, !first.isEmpty, takes.allSatisfy({ $0.count == first.count }) else { return nil }
        let n = takes.count
        let pitchFloor = n == 1 ? Self.levelSDSingle : Self.levelSDFloor
        syllables = first.indices.map { i in
            let col = takes.map { $0[i] }
            let points = col[0].levels.count
            func pointwise(_ pick: (NormalizedSyllable) -> [Double], floor: Double) -> ([Double], [Double]) {
                let rows = col.map(pick)
                let mean = (0..<points).map { k in rows.map { $0[k] }.reduce(0, +) / Double(n) }
                let sd = (0..<points).map { k in max(floor, Self.sd(rows.map { $0[k] }, mean: mean[k])) }
                return (mean, sd)
            }
            let (lv, lvSD) = pointwise(\.levels, floor: pitchFloor)
            let (ld, ldSD) = pointwise(\.loudness, floor: Self.loudnessSDFloor)
            let shares = col.map(\.share), slopes = col.map(\.slope), means = col.map(\.meanLoudness)
            let share = shares.reduce(0, +) / Double(n)
            let slope = slopes.reduce(0, +) / Double(n)
            let meanLoud = means.reduce(0, +) / Double(n)
            return Syllable(
                levels: lv, levelSD: lvSD, loudness: ld, loudnessSD: ldSD,
                share: share, shareSD: max(Self.shareSDFloor, Self.sd(shares, mean: share)),
                duration: col.map(\.duration).reduce(0, +) / Double(n),
                meanLoudness: meanLoud, meanLoudnessSD: max(Self.loudnessSDFloor + 1, Self.sd(means, mean: meanLoud)),
                slope: slope, slopeSD: max(pitchFloor, Self.sd(slopes, mean: slope))
            )
        }
        self.takes = n
    }

    static func sd(_ v: [Double], mean: Double) -> Double {
        guard v.count > 1 else { return 0 }
        return (v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(v.count - 1)).squareRoot()
    }
}

/// How a learner's recording compares with the natives': pitch (height and movement), length and loudness each scored
/// 0…1 against the band, weighted into one score. Pitch weighs most: listeners rely on it first, height and movement
/// about equally; length and loudness help (the 3rd tone is the longest and softest, the 4th the shortest and loudest)
/// — Tseng et al. 1986, Massaro et al. 1985, Kuo et al. 2008 (docs/pronunciation-coach.md §2).
nonisolated struct ProsodyScore: Sendable, Equatable {
    static let weights = (height: 0.35, movement: 0.35, length: 0.15, loudness: 0.15)
    /// A syllable at or above this is 「ネイティブの範囲」; at or above `close`, 「あと少し」.
    static let good = 85
    static let close = 65

    nonisolated struct Syllable: Sendable, Equatable {
        var total: Int
        var height: Double
        var movement: Double
        var length: Double
        var loudness: Double
        /// Learner − natives, for the advice: mean level, rise/fall, share of the word (or log₂ of the length ratio for a
        /// word of one syllable), mean loudness in dB.
        var heightDiff: Double
        var slope: Double
        var refSlope: Double
        var lengthDiff: Double
        var loudnessDiff: Double
    }

    nonisolated enum Advice: Equatable, Sendable {
        case great
        case higher(Int), lower(Int)
        case riseMore(Int), fallMore(Int), keepLevel(Int), followMovement(Int)
        case longer(Int), shorter(Int)
        case stronger(Int), softer(Int), followStress(Int)

        var syllable: Int? {
            switch self {
            case .great: nil
            case .higher(let i), .lower(let i), .riseMore(let i), .fallMore(let i), .keepLevel(let i),
                 .followMovement(let i), .longer(let i), .shorter(let i), .stronger(let i), .softer(let i),
                 .followStress(let i): i
            }
        }
    }

    var syllables: [Syllable]
    var total: Int
    /// 高さ (height and movement), 長さ, 強さ — 0…100.
    var pitch: Int
    var length: Int
    var loudness: Int
    var advice: Advice

    /// 1 inside the tolerance, falling to 0 at three times it.
    static func soft(_ d: Double, _ tol: Double) -> Double {
        let d = abs(d)
        guard d > tol else { return 1 }
        return max(0, 1 - (d - tol) / (2 * tol))
    }

    /// nil when the syllable counts differ.
    static func score(_ take: [NormalizedSyllable], against band: ProsodyBand) -> ProsodyScore? {
        guard !take.isEmpty, take.count == band.syllables.count else { return nil }
        let many = take.count > 1
        var rows: [Syllable] = []
        for (t, r) in zip(take, band.syllables) {
            let mean = t.levels.reduce(0, +) / Double(t.levels.count)
            let refMean = r.levels.reduce(0, +) / Double(r.levels.count)
            let meanSD = r.levelSD.reduce(0, +) / Double(r.levelSD.count)
            let heightDiff = mean - refMean
            let height = soft(heightDiff, max(0.5, meanSD))

            // Movement: the shape once both are moved to the same height, and the rise or fall from start to end.
            let shapeError = (zip(t.levels, r.levels).map { pair -> Double in
                let d = (pair.0 - mean) - (pair.1 - refMean)
                return d * d
            }.reduce(0, +) / Double(t.levels.count)).squareRoot()
            let slopeDiff = t.slope - r.slope
            let movement = min(soft(shapeError, max(0.45, meanSD)),
                               soft(slopeDiff, max(0.45, min(0.8, 1.2 * r.slopeSD))))

            let lengthDiff = many ? t.share - r.share : log2(max(t.duration, 0.01) / max(r.duration, 0.01))
            let length = many ? soft(lengthDiff, max(ProsodyBand.shareSDFloor, r.shareSD)) : soft(lengthDiff, 0.6)

            let tMeanDb = t.loudness.reduce(0, +) / Double(t.loudness.count)
            let rMeanDb = r.loudness.reduce(0, +) / Double(r.loudness.count)
            let envelope = (zip(t.loudness, r.loudness).map { pair -> Double in
                let d = (pair.0 - tMeanDb) - (pair.1 - rMeanDb)
                return d * d
            }.reduce(0, +) / Double(t.loudness.count)).squareRoot()
            let loudSD = r.loudnessSD.reduce(0, +) / Double(r.loudnessSD.count)
            let loudnessDiff = t.meanLoudness - r.meanLoudness
            var loud = soft(envelope, max(ProsodyBand.loudnessSDFloor, loudSD))
            if many { loud = 0.5 * loud + 0.5 * soft(loudnessDiff, r.meanLoudnessSD) }

            let w = weights
            var total = 100 * (w.height * height + w.movement * movement + w.length * length + w.loudness * loud)
            // A syllable whose pitch is clearly another tone is heard as another word, however right its length and
            // loudness: it never reaches 「あと少し」.
            let pitchFloor = min(height, movement)
            if pitchFloor < 0.5 { total = min(total, 60 + 50 * pitchFloor) }
            rows.append(Syllable(total: Int(total.rounded()), height: height, movement: movement, length: length,
                                 loudness: loud, heightDiff: heightDiff, slope: t.slope, refSlope: r.slope,
                                 lengthDiff: lengthDiff, loudnessDiff: loudnessDiff))
        }
        func average(_ v: [Double]) -> Int { Int((100 * v.reduce(0, +) / Double(v.count)).rounded()) }
        return ProsodyScore(
            syllables: rows,
            total: Int((Double(rows.map(\.total).reduce(0, +)) / Double(rows.count)).rounded()),
            pitch: average(rows.map { ($0.height + $0.movement) / 2 }),
            length: average(rows.map(\.length)),
            loudness: average(rows.map(\.loudness)),
            advice: advice(rows)
        )
    }

    /// One thing to fix: the biggest loss of the weakest syllable (none when every syllable is in the natives' range).
    static func advice(_ rows: [Syllable]) -> Advice {
        guard let i = rows.indices.min(by: { rows[$0].total < rows[$1].total }), rows[i].total < good else { return .great }
        let s = rows[i]
        let w = weights
        let losses: [(Double, Int)] = [
            (w.height * (1 - s.height), 0), (w.movement * (1 - s.movement), 1),
            (w.length * (1 - s.length), 2), (w.loudness * (1 - s.loudness), 3),
        ]
        let worst = losses.max(by: { $0.0 < $1.0 })?.1 ?? 0
        switch worst {
        case 0:
            return s.heightDiff < 0 ? .higher(i) : .lower(i)
        case 1:
            if s.refSlope >= 0.8, s.slope < s.refSlope { return .riseMore(i) }
            if s.refSlope <= -0.8, s.slope > s.refSlope { return .fallMore(i) }
            if abs(s.refSlope) < 0.6 { return .keepLevel(i) }
            return .followMovement(i)
        case 2:
            return s.lengthDiff < 0 ? .longer(i) : .shorter(i)
        default:
            if rows.count > 1, abs(s.loudnessDiff) >= 4 { return s.loudnessDiff < 0 ? .stronger(i) : .softer(i) }
            return .followStress(i)
        }
    }
}
