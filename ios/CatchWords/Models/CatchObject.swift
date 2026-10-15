import UIKit

/// Card catch: one object in the photo = the candidates that share `group` (the server's per-object
/// grouping; a candidate without a group is an object of its own), up to 3 words in the server's order.
/// Its tap point is the first word's `point`; its cut-out, box and tag place come from Vision's foreground
/// instance under that point (one mask request per photo, `InstanceMasks`).
nonisolated struct CatchObject: Identifiable, @unchecked Sendable {
    let id: Int
    let words: [Candidate]
    /// 0–1 of the photo, top-left origin: the AI's point for the thing (the server's `point`, [x, y] in 0–1000 — the
    /// middle of the box the AI drew round it on the 768 px upload, web `suggestion-position.ts`). It only finds the
    /// thing's Vision instance; the tag goes to `anchor`.
    let point: CGPoint
    /// 0–1 of the photo: the cut-out's alpha bounding box, or `fallbackBox` when Vision found no instance.
    let box: CGRect
    /// 0–1 of the photo, top-left origin: where the thing's name tag sits — deep inside its Vision instance's mask
    /// (`CatchAnchor`), so the tag is on the very thing its outline goes round and its cut-out shows; the AI's
    /// `point` when Vision found no instance for it.
    var anchor: CGPoint
    /// The subject on transparency, cropped exactly to `box`; nil = the prototype's "no cutImg" path.
    let cut: UIImage?
    /// Vision's instance under this object (nil = none, `fallbackBox`). The catch scan waits for that instance's
    /// outline (`CatchOutline.label`) before this object's tag comes up.
    var instance: Int? = nil
    /// The AI said where this thing is (a `point` / `box_2d` of its own). False: it sent none, or the very same place
    /// as an earlier thing — the tag was then put on a free Vision instance or on a spot of its own, never the middle
    /// (owner 2026-10-15: 「正確にもののうえに名前のタグを置いて。適当に真ん中ではなく。」), and the developer log says so.
    var positioned: Bool = true

    /// The prototype asks the AI for at most 4 objects (`askAI` → `.slice(0,4)`), 3 words each.
    static let maxObjects = 4
    static let maxWords = 3

    /// Candidates grouped per object, in order of first appearance.
    static func groups(_ items: [Candidate]) -> [[Candidate]] {
        var order: [String] = []
        var buckets: [String: [Candidate]] = [:]
        for (i, c) in items.enumerated() {
            let key = c.group.map { "g\($0)" } ?? "solo\(i)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(c)
        }
        return order.prefix(maxObjects).compactMap { key -> [Candidate]? in
            guard let list = buckets[key], !list.isEmpty else { return nil }
            return Array(list.prefix(maxWords))
        }
    }

    /// Heavy (renders masks): call off the main thread.
    /// Each object gets its OWN Vision instance (`assignInstances`): two objects whose points fall nearest the
    /// same instance used to get the same cut-out and box, so their outlines, hitboxes and tags sat on top of
    /// each other and only the top one could be tapped. The one left without an instance gets the box
    /// around its own point.
    /// Its tag sits inside that same instance (`InstanceMasks.anchors`). Owner 2026-10-11: 「カメラ撮ったあとの単語の
    /// 名前のタグが、その該当のもののうえに配置されてない。しっかりもののうえに名前タグをおいて。」 — the tags sat on the
    /// AI's point, the middle of the AI's own rough box, which often lies beside the thing, between its parts or on
    /// what stands in front of it, while the outline drawn round the thing (the same instance) was right.
    static func build(candidates: [Candidate], masks: InstanceMasks?, photoSize: CGSize) -> [CatchObject] {
        let list = groups(candidates)
        let points = list.map { words -> CGPoint in
            let raw = words[0].point
            return CGPoint(x: min(1, max(0, (raw.first ?? 500) / 1000)),
                           y: min(1, max(0, (raw.count > 1 ? raw[1] : 500) / 1000)))
        }
        // Which things the AI placed: a point or box on one of its names, and not the very place of an earlier thing
        // (owner 2026-10-15: four tags in one pile in the middle of the tablet — the answer carried no position, so
        // every thing was taken as "the middle", and the three without a Vision instance there stacked up).
        let given = list.map { words in words.contains { $0.positioned } }
        let own = TagPlacement.distinct(list.indices.map { given[$0] ? points[$0] : nil })
        var labels: [Int?]
        if let masks {
            labels = assignInstances(list.indices.map { own[$0] ? masks.instances(near: points[$0]) : [] })
            // A thing without a place of its own takes a Vision instance nobody has (the largest first): its tag then
            // sits on a real thing in the photo, inside its outline, and its sticker is that thing's cut-out.
            var taken = Set(labels.compactMap { $0 })
            let bySize = list.indices.contains(where: { !own[$0] && labels[$0] == nil }) ? masks.instancesBySize() : []
            for i in list.indices where !own[i] && labels[i] == nil {
                guard let free = bySize.first(where: { !taken.contains($0) }) else { break }
                labels[i] = free
                taken.insert(free)
            }
        } else {
            labels = Array(repeating: nil, count: points.count)
        }
        let inside = masks?.anchors() ?? [:]
        // Still nowhere (no position and no free instance): a spot of its own, spread clear of the placed things.
        let placed: [CGPoint] = list.indices.compactMap { i in
            own[i] ? points[i] : labels[i].flatMap { inside[$0] }
        }
        let spare = list.indices.filter { !own[$0] && labels[$0] == nil }
        let spots = TagPlacement.spreadSpots(count: spare.count, avoiding: placed)
        var spotAt: [Int: CGPoint] = [:]
        for (k, i) in spare.enumerated() { spotAt[i] = spots[k] }
        return list.enumerated().map { (i, words) -> CatchObject in
            let p = spotAt[i] ?? points[i]
            let deep = labels[i].flatMap { inside[$0] }
            // A thing placed by the AI is cut out so that its box is covered; one put on a free instance has no box
            // of its own to check against (a duplicate box belongs to another thing).
            if let masks, let label = labels[i],
               let cut = cutContainingObject(masks: masks, label: label, box: own[i] ? words[0].objectBox : nil) {
                let anchor = deep ?? CGPoint(x: cut.box.midX, y: cut.box.midY)
                return CatchObject(id: i, words: words, point: own[i] ? p : anchor, box: cut.box,
                                   anchor: anchor, cut: cut.image, instance: label, positioned: own[i])
            }
            return CatchObject(id: i, words: words, point: own[i] ? p : (deep ?? p), box: fallbackBox(at: deep ?? p, photoSize: photoSize),
                               anchor: deep ?? p, cut: nil, instance: labels[i], positioned: own[i])
        }
    }

    /// One line for the developer log when things were placed without a position from the server (nil: every thing
    /// had its own place). Says which names, and where their tags went instead.
    static func placementNote(_ objects: [CatchObject]) -> String? {
        let unplaced = objects.filter { !$0.positioned }
        guard !unplaced.isEmpty else { return nil }
        let names = unplaced.map { $0.words.first?.headword ?? "?" }.joined(separator: ", ")
        let onInstances = unplaced.filter { $0.instance != nil }.count
        return "no position from the server for \(unplaced.count) of \(objects.count) things (\(names)): "
            + "\(onInstances) put on free Vision instances, \(unplaced.count - onInstances) spread over the photo"
    }

    /// The cut-out for an object whose point found Vision instance `label`, made sure to contain the thing the AI
    /// boxed (`CutCoverage`; owner 2026-10-15: 冰火菠蘿油 held up in a selfie came out as the person alone — the bun was
    /// not an instance of its own, so the person under the AI's point was cut out). Without the AI's box, the instance
    /// as before.
    static func cutContainingObject(masks: InstanceMasks, label: Int, box: CGRect?) -> InstanceMasks.Cut? {
        guard let box else { return masks.cut(instance: label) }
        let c = masks.coverage(of: box)
        switch CutCoverage.decide(chosen: label, inBox: c.inBox, totals: c.totals, boxArea: c.area) {
        case .keep:
            return masks.cut(instance: label)
        case .union(let labels):
            return masks.cut(instances: IndexSet(labels)) ?? masks.crop(box)
        case .crop:
            return masks.crop(box) ?? masks.cut(instance: label)
        }
    }

    /// One Vision instance near an object's point, and how far it is (squared mask pixels; 0 = under the point).
    nonisolated struct InstanceHit: Equatable, Sendable {
        let label: Int
        let distance: Int
    }

    /// `ranked[i]`: the instances near object i, nearest first. Returns each object's instance, never the same
    /// one twice: the closest (object, instance) pairs are taken first (an object whose point lies ON an
    /// instance wins it over one that is merely near it; ties go to the earlier object, the server's order).
    /// nil = no free instance near that object (it gets `fallbackBox`).
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

    /// No Vision instance under the point: a square box around it, 36% of the photo's shorter side,
    /// kept inside the photo (outlined as the prototype's rounded rect, `outlineEl` without cutImg).
    static func fallbackBox(at p: CGPoint, photoSize s: CGSize) -> CGRect {
        let side = 0.36 * min(s.width, s.height)
        let w = min(1, side / max(s.width, 1)), h = min(1, side / max(s.height, 1))
        let x = min(max(0, p.x - w / 2), 1 - w), y = min(max(0, p.y - h / 2), 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// Whether an object's Vision instance really is the thing the AI named (owner 2026-10-15: a pineapple bun held up in a
/// selfie was cut out as the person alone — Vision had no instance for the bun, and the person under the AI's point
/// was taken). Pure: counts of the label mask in, a decision out (CardCatchPickTests / MaskCoverageTests).
/// - keep: the instance lies mostly inside the AI's box (it is the thing), or fills most of the box (the thing is part
///   of it — a person and the bun they hold as one instance).
/// - union: it does neither, but with the other instances that overlap the box it fills the box: those instances and it
///   together (the person with the thing they hold).
/// - crop: nothing Vision found covers the thing: the photo round the AI's box, so the sticker always shows it.
nonisolated enum CutCoverage {
    enum Decision: Equatable, Sendable {
        case keep
        case union([Int])
        case crop
    }

    /// Share of the instance inside the box above which it is the thing itself.
    static let mostlyInside = 0.5
    /// Share of the box an instance (or the instances together) must fill to show the thing.
    static let fillsBox = 0.6
    /// Share of the box another instance must cover to be taken in.
    static let overlaps = 0.15

    /// `inBox`: each label's pixels inside the box; `totals`: each label's pixels in the whole mask; `boxArea`: the
    /// box's pixels (same grid).
    static func decide(chosen: Int, inBox: [Int: Int], totals: [Int: Int], boxArea: Int) -> Decision {
        guard boxArea > 0, let total = totals[chosen], total > 0 else { return .keep }
        let mine = inBox[chosen] ?? 0
        let inside = Double(mine) / Double(total)
        let fills = Double(mine) / Double(boxArea)
        if inside >= mostlyInside || fills >= fillsBox { return .keep }
        let others = inBox.filter { $0.key != chosen && $0.key != 0 && Double($0.value) / Double(boxArea) >= overlaps }
            .map(\.key).sorted()
        let together = others.reduce(mine) { $0 + (inBox[$1] ?? 0) }
        if !others.isEmpty, Double(together) / Double(boxArea) >= fillsBox { return .union(([chosen] + others).sorted()) }
        return .crop
    }
}

/// Where a thing's name tag sits on its Vision instance (`CatchObject.anchor`; owner 2026-10-11
/// 「しっかりもののうえに名前タグをおいて」): a pixel deep inside the instance's mask, as near the middle of the thing
/// as its shape allows. A cup's tag sits on its body, not between the body and the handle; a plate half hidden behind
/// a mango gets its tag on the plate, not on the mango; a thing cut by the photo's edge gets its tag inside the
/// picture (the photo's edge counts as an edge, so the tag stays clear of the parts the screen crops).
/// Pure (no Vision): a label mask in, points out, so CardCatchPickTests checks it on made-up masks.
nonisolated enum CatchAnchor {
    /// "Deep inside": at least this share of the deepest pixel's distance from the edge.
    static let depth = 0.6

    /// Every instance's tag point in a label mask (one byte per pixel, row after row, `width` bytes each,
    /// 0 = background), by label: the centre of one of its pixels, 0–1 of the mask, top-left origin.
    static func anchors(mask: [UInt8], width w: Int, height h: Int) -> [Int: CGPoint] {
        guard w > 0, h > 0, mask.count >= w * h else { return [:] }
        // Each label's bounding box (one pass over the mask), so each label is measured only where it is.
        var minX = [Int](repeating: w, count: 256), minY = [Int](repeating: h, count: 256)
        var maxX = [Int](repeating: -1, count: 256), maxY = [Int](repeating: -1, count: 256)
        for y in 0..<h {
            for x in 0..<w {
                let l = Int(mask[y * w + x])
                guard l != 0 else { continue }
                if x < minX[l] { minX[l] = x }
                if x > maxX[l] { maxX[l] = x }
                if y < minY[l] { minY[l] = y }
                if y > maxY[l] { maxY[l] = y }
            }
        }
        var out: [Int: CGPoint] = [:]
        for l in 1..<256 where maxX[l] >= 0 {
            out[l] = anchor(mask: mask, width: w, height: h, label: UInt8(l),
                            x0: minX[l], y0: minY[l], x1: maxX[l], y1: maxY[l])
        }
        return out
    }

    /// `label`'s tag point, measured inside its bounding box `x0...x1` × `y0...y1` (mask pixels) on its largest
    /// 8-connected piece — the piece the scan outlines (`CatchOutlineTracer.boundary`), so a thing split in two by
    /// something in front of it gets its tag inside its outline: of that piece's pixels at least `depth` × the
    /// deepest one's distance from the edge, the one nearest the piece's centroid. Deep alone is not enough (a long
    /// thing is equally deep all along its middle) and the centroid alone can lie outside the thing (a C shape, a
    /// ring, a plate with a mango in front of it).
    private static func anchor(mask: [UInt8], width w: Int, height h: Int, label: UInt8,
                               x0: Int, y0: Int, x1: Int, y1: Int) -> CGPoint? {
        // The grid: the box with a 1-pixel frame round it that is never the label (nothing outside the box is the
        // label, and outside the photo counts as an edge too). The label's pixels start "far" from any edge.
        let gw = x1 - x0 + 3, gh = y1 - y0 + 3
        var d = [Int32](repeating: 0, count: gw * gh)
        let far = Int32.max / 4
        for y in y0...y1 {
            for x in x0...x1 where mask[y * w + x] == label {
                d[(y - y0 + 1) * gw + (x - x0 + 1)] = far
            }
        }
        // Its pieces (8-connected, found in reading order like the tracer's); the first largest is kept. A pixel of
        // the label is never on the frame, so its 8 neighbours are always inside the grid.
        let around = [-gw - 1, -gw, -gw + 1, -1, 1, gw - 1, gw, gw + 1]
        var piece = [Int32](repeating: 0, count: gw * gh)
        var stack: [Int] = []
        var id: Int32 = 0, kept: Int32 = 0
        var keptSize = 0
        for start in d.indices where d[start] != 0 && piece[start] == 0 {
            id += 1
            piece[start] = id
            stack.append(start)
            var size = 0
            while let j = stack.popLast() {
                size += 1
                for o in around where d[j + o] != 0 && piece[j + o] == 0 {
                    piece[j + o] = id
                    stack.append(j + o)
                }
            }
            if size > keptSize {
                keptSize = size
                kept = id
            }
        }
        guard keptSize > 0 else { return nil }
        // Chamfer distance (3 a step, 4 a diagonal step) of each of the label's pixels from the nearest pixel that is
        // not the label: forward, then backward.
        for y in 1..<(gh - 1) {
            for x in 1..<(gw - 1) {
                let i = y * gw + x
                guard d[i] != 0 else { continue }
                let a = d[i - 1] + 3, b = d[i - gw] + 3, c = d[i - gw - 1] + 4, e = d[i - gw + 1] + 4
                d[i] = min(d[i], min(min(a, b), min(c, e)))
            }
        }
        for y in stride(from: gh - 2, through: 1, by: -1) {
            for x in stride(from: gw - 2, through: 1, by: -1) {
                let i = y * gw + x
                guard d[i] != 0 else { continue }
                let a = d[i + 1] + 3, b = d[i + gw] + 3, c = d[i + gw + 1] + 4, e = d[i + gw - 1] + 4
                d[i] = min(d[i], min(min(a, b), min(c, e)))
            }
        }
        // Deep enough, then as central as the piece allows (grid coordinates throughout).
        var deepest: Int32 = 0
        var sumX = 0.0, sumY = 0.0
        for i in d.indices where piece[i] == kept {
            deepest = max(deepest, d[i])
            sumX += Double(i % gw)
            sumY += Double(i / gw)
        }
        let enough = Double(deepest) * depth
        let cx = sumX / Double(keptSize), cy = sumY / Double(keptSize)
        var best = -1
        var bestDistance = Double.greatestFiniteMagnitude
        for i in d.indices where piece[i] == kept && Double(d[i]) >= enough {
            let dx = Double(i % gw) - cx, dy = Double(i / gw) - cy
            let squared = dx * dx + dy * dy
            if squared < bestDistance {
                bestDistance = squared
                best = i
            }
        }
        guard best >= 0 else { return nil }
        let px = best % gw - 1 + x0, py = best / gw - 1 + y0
        return CGPoint(x: (CGFloat(px) + 0.5) / CGFloat(w), y: (CGFloat(py) + 0.5) / CGFloat(h))
    }
}
