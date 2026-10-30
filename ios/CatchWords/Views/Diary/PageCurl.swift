import SwiftUI

/// Which way a page is being turned in the book (`BookSpreadView`).
enum PageTurnDirection: Equatable {
    /// The right page goes over to the left: the next (newer) day.
    case forward
    /// The left page comes back over to the right: the day before.
    case backward
}

/// The geometry of a page being turned (Shaders/Effects.metal `pageCurl`), from how far it has gone and where the finger
/// holds it. Pure: tested in DiaryTests.
///
/// The model is paper folding with a soft roll. The edge being lifted (`grabY` on the outer edge) is carried to the
/// finger; the fold line is the perpendicular bisector of that move, pulled back by half the roll so the rolled paper
/// still lands under the finger. Early on, a finger held low or high lifts a corner (the fold runs slanted); as the page
/// goes over, the fold turns upright along the spine and the roll tightens to nothing, so at `progress` 1 the leaf lies
/// flat on the other page.
nonisolated struct PageCurlGeometry: Equatable {
    var fold: CGPoint
    var dir: CGVector
    var radius: CGFloat
    /// False when the page has not moved at all (nothing to draw but the page itself).
    var lifted: Bool

    /// - progress: 0 (flat) … 1 (landed on the other page). - liftY: the finger's height. - grabY: where the edge
    ///   was taken. All in the spread's own points; `size` is the whole spread, the spine at its middle. The geometry
    ///   is always for a forward turn: a backward turn is the same seen in a mirror (the shader flips it).
    static func make(progress raw: CGFloat, liftY: CGFloat, grabY: CGFloat, size: CGSize) -> PageCurlGeometry {
        let progress = min(1, max(0, raw))
        let w = size.width, h = max(1, size.height)
        let spine = w / 2
        let page = w - spine
        let corner = CGPoint(x: w, y: min(h, max(0, grabY)))
        let finger = CGPoint(x: w - progress * 2 * page, y: min(h, max(0, liftY)))
        let dx = corner.x - finger.x, dy = corner.y - finger.y
        let dist = (dx * dx + dy * dy).squareRoot()
        guard dist > 0.5 else {
            return PageCurlGeometry(fold: CGPoint(x: w + 1, y: 0), dir: CGVector(dx: 1, dy: 0), radius: 1, lifted: false)
        }
        // The fold turns upright as the page goes over (a slanted fold past the middle would tear the spine).
        let upright = smoothstep(0.30, 0.85, progress)
        var ux = dx / dist + (1 - dx / dist) * upright
        var uy = (dy / dist) * (1 - upright)
        let len = max(0.0001, (ux * ux + uy * uy).squareRoot())
        ux /= len
        uy /= len
        // The roll: a page's tenth at most, never more than the distance travelled allows, gone as the page lands.
        let rMax = min(page * 0.11, 44)
        var radius = rMax * (1 - smoothstep(0.72, 1.0, progress))
        radius = min(radius, dist / .pi)
        let mid = CGPoint(x: (corner.x + finger.x) / 2, y: (corner.y + finger.y) / 2)
        var fold = CGPoint(x: mid.x - ux * (.pi * radius / 2), y: mid.y - uy * (.pi * radius / 2))
        // The fold never crosses the spine.
        fold.x = max(fold.x, spine)
        return PageCurlGeometry(fold: fold, dir: CGVector(dx: ux, dy: uy), radius: max(0.0001, radius), lifted: true)
    }

    /// Where the leaf's back lies flat: the back page, drawn mirrored on the right half (the leaf), reflected over the
    /// line half a roll's length past the fold — a point `x` before the fold shows the leaf at `π r − x` past it.
    /// Its own inverse, so it is also the transform that draws the back page there.
    var backReflection: CGAffineTransform {
        let a = dir.dx, b = dir.dy
        let along = a * fold.x + b * fold.y
        let shift = 2 * along + .pi * radius
        return CGAffineTransform(a: 1 - 2 * a * a, b: -2 * a * b, c: -2 * a * b, d: 1 - 2 * b * b,
                                 tx: a * shift, ty: b * shift)
    }

    static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}

/// A page being turned (`BookSpreadView`), drawn over the spread it uncovers: the leaf's shadow, its front (the page
/// being turned) and its back (the page it becomes), each its own layer with its own shader (Shaders/Effects.metal
/// `pageCurlShadow` / `pageCurlFront` / `pageCurlBack`). The back page is drawn mirrored on the leaf and reflected
/// over the fold (`backReflection`), so the shaders only move a sample within the roll. (One layer with both sides had
/// to sample the back a spread's width away: with that much room the layer was too big and nothing was drawn, without
/// it the back came out blank — CI `spread-curl` / `spread-curl-late`, 2026-10-25.) Animatable, so a turn let go of
/// runs on by itself, frame by frame, from wherever the finger left it.
///
/// A backward turn (the left page coming back over to the right) is a forward one in a mirror: its pages go in
/// mirrored, and the whole leaf is mirrored back.
struct PageCurlLeaf<Front: View, Back: View>: View, Animatable {
    var progress: CGFloat
    var liftY: CGFloat
    var grabY: CGFloat
    var direction: PageTurnDirection
    /// The whole spread.
    var size: CGSize
    /// The page being turned (the right page going forward, the left one going back).
    let front: Front
    /// The page it becomes once it has landed.
    let back: Back

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, liftY) }
        set {
            progress = newValue.first
            liftY = newValue.second
        }
    }

    /// Room the shaders sample around a point: within the roll, at most 0.6 of its largest radius (44 pt).
    private static var sampleRoom: CGSize { CGSize(width: 30, height: 30) }

    var body: some View {
        let g = PageCurlGeometry.make(progress: progress, liftY: liftY, grabY: grabY, size: size)
        let flip: CGFloat = direction == .backward ? -1 : 1
        leaf(g, front: front.scaleEffect(x: flip, y: 1), back: back.scaleEffect(x: flip, y: 1))
            .scaleEffect(x: flip, y: 1)
            .frame(width: size.width, height: size.height)
    }

    private func leaf(_ g: PageCurlGeometry, front: some View, back: some View) -> some View {
        let page = CGSize(width: size.width / 2, height: size.height)
        let dir = CGPoint(x: g.dir.dx, y: g.dir.dy)
        let on = g.lifted && size.width > 1
        return ZStack(alignment: .topLeading) {
            // The leaf's shadow on the page it uncovers, its own plain layer (Shaders/Effects.metal `pageCurlShadow`).
            Rectangle()
                .fill(.black)
                .frame(width: page.width, height: page.height)
                .colorEffect(
                    ShaderLibrary.pageCurlShadow(.float2(CGPoint(x: g.fold.x - page.width, y: g.fold.y)), .float2(dir),
                                                 .float(g.radius)),
                    isEnabled: on
                )
                .opacity(on ? 1 : 0)
                .offset(x: page.width)
            front
                .frame(width: page.width, height: page.height)
                .offset(x: page.width)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .layerEffect(
                    ShaderLibrary.pageCurlFront(.float2(size), .float2(g.fold), .float2(dir), .float(g.radius),
                                                .float(page.width)),
                    maxSampleOffset: Self.sampleRoom,
                    isEnabled: on
                )
            back
                .frame(width: page.width, height: page.height)
                .scaleEffect(x: -1, y: 1)
                .offset(x: page.width)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .transformEffect(g.backReflection)
                .layerEffect(
                    ShaderLibrary.pageCurlBack(.float2(g.fold), .float2(dir), .float(g.radius)),
                    maxSampleOffset: Self.sampleRoom,
                    isEnabled: on
                )
                .opacity(on ? 1 : 0)
        }
    }
}
