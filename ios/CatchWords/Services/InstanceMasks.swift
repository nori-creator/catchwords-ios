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
    /// The photo the masks were made from (for `regionCut`).
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

    /// The cut-out `CatchPlan` chose for a thing, and why, for the developer log. `box`: the thing's box (0–1 of the
    /// photo) when the AI gave it one. Heavy: call off the main thread.
    func render(_ placement: CatchPlan.Placement, box: CGRect?) -> (cut: Cut?, note: String?) {
        var note = placement.note
        func add(_ s: String) { note = (note.map { $0 + "; " } ?? "") + s }
        if let region = placement.refine {
            if let whole = regionCut(region, minCover: Self.refineCover) {
                add("Vision on the region alone found the thing whole")
                return (whole, note)
            }
            add("the region alone found nothing whole: the whole instance")
        }
        switch placement.cut {
        case .instance(let l):
            return (cut(instance: l), note)
        case .union(let ls):
            return (cut(instances: IndexSet(ls)) ?? ls.first.flatMap { cut(instance: $0) }, note)
        case .part(let ls, let keep):
            return (cut(instances: IndexSet(ls), keep: keep), note)
        case .noMask:
            // Nothing Vision found is where the AI boxed the thing: Vision once more, on that region alone.
            guard let box else { return (nil, note) }
            let c = regionCut(box, minCover: Self.noMaskCover, fadeIfCut: true)
            add(c == nil ? "no cut-out (the region alone found nothing whole either)" : "cut from the region alone")
            return (c, note)
        }
    }

    /// A region's instance must fill this share of the thing's box to be the thing (refining an instance far larger
    /// than the box / a thing with no mask in its box at all — small and thin things fill little).
    static let refineCover = 0.3
    static let noMaskCover = 0.08
    /// How far round the box the region reaches, each side, as a share of the box: tried in turn while the instance in
    /// the box runs into the region's edge (a box smaller than the thing).
    static let regionWidening: [CGFloat] = [0.35, 0.8]

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

    /// Vision once more on the photo round `box` (0–1), for a thing the whole photo's request gave no mask of its own:
    /// the region reaches `regionWidening` of the box round it. Of the instances found there, the one that fills the
    /// most of the box is taken — only when it is whole (it does not run into the region's edge, other than the photo's
    /// own edge: such a cut-out would end in a straight line) and fills at least `minCover` of the box. A wider region
    /// is tried while the instance in the box is cut by the region's edge. `fadeIfCut` (a thing with no mask of its own
    /// at all, where nothing else would show it): after the widest try, an instance that still runs into the region's
    /// edge is taken with its alpha faded out towards that edge (`fadeWidth`), so it never ends in a hard line.
    /// nil = nothing: never a rectangle. Heavy: off the main thread.
    func regionCut(_ box: CGRect, minCover: Double, fadeIfCut: Bool = false) -> Cut? {
        guard let photo, box.width > 0, box.height > 0 else { return nil }
        let W = CGFloat(photo.width), H = CGFloat(photo.height)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        for (k, widen) in Self.regionWidening.enumerated() {
            let last = k == Self.regionWidening.count - 1
            let wide = box.insetBy(dx: -box.width * widen, dy: -box.height * widen).intersection(unit)
            guard !wide.isNull, wide.width > 0.02, wide.height > 0.02 else { return nil }
            let px = CGRect(x: wide.minX * W, y: wide.minY * H, width: wide.width * W, height: wide.height * H).integral
                .intersection(CGRect(x: 0, y: 0, width: W, height: H))
            guard px.width >= 16, px.height >= 16, let part = photo.cropping(to: px) else { return nil }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: part, orientation: .up)
            guard (try? handler.perform([request])) != nil, let result = request.results?.first,
                  !result.allInstances.isEmpty,
                  let m = MaskPixels.copy(result.instanceMask, known: result.allInstances, maxSide: 256) else { return nil }
            // The box and the region's open edges (not the photo's edge) on the region's grid.
            let inner = CGRect(x: (box.minX * W - px.minX) / px.width, y: (box.minY * H - px.minY) / px.height,
                               width: box.width * W / px.width, height: box.height * H / px.height)
            let open = (left: px.minX > 0.5, top: px.minY > 0.5, right: px.maxX < W - 0.5, bottom: px.maxY < H - 0.5)
            let pick = Self.wholeInstance(mask: m.mask, width: m.width, height: m.height, box: inner, open: open,
                                          minCover: minCover)
            let label = pick.label ?? (last && fadeIfCut ? pick.cutLabel : nil)
            if let label,
               let masked = try? result.generateMaskedImage(ofInstances: IndexSet(integer: label), from: handler,
                                                            croppedToInstancesExtent: false) {
                let ci = CIImage(cvPixelBuffer: masked)
                guard var full = context.createCGImage(ci, from: ci.extent) else { return nil }
                if pick.label == nil, let faded = Self.faded(full, open: open) { full = faded }
                guard let c = Self.trimmed(full) else { return nil }
                let sx = px.width / W, sy = px.height / H
                return Cut(cg: c.cg, box: CGRect(x: px.minX / W + c.box.minX * sx, y: px.minY / H + c.box.minY * sy,
                                                width: c.box.width * sx, height: c.box.height * sy))
            }
            guard pick.cutByEdge else { return nil }
        }
        return nil
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

    /// Of a region's instances, the one that fills the most of `box` (0–1 of the region) and is whole — fewer than 1%
    /// of the open edges' pixels are its — when it fills at least `minCover` of the box and at least 30% of it lies in
    /// the box. `cutByEdge`: an instance that would have been taken ran into an open edge (a wider region may help);
    /// `cutLabel`: the one of those that fills the most of the box. Pure, so CardCatchPickTests checks it.
    static func wholeInstance(mask: [UInt8], width w: Int, height h: Int, box: CGRect,
                              open: (left: Bool, top: Bool, right: Bool, bottom: Bool), minCover: Double)
    -> (label: Int?, cutByEdge: Bool, cutLabel: Int?) {
        guard w > 2, h > 2, mask.count >= w * h else { return (nil, false, nil) }
        let area = max(1, CatchPlan.gridArea(box, width: w, height: h))
        let inBox = CatchPlan.countsInside(box, mask: mask, width: w, height: h)
        var totals = [Int](repeating: 0, count: 256), edge = [Int](repeating: 0, count: 256)
        for y in 0..<h {
            for x in 0..<w {
                let l = Int(mask[y * w + x])
                guard l != 0 else { continue }
                totals[l] += 1
                if (open.left && x == 0) || (open.right && x == w - 1) || (open.top && y == 0) || (open.bottom && y == h - 1) {
                    edge[l] += 1
                }
            }
        }
        let openLength = (open.left ? h : 0) + (open.right ? h : 0) + (open.top ? w : 0) + (open.bottom ? w : 0)
        let allowed = max(1, Int(Double(openLength) * 0.01))
        var best: Int?, bestCut: Int?
        for l in 1..<256 where totals[l] > 0 {
            guard Double(inBox[l]) >= minCover * Double(area), Double(inBox[l]) / Double(totals[l]) >= 0.3 else { continue }
            if edge[l] > allowed {
                if bestCut.map({ inBox[l] > inBox[$0] }) ?? true { bestCut = l }
                continue
            }
            if let b = best, inBox[l] <= inBox[b] { continue }
            best = l
        }
        return (best, best == nil && bestCut != nil, best == nil ? bestCut : nil)
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
