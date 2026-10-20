import SwiftUI

// MARK: - The catch scan, v10 (owner 2026-10-11 「v10を承認する。アプリに実装して」)
//
// From the shutter to the word tags, as the approved concept film v10 (docs/design/catch-concepts/README.md › v10;
// the code it ports: film/js/o10_pen.js, scan7.js; a film pixel is 1/2.75 pt):
// - A bracket comes up over the photo, slides onto each thing and clicks there (white while it moves, blue when it
//   holds). From the click, a big point of light — the pen — draws that thing's outline in one stroke, slower where
//   the outline turns, quicker on the straights, then hops to the next thing.
// - The pen runs on its own clock τ: 1× until the names arrive, then it speeds up (over 0.15 s) so whatever is left
//   is drawn within 0.5 s, never faster than 4×. The bracket, its click and the glints go by the same clock.
// - A tag comes up once its thing has a name and a closed outline, 0.14 s after the names and 0.13 s apart.
// - Drawing done and still no names: one small light goes round the outlines until they come.
// - The outlines are Vision's foreground instances (`InstanceMasks.outlines`). None (or none in time): the bracket
//   waits over the photo, breathing, and the tags come up with the names.

/// The film's values, in points and seconds.
nonisolated enum CatchScanSpec {
    /// The bracket comes up this long after the scan starts (the film: 0.26 s after the shutter; the photo is on screen
    /// about 0.15 s after it).
    static let bracketIn = 0.12
    static let appear = 0.26, move = 0.54, hop = 0.26, fadeOut = 0.3
    static let catchWindow = 0.5, ramp = 0.15, kMax = 4.0
    static let tagLead = 0.14, tagGap = 0.13, tagAfterClose = 0.1
    static let patrolDelay = 0.3, patrolIn = 0.3, patrolOut = 0.25, penOut = 0.25
    /// Names in and the outlines still not: go on without them after this.
    static let outlineWait = 0.6
    static let px: CGFloat = 1 / 2.75
    static let penRadius = 34 * px, smallRadius = 20 * px, patrolSpeed = 1350 * px
    static let spacing = 4 * px, edge = 6 * px, hopRise = 160 * px
    static let pad: CGFloat = 14, margin: CGFloat = 10
    static let bracketLine: CGFloat = 3, bracketRadius: CGFloat = 12, bracketArm: CGFloat = 19
    /// The pen's time for one outline, from its length over the stage's diagonal (the film's cup 1.0 s, scooter 0.9 s
    /// and sign 0.6 s sit on this line).
    static func duration(lengthRatio r: Double) -> Double { min(1.0, max(0.6, 0.43 + 0.53 * r)) }
}

/// When the pen reaches, draws and leaves each thing on its own clock τ, and how τ runs faster than real time once
/// the names are in. Seconds from the scan's start. Pure, so CatchScanTests checks it against the film's times.
nonisolated struct CatchScanTimeline: Sendable, Equatable {
    let bracketIn: Double
    let durations: [Double]
    /// τ when the bracket clicks onto thing r (the pen arrives there).
    let lock: [Double]
    /// Real time the catch-up began (nil = not yet) and the speed it reached.
    private(set) var catchFrom: Double?
    private(set) var k: Double = 1

    /// `ready`: when the outlines were known (the bracket waits over the photo until then).
    init(durations: [Double], ready: Double, bracketIn: Double = CatchScanSpec.bracketIn) {
        self.bracketIn = bracketIn
        self.durations = durations
        var t = max(bracketIn + CatchScanSpec.appear, ready) + CatchScanSpec.move
        var lock: [Double] = []
        for d in durations {
            lock.append(t)
            t += d + CatchScanSpec.hop
        }
        self.lock = lock
    }

    /// The bracket leaves for thing r so that it clicks just as the pen arrives.
    func moveStart(_ r: Int) -> Double { lock[r] - CatchScanSpec.move }
    func close(_ r: Int) -> Double { lock[r] + durations[r] }
    var drawEnd: Double { durations.isEmpty ? bracketIn + CatchScanSpec.appear : close(durations.count - 1) }

    /// From `t` the pen speeds up so the rest is drawn within `catchWindow`, never above `kMax`. τ is still real
    /// time at `t`, so what is left is `drawEnd − t`. Called once (the names, or the outlines if they came later).
    mutating func startCatchUp(at t: Double) {
        guard catchFrom == nil else { return }
        catchFrom = t
        let s = CatchScanSpec.self
        let left = drawEnd - t
        k = left <= s.catchWindow ? 1 : min(s.kMax, 1 + (left - s.catchWindow) / (s.catchWindow - s.ramp / 2))
    }

    /// The extra τ the speed-up has added `d` seconds after it began (∫ of a smoothstep ramp, then linear).
    private static func extra(_ d: Double) -> Double {
        let r = CatchScanSpec.ramp
        if d <= r {
            let u = d / r
            return r * (u * u * u - u * u * u * u / 2)
        }
        return r / 2 + (d - r)
    }

    func tau(_ t: Double) -> Double {
        guard let c = catchFrom, k != 1, t > c else { return t }
        return t + (k - 1) * Self.extra(t - c)
    }

    /// The real time at which τ reads `x` (τ only grows: halve until close).
    func real(_ x: Double) -> Double {
        guard let c = catchFrom, k != 1, x > c else { return x }
        var lo = c, hi = x
        for _ in 0..<40 {
            let m = (lo + hi) / 2
            if tau(m) < x { lo = m } else { hi = m }
        }
        return hi
    }

    /// When the names show (the "found" sound): when they are in, and not before the first outline is closed.
    func found(names: Double) -> Double { durations.isEmpty ? names : max(names, real(close(0))) }

    /// When object `k`'s tag comes up: in turn after `found`, never before its own outline (`rank`) is closed.
    func tag(_ k: Int, rank: Int?, names: Double) -> Double {
        let s = CatchScanSpec.self
        let base = found(names: names) + s.tagLead + s.tagGap * Double(k)
        guard let r = rank, r >= 0, r < durations.count else { return base }
        return max(base, real(close(r)) + s.tagAfterClose)
    }
}

/// One thing the pen draws, in the stage's points: its outline every film 4 px from its top, clockwise; each
/// point's distance to the stage's edge; and at what share (0…1) of the drawing time the pen passes each point.
nonisolated struct CatchScanShape: Sendable {
    let label: Int
    let pts: [CGPoint]
    let edge: [CGFloat]
    let pace: [Double]
    let duration: Double
    let box: CGRect

    init?(outline: CatchOutline, fill: CGRect, stage: CGSize, diagonal: CGFloat) {
        let s = CatchScanSpec.self
        var p = outline.points.map { CGPoint(x: fill.minX + $0.x * fill.width, y: fill.minY + $0.y * fill.height) }
        guard p.count >= 3 else { return nil }
        // Clockwise on screen (a positive shoelace sum with y down), starting at the top (scan7.js `outlineOf`).
        var area: CGFloat = 0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            area += a.x * b.y - b.x * a.y
        }
        if area < 0 { p.reverse() }
        if let top = p.indices.min(by: { p[$0].y < p[$1].y }) { p = Array(p[top...] + p[..<top]) }
        let pts = Self.resample(p, every: s.spacing)
        let n = pts.count
        guard n >= 8 else { return nil }
        let edge = pts.map { min($0.x, stage.width - $0.x, $0.y, stage.height - $0.y) }
        // How sharply the outline turns at each point (3 points either side).
        var turn = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let a = pts[(i - 3 + n) % n], q = pts[i], b = pts[(i + 3) % n]
            let a1 = atan2(Double(q.y - a.y), Double(q.x - a.x)), a2 = atan2(Double(b.y - q.y), Double(b.x - q.x))
            var d = abs(a2 - a1)
            if d > .pi { d = 2 * .pi - d }
            turn[i] = d
        }
        // W2's pace: slower where it turns; a quarter of the time along the stage's edge (the pen is out of sight).
        var cum = [Double](repeating: 0, count: n)
        var acc = 0.0
        var length: CGFloat = 0
        for i in 0..<n {
            var sum = 0.0
            for d in -4...4 { sum += turn[(i + d + n) % n] }
            let atEdge = edge[i] < s.edge
            acc += (1 + 2.6 * sum / 9) * (atEdge ? 0.25 : 1)
            cum[i] = acc
            let b = pts[(i + 1) % n]
            length += hypot(b.x - pts[i].x, b.y - pts[i].y) * (atEdge ? 0.25 : 1)
        }
        let tot = max(acc, 1e-9)
        var x0 = CGFloat.greatestFiniteMagnitude, y0 = CGFloat.greatestFiniteMagnitude
        var x1 = -CGFloat.greatestFiniteMagnitude, y1 = -CGFloat.greatestFiniteMagnitude
        for q in pts {
            x0 = min(x0, q.x); y0 = min(y0, q.y)
            x1 = max(x1, q.x); y1 = max(y1, q.y)
        }
        self.label = outline.label
        self.pts = pts
        self.edge = edge
        self.pace = cum.map { acos(1 - 2 * min(1, $0 / tot)) / .pi }
        self.duration = s.duration(lengthRatio: Double(length / max(diagonal, 1)))
        self.box = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Points every `step` along a closed ring.
    static func resample(_ pts: [CGPoint], every step: CGFloat) -> [CGPoint] {
        guard pts.count > 1, step > 0 else { return pts }
        var out = [pts[0]]
        var carry: CGFloat = 0
        let n = pts.count
        for i in 0..<n {
            var a = pts[i]
            let b = pts[(i + 1) % n]
            var seg = hypot(b.x - a.x, b.y - a.y)
            while seg > 0, carry + seg >= step {
                let f = (step - carry) / seg
                a = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                out.append(a)
                seg = hypot(b.x - a.x, b.y - a.y)
                carry = 0
            }
            carry += seg
        }
        if out.count > 2, let last = out.last, hypot(last.x - out[0].x, last.y - out[0].y) < step / 2 { out.removeLast() }
        return out
    }

    /// How far the pen has drawn this outline at pen time `tau` (a fractional point index, 0…n) and where it is.
    func head(lock: Double, tau: Double) -> (h: Double, at: CGPoint) {
        let n = pts.count
        if tau <= lock { return (0, pts[0]) }
        if tau >= lock + duration { return (Double(n), pts[0]) }
        func td(_ i: Int) -> Double { lock + duration * pace[i] }
        var lo = 0, hi = n - 1
        while lo < hi {
            let m = (lo + hi + 1) / 2
            if td(m) <= tau { lo = m } else { hi = m - 1 }
        }
        let t0 = (lo == 0 && td(0) > tau) ? lock : td(lo)
        let t1 = td(min(n - 1, lo + 1))
        let f = t1 > t0 ? min(1, max(0, (tau - t0) / (t1 - t0))) : 0
        let p = pts[lo], q = pts[(lo + 1) % n]
        return (Double(lo) + f, CGPoint(x: p.x + (q.x - p.x) * CGFloat(f), y: p.y + (q.y - p.y) * CGFloat(f)))
    }
}

/// Everything the scan draws for one photo, in the stage's points (built once the outlines and the stage are known).
nonisolated struct CatchScanPlan: Sendable {
    let stage: CGSize
    let fill: CGRect
    let shapes: [CatchScanShape]
    var timeline: CatchScanTimeline
    /// When the outlines were known (seconds from the scan's start).
    let readyAt: Double
    /// The bracket's first place, over the middle of the photo, and its place round each thing.
    let full: CGRect
    let boxes: [CGRect]
    /// The small light's round: each outline, then the hop to the next (constant speed).
    let patrol: [PatrolLeg]
    let patrolLength: CGFloat

    nonisolated struct PatrolLeg: Sendable {
        /// The outline it goes round (nil = a hop through the air).
        let shape: Int?
        let pts: [CGPoint]
        let cum: [CGFloat]
        let start: CGFloat
    }

    init(outlines: [CatchOutline], stage: CGSize, fill: CGRect, ready: Double,
         bracketIn: Double = CatchScanSpec.bracketIn) {
        let s = CatchScanSpec.self
        let diagonal = hypot(stage.width, stage.height)
        let shapes = outlines.compactMap { CatchScanShape(outline: $0, fill: fill, stage: stage, diagonal: diagonal) }
        self.stage = stage
        self.fill = fill
        self.shapes = shapes
        self.readyAt = ready
        self.timeline = CatchScanTimeline(durations: shapes.map(\.duration), ready: ready, bracketIn: bracketIn)
        self.full = CGRect(x: 22, y: stage.height * 0.12, width: max(40, stage.width - 44), height: stage.height * 0.76)
        self.boxes = shapes.map { sh in
            let b = sh.box.insetBy(dx: -s.pad, dy: -s.pad)
            let x0 = max(s.margin, b.minX), y0 = max(s.margin, b.minY)
            let x1 = min(stage.width - s.margin, b.maxX), y1 = min(stage.height - s.margin, b.maxY)
            return CGRect(x: x0, y: y0, width: max(24, x1 - x0), height: max(24, y1 - y0))
        }
        var legs: [PatrolLeg] = []
        var total: CGFloat = 0
        for (r, sh) in shapes.enumerated() {
            var cum: [CGFloat] = [0]
            let ring = sh.pts + [sh.pts[0]]
            for i in 1..<ring.count {
                let d = hypot(ring[i].x - ring[i - 1].x, ring[i].y - ring[i - 1].y)
                cum.append(cum[i - 1] + d * (sh.edge[i - 1] < s.edge ? 0.25 : 1))
            }
            legs.append(PatrolLeg(shape: r, pts: ring, cum: cum, start: total))
            total += cum.last ?? 0
            let a = sh.pts[0], b = shapes[(r + 1) % shapes.count].pts[0]
            let c = Self.hopControl(a, b)
            let air = (0...40).map { Self.bez2(a, c, b, Double($0) / 40) }
            var acum: [CGFloat] = [0]
            for i in 1..<air.count { acum.append(acum[i - 1] + hypot(air[i].x - air[i - 1].x, air[i].y - air[i - 1].y)) }
            legs.append(PatrolLeg(shape: nil, pts: air, cum: acum, start: total))
            total += acum.last ?? 0
        }
        self.patrol = legs
        self.patrolLength = total
    }

    /// Where a `scaledToFill` photo sits inside `size` (as the words screen places it).
    static func fillRect(photo: CGSize, in size: CGSize) -> CGRect {
        guard photo.width > 0, photo.height > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = max(size.width / photo.width, size.height / photo.height)
        let w = photo.width * scale, h = photo.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    static func hopControl(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - CatchScanSpec.hopRise)
    }

    static func bez2(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        let u = CGFloat(u), v = 1 - u
        return CGPoint(x: v * v * a.x + 2 * v * u * c.x + u * u * b.x, y: v * v * a.y + 2 * v * u * c.y + u * u * b.y)
    }

    /// Where the small light is `distance` along its round, and the index of the point just behind it.
    func patrolPoint(_ distance: CGFloat) -> (leg: Int, index: Int, at: CGPoint)? {
        guard patrolLength > 0, !patrol.isEmpty else { return nil }
        let d = distance.truncatingRemainder(dividingBy: patrolLength)
        let pos = d < 0 ? d + patrolLength : d
        var li = patrol.count - 1
        for (i, leg) in patrol.enumerated() where pos < leg.start + (leg.cum.last ?? 0) {
            li = i
            break
        }
        let leg = patrol[li]
        let local = pos - leg.start
        var lo = 0, hi = leg.cum.count - 1
        while lo < hi - 1 {
            let m = (lo + hi) / 2
            if leg.cum[m] <= local { lo = m } else { hi = m }
        }
        let span = max(leg.cum[hi] - leg.cum[lo], 1e-6)
        let f = min(1, max(0, (local - leg.cum[lo]) / span))
        let p = leg.pts[lo], q = leg.pts[hi]
        return (li, lo, CGPoint(x: p.x + (q.x - p.x) * f, y: p.y + (q.y - p.y) * f))
    }
}

// MARK: - The scan for one photo (state, sounds, tags)

/// One photo's scan, kept by `CaptureViewModel` for the run (so going back from the celebration does not replay it).
/// The words screen starts it when it first shows the photo (`begin`), tells it where the photo sits (`layout`) and
/// steps it about 60 times a second (`step`): that plays the sounds at their moments and brings the tags up.
@Observable
final class CatchScanSession {
    enum Phase: Equatable { case scanning, naming, done }

    /// The objects (`CatchObject.id`) whose tags are up.
    private(set) var revealed: Set<Int> = []
    private(set) var phase: Phase = .scanning
    /// Everything has come up; only the outlines' slow pulse still moves.
    private(set) var settled = false

    @ObservationIgnored private(set) var started: Date?
    @ObservationIgnored private var outlines: [CatchOutline]?
    @ObservationIgnored private var outlinesAt: Date?
    @ObservationIgnored private var namesAt: Date?
    @ObservationIgnored private var objects: [CatchObject] = []
    @ObservationIgnored private(set) var plan: CatchScanPlan?
    @ObservationIgnored private var stage: CGSize?
    @ObservationIgnored private var fill: CGRect?
    @ObservationIgnored private var fired: Set<String> = []
    /// Object id → the rank of its drawn outline; the drawn outlines that got no name.
    @ObservationIgnored private var rankOf: [Int: Int] = [:]
    @ObservationIgnored private var unnamed: Set<Int> = []
    /// The UI tests' trace: when a frame was last noted (about twice a second while frames are drawn).
    @ObservationIgnored private var drawNoted: Double = -1

    /// The scan's clock starts (once) when the photo first shows.
    func begin(now: Date) {
        if started == nil { started = now }
    }

    /// Where the photo sits (the stage, and the photo's rect inside it as `scaledToFill` places it).
    func layout(stage: CGSize, fill: CGRect) {
        guard stage.width > 1, stage.height > 1 else { return }
        self.stage = stage
        self.fill = fill
    }

    /// Vision's outlines for this photo ([] = none). The first answer counts.
    func setOutlines(_ list: [CatchOutline], at: Date) {
        guard outlines == nil else { return }
        outlines = list
        outlinesAt = at
    }

    /// The names are in: the objects the words screen shows, each with its Vision instance.
    func setNames(_ list: [CatchObject], at: Date) {
        guard namesAt == nil else { return }
        objects = list
        namesAt = at
    }

    /// Seconds from the scan's start (clamped at 0: what was known before it began counts from its start).
    private func rel(_ date: Date?) -> Double? {
        guard let date, let started else { return nil }
        return max(0, date.timeIntervalSince(started))
    }

    /// The names' moment and the found / tag times (nil before the names).
    struct Moments {
        let names: Double
        let found: Double
        let tags: [Int: Double]
    }

    func moments(reduceMotion: Bool) -> Moments? {
        guard let names = rel(namesAt), let plan else { return nil }
        let tl = plan.timeline
        let found = reduceMotion ? names : tl.found(names: names)
        var tags: [Int: Double] = [:]
        for (k, o) in objects.enumerated() {
            if reduceMotion {
                tags[o.id] = found + CatchScanSpec.tagLead + CatchScanSpec.tagGap * Double(k)
            } else {
                tags[o.id] = tl.tag(k, rank: rankOf[o.id], names: names)
            }
        }
        return Moments(names: names, found: found, tags: tags)
    }

    func step(now: Date, reduceMotion: Bool) {
        guard let started else { return }
        let t = now.timeIntervalSince(started)
        buildPlan(t: t)
        guard var plan else { return }
        let names = rel(namesAt)
        if let names, plan.timeline.catchFrom == nil, !plan.shapes.isEmpty, !reduceMotion {
            plan.timeline.startCatchUp(at: max(names, plan.readyAt))
            self.plan = plan
        }
        let tl = plan.timeline
        if !reduceMotion {
            fire("in", due: tl.bracketIn, now: t) { SoundService.shared.play(.ccScanStart) }
            for r in plan.shapes.indices {
                fire("lock\(r)", due: tl.real(tl.lock[r]), now: t) {
                    SoundService.shared.play(.ccTick)
                    Haptics.selection()
                }
            }
        }
        var lastTag = 0.0
        if let m = moments(reduceMotion: reduceMotion) {
            fire("found", due: m.found, now: t) { SoundService.shared.play(.ccFound) }
            for o in objects {
                guard let due = m.tags[o.id] else { continue }
                lastTag = max(lastTag, due)
                if t >= due, !revealed.contains(o.id) {
                    revealed.insert(o.id)
                    UITestTrace.log("scan.reveal \(o.id) t=\(String(format: "%.2f", t)) due=\(String(format: "%.2f", due))")
                    if t - due < 0.25 {
                        SoundService.shared.playLayered(.ccPop)
                        Haptics.impact(.light)
                    }
                }
            }
        }
        let drawEnd = plan.shapes.isEmpty ? 0 : tl.real(tl.drawEnd)
        let drawing = reduceMotion ? false : (plan.shapes.isEmpty || t < drawEnd)
        let next: Phase
        if names != nil, revealed.count >= objects.count {
            next = .done
        } else if drawing || names != nil {
            next = .scanning
        } else {
            next = .naming
        }
        if next != phase {
            phase = next
            UITestTrace.log("scan.phase \(next) t=\(String(format: "%.2f", t))")
        }
        if next == .done, !settled, t >= max(drawEnd + CatchScanSpec.penOut, lastTag) + 0.6 {
            settled = true
            UITestTrace.log("scan.settled t=\(String(format: "%.2f", t)) shapes=\(plan.shapes.count)")
        }
    }

    /// Everything is up and nothing moves any more — no named outline to pulse (or reduced motion): the overlay stops
    /// redrawing, so the words screen is still again, as it was before the scan (it used to redraw an empty frame 30
    /// times a second for as long as the words were on screen).
    func idle(reduceMotion: Bool) -> Bool {
        guard settled else { return false }
        guard !reduceMotion, let plan else { return true }
        return plan.shapes.indices.allSatisfy { unnamed.contains($0) }
    }

    /// Plays an event once when its moment comes; one already well past (the app was away) is skipped silently.
    private func fire(_ id: String, due: Double, now t: Double, _ action: () -> Void) {
        guard t >= due, !fired.contains(id) else { return }
        fired.insert(id)
        if t - due < 0.25 { action() }
    }

    private func buildPlan(t: Double) {
        if plan == nil, let stage, let fill {
            if let outlines {
                plan = CatchScanPlan(outlines: outlines, stage: stage, fill: fill, ready: rel(outlinesAt) ?? t)
            } else if let names = rel(namesAt), t >= names + CatchScanSpec.outlineWait {
                // The names came and the outlines did not: never hold the tags back for the decoration.
                plan = CatchScanPlan(outlines: [], stage: stage, fill: fill, ready: t)
            }
        }
        if let plan, namesAt != nil, rankOf.isEmpty, unnamed.isEmpty {
            var named = Set<Int>()
            for o in objects {
                if let label = o.instance, let r = plan.shapes.firstIndex(where: { $0.label == label }) {
                    rankOf[o.id] = r
                    named.insert(r)
                }
            }
            unnamed = Set(plan.shapes.indices).subtracting(named)
            if unnamed.isEmpty { unnamed = [-1] }   // marks the matching as done
        }
    }

    // MARK: Drawing

    /// Draws the frame at `now` into the stage (`size`): the photo's dimming, the outlines, the light trails, the
    /// bracket, the pen and the small light. The stage may have changed size since the plan (the keyboard): the plan
    /// is moved onto the photo's new place.
    func draw(_ g: inout GraphicsContext, size: CGSize, photo: CGSize, now: Date, reduceMotion: Bool) {
        guard let started else { return }
        let t = now.timeIntervalSince(started)
        if t - drawNoted >= 0.5 || t < drawNoted {
            drawNoted = t
            UITestTrace.log("scan.draw t=\(String(format: "%.2f", t))")
        }
        let m = moments(reduceMotion: reduceMotion)
        let names = m?.names
        if !reduceMotion {
            // A little darker while the AI works, so the blue reads (scan7.js `dimOf`).
            let on = ScanEase.outCubic(min(1, max(0, t / 0.5)))
            let off = names.map { ScanEase.inOutCubic(min(1, max(0, (t - $0 - 0.25) / 0.6))) } ?? 0
            let dim = 0.2 * on * (1 - off)
            if dim > 0.003 { g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(dim))) }
        }
        guard let plan else {
            if !reduceMotion { drawBracket(&g, rect: fullRect(size), alpha: bracketAppear(t), locked: false, squash: breath(t)) }
            return
        }
        var g = g
        let fillNow = CatchScanPlan.fillRect(photo: photo, in: size)
        let moved = abs(fillNow.width - plan.fill.width) > 0.5 || abs(fillNow.minX - plan.fill.minX) > 0.5
            || abs(fillNow.minY - plan.fill.minY) > 0.5
        if plan.fill.width > 0, moved {
            let k = fillNow.width / plan.fill.width
            g.translateBy(x: fillNow.minX, y: fillNow.minY)
            g.scaleBy(x: k, y: k)
            g.translateBy(x: -plan.fill.minX, y: -plan.fill.minY)
        }
        if reduceMotion {
            drawStaticOutlines(&g, plan: plan, t: t, found: m?.found)
            return
        }
        let tl = plan.timeline
        let tau = tl.tau(t)
        drawOutlines(&g, plan: plan, t: t, tau: tau, found: m?.found)
        drawTrails(&g, plan: plan, t: t, tau: tau, names: names)
        // The bracket: on the pen's clock; it fades in real time when the last outline closes (or with the names).
        let fadeFrom = plan.shapes.isEmpty ? (m?.found ?? .infinity) : tl.real(tl.drawEnd)
        let alpha = bracketAppear(tau) * (1 - min(1, max(0, (t - fadeFrom) / CatchScanSpec.fadeOut)))
        if alpha > 0.003 {
            var r = -1
            for i in plan.shapes.indices where tau >= tl.moveStart(i) { r = i }
            let to = r < 0 ? plan.full : plan.boxes[r]
            let from = r <= 0 ? plan.full : plan.boxes[r - 1]
            let u = r < 0 ? 1 : ScanEase.bracket(min(1, max(0, (tau - tl.moveStart(r)) / CatchScanSpec.move)))
            let rect = CGRect(x: from.minX + (to.minX - from.minX) * u, y: from.minY + (to.minY - from.minY) * u,
                              width: from.width + (to.width - from.width) * u,
                              height: from.height + (to.height - from.height) * u)
            let locked = r >= 0 && tau >= tl.lock[r]
            var squash: CGFloat = plan.shapes.isEmpty ? breath(t) : 1
            if locked {
                let v = min(1, max(0, (tau - tl.lock[r]) / 0.26))
                squash = CGFloat(1 - 0.06 * (1 - abs(1 - 2 * v)))
            }
            drawBracket(&g, rect: rect, alpha: alpha, locked: locked, squash: squash)
        }
        if let pen = penAt(plan: plan, t: t, tau: tau) {
            glowDot(&g, at: pen.at, radius: CatchScanSpec.penRadius, alpha: pen.alpha * edgeFade(pen.at, plan.stage))
        }
        let pa = patrolAlpha(plan: plan, t: t, names: names)
        if pa > 0, let p = plan.patrolPoint(CGFloat(t - patrolStart(plan)) * CatchScanSpec.patrolSpeed) {
            glowDot(&g, at: p.at, radius: CatchScanSpec.smallRadius, alpha: 0.8 * pa * edgeFade(p.at, plan.stage))
        }
    }

    private func fullRect(_ size: CGSize) -> CGRect {
        CGRect(x: 22, y: size.height * 0.12, width: max(40, size.width - 44), height: size.height * 0.76)
    }

    private func bracketAppear(_ tau: Double) -> Double {
        let u = (tau - CatchScanSpec.bracketIn) / CatchScanSpec.appear
        return u <= 0 ? 0 : min(1, max(0, Double(ScanEase.bracket(min(1, u)))))
    }

    /// Waiting over the photo with nothing to draw: a slow breath, so it never looks stuck.
    private func breath(_ t: Double) -> CGFloat {
        let s = sin(.pi * max(0, t - CatchScanSpec.bracketIn) / 1.2)
        return 1 - 0.02 * CGFloat(s * s)
    }

    private func patrolStart(_ plan: CatchScanPlan) -> Double {
        plan.timeline.real(plan.timeline.drawEnd) + CatchScanSpec.patrolDelay
    }

    private func patrolAlpha(plan: CatchScanPlan, t: Double, names: Double?) -> Double {
        guard !plan.shapes.isEmpty else { return 0 }
        let p0 = patrolStart(plan)
        let names = names ?? .infinity
        guard names > p0 else { return 0 }
        return min(1, max(0, (t - p0) / CatchScanSpec.patrolIn)) * (1 - min(1, max(0, (t - names) / CatchScanSpec.patrolOut)))
    }

    /// The pen: on the outline being drawn, in the air between two things, or fading where it closed the last.
    private func penAt(plan: CatchScanPlan, t: Double, tau: Double) -> (at: CGPoint, alpha: Double, hop: (CGPoint, CGPoint, Double)?)? {
        let tl = plan.timeline
        for r in plan.shapes.indices {
            let lock = tl.lock[r], close = tl.close(r)
            if tau >= lock, tau < close { return (plan.shapes[r].head(lock: lock, tau: tau).at, 1, nil) }
            if r < plan.shapes.count - 1, tau >= close, tau < tl.lock[r + 1] {
                let a = plan.shapes[r].pts[0], b = plan.shapes[r + 1].pts[0]
                let u = ScanEase.inOutSine((tau - close) / (tl.lock[r + 1] - close))
                return (CatchScanPlan.bez2(a, CatchScanPlan.hopControl(a, b), b, u), 0.55, (a, b, u))
            }
        }
        guard let last = plan.shapes.last else { return nil }
        let end = tl.real(tl.drawEnd)
        if t >= end, t < end + CatchScanSpec.penOut { return (last.pts[0], 1 - (t - end) / CatchScanSpec.penOut, nil) }
        return nil
    }

    private func edgeFade(_ p: CGPoint, _ stage: CGSize) -> Double {
        let d = min(p.x, stage.width - p.x, p.y, stage.height - p.y)
        return Double(min(1, max(0, (d - 4 * CatchScanSpec.px) / (36 * CatchScanSpec.px))))
    }

    // MARK: Outlines (v8's look, as the pen draws them)

    private static let core = Gradient(colors: [Color(red: 0xBF / 255, green: 0xE8 / 255, blue: 1),
                                                Color(red: 0x9C / 255, green: 0xC8 / 255, blue: 1),
                                                Color(red: 0xCF / 255, green: 0xE3 / 255, blue: 1)])
    private static let glowLine = Color(red: 120 / 255, green: 190 / 255, blue: 1)

    /// The outlines' strength after the names: the words screen's slow pulse (1 ↔ 0.5 every 2 s); an outline that got
    /// no name leaves.
    private func outlineAlpha(_ r: Int, t: Double, found: Double?) -> Double {
        guard let found, t > found else { return 1 }
        let p = (t - found).truncatingRemainder(dividingBy: 2) / 2
        var a = p < 0.5 ? 1 - 0.5 * CCBezier.easeInOut(p * 2) : 0.5 + 0.5 * CCBezier.easeInOut(p * 2 - 1)
        if unnamed.contains(r) { a *= 1 - min(1, (t - found) / 0.4) }
        return a
    }

    private func drawnPath(_ sh: CatchScanShape, upTo h: Double) -> Path {
        var path = Path()
        var down = false
        let n = sh.pts.count
        let last = min(n, Int(h))
        func put(_ q: CGPoint, _ e: CGFloat) {
            if e < CatchScanSpec.edge {
                down = false
                return
            }
            if down { path.addLine(to: q) } else {
                path.move(to: q)
                down = true
            }
        }
        for i in 0...last { put(sh.pts[i % n], sh.edge[i % n]) }
        if h < Double(n) {
            let f = CGFloat(h - Double(last))
            let p = sh.pts[last % n], q = sh.pts[(last + 1) % n]
            put(CGPoint(x: p.x + (q.x - p.x) * f, y: p.y + (q.y - p.y) * f), min(sh.edge[last % n], sh.edge[(last + 1) % n]))
        }
        return path
    }

    private func strokeOutline(_ g: inout GraphicsContext, _ path: Path, box: CGRect, alpha: Double) {
        let round = StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
        // A soft blue glow under the line (two blurs, screen), then the line itself with two drop shadows.
        for (blur, a) in [(2.5, 0.65), (8.0, 0.6)] {
            var glow = g
            glow.blendMode = .screen
            glow.opacity = a * alpha
            glow.addFilter(.blur(radius: CGFloat(blur)))
            glow.stroke(path, with: .color(Self.glowLine), style: round)
        }
        var line = g
        line.opacity = alpha
        line.addFilter(.shadow(color: Color(red: 140 / 255, green: 200 / 255, blue: 1, opacity: 0.95), radius: 5))
        line.addFilter(.shadow(color: Color(red: 40 / 255, green: 120 / 255, blue: 1, opacity: 0.6), radius: 16))
        line.stroke(path, with: .linearGradient(Self.core, startPoint: box.origin, endPoint: CGPoint(x: box.maxX, y: box.maxY)),
                    style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
    }

    private func drawOutlines(_ g: inout GraphicsContext, plan: CatchScanPlan, t: Double, tau: Double, found: Double?) {
        for (r, sh) in plan.shapes.enumerated() where tau >= plan.timeline.lock[r] {
            let a = outlineAlpha(r, t: t, found: found)
            guard a > 0.005 else { continue }
            let h = sh.head(lock: plan.timeline.lock[r], tau: tau).h
            strokeOutline(&g, drawnPath(sh, upTo: h), box: sh.box, alpha: a)
        }
    }

    /// Reduced motion: no bracket, pen or lights — the named outlines simply fade in with the names.
    private func drawStaticOutlines(_ g: inout GraphicsContext, plan: CatchScanPlan, t: Double, found: Double?) {
        guard let found, t > found else { return }
        let a = 0.85 * min(1, (t - found) / 0.3)
        for (r, sh) in plan.shapes.enumerated() where !unnamed.contains(r) {
            strokeOutline(&g, drawnPath(sh, upTo: Double(sh.pts.count)), box: sh.box, alpha: a)
        }
    }

    // MARK: Light trails (the fresh line behind the pen, the hop's arc, the small light's glint)

    private func drawTrails(_ g: inout GraphicsContext, plan: CatchScanPlan, t: Double, tau: Double, names: Double?) {
        var segs: [(CGPoint, CGPoint, Double, CGFloat)] = []
        let tl = plan.timeline
        for (r, sh) in plan.shapes.enumerated() {
            let lock = tl.lock[r]
            guard tau >= lock, tau <= tl.close(r) + 0.4 else { continue }
            let n = sh.pts.count
            let h = min(n - 1, Int(sh.head(lock: lock, tau: tau).h))
            for i in max(0, h - 60)..<max(0, h) {
                let a = 0.75 * exp(-(tau - (lock + sh.duration * sh.pace[i])) / 0.14)
                segs.append((sh.pts[i], sh.pts[i + 1], a, 2.4))
            }
        }
        if let pen = penAt(plan: plan, t: t, tau: tau), let hop = pen.hop {
            let c = CatchScanPlan.hopControl(hop.0, hop.1)
            let m = Int(hop.2 * 40)
            for i in max(0, m - 14)..<m {
                let p = CatchScanPlan.bez2(hop.0, c, hop.1, Double(i) / 40), q = CatchScanPlan.bez2(hop.0, c, hop.1, Double(i + 1) / 40)
                segs.append((p, q, 0.3 * exp(-Double(m - i) / 6), 1.6))
            }
        }
        let pa = patrolAlpha(plan: plan, t: t, names: names)
        if pa > 0, let p = plan.patrolPoint(CGFloat(t - patrolStart(plan)) * CatchScanSpec.patrolSpeed) {
            let leg = plan.patrol[p.leg]
            if let s = leg.shape {
                let ring = plan.shapes[s].pts, n = ring.count
                let j = p.index + n
                func at(_ i: Int) -> CGPoint { ring[((i % n) + n) % n] }
                for i in (j - 30)..<j {
                    segs.append((at(i), at(i + 1), 0.55 * pa * exp(-Double(j - i) / 9), 2))
                }
            } else {
                let m = p.index
                for i in max(0, m - 10)..<m {
                    segs.append((leg.pts[i], leg.pts[i + 1], 0.25 * pa * exp(-Double(m - i) / 5), 1.4))
                }
            }
        }
        guard !segs.isEmpty else { return }
        for blurred in [true, false] {
            var l = g
            l.blendMode = .plusLighter
            if blurred { l.addFilter(.blur(radius: 1.8)) }
            for (p, q, a, w) in segs {
                let al = a * min(edgeFade(p, plan.stage), edgeFade(q, plan.stage))
                guard al >= 0.01 else { continue }
                var line = Path()
                line.move(to: p)
                line.addLine(to: q)
                l.stroke(line, with: .color(Color(red: 200 / 255, green: 232 / 255, blue: 1, opacity: min(1, al))),
                         style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
        }
    }

    // MARK: The bracket (v8) and the points of light

    private func drawBracket(_ g: inout GraphicsContext, rect: CGRect, alpha: Double, locked: Bool, squash: CGFloat) {
        guard alpha > 0.003 else { return }
        let s = CatchScanSpec.self
        let d: CGFloat = -s.bracketLine / 2, r = s.bracketRadius - s.bracketLine / 2, arm = s.bracketArm
        var path = Path()
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(rect.minX, rect.minY, 1, 1), (rect.maxX, rect.minY, -1, 1),
                                                               (rect.minX, rect.maxY, 1, -1), (rect.maxX, rect.maxY, -1, -1)]
        for (x, y, sx, sy) in corners {
            path.move(to: CGPoint(x: x + sx * d, y: y + sy * arm))
            path.addLine(to: CGPoint(x: x + sx * d, y: y + sy * (d + r)))
            path.addArc(tangent1End: CGPoint(x: x + sx * d, y: y + sy * d),
                        tangent2End: CGPoint(x: x + sx * (d + r), y: y + sy * d), radius: r)
            path.addLine(to: CGPoint(x: x + sx * arm, y: y + sy * d))
        }
        var b = g
        b.opacity = alpha
        let c = CGPoint(x: rect.midX, y: rect.midY)
        b.translateBy(x: c.x, y: c.y)
        b.scaleBy(x: squash, y: squash)
        b.translateBy(x: -c.x, y: -c.y)
        b.addFilter(.shadow(color: Color(red: 100 / 255, green: 224 / 255, blue: 1, opacity: 0.9), radius: 6))
        b.stroke(path, with: .color(locked ? Color(red: 0x6C / 255, green: 0xC8 / 255, blue: 1) : .white),
                 style: StrokeStyle(lineWidth: s.bracketLine, lineCap: .butt, lineJoin: .round))
    }

    private func glowDot(_ g: inout GraphicsContext, at p: CGPoint, radius r: CGFloat, alpha a: Double) {
        guard a > 0.01 else { return }
        let blue = (red: 160.0 / 255, green: 215.0 / 255, blue: 1.0)
        let shade = Gradient(stops: [
            .init(color: .white.opacity(a), location: 0),
            .init(color: Color(red: blue.red, green: blue.green, blue: blue.blue, opacity: 0.6 * a), location: 0.28),
            .init(color: Color(red: blue.red, green: blue.green, blue: blue.blue, opacity: 0), location: 1),
        ])
        var l = g
        l.blendMode = .plusLighter
        l.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
               with: .radialGradient(shade, center: p, startRadius: 0, endRadius: r))
    }
}

/// The film's easing curves.
nonisolated enum ScanEase {
    /// The bracket's slide: CSS `cubic-bezier(.3, 1.3, .5, 1)` (overshoots a little).
    static let bracketCurve = CCBezier(0.3, 1.3, 0.5, 1)
    static func bracket(_ u: Double) -> CGFloat { CGFloat(bracketCurve(u)) }
    static func outCubic(_ u: Double) -> Double { 1 - pow(1 - u, 3) }
    static func inOutCubic(_ u: Double) -> Double { u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2 }
    static func inOutSine(_ u: Double) -> Double { -(cos(.pi * min(1, max(0, u))) - 1) / 2 }
}

/// The scan over the photo: redrawn every frame while it moves, then slowly for the outlines' pulse, and not at all
/// once nothing moves (`idle`).
struct CatchScanOverlay: View {
    let scan: CatchScanSession
    let photo: CGSize
    let reduceMotion: Bool
    /// Under the choose screen's page: nothing of it shows, so nothing is drawn.
    var hidden: Bool = false

    var body: some View {
        let _ = UITestTrace.log("scan.overlay settled=\(scan.settled) paused=\(scan.idle(reduceMotion: reduceMotion))")
        TimelineView(.animation(minimumInterval: scan.settled ? 1.0 / 30 : nil,
                                paused: hidden || scan.idle(reduceMotion: reduceMotion))) { ctx in
            Canvas { g, size in
                scan.draw(&g, size: size, photo: photo, now: ctx.date, reduceMotion: reduceMotion)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
