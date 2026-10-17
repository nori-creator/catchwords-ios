import CoreGraphics
import Foundation

/// Whether an object's Vision instance really is the thing the AI named, and which other pieces of the mask belong to
/// it. Pure: counts of the label mask in, a decision out (MaskCoverageTests; `CatchPlan` acts on it).
/// - keep: the instance fills most of the AI's box (the thing, or the thing as part of it — a person and the bun they
///   hold as one instance), or lies mostly inside it (a thin thing: a bicycle, glasses).
/// - union: with other instances in the box it shows the thing far better: a person whose hand only reaches into the box
///   and the bun beside it (owner 2026-10-15), or one thing Vision saw in pieces — the dorayaki's two pancakes and the
///   ice cream between them, each mostly inside the box (owner 2026-10-16).
/// - larger: it is mostly outside the box and fills little of it (the thing merged with what is behind it, or the AI's
///   box off to one side). It is never cut to the box (owner 2026-10-16: a straight-sided dorayaki): `CatchPlan` keeps it
///   whole and has Vision look again at the region (`Placement.refine`).
nonisolated enum CutCoverage {
    enum Decision: Equatable, Sendable {
        case keep
        case union([Int])
        case larger
    }

    /// Share of the instance inside the box above which it is the thing itself.
    static let mostlyInside = 0.5
    /// Share of the box an instance (or the instances together) must fill to show the thing.
    static let fillsBox = 0.6
    /// Share of the box another instance must cover to be taken in on its own.
    static let overlaps = 0.15
    /// How much more of the box the pieces must fill together than the instance alone (a speck is no piece).
    static let pieceGain = 0.15

    /// `inBox`: each label's pixels inside the box; `totals`: each label's pixels in the whole mask; `boxArea`: the
    /// box's pixels (same grid); `excluding`: instances that are other things' own (never taken in here).
    static func decide(chosen: Int, inBox: [Int: Int], totals: [Int: Int], boxArea: Int,
                       excluding: Set<Int> = []) -> Decision {
        guard boxArea > 0, let total = totals[chosen], total > 0 else { return .keep }
        let mine = inBox[chosen] ?? 0
        let inside = Double(mine) / Double(total)
        let fills = Double(mine) / Double(boxArea)
        if fills >= fillsBox { return .keep }
        let others = inBox.filter { $0.key != chosen && $0.key != 0 && !excluding.contains($0.key) }
        // Instances covering a good part of the box that, with this one, fill it.
        let large = others.filter { Double($0.value) / Double(boxArea) >= overlaps }.map(\.key).sorted()
        let together = large.reduce(mine) { $0 + (inBox[$1] ?? 0) }
        if !large.isEmpty, Double(together) / Double(boxArea) >= fillsBox { return .union(([chosen] + large).sorted()) }
        // Pieces of the same thing: real parts of the box that lie mostly inside it.
        let pieces = others.filter { l, n in
            Double(n) >= CatchPlan.presence * Double(boxArea) && Double(n) / Double(max(1, totals[l] ?? 0)) >= mostlyInside
        }.map(\.key).sorted()
        let withPieces = pieces.reduce(mine) { $0 + (inBox[$1] ?? 0) }
        if !pieces.isEmpty, Double(withPieces) / Double(boxArea) >= fills + pieceGain { return .union(([chosen] + pieces).sorted()) }
        if inside >= mostlyInside { return .keep }
        return .larger
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
