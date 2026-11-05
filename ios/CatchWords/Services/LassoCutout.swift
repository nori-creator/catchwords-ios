import CoreGraphics
import UIKit

/// 囲んで切り抜き直す (owner 2026-11-04): the cut-out made again from the loop the learner drew on the original photo
/// (`LassoCutoutView`). Vision runs once more on a crop round the loop — on a tighter crop it sees the thing itself —
/// and the instances that lie in the loop are kept (`LassoCut.pick`), only inside the loop (`LassoCut.keep`). When
/// Vision finds nothing there (a flat thing on a busy table), the loop itself is the outline.
nonisolated enum LassoCutout {
    /// The crop round the loop is this much bigger on every side, so Vision sees the thing's edge.
    static let margin: CGFloat = 0.04

    /// `loop`: 0–1 of the upright photo. Heavy: runs Vision; call off the main thread.
    static func cut(_ photo: UIImage, loop: [CGPoint]) -> UIImage? {
        guard LassoCut.isLoop(loop) else { return nil }
        let upright = ImageTools.resized(photo.normalizedOrientation(), maxSide: 1600)
        guard let cg = upright.cgImage else { return nil }
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let b = LassoCut.bounds(loop)
        let crop = CGRect(x: (b.minX - margin) * W, y: (b.minY - margin) * H,
                          width: (b.width + margin * 2) * W, height: (b.height + margin * 2) * H)
            .integral.intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard crop.width >= 8, crop.height >= 8, let piece = cg.cropping(to: crop) else { return nil }
        // The loop in the crop's own 0–1.
        let local = loop.map { CGPoint(x: ($0.x * W - crop.minX) / crop.width, y: ($0.y * H - crop.minY) / crop.height) }
        if let masks = InstanceMasks.make(from: piece), let grid = masks.labelMaskCopy() {
            let inside = LassoCut.inside(local, width: grid.width, height: grid.height)
            let labels = LassoCut.pick(mask: grid.mask, inside: inside, width: grid.width, height: grid.height)
            if !labels.isEmpty {
                let bits = LassoCut.keep(mask: grid.mask, labels: labels, inside: inside, width: grid.width, height: grid.height)
                let keep = CatchPlan.Keep(width: grid.width, height: grid.height, bits: bits)
                if let c = masks.cut(instances: IndexSet(labels), keep: keep) { return UIImage(cgImage: c.cg) }
            }
        }
        return clipped(piece, loop: local)
    }

    /// The crop with everything outside the loop made transparent, trimmed to the loop.
    static func clipped(_ piece: CGImage, loop: [CGPoint]) -> UIImage? {
        let w = piece.width, h = piece.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // CGContext's origin is bottom-left; the loop's is top-left.
        let path = CGMutablePath()
        path.addLines(between: loop.map { CGPoint(x: $0.x * CGFloat(w), y: (1 - $0.y) * CGFloat(h)) })
        path.closeSubpath()
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(piece, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let full = ctx.makeImage() else { return nil }
        let r = path.boundingBoxOfPath.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        let top = CGRect(x: r.minX, y: CGFloat(h) - r.maxY, width: r.width, height: r.height).integral
        guard let trimmed = full.cropping(to: top) else { return UIImage(cgImage: full) }
        return UIImage(cgImage: trimmed)
    }
}
