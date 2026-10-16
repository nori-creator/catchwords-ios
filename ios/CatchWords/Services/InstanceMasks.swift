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
    func render(_ plans: [CatchPlan.Placement], boxes: [CGRect?], points: [CGPoint]) -> [(cut: Cut?, note: String?)] {
        let n = plans.count
        var hits: [Int: RegionHit] = [:]
        for i in 0..<n {
            guard let box = boxes[i], !plans[i].sharedWith.isEmpty || plans[i].refine != nil else { continue }
            if let h = regionHit(box, point: points[i], fadeIfCut: false) { hits[i] = h }
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
        for i in 0..<n {
            let p = plans[i]
            var note = p.note
            func add(_ s: String) { note = (note.map { $0 + "; " } ?? "") + s }
            if let j = merged[i] { add("the crop's instance held thing \(j + 1) too") }
            if let h = hits[i] {
                add("Vision on a crop round its box found it whole")
                out.append((h.cut, note))
                continue
            }
            if p.refine != nil { add("no crop found it whole: the whole instance") }
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
                let mine = CatchPlan.reaching(CatchPlan.Keep(width: g.width, height: g.height, bits: bits), box: box,
                                              width: g.width, height: g.height)
                add("the instance without what a crop found for thing \(rivals.map { String($0 + 1) }.joined(separator: ", "))")
                out.append((mine.count > 0 ? cut(instances: IndexSet(ls), keep: mine) : nil, note))
            case .noMask:
                // Nothing Vision found is where the AI boxed the thing: Vision once more, on a crop round it.
                guard let box = boxes[i] else {
                    out.append((nil, note))
                    continue
                }
                let h = regionHit(box, point: points[i], fadeIfCut: true)
                add(h == nil ? "no cut-out (no crop round its box found it either)" : "cut from a crop round its box")
                out.append((h?.cut, note))
            }
        }
        return out
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
                return hit(result, handler, label: label, px: px, m: m, fade: nil)
            }
            if let label = pick.cutLabel, cutOne == nil { cutOne = (result, handler, label, px, open, m) }
            guard pick.cutByEdge else { break }
        }
        if fadeIfCut, let c = cutOne {
            return hit(c.result, c.handler, label: c.label, px: c.px, m: c.m, fade: c.open)
        }
        return nil
    }

    /// A crop's instance as a `RegionHit` (faded towards `fade`'s open edges when given).
    private func hit(_ result: VNInstanceMaskObservation, _ handler: VNImageRequestHandler, label: Int, px: CGRect,
                     m: (mask: [UInt8], width: Int, height: Int),
                     fade: (left: Bool, top: Bool, right: Bool, bottom: Bool)?) -> RegionHit? {
        guard let photo,
              let masked = try? result.generateMaskedImage(ofInstances: IndexSet(integer: label), from: handler,
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
                    if Int(m.mask[ry * m.width + rx]) == label { b[gy * g.width + gx] = 1 }
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
        var near = [CGFloat](repeating: .greatestFiniteMagnitude, count: 256)
        for y in 0..<h {
            for x in 0..<w {
                let l = Int(mask[y * w + x])
                guard l != 0 else { continue }
                totals[l] += 1
                if (open.left && x == 0) || (open.right && x == w - 1) || (open.top && y == 0) || (open.bottom && y == h - 1) {
                    edge[l] += 1
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
        let openLength = (open.left ? h : 0) + (open.right ? h : 0) + (open.top ? w : 0) + (open.bottom ? w : 0)
        let allowed = max(1, Int(Double(openLength) * 0.01))
        return edge[pick] > allowed ? (nil, true, pick) : (pick, false, nil)
    }

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
