import CoreGraphics
import Foundation

/// 囲んで切り抜き直す (owner 2026-11-04: 「切り抜いたあとの画像を、指でその物体をサークルで囲うと切り抜きをその部分やり直す
/// 機能をつけて」): the learner draws a loop round the thing on the original photo, and the cut-out is made again from
/// what lies in the loop (`LassoCutout`). The pure part — which pixels are in the loop, and which of Vision's instances
/// are the thing — so CardCatchPickTests checks it without Vision.
nonisolated enum LassoCut {
    /// A loop smaller than this share of the photo is a slip of the finger, not a loop round a thing.
    static let minArea: CGFloat = 0.002
    /// An instance is the thing when this share of it lies in the loop…
    static let insideShare = 0.5
    /// … and it is not a speck: at least this share of the loop.
    static let speck = 0.01
    /// The kept pixels may lie this many grid pixels outside the loop (a loop drawn on the thing's very edge).
    static let slack = 2

    /// The loop's area, 0–1 of the photo (shoelace formula; the loop is closed from its last point to its first).
    static func area(_ loop: [CGPoint]) -> CGFloat {
        guard loop.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in loop.indices {
            let a = loop[i], b = loop[(i + 1) % loop.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Whether the points make a loop round something (not a tap or a short stroke).
    static func isLoop(_ loop: [CGPoint]) -> Bool {
        loop.count >= 8 && area(loop) >= minArea
    }

    /// The loop's bounding box, 0–1 of the photo.
    static func bounds(_ loop: [CGPoint]) -> CGRect {
        guard !loop.isEmpty else { return .zero }
        let xs = loop.map(\.x), ys = loop.map(\.y)
        let x0 = xs.min()!, x1 = xs.max()!, y0 = ys.min()!, y1 = ys.max()!
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// The pixels of a `width` × `height` grid whose centres lie in the loop (0–1 of the grid; even–odd rule, a row at a
    /// time), 1 = inside.
    static func inside(_ loop: [CGPoint], width w: Int, height h: Int) -> [UInt8] {
        var bits = [UInt8](repeating: 0, count: max(0, w * h))
        guard loop.count >= 3, w > 0, h > 0 else { return bits }
        let pts = loop.map { CGPoint(x: $0.x * CGFloat(w), y: $0.y * CGFloat(h)) }
        var xs: [CGFloat] = []
        for y in 0..<h {
            let cy = CGFloat(y) + 0.5
            xs.removeAll(keepingCapacity: true)
            for i in pts.indices {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                guard (a.y <= cy) != (b.y <= cy) else { continue }
                xs.append(a.x + (cy - a.y) / (b.y - a.y) * (b.x - a.x))
            }
            xs.sort()
            var k = 0
            while k + 1 < xs.count {
                let x0 = max(0, Int((xs[k] - 0.5).rounded(.up))), x1 = min(w - 1, Int((xs[k + 1] - 0.5).rounded(.down)))
                if x0 <= x1 { for x in x0...x1 { bits[y * w + x] = 1 } }
                k += 2
            }
        }
        return bits
    }

    /// `bits` grown by `by` pixels (8 neighbours, one step at a time).
    static func grown(_ bits: [UInt8], width w: Int, height h: Int, by steps: Int) -> [UInt8] {
        var out = bits
        for _ in 0..<max(0, steps) {
            let src = out
            for y in 0..<h {
                for x in 0..<w where src[y * w + x] == 0 {
                    var near = false
                    for dy in -1...1 where !near {
                        for dx in -1...1 {
                            let nx = x + dx, ny = y + dy
                            if nx >= 0, ny >= 0, nx < w, ny < h, src[ny * w + nx] != 0 { near = true; break }
                        }
                    }
                    if near { out[y * w + x] = 1 }
                }
            }
        }
        return out
    }

    /// The instances of a label mask (0 = background) that are the thing in the loop: those with `insideShare` of their
    /// pixels in it that are no speck. A neighbour the loop only grazes stays out; a thing Vision saw in pieces (a lint
    /// roller's roller and handle) comes in whole.
    static func pick(mask: [UInt8], inside: [UInt8], width w: Int, height h: Int) -> [Int] {
        guard w > 0, h > 0, mask.count >= w * h, inside.count >= w * h else { return [] }
        var total = [Int](repeating: 0, count: 256), within = [Int](repeating: 0, count: 256)
        var loopArea = 0
        for i in 0..<(w * h) {
            if inside[i] != 0 { loopArea += 1 }
            let l = Int(mask[i])
            guard l != 0 else { continue }
            total[l] += 1
            if inside[i] != 0 { within[l] += 1 }
        }
        guard loopArea > 0 else { return [] }
        return (1..<256).filter { l in
            total[l] > 0 && Double(within[l]) >= insideShare * Double(total[l])
                && Double(within[l]) >= speck * Double(loopArea)
        }
    }

    /// What is kept of the picked instances: their pixels in the loop (grown by `slack`), so a part the loop cut off
    /// stays off — the learner's loop is the last word on what the thing is.
    static func keep(mask: [UInt8], labels: [Int], inside: [UInt8], width w: Int, height h: Int) -> [UInt8] {
        var on = [Bool](repeating: false, count: 256)
        for l in labels where l > 0 && l < 256 { on[l] = true }
        let loop = grown(inside, width: w, height: h, by: slack)
        return (0..<(w * h)).map { i in on[Int(mask[i])] && loop[i] != 0 ? 1 : 0 }
    }
}
