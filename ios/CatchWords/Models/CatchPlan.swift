import CoreGraphics
import Foundation

/// Which piece of Vision's foreground mask is each thing's cut-out, and where its name tag sits — worked out on a copy
/// of the label mask (one byte per pixel, 0 = background), so CardCatchPickTests checks it without Vision or a photo.
///
/// Owner 2026-10-16 (iPad, glasses lying against a green water bottle): Vision made ONE instance of the two things
/// touching each other. The glasses' point won that instance; it was mostly bottle (outside the glasses' box) and only
/// thin frames inside it, so the old rule (`CutCoverage`: neither "mostly inside" nor "fills the box") fell back to a
/// rectangle of the photo round the glasses' box — shown on 「覚える単語を選ぶ」 and uploaded as the "cut-out". Its tag went
/// to the deepest point of the whole instance: the bottle's body. The bottle had no instance left, so its tag went to
/// its own point: the bottle too. Both tags stacked on the bottle.
///
/// Now:
/// - an instance that lies in two things' boxes is shared: each thing gets the instance's pixels inside its own box
///   (`Cut.clip`), and its tag sits deep inside that part — the glasses get the frames, the bottle the bottle;
/// - an instance that is neither the thing nor fills its box is clipped to the box the same way (never a rectangle);
/// - a thing whose box holds no mask at all gets `.noMask`: `CatchObject.build` then asks Vision again on that region
///   alone, and shows no cut-out rather than a rectangle when that finds nothing either;
/// - a thing the point-based assignment left without an instance still takes the instance most present in its box.
nonisolated enum CatchPlan {
    /// One thing as the AI placed it: its point and box, 0–1 of the photo (top-left origin), and whether the position is
    /// its own (`TagPlacement.distinct`).
    struct Thing: Equatable, Sendable {
        var point: CGPoint
        var box: CGRect?
        var own: Bool
    }

    enum Cut: Equatable, Sendable {
        /// The whole instance: it is the thing.
        case instance(Int)
        /// These instances together (a person and the thing they hold).
        case union([Int])
        /// These instances' pixels inside the rect only (0–1 of the photo: the thing's box, widened a little).
        case clip([Int], CGRect)
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
    }

    /// An instance must cover this share of a thing's box to count as being there.
    static let presence = 0.02
    /// An instance is shared when at least this share of it lies inside each of two things' boxes.
    static let sharedShare = 0.12
    /// A clip keeps this much more than the box on each side (a frame drawn just outside the AI's box is not cut off).
    static let clipMargin: CGFloat = 0.04

    static func plan(things: [Thing], mask: [UInt8], width w: Int, height h: Int) -> [Placement] {
        let hasMask = w > 0 && h > 0 && mask.count >= w * h && mask.contains { $0 != 0 }
        // Each thing with a place of its own takes its own instance, nearest pairs first (`assignInstances`).
        var labels: [Int?] = hasMask
            ? CatchObject.assignInstances(things.map { $0.own ? ranked(mask: mask, width: w, height: h, to: $0.point) : [] })
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

        var out: [Placement] = things.indices.map { i in
            let t = things[i]
            guard hasMask, let box = boxes[i], areas[i] > 0 else {
                if let l = labels[i] { return Placement(label: l, cut: .instance(l), anchor: anchors[l] ?? t.point) }
                return Placement(label: nil, cut: .noMask, anchor: t.point, note: hasMask && t.own ? "no Vision instance near its point" : nil)
            }
            let inBox = counts[i], area = areas[i]
            // There: it covers a little of the box, and either a real part of it lies in the box or it fills the box —
            // never the edge of a neighbour that merely reaches into the box (the bottle's foot in the glasses' box).
            let present = { (l: Int) -> Bool in
                let n = Double(inBox[l])
                return n >= presence * Double(area)
                    && (n / Double(max(1, totals[l])) >= sharedShare || n / Double(area) >= CutCoverage.fillsBox)
            }
            // Its own instance when that is really in its box, else the instance most present there.
            let best = (1..<256).filter(present).max { inBox[$0] != inBox[$1] ? inBox[$0] < inBox[$1] : $0 > $1 }
            guard let chosen = labels[i].flatMap({ present($0) ? $0 : nil }) ?? best else {
                return Placement(label: nil, cut: .noMask, anchor: t.point, note: "no Vision mask inside its box")
            }
            let clipRect = box.insetBy(dx: -box.width * clipMargin, dy: -box.height * clipMargin)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            // Shared: a real part of the instance lies inside another thing's box and outside this one's (two things
            // Vision saw as one). Boxes that merely overlap do not make a thing that lies whole in its own box shared.
            let mine = Double(inBox[chosen]) / Double(max(1, totals[chosen]))
            let other = things.indices.first { j in
                guard j != i, let theirs = boxes[j], !counts[j].isEmpty else { return false }
                let elsewhere = Self.countOutside(UInt8(chosen), in: theirs, notIn: box, mask: mask, width: w, height: h)
                return Double(elsewhere) / Double(max(1, totals[chosen])) >= sharedShare
            }
            if let other, mine >= sharedShare {
                return Placement(label: chosen, cut: .clip([chosen], clipRect),
                                 anchor: clippedAnchor([chosen], in: box, mask: mask, width: w, height: h) ?? t.point,
                                 note: "one Vision instance with thing \(other + 1): cut to its own box")
            }
            var inBoxMap: [Int: Int] = [:], totalMap: [Int: Int] = [:]
            for l in 1..<256 where totals[l] > 0 {
                totalMap[l] = totals[l]
                if inBox[l] > 0 { inBoxMap[l] = inBox[l] }
            }
            switch CutCoverage.decide(chosen: chosen, inBox: inBoxMap, totals: totalMap, boxArea: area) {
            case .keep:
                return Placement(label: chosen, cut: .instance(chosen), anchor: anchors[chosen] ?? t.point,
                                 note: chosen == labels[i] ? nil : "took the instance most present in its box")
            case .union(let ls):
                return Placement(label: chosen, cut: .union(ls), anchor: anchors[chosen] ?? t.point,
                                 note: "instances \(ls) together")
            case .crop:
                // Neither the thing nor filling its box (it is part of something bigger): its pixels inside the box.
                let ls = ([chosen] + (1..<256).filter { $0 != chosen && Double(inBox[$0]) / Double(area) >= CutCoverage.overlaps })
                return Placement(label: chosen, cut: .clip(ls, clipRect),
                                 anchor: clippedAnchor(ls, in: box, mask: mask, width: w, height: h) ?? t.point,
                                 note: "instance larger than its box: cut to its box")
            }
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

    // MARK: Pieces

    /// Every instance label within ~8% of `point`, nearest first, with its squared distance in mask pixels (0 = under
    /// the point) — `CutoutService.rankedInstances` on the copy of the mask.
    static func ranked(mask: [UInt8], width w: Int, height h: Int, to point: CGPoint) -> [CatchObject.InstanceHit] {
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
        return best.map { CatchObject.InstanceHit(label: $0.key, distance: $0.value) }
            .sorted { $0.distance != $1.distance ? $0.distance < $1.distance : $0.label < $1.label }
    }

    /// The box on the mask grid: columns x0..<x1, rows y0..<y1.
    private static func grid(_ box: CGRect, width w: Int, height h: Int) -> (x0: Int, x1: Int, y0: Int, y1: Int) {
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

    /// Pixels of `label` inside `a` but not inside `b`.
    static func countOutside(_ label: UInt8, in a: CGRect, notIn b: CGRect, mask: [UInt8], width w: Int, height h: Int) -> Int {
        let ga = grid(a, width: w, height: h), gb = grid(b, width: w, height: h)
        guard ga.x1 > ga.x0, ga.y1 > ga.y0 else { return 0 }
        var n = 0
        for y in ga.y0..<ga.y1 {
            let rowInB = y >= gb.y0 && y < gb.y1
            for x in ga.x0..<ga.x1 where mask[y * w + x] == label {
                if rowInB && x >= gb.x0 && x < gb.x1 { continue }
                n += 1
            }
        }
        return n
    }

    /// The tag's place deep inside the part of `labels` that lies in `box` (`CatchAnchor` on that part alone).
    static func clippedAnchor(_ labels: [Int], in box: CGRect, mask: [UInt8], width w: Int, height h: Int) -> CGPoint? {
        let g = grid(box, width: w, height: h)
        guard g.x1 > g.x0, g.y1 > g.y0 else { return nil }
        var keep = [Bool](repeating: false, count: 256)
        for l in labels where l > 0 && l < 256 { keep[l] = true }
        var part = [UInt8](repeating: 0, count: w * h)
        var any = false
        for y in g.y0..<g.y1 {
            for x in g.x0..<g.x1 where keep[Int(mask[y * w + x])] {
                part[y * w + x] = 1
                any = true
            }
        }
        guard any else { return nil }
        return CatchAnchor.anchors(mask: part, width: w, height: h)[1]
    }
}
