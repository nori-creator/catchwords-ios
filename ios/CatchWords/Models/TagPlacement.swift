import UIKit

/// Where a thing's name tag goes on the screen (owner 2026-10-15: 「正確にもののうえに名前のタグを置いて。適当に真ん中では
/// なく。」 — four tags, stylus / tablet / cup / tissue, sat in one pile in the middle of the tablet). Pure maths, so
/// TagPlacementTests checks every step without a photo or Vision:
/// - the photo's own coordinates (0–1 of the upright picture, top-left origin — the server's `point` / `box_2d` are
///   0–1000 of the 768 px upload, which is drawn upright before it is sent, and Vision's masks are made from the same
///   upright bitmap) go through the rect the photo really covers on the stage (`displayedRect`: scaledToFill crops,
///   scaledToFit letterboxes — a tag used to be placed as if the photo filled the stage exactly);
/// - a bitmap still carrying its EXIF orientation is turned upright first (`uprightPoint`), never read as stored;
/// - a position the AI did not give, or gave twice (the same box for two things), is not "the middle": such a tag goes
///   to a free Vision instance (`CatchObject.build`) or, failing that, to its own spot spread over the photo
///   (`spreadSpots`), so tags never gather at one point.
nonisolated enum TagPlacement {
    enum Mode: Sendable {
        /// `scaledToFill`: the photo covers the stage and its edges are cropped (the words screen).
        case fill
        /// `scaledToFit`: the whole photo shows, with empty bands on two sides.
        case fit
    }

    /// Where a photo of `image` size sits inside `stage` (stage points, top-left origin).
    static func displayedRect(image: CGSize, in stage: CGSize, mode: Mode) -> CGRect {
        guard image.width > 0, image.height > 0, stage.width > 0, stage.height > 0 else {
            return CGRect(origin: .zero, size: stage)
        }
        let sx = stage.width / image.width, sy = stage.height / image.height
        let scale = mode == .fill ? max(sx, sy) : min(sx, sy)
        let w = image.width * scale, h = image.height * scale
        return CGRect(x: (stage.width - w) / 2, y: (stage.height - h) / 2, width: w, height: h)
    }

    /// A point of the photo (0–1, top-left origin) on the stage.
    static func stagePoint(_ p: CGPoint, image: CGSize, in stage: CGSize, mode: Mode) -> CGPoint {
        stagePoint(p, in: displayedRect(image: image, in: stage, mode: mode))
    }

    /// A point of the photo (0–1) inside the rect the photo covers.
    static func stagePoint(_ p: CGPoint, in displayed: CGRect) -> CGPoint {
        CGPoint(x: displayed.minX + p.x * displayed.width, y: displayed.minY + p.y * displayed.height)
    }

    /// A rect of the photo (0–1) on the stage.
    static func stageRect(_ r: CGRect, image: CGSize, in stage: CGSize, mode: Mode) -> CGRect {
        stageRect(r, in: displayedRect(image: image, in: stage, mode: mode))
    }

    static func stageRect(_ r: CGRect, in displayed: CGRect) -> CGRect {
        CGRect(x: displayed.minX + r.minX * displayed.width, y: displayed.minY + r.minY * displayed.height,
               width: r.width * displayed.width, height: r.height * displayed.height)
    }

    // MARK: EXIF orientation

    /// The size the picture has once it is drawn upright (a camera photo is stored on its side, `.right`).
    static func uprightSize(pixels: CGSize, orientation: UIImage.Orientation) -> CGSize {
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored: CGSize(width: pixels.height, height: pixels.width)
        default: pixels
        }
    }

    /// A point of the stored bitmap (0–1 of the bitmap as it lies in the file, top-left origin) where it shows once the
    /// picture is drawn upright (0–1 of the upright picture). `UIImage.Orientation` names how the bitmap was turned
    /// from the picture: `.right` = the picture is the bitmap turned 90° clockwise, `.left` = 90° counter-clockwise,
    /// `.down` = 180°; the mirrored ones are flipped left-to-right as well.
    static func uprightPoint(_ p: CGPoint, orientation: UIImage.Orientation) -> CGPoint {
        switch orientation {
        case .up: return p
        case .down: return CGPoint(x: 1 - p.x, y: 1 - p.y)
        case .right: return CGPoint(x: 1 - p.y, y: p.x)
        case .left: return CGPoint(x: p.y, y: 1 - p.x)
        case .upMirrored: return CGPoint(x: 1 - p.x, y: p.y)
        case .downMirrored: return CGPoint(x: p.x, y: 1 - p.y)
        case .rightMirrored: return CGPoint(x: p.y, y: p.x)
        case .leftMirrored: return CGPoint(x: 1 - p.y, y: 1 - p.x)
        @unknown default: return p
        }
    }

    /// A rect of the stored bitmap (0–1) as it lies once the picture is upright.
    static func uprightRect(_ r: CGRect, orientation: UIImage.Orientation) -> CGRect {
        let a = uprightPoint(CGPoint(x: r.minX, y: r.minY), orientation: orientation)
        let b = uprightPoint(CGPoint(x: r.maxX, y: r.maxY), orientation: orientation)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: Positions that are missing or shared

    /// Two things cannot be at one point: a position that lies within `tolerance` (0–1 of the photo) of an earlier
    /// one in the list is not its own (the AI drew the same box round two things, or sent the middle for both). nil =
    /// no position at all. The first of a pile keeps its place; the others are treated as having none.
    static func distinct(_ points: [CGPoint?], tolerance: CGFloat = 0.02) -> [Bool] {
        var kept: [CGPoint] = []
        return points.map { p in
            guard let p else { return false }
            if kept.contains(where: { hypot($0.x - p.x, $0.y - p.y) <= tolerance }) { return false }
            kept.append(p)
            return true
        }
    }

    /// Spots over the photo for tags that have no place of their own, each as far from the taken places and from each
    /// other as the candidates allow — the middle first when it is free, then the quarters, the thirds and the
    /// edges' middles. `count` spots come back (the list repeats with small shifts should more be needed than there
    /// are candidates, which four tags never need).
    static func spreadSpots(count: Int, avoiding taken: [CGPoint]) -> [CGPoint] {
        guard count > 0 else { return [] }
        let candidates: [CGPoint] = [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.28, y: 0.34), CGPoint(x: 0.72, y: 0.34), CGPoint(x: 0.28, y: 0.66), CGPoint(x: 0.72, y: 0.66),
            CGPoint(x: 0.5, y: 0.24), CGPoint(x: 0.5, y: 0.76), CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.8, y: 0.5),
            CGPoint(x: 0.35, y: 0.5), CGPoint(x: 0.65, y: 0.5), CGPoint(x: 0.5, y: 0.38), CGPoint(x: 0.5, y: 0.62),
        ]
        var used = taken
        var out: [CGPoint] = []
        for i in 0..<count {
            let shift = CGFloat(i / candidates.count) * 0.05
            let best = candidates.map { CGPoint(x: min(0.9, $0.x + shift), y: min(0.9, $0.y + shift)) }
                .max { a, b in nearest(a, used) < nearest(b, used) } ?? CGPoint(x: 0.5, y: 0.5)
            out.append(best)
            used.append(best)
        }
        return out
    }

    private static func nearest(_ p: CGPoint, _ others: [CGPoint]) -> CGFloat {
        others.map { hypot($0.x - p.x, $0.y - p.y) }.min() ?? .greatestFiniteMagnitude
    }
}
