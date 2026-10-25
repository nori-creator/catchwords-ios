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

    static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}

/// Draws its content (a whole spread laid out for the turn, see `pageCurl`) as a page being turned. Animatable, so a
/// turn let go of runs on by itself, frame by frame, from wherever the finger left it.
struct PageCurl: ViewModifier, Animatable {
    var progress: CGFloat
    var liftY: CGFloat
    var grabY: CGFloat
    var direction: PageTurnDirection
    var size: CGSize

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, liftY) }
        set {
            progress = newValue.first
            liftY = newValue.second
        }
    }

    func body(content: Content) -> some View {
        let g = PageCurlGeometry.make(progress: progress, liftY: liftY, grabY: grabY, size: size)
        content
            .layerEffect(
                ShaderLibrary.pageCurl(
                    .float2(size),
                    .float2(g.fold),
                    .float2(CGPoint(x: g.dir.dx, y: g.dir.dy)),
                    .float(g.radius),
                    .float(size.width / 2),
                    .float(direction == .backward ? 1 : 0)
                ),
                // Every sample stays inside the spread (the back is the spread's own left half), so the layer needs no
                // room around it. A spread's size here padded the layer to three spreads each way — 9000 px wide on
                // iPhone Duo at 3×, past what Metal draws — and the leaf was not drawn at all (CI `spread-curl`).
                maxSampleOffset: .zero,
                isEnabled: size.width > 1
            )
    }
}
