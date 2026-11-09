import CoreGraphics
import UIKit

/// 囲んで切り抜き直す (owner 2026-11-04): the cut-out made again from the loop the learner drew on the original photo
/// (`LassoCutoutView`). The photo is cut along the loop itself, smoothed a little (`LassoCut.smoothed`): owner 2026-11-09
/// 「どんな形でサークルを作っても切り抜きが一つにしかなってない」 — Vision ran again in the loop and its thing was kept, so a loop
/// round a stone bowl and its board still gave the food alone. The learner draws the loop because the automatic cut-out
/// was wrong; what they drew is what they get.
nonisolated enum LassoCutout {
    /// `loop`: 0–1 of the upright photo. Call off the main thread (it draws the photo).
    static func cut(_ photo: UIImage, loop: [CGPoint]) -> UIImage? {
        guard LassoCut.isLoop(loop) else { return nil }
        let upright = ImageTools.resized(photo.normalizedOrientation(), maxSide: 1600)
        guard let cg = upright.cgImage else { return nil }
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let b = LassoCut.bounds(loop)
        let crop = CGRect(x: b.minX * W, y: b.minY * H, width: b.width * W, height: b.height * H)
            .insetBy(dx: -2, dy: -2).integral.intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard crop.width >= 8, crop.height >= 8, let piece = cg.cropping(to: crop) else { return nil }
        // The loop in the crop's own 0–1.
        let local = LassoCut.smoothed(loop).map {
            CGPoint(x: ($0.x * W - crop.minX) / crop.width, y: ($0.y * H - crop.minY) / crop.height)
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
