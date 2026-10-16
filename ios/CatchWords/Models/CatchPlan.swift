import CoreGraphics
import Foundation

/// Which piece of Vision's foreground mask is each thing's cut-out, and where its name tag sits — worked out on a copy
/// of the label mask (one byte per pixel, 0 = background), so CardCatchPickTests checks it without Vision or a photo,
/// and scripts/cutout-harness runs this very file on real photos with real Vision (docs/cutout-failure-modes.md).
///
/// The rule (owner 2026-10-16, after a dorayaki ice cream came out with a straight left side and a straight bottom —
/// cut along the AI's box, which was smaller than the thing and off to one side): **a cut-out is never cut along the
/// AI's box.** The box only says which pieces of Vision's mask are the thing; the mask's own outline is the cut-out.
/// - One thing claims an instance: the whole instance, also where it goes past the box (only its pieces that do not
///   reach the box at all are left out).
/// - One thing seen in several instances (the dorayaki's two pancakes and the ice cream between them): those that lie
///   in its box together (`CutCoverage.union`).
/// - Two things claim one instance (glasses lying against a water bottle, which Vision saw as one): it is split where
///   the two meet — each thing grows over the mask from the part only it has in its box, and growing across a change of
///   colour in the photo is dear, so the line between them runs along the photo's own edge between the two things
///   (`split`, `Cut.part`), never along a box.
/// - An instance mostly outside the thing's box that no other thing claims (the dorayaki merged with the carton behind
///   it, or a box off to one side): `refine` asks Vision once more on the region round the box, and that answer is used
///   only when it is a whole thing — not touching the region's edge — that covers the box; otherwise the whole instance
///   stays. Its tag goes on its part in the box.
/// - No mask in the thing's box at all: Vision once more on the region round the box; a thing that still runs into the
///   region's edge after the widest try is taken with that edge faded out, never cut with a hard line.
///   With nothing there either: no cut-out (never a rectangle of the photo).
nonisolated enum CatchPlan {
    /// One thing as the AI placed it: its point and box, 0–1 of the photo (top-left origin), and whether the position is
    /// its own (`TagPlacement.distinct`).
    struct Thing: Equatable, Sendable {
        var point: CGPoint
        var box: CGRect?
        var own: Bool
    }

    /// The mask pixels a thing keeps, on the plan's grid (the label mask copy, `width` × `height`, row after row).
    struct Keep: Hashable, Sendable {
        let width: Int
        let height: Int
        /// 1 = kept.
        var bits: [UInt8]

        var count: Int { bits.reduce(0) { $0 + Int($1) } }

        func contains(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < width && y < height && bits[y * width + x] != 0
        }
    }

    enum Cut: Equatable, Sendable {
        /// The whole instance: it is the thing.
        case instance(Int)
        /// These instances together (a person and the thing they hold; one thing Vision saw in pieces).
        case union([Int])
        /// These instances' pixels where `Keep` is set: one of two things Vision saw as one, or an instance without its
        /// pieces that lie away from the thing. Its edge is the mask's own, or where two things meet.
        case part([Int], Keep)
        /// No mask where the thing is.
        case noMask
    }

    struct Placement: Equatable, Sendable {
        /// The Vision instance the thing is on (the catch scan waits for its outline); nil = none.
        var label: Int?
        var cut: Cut
        /// Where its name tag sits, 0–1 of the photo.
        var anchor: CGPoint
        /// Why it was cut so, for the developer log (nil = its own instance, the usual case).
        var note: String?
        /// The instance is far larger than this box (0–1 of the photo) and no other thing claims it: Vision is asked
        /// once more on the region round the box (`InstanceMasks.render`), kept only when whole; else `cut` stays.
        var refine: CGRect? = nil
    }

    /// One Vision instance near an object's point, and how far it is (squared mask pixels; 0 = under the point).
    struct InstanceHit: Equatable, Sendable {
        let label: Int
        let distance: Int
    }

    /// An instance must cover this share of a thing's box to count as being there.
    static let presence = 0.02
    /// … and this share of the instance must lie in the box, unless it fills the box (`CutCoverage.fillsBox`): the edge
    /// of a neighbour that merely reaches into the box is not there.
    static let sharedShare = 0.12
    /// A piece of an instance "reaches" the box when it touches the box grown by this share of its size on each side.
    static let reachMargin: CGFloat = 0.03

    /// `colours`: the photo at the mask's grid, 3 bytes (RGB) a pixel, row after row (`InstanceMasks.colourGrid`); it
    /// lets a shared instance be split along the photo's own edges (nil: along the mask alone, as in the unit tests).
    static func plan(things: [Thing], mask: [UInt8], width w: Int, height h: Int, colours: [UInt8]? = nil) -> [Placement] {
        let hasMask = w > 0 && h > 0 && mask.count >= w * h && mask.contains { $0 != 0 }
        // Each thing with a place of its own takes its own instance, nearest pairs first (`assignInstances`).
        var labels: [Int?] = hasMask
            ? assignInstances(things.map { $0.own ? ranked(mask: mask, width: w, height: h, to: $0.point) : [] })
            : Array(repeating: nil, count: things.count)
        var totals = [Int](repeating: 0, count: 256)
        if hasMask { for v in mask where v != 0 { totals[Int(v)] += 1 } }
        // A thing without a place of its own takes a free instance (the largest first): its tag then sits on a real thing.
        if hasMask, things.indices.contains(where: { !things[$0].own && labels[$0] == nil }) {
            var taken = Set(labels.compactMap { $0 })
            let area = Double(w * h)
            let bySize = (1..<256).filter { Double(totals[$0]) / area >= 0.012 }
                .sorted { totals[$0] != totals[$1] ? totals[$0] > totals[$1] : $0 < $1 }
            for i in things.indices where !things[i].own && labels[i] == nil {
                guard let free = bySize.first(where: { !taken.contains($0) }) else { break }
                labels[i] = free
                taken.insert(free)
            }
        }
        let anchors = hasMask ? CatchAnchor.anchors(mask: mask, width: w, height: h) : [:]
        // Each placed thing's box on the mask grid, and how much of every instance lies inside it.
        let boxes: [CGRect?] = things.map { $0.own ? $0.box : nil }
        let counts: [[Int]] = boxes.map { b in
            guard hasMask, let b else { return [] }
            return countsInside(b, mask: mask, width: w, height: h)
        }
        let areas: [Int] = boxes.map { b in b.map { gridArea($0, width: w, height: h) } ?? 0 }

        // 1. What each boxed thing claims: its instance (or the one most present in its box), with the other pieces of
        //    the thing (`CutCoverage`); whether that instance is far larger than the box.
        struct Claim {
            var chosen: Int
            var labels: [Int]
            var larger: Bool
            var note: String?
        }
        let claims: [Claim?] = things.indices.map { i -> Claim? in
            guard hasMask, boxes[i] != nil, areas[i] > 0 else { return nil }
            let inBox = counts[i], area = areas[i]
            let present = { (l: Int) -> Bool in
                let n = Double(inBox[l])
                return n >= presence * Double(area)
                    && (n / Double(max(1, totals[l])) >= sharedShare || n / Double(area) >= CutCoverage.fillsBox)
            }
            let best = (1..<256).filter(present).max { inBox[$0] != inBox[$1] ? inBox[$0] < inBox[$1] : $0 > $1 }
            guard let chosen = labels[i].flatMap({ present($0) ? $0 : nil }) ?? best else { return nil }
            var inBoxMap: [Int: Int] = [:], totalMap: [Int: Int] = [:]
            for l in 1..<256 where totals[l] > 0 {
                totalMap[l] = totals[l]
                if inBox[l] > 0 { inBoxMap[l] = inBox[l] }
            }
            // Another thing's own instance is never taken in as a piece of this one.
            let theirs = Set(things.indices.filter { $0 != i }.compactMap { labels[$0] }).subtracting([chosen])
            let note: String? = chosen == labels[i] ? nil : "took the instance most present in its box"
            let decision = CutCoverage.decide(chosen: chosen, inBox: inBoxMap, totals: totalMap, boxArea: area, excluding: theirs)
            var ls = [chosen]
            if case .union(let together) = decision { ls = together }
            // Mostly outside the box (the thing merged with what is behind it, or a box off to one side): kept whole,
            // and Vision looks again at the region (`refine`).
            let share = Double(ls.reduce(0) { $0 + inBox[$1] }) / Double(max(1, ls.reduce(0) { $0 + totals[$1] }))
            let larger = decision == .larger || share < CutCoverage.mostlyInside
            let notes: [String?] = [note, ls.count > 1 ? "instances \(ls) together" : nil,
                         larger ? "instance mostly outside its box: kept whole, Vision asked again on the region" : nil]
            let joined = notes.compactMap { $0 }.joined(separator: "; ")
            return Claim(chosen: chosen, labels: ls, larger: larger, note: joined.isEmpty ? nil : joined)
        }
        // 2. Who claims each instance.
        var claimants = [[Int]](repeating: [], count: 256)
        for (i, c) in claims.enumerated() {
            for l in c?.labels ?? [] { claimants[l].append(i) }
        }

        // 3. Each thing's cut.
        var out: [Placement] = things.indices.map { i in
            let t = things[i]
            guard hasMask, let box = boxes[i], areas[i] > 0 else {
                if let l = labels[i] { return Placement(label: l, cut: .instance(l), anchor: anchors[l] ?? t.point) }
                return Placement(label: nil, cut: .noMask, anchor: t.point, note: hasMask && t.own ? "no Vision instance near its point" : nil)
            }
            guard let c = claims[i] else {
                return Placement(label: nil, cut: .noMask, anchor: t.point, note: "no Vision mask inside its box")
            }
            let rivals = Set(c.labels.flatMap { claimants[$0] }).subtracting([i]).sorted()
            if rivals.isEmpty {
                // Its own: whole, past the box too — only pieces that do not reach the box at all are left out.
                let keep = reaching(c.labels, box: box, mask: mask, width: w, height: h)
                let all = c.labels.reduce(0) { $0 + totals[$1] }
                // The tag of an instance far larger than the box goes on its part in the box (the dorayaki, not the
                // carton it merged with).
                let inBoxAnchor = c.larger ? anchorInside(keep, box: box, width: w, height: h) : nil
                if keep.count >= all {
                    let cut: Cut = c.labels.count == 1 ? .instance(c.chosen) : .union(c.labels)
                    return Placement(label: c.chosen, cut: cut, anchor: inBoxAnchor ?? anchors[c.chosen] ?? t.point,
                                     note: c.note, refine: c.larger ? box : nil)
                }
                let anchor = inBoxAnchor ?? CatchAnchor.anchors(mask: keep.bits, width: w, height: h)[1] ?? anchors[c.chosen] ?? t.point
                return Placement(label: c.chosen, cut: .part(c.labels, keep), anchor: anchor,
                                 note: [c.note, "pieces of the instance away from its box left out"].compactMap { $0 }.joined(separator: "; "),
                                 refine: c.larger ? box : nil)
            }
            // Shared with other things: split where they meet (`split`), then only the pieces that reach its box.
            let side = split(owner: i, labels: c.labels, claimants: claimants, boxes: boxes, mask: mask, width: w, height: h,
                             colours: colours)
            let keep = reaching(side, box: box, width: w, height: h)
            guard keep.count > 0 else {
                return Placement(label: nil, cut: .noMask, anchor: t.point, note: "its share of a shared instance was empty")
            }
            let anchor = CatchAnchor.anchors(mask: keep.bits, width: w, height: h)[1] ?? t.point
            return Placement(label: c.chosen, cut: .part(c.labels, keep), anchor: anchor,
                             note: "one Vision instance with thing \(rivals.map { String($0 + 1) }.joined(separator: ", ")): split where they meet")
        }

        // Things still without a place of their own: a spot of their own, clear of the placed ones.
        let spare = things.indices.filter { !things[$0].own && out[$0].label == nil }
        let placed = things.indices.filter { !spare.contains($0) }.map { out[$0].anchor }
        for (k, spot) in TagPlacement.spreadSpots(count: spare.count, avoiding: placed).enumerated() {
            out[spare[k]].anchor = spot
        }
        // Two tags never on one spot: a later one moves to the middle of its own box when that is elsewhere.
        for j in out.indices {
            for i in 0..<j where hypot(out[i].anchor.x - out[j].anchor.x, out[i].anchor.y - out[j].anchor.y) < 0.05 {
                guard let b = boxes[j] else { continue }
                let centre = CGPoint(x: b.midX, y: b.midY)
                if hypot(centre.x - out[i].anchor.x, centre.y - out[i].anchor.y) >= 0.05 {
                    out[j].anchor = centre
                    out[j].note = (out[j].note.map { $0 + "; " } ?? "") + "tag moved off thing \(i + 1)'s tag"
                }
            }
        }
        return out
    }

    // MARK: Splitting one instance between things

    /// `owner`'s side of the instances in `labels` that other things claim too (two things Vision saw as one).
    ///
    /// Seeds: a pixel of such an instance in exactly one claimant's box, and clear of the others' boxes by
    /// `seedMargin`, is that claimant's. A pixel in several boxes is the smallest box's when that box lies
    /// (`nestedShare`) inside the others and the pixel is in its middle part (a cup's box inside its saucer's: the cup's
    /// body is the cup's); otherwise nobody's yet. A claimant left without any seed (a spoon whose box lies all inside
    /// the cup's and saucer's) gets nothing here, and Vision is asked again on its region alone (`.noMask`).
    /// Growth: from the seeds, every claimant spreads over the instance at once, cheapest path first (Dijkstra, 8
    /// neighbours), and a pixel belongs to the first to reach it. A step costs its length, many times more where the photo
    /// changes colour (`colours`: the edge between a black temple and an orange bottle, a black helmet and an orange
    /// suit), so the line between two things runs along the photo's own edge between them — never along a box.
    /// Pixels no growth reaches go to the claimant whose box is nearest (inside two boxes, the one it lies deeper in).
    /// A label only `owner` claims is all `owner`'s.
    static func split(owner: Int, labels: [Int], claimants: [[Int]], boxes: [CGRect?], mask: [UInt8],
                      width w: Int, height h: Int, colours: [UInt8]? = nil) -> Keep {
        var mine = [Bool](repeating: false, count: 256)
        for l in labels where l > 0 && l < 256 { mine[l] = true }
        var result = [UInt8](repeating: 0, count: w * h)
        var holder = [Int](repeating: -1, count: w * h)
        var cost = [Float](repeating: .greatestFiniteMagnitude, count: w * h)
        var heap = MinHeap()
        let grids: [(x0: Int, x1: Int, y0: Int, y1: Int)?] = boxes.map { $0.map { grid($0, width: w, height: h) } }
        func inside(_ j: Int, _ x: Int, _ y: Int) -> Bool {
            guard let g = grids[j] else { return false }
            return x >= g.x0 && x < g.x1 && y >= g.y0 && y < g.y1
        }
        let area: [CGFloat] = boxes.map { b in b.map { $0.width * $0.height } ?? .greatestFiniteMagnitude }
        func nested(_ j: Int, in k: Int) -> Bool {
            guard let a = boxes[j], let b = boxes[k], a.width > 0, a.height > 0 else { return false }
            let o = a.intersection(b)
            return !o.isNull && o.width * o.height >= Self.nestedShare * a.width * a.height
        }
        /// Clear of claimant `k`'s box by `seedMargin` of its size (a pixel just at another thing's box edge is not
        /// sure: the AI's box is rough, and a seed there would put a straight line along that edge).
        func clear(of k: Int, _ px: CGFloat, _ py: CGFloat) -> Bool {
            guard let b = boxes[k] else { return true }
            let m = Self.seedMargin * max(b.width, b.height)
            return !(px >= b.minX - m && px <= b.maxX + m && py >= b.minY - m && py <= b.maxY + m)
        }
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let l = Int(mask[i])
                guard l != 0, mine[l] else { continue }
                let who = claimants[l]
                if who.count <= 1 {
                    result[i] = 1
                    continue
                }
                let within = who.filter { inside($0, x, y) }
                let px = (CGFloat(x) + 0.5) / CGFloat(w), py = (CGFloat(y) + 0.5) / CGFloat(h)
                var seed: Int?
                if within.count == 1 {
                    if who.allSatisfy({ $0 == within[0] || clear(of: $0, px, py) }) { seed = within[0] }
                } else if within.count > 1, let small = within.min(by: { area[$0] < area[$1] }),
                          within.allSatisfy({ $0 == small || nested(small, in: $0) }), let b = boxes[small] {
                    let depth = max(abs(px - b.midX) / (b.width / 2), abs(py - b.midY) / (b.height / 2))
                    if depth <= 0.6 { seed = small }
                }
                if let seed {
                    holder[i] = seed
                    cost[i] = 0
                    heap.push(0, Int32(i))
                }
            }
        }
        let steps: [(Int, Int, Float)] = [(-1, -1, 1.4142), (0, -1, 1), (1, -1, 1.4142), (-1, 0, 1), (1, 0, 1),
                                          (-1, 1, 1.4142), (0, 1, 1), (1, 1, 1.4142)]
        let hasColour = (colours?.count ?? 0) >= w * h * 3
        while let top = heap.pop() {
            let (c, idx) = top
            let i = Int(idx)
            guard c <= cost[i] else { continue }
            let x = i % w, y = i / w
            for (dx, dy, len) in steps {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let n = ny * w + nx
                let l = Int(mask[n])
                guard l != 0, mine[l], claimants[l].count > 1, claimants[l].contains(holder[i]) else { continue }
                var step = len
                if hasColour, let px = colours {
                    let a = i * 3, b = n * 3
                    let d = max(abs(Int(px[a]) - Int(px[b])), abs(Int(px[a + 1]) - Int(px[b + 1])), abs(Int(px[a + 2]) - Int(px[b + 2])))
                    step *= 1 + Self.edgeCost * Float(d) / 255
                }
                let next = c + step
                if next < cost[n] {
                    cost[n] = next
                    holder[n] = holder[i]
                    heap.push(next, Int32(n))
                }
            }
        }
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let l = Int(mask[i])
                guard l != 0, mine[l], claimants[l].count > 1 else { continue }
                let who = holder[i] >= 0 ? holder[i] : nearest(of: claimants[l], x: x, y: y, boxes: boxes, width: w, height: h)
                if who == owner { result[i] = 1 }
            }
        }
        return Keep(width: w, height: h, bits: result)
    }

    /// How many times dearer a step across the strongest colour change is than one across none (`split`).
    static let edgeCost: Float = 30
    /// A box this much (or more) inside another's is "in front of" it (a cup's box in its saucer's): its middle is a seed.
    static let nestedShare: CGFloat = 0.75
    /// A seed keeps this share of another claimant's box size away from that box.
    static let seedMargin: CGFloat = 0.06

    /// A small binary min-heap of (cost, pixel) for `split`.
    struct MinHeap {
        private var items: [(Float, Int32)] = []

        mutating func push(_ cost: Float, _ index: Int32) {
            items.append((cost, index))
            var i = items.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                guard items[i].0 < items[parent].0 else { break }
                items.swapAt(i, parent)
                i = parent
            }
        }

        mutating func pop() -> (Float, Int32)? {
            guard let first = items.first else { return nil }
            let last = items.removeLast()
            if !items.isEmpty {
                items[0] = last
                var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1
                    var m = i
                    if l < items.count && items[l].0 < items[m].0 { m = l }
                    if r < items.count && items[r].0 < items[m].0 { m = r }
                    if m == i { break }
                    items.swapAt(i, m)
                    i = m
                }
            }
            return first
        }
    }

    /// Of `candidates`, the one whose box is nearest the pixel (grid units, 0 inside); inside several boxes, the one it
    /// lies deepest in (distance from the box's middle as a share of its half size).
    private static func nearest(of candidates: [Int], x: Int, y: Int, boxes: [CGRect?], width w: Int, height h: Int) -> Int {
        let px = (CGFloat(x) + 0.5) / CGFloat(w), py = (CGFloat(y) + 0.5) / CGFloat(h)
        func score(_ j: Int) -> (CGFloat, CGFloat) {
            guard let b = boxes[j], b.width > 0, b.height > 0 else { return (.greatestFiniteMagnitude, .greatestFiniteMagnitude) }
            let dx = max(0, b.minX - px, px - b.maxX) * CGFloat(w), dy = max(0, b.minY - py, py - b.maxY) * CGFloat(h)
            let depth = max(abs(px - b.midX) / (b.width / 2), abs(py - b.midY) / (b.height / 2))
            return ((dx * dx + dy * dy).squareRoot(), depth)
        }
        return candidates.min { a, b in
            let sa = score(a), sb = score(b)
            if abs(sa.0 - sb.0) >= 0.5 { return sa.0 < sb.0 }
            if sa.1 != sb.1 { return sa.1 < sb.1 }
            return a < b
        } ?? candidates[0]
    }

    /// The tag's place deep inside the part of `keep` that lies in `box` (`CatchAnchor` on that part alone).
    static func anchorInside(_ keep: Keep, box: CGRect, width w: Int, height h: Int) -> CGPoint? {
        let g = grid(box, width: w, height: h)
        guard g.x1 > g.x0, g.y1 > g.y0 else { return nil }
        var part = [UInt8](repeating: 0, count: w * h)
        var any = false
        for y in g.y0..<g.y1 {
            for x in g.x0..<g.x1 where keep.bits[y * w + x] != 0 {
                part[y * w + x] = 1
                any = true
            }
        }
        return any ? CatchAnchor.anchors(mask: part, width: w, height: h)[1] : nil
    }

    // MARK: Pieces that reach the box

    /// The pixels of `labels` in the 8-connected pieces that reach `box` (grown by `reachMargin`).
    static func reaching(_ labels: [Int], box: CGRect, mask: [UInt8], width w: Int, height h: Int) -> Keep {
        var on = [Bool](repeating: false, count: 256)
        for l in labels where l > 0 && l < 256 { on[l] = true }
        var bits = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) where on[Int(mask[i])] { bits[i] = 1 }
        return reaching(Keep(width: w, height: h, bits: bits), box: box, width: w, height: h)
    }

    /// The pieces of `keep` (8-connected) that reach `box` grown by `reachMargin` of its size on each side.
    static func reaching(_ keep: Keep, box: CGRect, width w: Int, height h: Int) -> Keep {
        let grown = box.insetBy(dx: -max(box.width * reachMargin, 1 / CGFloat(w)), dy: -max(box.height * reachMargin, 1 / CGFloat(h)))
        let g = grid(grown, width: w, height: h)
        var piece = [Int32](repeating: 0, count: w * h)
        var touches: [Bool] = [false]
        var stack: [Int] = []
        var id: Int32 = 0
        for start in 0..<(w * h) where keep.bits[start] != 0 && piece[start] == 0 {
            id += 1
            piece[start] = id
            stack.append(start)
            var reaches = false
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                if x >= g.x0 && x < g.x1 && y >= g.y0 && y < g.y1 { reaches = true }
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        let n = ny * w + nx
                        if keep.bits[n] != 0 && piece[n] == 0 {
                            piece[n] = id
                            stack.append(n)
                        }
                    }
                }
            }
            touches.append(reaches)
        }
        var bits = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) where piece[i] != 0 && touches[Int(piece[i])] { bits[i] = 1 }
        return Keep(width: w, height: h, bits: bits)
    }

    // MARK: Pieces

    /// `ranked[i]`: the instances near object i, nearest first. Returns each object's instance, never the same
    /// one twice: the closest (object, instance) pairs are taken first (an object whose point lies ON an
    /// instance wins it over one that is merely near it; ties go to the earlier object, the server's order).
    /// nil = no free instance near that object.
    static func assignInstances(_ ranked: [[InstanceHit]]) -> [Int?] {
        var pairs: [(object: Int, hit: InstanceHit)] = []
        for (i, hits) in ranked.enumerated() {
            for h in hits { pairs.append((i, h)) }
        }
        pairs.sort { a, b in
            if a.hit.distance != b.hit.distance { return a.hit.distance < b.hit.distance }
            return a.object < b.object
        }
        var out = [Int?](repeating: nil, count: ranked.count)
        var taken = Set<Int>()
        for p in pairs where out[p.object] == nil && !taken.contains(p.hit.label) {
            out[p.object] = p.hit.label
            taken.insert(p.hit.label)
        }
        return out
    }

    /// Every instance label within ~8% of `point`, nearest first, with its squared distance in mask pixels (0 = under
    /// the point) — `MaskPixels.rankedInstances` on the copy of the mask.
    static func ranked(mask: [UInt8], width w: Int, height h: Int, to point: CGPoint) -> [InstanceHit] {
        guard w > 0, h > 0, mask.count >= w * h else { return [] }
        let x = min(w - 1, max(0, Int(point.x * CGFloat(w))))
        let y = min(h - 1, max(0, Int(point.y * CGFloat(h))))
        var best: [Int: Int] = [:]
        let under = Int(mask[y * w + x])
        if under != 0 { best[under] = 0 }
        let reach = max(4, Int(Double(max(w, h)) * 0.08))
        let step = max(1, reach / 16)
        for py in stride(from: max(0, y - reach), through: min(h - 1, y + reach), by: step) {
            for px in stride(from: max(0, x - reach), through: min(w - 1, x + reach), by: step) {
                let l = Int(mask[py * w + px])
                guard l != 0 else { continue }
                let d = (px - x) * (px - x) + (py - y) * (py - y)
                if d < best[l, default: Int.max] { best[l] = d }
            }
        }
        return best.map { InstanceHit(label: $0.key, distance: $0.value) }
            .sorted { $0.distance != $1.distance ? $0.distance < $1.distance : $0.label < $1.label }
    }

    /// The box on the mask grid: columns x0..<x1, rows y0..<y1.
    static func grid(_ box: CGRect, width w: Int, height h: Int) -> (x0: Int, x1: Int, y0: Int, y1: Int) {
        let x0 = max(0, min(w, Int((box.minX * CGFloat(w)).rounded(.down))))
        let x1 = max(0, min(w, Int((box.maxX * CGFloat(w)).rounded(.up))))
        let y0 = max(0, min(h, Int((box.minY * CGFloat(h)).rounded(.down))))
        let y1 = max(0, min(h, Int((box.maxY * CGFloat(h)).rounded(.up))))
        return (x0, x1, y0, y1)
    }

    static func gridArea(_ box: CGRect, width w: Int, height h: Int) -> Int {
        let g = grid(box, width: w, height: h)
        return max(0, g.x1 - g.x0) * max(0, g.y1 - g.y0)
    }

    /// Pixels of each label (index = label) inside the box.
    static func countsInside(_ box: CGRect, mask: [UInt8], width w: Int, height h: Int) -> [Int] {
        var c = [Int](repeating: 0, count: 256)
        let g = grid(box, width: w, height: h)
        guard g.x1 > g.x0, g.y1 > g.y0 else { return c }
        for y in g.y0..<g.y1 {
            for x in g.x0..<g.x1 {
                let v = mask[y * w + x]
                if v != 0 { c[Int(v)] += 1 }
            }
        }
        return c
    }
}
