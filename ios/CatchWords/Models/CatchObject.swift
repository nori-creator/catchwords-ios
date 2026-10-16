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
    /// How the cut-out was made when it was not simply the thing's own Vision instance (shared with another thing,
    /// clipped to the thing's box, Vision run again on the region, or none at all) — for the developer log.
    var cutNote: String? = nil

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
    /// each other and only the top one could be tapped. One instance that two things' boxes split (two things
    /// touching, which Vision sees as one) is split where the two meet (`CatchPlan`, owner 2026-10-16); a cut-out is never
    /// cut along the AI's box. A thing with no mask where the AI boxed it gets Vision once more on that region, else no
    /// cut-out — never a rectangle.
    /// Its tag sits inside that same instance (`InstanceMasks.anchors`). Owner 2026-10-11: 「カメラ撮ったあとの単語の
    /// 名前のタグが、その該当のもののうえに配置されてない。しっかりもののうえに名前タグをおいて。」 — the tags sat on the
    /// AI's point, the middle of the AI's own rough box, which often lies beside the thing, between its parts or on
    /// what stands in front of it, while the outline drawn round the thing (the same instance) was right.
    static func build(candidates: [Candidate], masks: InstanceMasks?, photoSize: CGSize) -> [CatchObject] {
        let list = groups(candidates)
        let things = plannedThings(list)
        let points = things.map(\.point)
        let own = things.map(\.own)
        let boxes = things.map(\.box)
        // Which piece of the mask is each thing, and where its tag goes (`CatchPlan`, on a copy of the label mask).
        let copy = masks?.labelMaskCopy()
        let plans = CatchPlan.plan(things: things, mask: copy?.mask ?? [], width: copy?.width ?? 0, height: copy?.height ?? 0,
                                   colours: masks?.colourGrid())
        return list.enumerated().map { (i, words) -> CatchObject in
            let plan = plans[i]
            let made = masks?.render(plan, box: own[i] ? boxes[i] : nil)
            let cut = made?.cut
            let box = cut?.box ?? (own[i] ? boxes[i] : nil) ?? fallbackBox(at: plan.anchor, photoSize: photoSize)
            return CatchObject(id: i, words: words, point: own[i] ? points[i] : plan.anchor, box: box,
                               anchor: plan.anchor, cut: cut?.image, instance: plan.label, positioned: own[i],
                               cutNote: made?.note ?? plan.note)
        }
    }

    /// Each object's place as the AI gave it (`groups` of the server's candidates): the first name's point and box
    /// (0–1 of the photo; the box of any of its names when the first has none), and whether the place is its own.
    static func plannedThings(_ list: [[Candidate]]) -> [CatchPlan.Thing] {
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
        let boxes: [CGRect?] = list.map { words in words[0].objectBox ?? words.lazy.compactMap(\.objectBox).first }
        return list.indices.map { CatchPlan.Thing(point: points[$0], box: boxes[$0], own: own[$0]) }
    }

    /// Developer-log lines for a photo's things (owner 2026-10-16: the tags stacked on one thing and a rectangle was
    /// saved as the cut-out): the photo's size and orientation, and for each thing its name, the AI's point and box
    /// (0–1000, as sent), its Vision instance, how it was cut and where its tag went.
    static func traceLines(_ objects: [CatchObject], photo: CGSize, orientation: Int) -> [String] {
        var lines = ["photo \(Int(photo.width))×\(Int(photo.height)) orientation \(orientation), \(objects.count) things"]
        for o in objects {
            let w = o.words.first
            let box = w?.box.map { "[\($0.map { String(Int($0)) }.joined(separator: ","))]" } ?? "-"
            let pt = w.map { "[\(Int($0.point.first ?? -1)),\(Int($0.point.count > 1 ? $0.point[1] : -1))]" } ?? "-"
            lines.append("\(o.id + 1) \(w?.headword ?? "?"): point \(pt) box \(box) instance \(o.instance.map(String.init) ?? "-") "
                         + "cut \(o.cut == nil ? "none" : "mask") tag (\(String(format: "%.2f", o.anchor.x)), \(String(format: "%.2f", o.anchor.y)))"
                         + (o.cutNote.map { " — \($0)" } ?? ""))
        }
        return lines
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

    /// One Vision instance near an object's point (`CatchPlan.InstanceHit`).
    typealias InstanceHit = CatchPlan.InstanceHit

    /// Each object's own instance, never the same one twice (`CatchPlan.assignInstances`).
    static func assignInstances(_ ranked: [[InstanceHit]]) -> [Int?] { CatchPlan.assignInstances(ranked) }

    /// No Vision instance under the point: a square box around it, 36% of the photo's shorter side,
    /// kept inside the photo (outlined as the prototype's rounded rect, `outlineEl` without cutImg).
    static func fallbackBox(at p: CGPoint, photoSize s: CGSize) -> CGRect {
        let side = 0.36 * min(s.width, s.height)
        let w = min(1, side / max(s.width, 1)), h = min(1, side / max(s.height, 1))
        let x = min(max(0, p.x - w / 2), 1 - w), y = min(max(0, p.y - h / 2), 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
