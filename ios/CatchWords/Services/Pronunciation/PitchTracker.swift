import Accelerate
import Foundation

// 発音コーチ（2026-11-28、オーナー「Catchwordsは最高品質の発音機能があるアプリを目指す」、11-29「本物の発音から分析して、
// この範囲で高さ・長さ・強さなどの要素で総合的に判定したい」）。設計は docs/pronunciation-coach.md。
// 声はすべて端末の中で分析する（学習者の声はサーバーに送らない）。

/// One moment of a recording, 10 ms apart: the voice's pitch and loudness there.
nonisolated struct ProsodyFrame: Sendable, Equatable {
    /// The middle of the frame, seconds from the start of the recording.
    var time: Double
    /// The pitch in Hz; nil where no clear period was found (silence, noise, a voiceless consonant).
    var f0: Double?
    /// YIN's aperiodicity at the chosen period: 0 = a perfectly regular voice, 1 = noise.
    var aperiodicity: Double
    /// Loudness, dB of the mean square of the frame. Only differences are used (the microphone's gain cancels out).
    var db: Double
}

/// The pitch of a voice by YIN (de Cheveigné & Kawahara 2002), on 16 kHz mono samples.
///
/// A frame every 10 ms over 40 ms of sound: wide enough for two periods of a low male voice (65 Hz), fine enough to
/// follow a falling 4th tone. The difference function is one `vDSP_distancesq` per lag (a few hundred per frame), so a
/// live recording is analysed as it comes in. Checked against synthetic voices in `PitchTrackerTests`.
nonisolated enum PitchTracker {
    static let sampleRate: Double = 16_000
    /// 40 ms of samples per frame.
    static let window = 640
    /// 10 ms between frames.
    static let hop = 160
    /// The lowest and highest voice followed (a low male voice … a high child's voice).
    static let minF0: Double = 65
    static let maxF0: Double = 650
    /// YIN's absolute threshold: the first dip of the normalised difference below it is the period.
    static let threshold: Float = 0.15
    /// Above this aperiodicity the frame has no pitch at all.
    static let unvoicedAbove: Double = 0.35

    static var tauMax: Int { Int(sampleRate / minF0) }
    static var tauMin: Int { Int(sampleRate / maxF0) }
    /// Samples compared at each lag (the window less the longest lag).
    static var span: Int { window - tauMax }

    /// The frames of a whole recording.
    static func frames(_ samples: [Float]) -> [ProsodyFrame] {
        frames(samples, from: 0, upTo: samples.count)
    }

    /// The frames whose windows start at `from`, `from + hop`, … and fit before `upTo` (a live recording analyses each
    /// new stretch as it arrives).
    static func frames(_ samples: [Float], from start: Int, upTo end: Int) -> [ProsodyFrame] {
        let end = min(end, samples.count)
        guard start >= 0, end - start >= window else { return [] }
        let count = (end - start - window) / hop + 1
        var out: [ProsodyFrame] = []
        out.reserveCapacity(count)
        var diff = [Float](repeating: 0, count: tauMax + 1)
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for i in 0..<count {
                let s = start + i * hop
                let time = (Double(s) + Double(window) / 2) / sampleRate
                out.append(frame(base + s, diff: &diff, time: time))
            }
        }
        return out
    }

    /// One frame: `p` points at its first sample, `window` samples are read.
    private static func frame(_ p: UnsafePointer<Float>, diff: inout [Float], time: Double) -> ProsodyFrame {
        let tMax = tauMax
        let tMin = tauMin
        let n = vDSP_Length(span)

        var meanSquare: Float = 0
        vDSP_measqv(p, 1, &meanSquare, vDSP_Length(window))
        let db = 10 * log10(Double(meanSquare) + 1e-10)

        // The difference function d(τ) = Σ (x[j] − x[j+τ])², then its cumulative mean normalisation, in place.
        diff.withUnsafeMutableBufferPointer { d in
            d[0] = 1
            for tau in 1...tMax {
                var v: Float = 0
                vDSP_distancesq(p, 1, p + tau, 1, &v, n)
                d[tau] = v
            }
            var running: Float = 0
            for tau in 1...tMax {
                running += d[tau]
                d[tau] = running > 0 ? d[tau] * Float(tau) / running : 1
            }
        }

        // The first dip under the threshold (walked down to its bottom); else the deepest dip.
        var best = -1
        var tau = tMin
        while tau <= tMax {
            if diff[tau] < threshold {
                while tau + 1 <= tMax, diff[tau + 1] < diff[tau] { tau += 1 }
                best = tau
                break
            }
            tau += 1
        }
        if best < 0 {
            var lowest = Float.greatestFiniteMagnitude
            for t in tMin...tMax where diff[t] < lowest {
                lowest = diff[t]
                best = t
            }
        }
        let aperiodicity = Double(diff[best])
        // A parabola through the dip and its neighbours: the period between two samples.
        var period = Double(best)
        if best > tMin, best < tMax {
            let y0 = Double(diff[best - 1]), y1 = Double(diff[best]), y2 = Double(diff[best + 1])
            let den = y0 - 2 * y1 + y2
            if abs(den) > 1e-12 { period = Double(best) + 0.5 * (y0 - y2) / den }
        }
        let f0: Double? = (aperiodicity < unvoicedAbove && period > 0) ? sampleRate / period : nil
        return ProsodyFrame(time: time, f0: f0, aperiodicity: aperiodicity, db: db)
    }
}
