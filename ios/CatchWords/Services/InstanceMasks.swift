import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#endif

/// Reading Vision's label mask (one byte per pixel, 0 = background, else the instance's label).
nonisolated enum MaskPixels {
    /// The instance label under `point` (0–1, top-left origin) in Vision's label mask, or the nearest
    /// instance within ~8% of the image when the point lands just beside a thin or small subject.
    static func nearestInstance(in mask: CVPixelBuffer, to point: CGPoint) -> Int? {
        rankedInstances(in: mask, to: point).first?.label
    }

    /// Every instance label within ~8% of `point` (0–1, top-left origin), nearest first, with its squared
    /// distance in mask pixels (0 = the point lies on it). Card catch hands each object its own instance from
    /// this list (`CatchPlan.assignInstances`), so two objects never share one cut-out and box.
    static func rankedInstances(in mask: CVPixelBuffer, to point: CGPoint) -> [CatchPlan.InstanceHit] {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        let w = CVPixelBufferGetWidth(mask)
        let h = CVPixelBufferGetHeight(mask)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(mask) else { return [] }
        let row = CVPixelBufferGetBytesPerRow(mask)
        let x = min(w - 1, max(0, Int(point.x * CGFloat(w))))
        let y = min(h - 1, max(0, Int(point.y * CGFloat(h))))
        func label(_ px: Int, _ py: Int) -> Int { Int(base.advanced(by: py * row + px).load(as: UInt8.self)) }
        var best: [Int: Int] = [:]
        let under = label(x, y)
        if under != 0 { best[under] = 0 }
        let reach = max(4, Int(Double(max(w, h)) * 0.08))
        let step = max(1, reach / 16)
        for py in stride(from: max(0, y - reach), through: min(h - 1, y + reach), by: step) {
            for px in stride(from: max(0, x - reach), through: min(w - 1, x + reach), by: step) {
                let l = label(px, py)
                guard l != 0 else { continue }
                let d = (px - x) * (px - x) + (py - y) * (py - y)
                if d < best[l, default: Int.max] { best[l] = d }
            }
        }
        return best.map { CatchPlan.InstanceHit(label: $0.key, distance: $0.value) }
            .sorted { $0.distance != $1.distance ? $0.distance < $1.distance : $0.label < $1.label }
    }

    /// A copy of the label mask at most `maxSide` px on its long side (every `step`-th pixel), with only `known`
    /// labels kept (0 = background).
    static func copy(_ buffer: CVPixelBuffer, known labels: IndexSet, maxSide: Int = 512) -> (mask: [UInt8], width: Int, height: Int)? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let step = max(1, Int((Double(max(w, h)) / Double(maxSide)).rounded(.up)))
        let mw = (w + step - 1) / step, mh = (h + step - 1) / step
        var known = [Bool](repeating: false, count: 256)
        for label in labels where label > 0 && label < 256 { known[label] = true }
        var mask = [UInt8](repeating: 0, count: mw * mh)
        for y in 0..<mh {
            let line = base.advanced(by: y * step * row)
            for x in 0..<mw {
                let v = line.load(fromByteOffset: x * step, as: UInt8.self)
                if v != 0, known[Int(v)] { mask[y * mw + x] = v }
            }
        }
        return (mask: mask, width: mw, height: mh)
    }
}

/// The result of one foreground-instance request on a photo (`InstanceMasks.make`, `CutoutService.instanceMasks`):
/// hit-test a point, cut things out with their alpha bounding box (normalized to the photo, top-left origin) so the
/// cut-out and its box always match, and carry out a `CatchPlan` (`render`). No UIKit in here, so
/// scripts/cutout-harness runs this same file on a Mac with real Vision.
nonisolated final class InstanceMasks: @unchecked Sendable {
    nonisolated struct Cut: @unchecked Sendable {
        /// The subject on transparency, cropped exactly to `box`.
        let cg: CGImage
        /// The opaque pixels' bounding box, 0–1 of the photo.
        let box: CGRect

        #if canImport(UIKit)
        var image: UIImage { UIImage(cgImage: cg) }
        #endif
    }

    private let observation: VNInstanceMaskObservation
    private let handler: VNImageRequestHandler
    /// The photo the masks were made from (for `regionHit` and `colourGrid`).
    private let photo: CGImage?
    private let context = CIContext()
    private let lock = NSLock()
    private var cache: [Int: Cut] = [:]
    private var unionCache: [String: Cut] = [:]
    /// The label mask copy (`labelMask`), made once for the plan.
    private let maskLock = NSLock()
    private var maskCache: (mask: [UInt8], width: Int, height: Int)?
    /// The tags' places (`anchors`), measured once. A lock of their own, so they never wait for a cut-out to render.
    private let anchorLock = NSLock()
    private var anchorCache: [Int: CGPoint]?
    private let colourLock = NSLock()
    private var colourCache: [UInt8]?
    private let personLock = NSLock()
    private var personCache: [UInt8]?

    init(observation: VNInstanceMaskObservation, handler: VNImageRequestHandler, photo: CGImage? = nil) {
        self.observation = observation
        self.handler = handler
        self.photo = photo
    }

    /// Vision's foreground instances of an upright bitmap (the app draws the photo upright and at most 1600 px first:
    /// `CutoutService.instanceMasks`). nil when Vision finds no subject, or cannot run (the Simulator).
    static func make(from cg: CGImage) -> InstanceMasks? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        do { try handler.perform([request]) } catch { return nil }
        guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
        return InstanceMasks(observation: result, handler: handler, photo: cg)
    }

    // MARK: Carrying out the plan

    /// Every thing's cut-out as `CatchPlan` chose it, and why (for the developer log). `boxes` / `points`: each thing's
    /// box (nil = none) and point, 0–1 of the photo. Heavy: call off the main thread.
    ///
    /// A thing that shares its Vision instance with another thing, or whose instance lies mostly outside its box,
    /// first gets Vision once more on a crop round its own box (`regionHit`): on a tighter crop Vision usually makes the
    /// touching things separate instances, and the one at the thing's point is used as it is — its own outline. The
    /// other things of that shared instance then get the instance without it (so the line between them is that
    /// outline too); only when no crop finds the thing whole does the plan's split (along the photo's colour edges)
    /// stand.
    ///
    /// A crop's thing is used only when it is the thing: it covers its box (`CatchPlan.minBoxCover`), and it is not a
    /// person when the thing cannot be one (`mayBePerson`, owner 2026-10-26: the swing's cut-out was the man at it).
    func render(_ plans: [CatchPlan.Placement], boxes: [CGRect?], points: [CGPoint],
                mayBePerson: [Bool]? = nil) -> [(cut: Cut?, note: String?)] {
        let n = plans.count
        let people = (mayBePerson ?? []).contains(false) ? personGrid() : nil
        let gridSize = labelMaskCopy().map { (w: $0.width, h: $0.height) }
        func isTheThing(_ h: RegionHit, _ i: Int) -> Bool {
            guard let box = boxes[i] else { return true }
            if CatchPlan.cover(h.cut.box, of: box) < CatchPlan.minBoxCover {
                Self.trace?("thing \(i + 1): the crop's instance covers too little of its box — not used")
                return false
            }
            if mayBePerson?[i] == false, let g = h.grid, CatchPlan.isPerson(g, people: people) {
                Self.trace?("thing \(i + 1): the crop's instance is a person — not used")
                return false
            }
            // A crop's instance that lies much in other named things' boxes (and outside its own) holds another thing
            // too (keys and the flip-flop under them, one instance again in the crop round the keys): not this thing
            // alone (the cut-out harness, 2026-11-03).
            if let g = h.grid, let size = gridSize, g.count == size.w * size.h {
                let others = boxes.indices.filter { $0 != i }.compactMap { boxes[$0] }
                let share = Self.share(of: g, outside: box.insetBy(dx: -box.width * 0.05, dy: -box.height * 0.05),
                                       inAny: others, width: size.w, height: size.h)
                if share > Self.cropOthersLimit {
                    Self.trace?(String(format: "thing %d: %.0f%% of the crop's instance lies in other things' boxes — not used", i + 1, share * 100))
                    return false
                }
            }
            return true
        }
        var hits: [Int: RegionHit] = [:]
        for i in 0..<n {
            guard let box = boxes[i], !plans[i].sharedWith.isEmpty || plans[i].refine != nil else { continue }
            if let h = regionHit(box, point: points[i], fadeIfCut: false), isTheThing(h, i) { hits[i] = h }
        }
        // A crop's instance that takes most of another thing it shares the instance with is the two things together
        // again (a person and the helmet held against them, both whole in the widest crop): not this thing alone.
        var merged: [Int: Int] = [:]
        for (i, h) in hits {
            guard let hb = h.grid else { continue }
            for j in plans[i].sharedWith where j < n {
                guard case .part(_, let theirs) = plans[j].cut, theirs.bits.count == hb.count else { continue }
                let total = theirs.count
                guard total > 0 else { continue }
                var both = 0
                for k in hb.indices where hb[k] != 0 && theirs.bits[k] != 0 { both += 1 }
                if Double(both) >= Self.mergedShare * Double(total) { merged[i] = j }
            }
        }
        for (i, j) in merged {
            hits[i] = nil
            Self.trace?("thing \(i + 1): the crop's instance holds most of thing \(j + 1) too — not used")
        }
        let grid = labelMaskCopy()
        var out: [(cut: Cut?, note: String?)] = []
        /// The grid pixels each thing's cut keeps (for `takesOthers`), when known.
        var kept: [[Bool]?] = []
        func labelBits(_ labels: [Int]) -> [Bool]? {
            guard let g = grid else { return nil }
            var on = [Bool](repeating: false, count: 256)
            for l in labels where l > 0 && l < 256 { on[l] = true }
            return g.mask.map { on[Int($0)] }
        }
        for i in 0..<n {
            let p = plans[i]
            var note = p.note
            func add(_ s: String) { note = (note.map { $0 + "; " } ?? "") + s }
            if let j = merged[i] { add("the crop's instance held thing \(j + 1) too") }
            if let h = hits[i] {
                add("Vision on a crop round its box found it whole")
                out.append((h.cut, note))
                kept.append(h.grid.map { $0.map { $0 != 0 } })
                continue
            }
            // Mostly outside its box and no crop found it alone: the whole instance (a box drawn smaller than the thing is
            // common — the cut-out harness's box-small cases). When that instance is mostly other named things, the
            // check after this loop drops it for the photo round the box.
            if p.refine != nil { add("no crop found it whole: the whole instance") }
            switch p.cut {
            case .instance(let l): kept.append(labelBits([l]))
            case .union(let ls): kept.append(labelBits(ls))
            case .part(_, let keep): kept.append(keep.bits.map { $0 != 0 })
            case .noMask: kept.append(nil)
            }
            switch p.cut {
            case .instance(let l):
                out.append((cut(instance: l), note))
            case .union(let ls):
                out.append((cut(instances: IndexSet(ls)) ?? ls.first.flatMap { cut(instance: $0) }, note))
            case .part(let ls, let keep):
                // The things of this shared instance that a crop found whole take their own outline out of it.
                let rivals = p.sharedWith.filter { $0 < n && hits[$0] != nil }
                guard !rivals.isEmpty, let g = grid, g.width == keep.width, g.height == keep.height, let box = boxes[i] else {
                    out.append((cut(instances: IndexSet(ls), keep: keep), note))
                    continue
                }
                let left = p.sharedWith.filter { $0 < n && hits[$0] == nil }
                var bits = keep.bits
                var taken = [Bool](repeating: false, count: g.width * g.height)
                for j in rivals { if let hb = hits[j]?.grid { for k in hb.indices where hb[k] != 0 { taken[k] = true } } }
                taken = Self.grown(taken, width: g.width, height: g.height)
                var on = [Bool](repeating: false, count: 256)
                for l in ls where l > 0 && l < 256 { on[l] = true }
                for k in bits.indices where on[Int(g.mask[k])] {
                    if taken[k] { bits[k] = 0; continue }
                    // What a rival found whole does not take is this thing's when no other thing is left to share it.
                    if bits[k] == 0 && left.isEmpty { bits[k] = 1 }
                }
                // What a rival took from inside its outline is given back (no hole where the cutlet lay on the curry).
                let kept0 = CatchPlan.Keep(width: g.width, height: g.height, bits: bits)
                let whole = CatchPlan.filledHoles(kept0, labels: ls, mask: g.mask, width: g.width, height: g.height)
                let mine = CatchPlan.reaching(whole, box: box, width: g.width, height: g.height)
                add("the instance without what a crop found for thing \(rivals.map { String($0 + 1) }.joined(separator: ", "))")
                out.append((mine.count > 0 ? cut(instances: IndexSet(ls), keep: mine) : nil, note))
            case .noMask:
                // Nothing Vision found is where the AI boxed the thing: Vision once more, on a crop round it.
                guard let box = boxes[i] else {
                    out.append((nil, note))
                    continue
                }
                let h = regionHit(box, point: points[i], fadeIfCut: true).flatMap { isTheThing($0, i) ? $0 : nil }
                add(h == nil ? "no cut-out (no crop round its box found it either)" : "cut from a crop round its box")
                out.append((h?.cut, note))
                kept[kept.count - 1] = h?.grid.map { $0.map { $0 != 0 } }
            }
        }
        // A cut-out that is mostly other named things (the spoon's cut that was the cup, the saucer and the spoon) is
        // not this thing: the photo round its box instead (owner 2026-10-26: 「別の物を切り抜くくらいなら四角」, check
        // 2026-11-03 S12). The caller falls back to `StickerCrop.shaped` for a thing without a cut-out.
        if let g = grid {
            for i in 0..<n {
                guard out[i].cut != nil, let own = boxes[i], let mine = kept[i], mine.count == g.width * g.height else { continue }
                let others = boxes.indices.filter { $0 != i }.compactMap { boxes[$0] }
                let share = Self.othersShare(mine, own: own, others: others, width: g.width, height: g.height)
                if share > Self.othersLimit {
                    let why = String(format: "%.0f%% of it lies in other things' boxes: no cut-out (the photo round its box)", share * 100)
                    out[i] = (nil, (out[i].note.map { $0 + "; " } ?? "") + why)
                    Self.trace?("thing \(i + 1): \(why)")
                }
            }
        }
        // A cut-out that is likely wrong is not used: the photo round the thing's box, as a rectangle, instead (owner
        // 2026-11-04: 「失敗するなら切り抜かず四角のまま表示して」; the caller falls back to `StickerCrop.shaped`).
        let w = 96, h = 96
        let grids: [[UInt8]?] = out.map { $0.cut.flatMap { Self.alphaGrid($0, width: w, height: h) } }
        let reasons: [String?] = (0..<n).map { i in
            guard let c = out[i].cut, let g = grids[i] else { return nil }
            return Self.doubtful(c, g, i, plans: plans, boxes: boxes, grids: grids, width: w, height: h)
        }
        for i in 0..<n {
            guard let why = reasons[i] else { continue }
            out[i] = (nil, (out[i].note.map { $0 + "; " } ?? "") + why + ": the photo round its box instead")
            Self.trace?("thing \(i + 1): \(why) — no cut-out")
        }
        // A whole instance's edge, made again on a crop round it (owner 2026-11-04: the pot's handles came out lumpy —
        // Vision's mask of the whole photo is coarse at thin parts; on a crop round the pot both handles were exact).
        for i in 0..<n where hits[i] == nil {
            guard let c = out[i].cut else { continue }
            switch plans[i].cut {
            case .instance, .union:
                if let better = refined(c) {
                    out[i] = (better, (out[i].note.map { $0 + "; " } ?? "") + "edge made again on a crop round it")
                    Self.trace?("thing \(i + 1): edge made again on a crop round it")
                }
            default: break
            }
        }
        return out
    }

    /// The crop round a cut-out is this much bigger on every side (`refined`).
    static let refineMargin: CGFloat = 0.06
    /// The crop's cut-out is used only when it is the same thing: this much overlap (intersection over union) with the
    /// first one …
    static let refineMinOverlap = 0.8
    /// … from crop instances that lie at least this much inside the first one.
    static let refineInside = 0.5

    /// `c` cut again from Vision on a crop round it: the same thing at a finer resolution, so thin parts (handles,
    /// straps) follow the photo. nil when the crop is not much smaller than the photo, Vision finds nothing there, or what
    /// it finds is not the same thing (`refineMinOverlap`). Heavy: call off the main thread.
    func refined(_ c: Cut) -> Cut? {
        guard let photo else { return nil }
        let W = CGFloat(photo.width), H = CGFloat(photo.height)
        let b = c.box
        let mx = b.width * Self.refineMargin, my = b.height * Self.refineMargin
        let r = CGRect(x: (b.minX - mx) * W, y: (b.minY - my) * H, width: (b.width + 2 * mx) * W, height: (b.height + 2 * my) * H)
            .integral.intersection(CGRect(x: 0, y: 0, width: W, height: H))
        // Only a crop clearly smaller than the photo is finer.
        guard r.width >= 32, r.height >= 32, r.width * r.height < 0.7 * W * H,
              let crop = photo.cropping(to: r), let masks = InstanceMasks.make(from: crop), let g = masks.labelMaskCopy()
        else { return nil }
        let gw = g.width, gh = g.height
        // The first cut-out on the crop's grid.
        var first = [UInt8](repeating: 0, count: gw * gh)
        let drawn: Bool = first.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: gw, height: gh, bitsPerComponent: 8, bytesPerRow: gw,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            else { return false }
            let x = (b.minX * W - r.minX) / r.width * CGFloat(gw), top = (b.minY * H - r.minY) / r.height * CGFloat(gh)
            let bw = b.width * W / r.width * CGFloat(gw), bh = b.height * H / r.height * CGFloat(gh)
            ctx.draw(c.cg, in: CGRect(x: x, y: CGFloat(gh) - top - bh, width: bw, height: bh))
            return true
        }
        guard drawn else { return nil }
        var total = [Int](repeating: 0, count: 256), inside = [Int](repeating: 0, count: 256)
        for k in 0..<(gw * gh) {
            let l = Int(g.mask[k])
            guard l != 0 else { continue }
            total[l] += 1
            if first[k] > 127 { inside[l] += 1 }
        }
        let labels = (1..<256).filter { total[$0] > 0 && Double(inside[$0]) >= Self.refineInside * Double(total[$0]) }
        guard !labels.isEmpty else { return nil }
        var on = [Bool](repeating: false, count: 256)
        for l in labels { on[l] = true }
        var both = 0, either = 0
        for k in 0..<(gw * gh) {
            let a = on[Int(g.mask[k])], f = first[k] > 127
            if a && f { both += 1 }
            if a || f { either += 1 }
        }
        guard either > 0, Double(both) >= Self.refineMinOverlap * Double(either) else { return nil }
        // A thing that runs on past the crop would come out cut straight along the crop's edge: kept as it was.
        let left = r.minX > 0.5, right = r.maxX < W - 0.5, top = r.minY > 0.5, bottom = r.maxY < H - 0.5
        for y in 0..<gh {
            for x in 0..<gw where on[Int(g.mask[y * gw + x])] {
                if (left && x == 0) || (right && x == gw - 1) || (top && y == 0) || (bottom && y == gh - 1) { return nil }
            }
        }
        guard let made = masks.cut(instances: IndexSet(labels)) else { return nil }
        let mb = made.box
        let box = CGRect(x: (r.minX + mb.minX * r.width) / W, y: (r.minY + mb.minY * r.height) / H,
                         width: mb.width * r.width / W, height: mb.height * r.height / H)
        return Cut(cg: made.cg, box: box)
    }

    /// Why a cut-out is likely wrong, nil when it is not (`render`; `mine` is the cut-out on a `width` × `height` grid of
    /// the photo, `grids` every thing's). Only where two named things are in the photo — a thing alone keeps its
    /// cut-out (the cut-out harness: the single things pass):
    /// - another thing in it: more than `doubtOthers` of it lies outside its own box (grown 5%) and inside another
    ///   thing's box (a can's cut-out with the cake in front of it), or is also in another thing's cut-out (both kept
    ///   what lies between them). A box that holds this box (a saucer's round its cup's) does not count;
    /// - a part of it missing: when it was split from an instance shared with another thing, or found by Vision again
    ///   on a crop, its outline spans less than `doubtSpan` of its box's width or height (one flip-flop of a pair).
    static func doubtful(_ c: Cut, _ mine: [UInt8], _ i: Int, plans: [CatchPlan.Placement], boxes: [CGRect?],
                         grids: [[UInt8]?], width w: Int, height h: Int) -> String? {
        guard let own = boxes[i] else { return nil }
        // Other things' boxes, without those this box lies in (`nestedShare`).
        let others = boxes.indices.filter { $0 != i }.filter { j in
            guard let b = boxes[j] else { return false }
            return CatchPlan.cover(b, of: own) < Double(CatchPlan.nestedShare)
        }
        guard boxes.indices.contains(where: { $0 != i && boxes[$0] != nil }) else { return nil }
        let share = Self.share(of: mine, outside: own.insetBy(dx: -own.width * 0.05, dy: -own.height * 0.05),
                               inAny: others.compactMap { boxes[$0] }, width: w, height: h)
        if share > doubtOthers { return String(format: "%.0f%% of the cut-out lies in other things' boxes", share * 100) }
        let total = mine.reduce(0) { $0 + Int($1) }
        if total > 0 {
            for j in others {
                guard let g = grids[j], g.count == mine.count, let bj = boxes[j] else { continue }
                // A part of this thing named on its own (its box inside this one): sharing its pixels is right.
                if CatchPlan.cover(own, of: bj) >= Double(CatchPlan.nestedShare) { continue }
                // Where the two cut-outs overlap: on this thing's side (its box, not the other's) the other one took
                // this thing — this one is right; on the other's side this one took the other thing.
                var both = 0, mineSide = 0, theirSide = 0
                for k in mine.indices where mine[k] != 0 && g[k] != 0 {
                    both += 1
                    let pt = CGPoint(x: (CGFloat(k % w) + 0.5) / CGFloat(w), y: (CGFloat(k / w) + 0.5) / CGFloat(h))
                    let inMine = own.contains(pt), inTheirs = bj.contains(pt)
                    if inMine && !inTheirs { mineSide += 1 }
                    if inTheirs && !inMine { theirSide += 1 }
                }
                let s = Double(both) / Double(total)
                guard s > doubtOthers, theirSide > mineSide else { continue }
                return String(format: "%.0f%% of the cut-out is thing %d's too, on its side", s * 100, j + 1)
            }
        }
        let split = !plans[i].sharedWith.isEmpty || plans[i].note?.contains("split where they meet") == true
        let cropped = plans[i].refine != nil || plans[i].cut == .noMask
        if split || cropped {
            let o = c.box.intersection(own)
            let spanW = o.isNull ? 0 : o.width / max(own.width, 1e-6), spanH = o.isNull ? 0 : o.height / max(own.height, 1e-6)
            if min(spanW, spanH) < doubtSpan {
                return String(format: "the cut-out spans only %.0f%% × %.0f%% of its box", spanW * 100, spanH * 100)
            }
        }
        return nil
    }

    /// Above this share of a cut-out in other things' boxes (outside its own), it is not used (`doubtful`).
    static let doubtOthers = 0.15
    /// A cut-out split from a shared instance (or found on a crop) that spans less than this share of its box's width or
    /// height is missing a part.
    static let doubtSpan: CGFloat = 0.6

    /// The cut-out's opaque pixels on a `width` × `height` grid of the whole photo (1 = opaque).
    static func alphaGrid(_ c: Cut, width w: Int, height h: Int) -> [UInt8]? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        let b = c.box
        // CG's origin is the bottom left.
        ctx.draw(c.cg, in: CGRect(x: b.minX * CGFloat(w), y: (1 - b.maxY) * CGFloat(h), width: b.width * CGFloat(w), height: b.height * CGFloat(h)))
        let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w where p[(y * w + x) * 4 + 3] > 127 { out[y * w + x] = 1 }
        }
        return out
    }

    /// Above this share of a crop's instance in other things' boxes (outside its own), it is not the thing (`render`).
    static let cropOthersLimit = 0.2

    /// The share of `bits` (1 = on, a grid `width` × `height`) outside `own` and inside one of `others` (0–1 boxes).
    static func share(of bits: [UInt8], outside own: CGRect, inAny others: [CGRect], width w: Int, height h: Int) -> Double {
        guard !others.isEmpty else { return 0 }
        var total = 0, theirs = 0
        for y in 0..<h {
            let fy = (CGFloat(y) + 0.5) / CGFloat(h)
            for x in 0..<w where bits[y * w + x] != 0 {
                total += 1
                let pt = CGPoint(x: (CGFloat(x) + 0.5) / CGFloat(w), y: fy)
                if own.contains(pt) { continue }
                if others.contains(where: { $0.contains(pt) }) { theirs += 1 }
            }
        }
        return total == 0 ? 0 : Double(theirs) / Double(total)
    }

    /// Above this share of a cut-out lying in other things' boxes (and not in its own), it is not used (`render`). Half: a
    /// cup with its saucer stays the cup; the spoon whose cut-out was the cup, the saucer and the spoon does not.
    static let othersLimit = 0.5

    /// The share of `mine`'s pixels that lie outside `own` and inside one of `others` (boxes 0–1 of the photo).
    static func othersShare(_ mine: [Bool], own: CGRect, others: [CGRect], width w: Int, height h: Int) -> Double {
        share(of: mine.map { $0 ? 1 : 0 }, outside: own, inAny: others, width: w, height: h)
    }

    /// `bits` grown by one pixel (8 neighbours).
    private static func grown(_ bits: [Bool], width w: Int, height h: Int) -> [Bool] {
        var out = bits
        for y in 0..<h {
            for x in 0..<w where bits[y * w + x] {
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, ny >= 0, nx < w, ny < h { out[ny * w + nx] = true }
                    }
                }
            }
        }
        return out
    }

    /// How far round the box the crop reaches, each side, as a share of the box: tried in turn while the thing runs
    /// into the crop's edge (a box smaller than the thing).
    static let regionWidening: [CGFloat] = [0.25, 0.6]
    /// A crop's instance holding this share of another thing's part is both things (`render`).
    static let mergedShare = 0.5
    /// Where the crops' decisions are told (the cut-out harness prints them; the app sends them to the developer log).
    nonisolated(unsafe) static var trace: ((String) -> Void)?

    // MARK: Cut-outs

    /// The full-size masked image of these instances (the photo on transparency, the size of the photo).
    func maskedImage(of labels: IndexSet) -> CGImage? {
        guard let masked = try? observation.generateMaskedImage(ofInstances: labels, from: handler,
                                                               croppedToInstancesExtent: false) else { return nil }
        let ci = CIImage(cvPixelBuffer: masked)
        return context.createCGImage(ci, from: ci.extent)
    }

    /// Heavy (renders a full-size mask): call off the main thread.
    func cut(instance label: Int) -> Cut? {
        lock.lock()
        defer { lock.unlock() }
        if let c = cache[label] { return c }
        guard let full = maskedImage(of: IndexSet(integer: label)), let c = Self.trimmed(full) else { return nil }
        cache[label] = c
        return c
    }

    /// Several instances cut out together (the person and the thing they hold). Heavy: call off the main thread.
    func cut(instances labels: IndexSet) -> Cut? {
        if labels.count == 1, let only = labels.first { return cut(instance: only) }
        let key = labels.map { String($0) }.joined(separator: ",")
        lock.lock()
        defer { lock.unlock() }
        if let c = unionCache[key] { return c }
        guard let full = maskedImage(of: labels), let c = Self.trimmed(full) else { return nil }
        unionCache[key] = c
        return c
    }

    /// These instances' pixels where `keep` is set (`CatchPlan.Cut.part`): one of two things Vision saw as one, or an
    /// instance without its pieces away from the thing. `keep` is on the plan's grid; it is grown two grid pixels into
    /// the background before it is laid over the full-size cut-out, so the outline stays Vision's own soft edge
    /// everywhere except where two things meet, and there it is smoothed. Heavy: call off the main thread.
    func cut(instances labels: IndexSet, keep: CatchPlan.Keep) -> Cut? {
        let key = labels.map { String($0) }.joined(separator: ",") + "#\(keep.hashValue)"
        lock.lock()
        defer { lock.unlock() }
        if let c = unionCache[key] { return c }
        guard let full = maskedImage(of: labels), keep.width > 0, keep.height > 0 else { return nil }
        let grid = labelMaskCopy()
        var bits = keep.bits.map { $0 != 0 ? UInt8(255) : 0 }
        if let g = grid, g.width == keep.width, g.height == keep.height {
            for _ in 0..<2 {
                var grown = bits
                for y in 0..<keep.height {
                    for x in 0..<keep.width where bits[y * keep.width + x] == 0 && g.mask[y * keep.width + x] == 0 {
                        var near = false
                        for dy in -1...1 where !near {
                            for dx in -1...1 {
                                let nx = x + dx, ny = y + dy
                                if nx >= 0, ny >= 0, nx < keep.width, ny < keep.height, bits[ny * keep.width + nx] != 0 {
                                    near = true
                                    break
                                }
                            }
                        }
                        if near { grown[y * keep.width + x] = 255 }
                    }
                }
                bits = grown
            }
        }
        guard let provider = CGDataProvider(data: Data(bits) as CFData),
              let maskImage = CGImage(width: keep.width, height: keep.height, bitsPerComponent: 8, bitsPerPixel: 8,
                                      bytesPerRow: keep.width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
              let ctx = CGContext(data: nil, width: full.width, height: full.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: full.width, height: full.height)
        ctx.interpolationQuality = .high
        ctx.clip(to: rect, mask: maskImage)
        ctx.draw(full, in: rect)
        guard let out = ctx.makeImage(), let c = Self.trimmed(out) else { return nil }
        unionCache[key] = c
        return c
    }

    /// What Vision found on a crop round one thing's box.
    struct RegionHit {
        /// The thing on transparency, its own outline (`trimmed`), and where it is in the photo.
        let cut: Cut
        /// The same thing on the plan's grid (`labelMaskCopy`; 1 = the thing): a shared instance is split by it.
        let grid: [UInt8]?
    }

    /// Vision once more on a crop of the photo round `box` (0–1), reaching `regionWidening` of the box round it. Of the
    /// crop's instances, the one at the thing's `point` (else nearest it) among those lying mostly in the box is the
    /// thing (`pickInstance`). It is used only when it is whole — it does not run into the crop's edge, other than the
    /// photo's own edge (a cut-out cut by the crop would end in a straight line); while it does, a wider crop is tried.
    /// `fadeIfCut` (a thing with no mask of its own at all, where nothing else would show it): if even the widest crop
    /// cuts it, the narrowest crop's instance is taken with its alpha faded out towards the crop's edge (`fadeWidth`),
    /// never a hard line. nil = nothing: never a rectangle. Heavy: off the main thread.
    func regionHit(_ box: CGRect, point: CGPoint?, fadeIfCut: Bool) -> RegionHit? {
        guard let photo, box.width > 0, box.height > 0 else { return nil }
        let W = CGFloat(photo.width), H = CGFloat(photo.height)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        var cutOne: (result: VNInstanceMaskObservation, handler: VNImageRequestHandler, label: Int, px: CGRect,
                     open: (left: Bool, top: Bool, right: Bool, bottom: Bool), m: (mask: [UInt8], width: Int, height: Int))?
        for widen in Self.regionWidening {
            let wide = box.insetBy(dx: -box.width * widen, dy: -box.height * widen).intersection(unit)
            guard !wide.isNull, wide.width > 0.02, wide.height > 0.02 else { break }
            let px = CGRect(x: wide.minX * W, y: wide.minY * H, width: wide.width * W, height: wide.height * H).integral
                .intersection(CGRect(x: 0, y: 0, width: W, height: H))
            guard px.width >= 16, px.height >= 16, let part = photo.cropping(to: px) else { break }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: part, orientation: .up)
            guard (try? handler.perform([request])) != nil, let result = request.results?.first,
                  !result.allInstances.isEmpty,
                  let m = MaskPixels.copy(result.instanceMask, known: result.allInstances, maxSide: 256) else { continue }
            let inner = CGRect(x: (box.minX * W - px.minX) / px.width, y: (box.minY * H - px.minY) / px.height,
                               width: box.width * W / px.width, height: box.height * H / px.height)
            let at = point.map { CGPoint(x: ($0.x * W - px.minX) / px.width, y: ($0.y * H - px.minY) / px.height) }
            let open = (left: px.minX > 0.5, top: px.minY > 0.5, right: px.maxX < W - 0.5, bottom: px.maxY < H - 0.5)
            let pick = Self.pickInstance(mask: m.mask, width: m.width, height: m.height, box: inner, point: at, open: open)
            Self.trace?(String(format: "crop %.0f%% round (%.2f,%.2f %.2f×%.2f): %d instances, ", widen * 100, box.minX, box.minY,
                               box.width, box.height, result.allInstances.count)
                        + (pick.label.map { "instance \($0) whole" } ?? pick.cutLabel.map { "instance \($0) cut by the crop's edge" }
                           ?? "none mostly inside the box"))
            if let label = pick.label {
                // The thing's other pieces in the crop (a roller beside its handle), when the crop did not cut them.
                var totals = [Int](repeating: 0, count: 256)
                for v in m.mask where v != 0 { totals[Int(v)] += 1 }
                let more = CatchPlan.gather([label], box: inner, mask: m.mask, totals: totals, excluding: [],
                                            width: m.width, height: m.height)
                    .filter { !Self.cutByOpenEdge(label: $0, mask: m.mask, width: m.width, height: m.height, open: open) }
                if !more.isEmpty { Self.trace?("  with its pieces \(more) in the crop") }
                return hit(result, handler, labels: [label] + more, px: px, m: m, fade: nil)
            }
            if let label = pick.cutLabel, cutOne == nil { cutOne = (result, handler, label, px, open, m) }
            guard pick.cutByEdge else { break }
        }
        if fadeIfCut, let c = cutOne {
            return hit(c.result, c.handler, labels: [c.label], px: c.px, m: c.m, fade: c.open)
        }
        return nil
    }

    /// A crop's instance as a `RegionHit` (faded towards `fade`'s open edges when given).
    private func hit(_ result: VNInstanceMaskObservation, _ handler: VNImageRequestHandler, labels: [Int], px: CGRect,
                     m: (mask: [UInt8], width: Int, height: Int),
                     fade: (left: Bool, top: Bool, right: Bool, bottom: Bool)?) -> RegionHit? {
        guard let photo,
              let masked = try? result.generateMaskedImage(ofInstances: IndexSet(labels), from: handler,
                                                           croppedToInstancesExtent: false) else { return nil }
        let W = CGFloat(photo.width), H = CGFloat(photo.height)
        let ci = CIImage(cvPixelBuffer: masked)
        guard var full = context.createCGImage(ci, from: ci.extent) else { return nil }
        if let fade, let faded = Self.faded(full, open: fade) { full = faded }
        guard let c = Self.trimmed(full) else { return nil }
        let sx = px.width / W, sy = px.height / H
        let cut = Cut(cg: c.cg, box: CGRect(x: px.minX / W + c.box.minX * sx, y: px.minY / H + c.box.minY * sy,
                                            width: c.box.width * sx, height: c.box.height * sy))
        // The thing on the plan's grid: each grid pixel's place in the crop.
        var bits: [UInt8]?
        if let g = labelMaskCopy(), g.width > 0, g.height > 0 {
            var b = [UInt8](repeating: 0, count: g.width * g.height)
            for gy in 0..<g.height {
                let y = (CGFloat(gy) + 0.5) / CGFloat(g.height) * H
                guard y >= px.minY, y < px.maxY else { continue }
                let ry = min(m.height - 1, Int((y - px.minY) / px.height * CGFloat(m.height)))
                for gx in 0..<g.width {
                    let x = (CGFloat(gx) + 0.5) / CGFloat(g.width) * W
                    guard x >= px.minX, x < px.maxX else { continue }
                    let rx = min(m.width - 1, Int((x - px.minX) / px.width * CGFloat(m.width)))
                    if labels.contains(Int(m.mask[ry * m.width + rx])) { b[gy * g.width + gx] = 1 }
                }
            }
            bits = b
        }
        return RegionHit(cut: cut, grid: bits)
    }

    /// How far in from a region's open edge a cut-off thing fades out (share of the region's shorter side).
    static let fadeWidth: CGFloat = 0.08

    /// `image` with its alpha (and colour, premultiplied) faded to nothing towards each `open` edge.
    private static func faded(_ image: CGImage, open: (left: Bool, top: Bool, right: Bool, bottom: Bool)) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let fade = max(1, CGFloat(min(w, h)) * fadeWidth)
        for y in 0..<h {
            for x in 0..<w {
                var f: CGFloat = 1
                if open.left { f = min(f, CGFloat(x) / fade) }
                if open.right { f = min(f, CGFloat(w - 1 - x) / fade) }
                if open.top { f = min(f, CGFloat(y) / fade) }
                if open.bottom { f = min(f, CGFloat(h - 1 - y) / fade) }
                guard f < 1 else { continue }
                let o = (y * w + x) * 4
                for c in 0..<4 { p[o + c] = UInt8(CGFloat(p[o + c]) * max(0, f)) }
            }
        }
        return ctx.makeImage()
    }

    /// Which of a crop's instances is the thing: of those lying mostly (half or more) in `box` grown by 10% and covering
    /// at least 2% of it, the one at `point` (0–1 of the crop; the box's middle when nil), else the nearest to it, else
    /// the one covering the most of the box. `label`: it, when it is whole — fewer than 1% of the crop's open edges'
    /// pixels are its; otherwise `cutByEdge` and `cutLabel` (a wider crop may help). Pure, so CardCatchPickTests
    /// checks it.
    static func pickInstance(mask: [UInt8], width w: Int, height h: Int, box: CGRect, point: CGPoint? = nil,
                             open: (left: Bool, top: Bool, right: Bool, bottom: Bool))
    -> (label: Int?, cutByEdge: Bool, cutLabel: Int?) {
        guard w > 2, h > 2, mask.count >= w * h else { return (nil, false, nil) }
        let grown = box.insetBy(dx: -box.width * 0.1, dy: -box.height * 0.1)
        let area = max(1, CatchPlan.gridArea(box, width: w, height: h))
        let inGrown = CatchPlan.countsInside(grown, mask: mask, width: w, height: h)
        let p = point ?? CGPoint(x: box.midX, y: box.midY)
        let px = p.x * CGFloat(w), py = p.y * CGFloat(h)
        var totals = [Int](repeating: 0, count: 256), edge = [Int](repeating: 0, count: 256)
        // Contact with each open edge (left, top, right, bottom) and each instance's extent, for the edge test below.
        var contact = [[Int]](repeating: [0, 0, 0, 0], count: 256)
        var minX = [Int](repeating: Int.max, count: 256), maxX = [Int](repeating: -1, count: 256)
        var minY = [Int](repeating: Int.max, count: 256), maxY = [Int](repeating: -1, count: 256)
        var near = [CGFloat](repeating: .greatestFiniteMagnitude, count: 256)
        for y in 0..<h {
            for x in 0..<w {
                let l = Int(mask[y * w + x])
                guard l != 0 else { continue }
                totals[l] += 1
                minX[l] = min(minX[l], x); maxX[l] = max(maxX[l], x)
                minY[l] = min(minY[l], y); maxY[l] = max(maxY[l], y)
                if x == 0 || y == 0 || x == w - 1 || y == h - 1 {
                    let touches = [open.left && x == 0, open.top && y == 0, open.right && x == w - 1, open.bottom && y == h - 1]
                    if touches.contains(true) { edge[l] += 1 }
                    for e in 0..<4 where touches[e] { contact[l][e] += 1 }
                }
                let dx = CGFloat(x) + 0.5 - px, dy = CGFloat(y) + 0.5 - py
                near[l] = min(near[l], dx * dx + dy * dy)
            }
        }
        let candidates = (1..<256).filter { l in
            totals[l] > 0 && Double(inGrown[l]) >= CatchPlan.presence * Double(area)
                && Double(inGrown[l]) / Double(totals[l]) >= 0.5
        }
        guard let pick = candidates.min(by: { a, b in near[a] != near[b] ? near[a] < near[b] : inGrown[a] > inGrown[b] })
        else { return (nil, false, nil) }
        return touchesOpenEdge(contact: contact[pick], total: edge[pick],
                               extent: (width: maxX[pick] - minX[pick] + 1, height: maxY[pick] - minY[pick] + 1),
                               crop: (width: w, height: h), open: open)
            ? (nil, true, pick) : (pick, false, nil)
    }

    /// Whether an instance runs into an open edge of a crop (so the crop cut it). A few pixels of a big thing grazing
    /// the edge are not a cut, but the allowance is judged against the thing's OWN size along that edge (`edgeGraze`
    /// of it), not the crop's: a 5 px spoon handle crossing the edge of a 256 px crop touches it with all its width,
    /// which a share of the crop's perimeter (10 px) would have let through as whole — and then cut straight there.
    /// Never more than the old allowance (1% of the open perimeter), whatever the thing's size.
    static func touchesOpenEdge(contact: [Int], total: Int, extent: (width: Int, height: Int), crop: (width: Int, height: Int),
                                open: (left: Bool, top: Bool, right: Bool, bottom: Bool)) -> Bool {
        let openLength = (open.left ? crop.height : 0) + (open.right ? crop.height : 0)
            + (open.top ? crop.width : 0) + (open.bottom ? crop.width : 0)
        let cap = max(1, Int(Double(openLength) * 0.01))
        if total > cap { return true }
        // left and right edges: the thing's height crosses them; top and bottom: its width.
        let along = [extent.height, extent.width, extent.height, extent.width]
        for e in 0..<4 where contact[e] > 0 {
            let allowed = max(1, min(cap, Int(Double(along[e]) * edgeGraze)))
            if contact[e] > allowed { return true }
        }
        return false
    }

    /// Whether instance `label` of a crop's mask runs into one of the crop's open edges (`touchesOpenEdge`).
    static func cutByOpenEdge(label: Int, mask: [UInt8], width w: Int, height h: Int,
                              open: (left: Bool, top: Bool, right: Bool, bottom: Bool)) -> Bool {
        var contact = [0, 0, 0, 0], edge = 0
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<h {
            for x in 0..<w where Int(mask[y * w + x]) == label {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                let touches = [open.left && x == 0, open.top && y == 0, open.right && x == w - 1, open.bottom && y == h - 1]
                if touches.contains(true) { edge += 1 }
                for e in 0..<4 where touches[e] { contact[e] += 1 }
            }
        }
        guard maxX >= 0 else { return false }
        return touchesOpenEdge(contact: contact, total: edge, extent: (width: maxX - minX + 1, height: maxY - minY + 1),
                               crop: (width: w, height: h), open: open)
    }

    /// The share of a thing's own extent along an edge it may touch that edge with and still count as whole.
    static let edgeGraze = 0.03

    /// The opaque part of a full-size cut-out and its box (0–1 of the image).
    private static func trimmed(_ full: CGImage) -> Cut? {
        guard let px = alphaBounds(full), let cropped = full.cropping(to: px) else { return nil }
        let w = CGFloat(full.width), h = CGFloat(full.height)
        return Cut(cg: cropped, box: CGRect(x: px.minX / w, y: px.minY / h, width: px.width / w, height: px.height / h))
    }

    // MARK: The label mask

    /// The photo at the label mask copy's grid (`labelMaskCopy`), 3 bytes (RGB) a pixel: `CatchPlan` splits a shared
    /// instance along the photo's own colour edges. Made once.
    func colourGrid() -> [UInt8]? {
        colourLock.lock()
        defer { colourLock.unlock() }
        if let c = colourCache { return c }
        guard let photo, let m = labelMaskCopy(), m.width > 0, m.height > 0,
              let ctx = CGContext(data: nil, width: m.width, height: m.height, bitsPerComponent: 8, bytesPerRow: m.width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(photo, in: CGRect(x: 0, y: 0, width: m.width, height: m.height))
        let p = data.bindMemory(to: UInt8.self, capacity: m.width * m.height * 4)
        var out = [UInt8](repeating: 0, count: m.width * m.height * 3)
        for i in 0..<(m.width * m.height) {
            out[i * 3] = p[i * 4]
            out[i * 3 + 1] = p[i * 4 + 1]
            out[i * 3 + 2] = p[i * 4 + 2]
        }
        colourCache = out
        return out
    }

    /// Where people are, on the plan's grid (`labelMaskCopy`; 1 = a person), made once: Vision's person segmentation of
    /// the same photo. A Vision instance that is mostly a person is never the cut-out of a thing that is not a person
    /// or worn by one (owner 2026-10-26: the swing's tag cut out the man pushing it — `CatchPlan.Thing.mayBePerson`).
    /// nil when Vision cannot tell (the Simulator).
    func personGrid() -> [UInt8]? {
        personLock.lock()
        defer { personLock.unlock() }
        if let p = personCache { return p }
        guard let photo, let m = labelMaskCopy(), m.width > 0, m.height > 0 else { return nil }
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cgImage: photo, orientation: .up)
        guard (try? handler.perform([request])) != nil, let buffer = request.results?.first?.pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let bw = CVPixelBufferGetWidth(buffer), bh = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        guard bw > 0, bh > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        var out = [UInt8](repeating: 0, count: m.width * m.height)
        for y in 0..<m.height {
            let by = min(bh - 1, Int((Double(y) + 0.5) / Double(m.height) * Double(bh)))
            let line = base.advanced(by: by * row)
            for x in 0..<m.width {
                let bx = min(bw - 1, Int((Double(x) + 0.5) / Double(m.width) * Double(bw)))
                if line.load(fromByteOffset: bx, as: UInt8.self) >= 128 { out[y * m.width + x] = 1 }
            }
        }
        personCache = out
        return out
    }

    /// The copy of the label mask the things are planned on (`CatchPlan`), made once.
    func labelMaskCopy() -> (mask: [UInt8], width: Int, height: Int)? {
        maskLock.lock()
        defer { maskLock.unlock() }
        if maskCache == nil { maskCache = labelMask() }
        return maskCache
    }

    /// The foreground instances near `point`, nearest first (see `MaskPixels.rankedInstances`).
    func instances(near point: CGPoint) -> [CatchPlan.InstanceHit] {
        let all = observation.allInstances
        return MaskPixels.rankedInstances(in: observation.instanceMask, to: point).filter { all.contains($0.label) }
    }

    /// Where each instance's name tag sits (`CatchAnchor`: deep inside its mask, near the middle of the thing), by
    /// label, 0–1 of the photo, top-left origin — read from the same copy of the label mask as the outlines, so a tag
    /// lands inside its own outline. Measured once for every instance, then cached; heavy the first time (reads the
    /// whole mask): call off the main thread (the capture warms it while the AI is still naming the things).
    func anchors() -> [Int: CGPoint] {
        anchorLock.lock()
        defer { anchorLock.unlock() }
        if let cached = anchorCache { return cached }
        let found = labelMask().map { CatchAnchor.anchors(mask: $0.mask, width: $0.width, height: $0.height) } ?? [:]
        anchorCache = found
        return found
    }

    /// A copy of Vision's label mask at most `maxSide` px on its long side, with only this observation's own instances.
    private func labelMask(maxSide: Int = 512) -> (mask: [UInt8], width: Int, height: Int)? {
        MaskPixels.copy(observation.instanceMask, known: observation.allInstances, maxSide: maxSide)
    }

    /// Renders the cut-outs of the first `limit` instances into the cache. Called off the main thread while the AI
    /// is still naming the things, so the words screen only picks finished cut-outs (they used to be rendered after
    /// the server answered, on the way to the words — owner 2026-10-10: 「ただ待たされる時間は苦痛」).
    func prerenderCuts(limit: Int = 6) {
        for label in observation.allInstances.prefix(limit) { _ = cut(instance: label) }
    }

    /// Pixel rect (top-left origin) of every pixel whose alpha is above a faint threshold.
    static func alphaBounds(_ image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let rowStart = y * w * 4
            for x in 0..<w where bytes[rowStart + x * 4 + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
