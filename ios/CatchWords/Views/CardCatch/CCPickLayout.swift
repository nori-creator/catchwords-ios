import UIKit

/// Where each word's tag sits over the photo, and which object a tap on the photo means.
/// Every tag starts at its object (the card catch prototype: the object's top centre; the candidates screen:
/// centred on `CatchObject.anchor`, deep inside the object's Vision instance — the AI's point only without one).
/// With several objects close together (or two names for one thing) the tags covered each other and some could
/// not be chosen: a tag only moves (up or down) when it would overlap another one. However near the photo's edge
/// its object is, a tag stays inside the area (`anchor(at:size:in:)`; one wider than the area is centred).
enum CCPickLayout {
    /// The space the tags live in: its width, and where a tag's bottom edge may go.
    struct Area {
        var width: CGFloat
        var minBottom: CGFloat
        var maxBottom: CGFloat
        /// The least distance of a tag's centre from either side.
        var sideClamp: CGFloat

        /// The 390×844 prototype screen: below the pill, above 撮り直す.
        static let design = Area(width: CCSpace.w, minBottom: 170, maxBottom: CCSpace.h - 110, sideClamp: 60)
    }

    /// The tags' bottom edge stays between these (design points): below the pill, above 撮り直す.
    static let minBottom: CGFloat = Area.design.minBottom
    static let maxBottom: CGFloat = Area.design.maxBottom
    /// The prototype's horizontal clamp of the tag's centre.
    static let sideClamp: CGFloat = Area.design.sideClamp
    /// Space kept between two tags.
    static let gap: CGFloat = 6

    /// The tag's font (CandidatePickerView.tag draws its name with exactly this).
    static let tagFontSize: CGFloat = 13

    /// The width of the 「言い方の数」 badge after a name (CandidatePickerView draws it exactly this wide).
    static let badgeWidth: CGFloat = 32

    /// A tag's size for a name: 8 + dot 10 + 7 + text (+ 7 + badge) + 12 wide, 7 + line + 7 high.
    static func tagSize(name: String, badge: Bool = false) -> CGSize {
        let font = UIFont.systemFont(ofSize: tagFontSize, weight: .heavy)
        let w = (name as NSString).size(withAttributes: [.font: font]).width
        return CGSize(width: ceil(w) + 37 + (badge ? 7 + badgeWidth : 0),
                      height: ceil(max(badge ? 18 : 10, font.lineHeight)) + 14)
    }

    /// The tag's x, kept inside the area.
    private static func clampX(_ x: CGFloat, size: CGSize, in area: Area) -> CGFloat {
        let side = max(area.sideClamp, size.width / 2 + 8)
        return side * 2 > area.width ? area.width / 2 : max(side, min(area.width - side, x))
    }

    /// The tag's own place (its bottom centre), as the prototype puts it: the object's top centre.
    static func anchor(for rect: CGRect, size: CGSize, in area: Area = .design) -> CGPoint {
        CGPoint(x: clampX(rect.midX, size: size, in: area), y: max(area.minBottom, rect.minY + 6))
    }

    /// The tag's own place (its bottom centre) when it sits centred on `point`, inside the area.
    static func anchor(at point: CGPoint, size: CGSize, in area: Area) -> CGPoint {
        let y = max(area.minBottom, min(area.maxBottom, point.y + size.height / 2))
        return CGPoint(x: clampX(point.x, size: size, in: area), y: y)
    }

    /// The rect a tag covers when its bottom centre is at `p`.
    static func frame(bottomCenter p: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: p.x - size.width / 2, y: p.y - size.height, width: size.width, height: size.height)
    }

    /// Every tag's bottom centre, each starting at its object's top centre (`anchor(for:size:in:)`).
    static func layout(rects: [CGRect], sizes: [CGSize], in area: Area = .design) -> [CGPoint] {
        let anchors = rects.enumerated().map { i, r in
            anchor(for: r, size: i < sizes.count ? sizes[i] : CGSize(width: 80, height: 30), in: area)
        }
        return layout(anchors: anchors, sizes: sizes, in: area)
    }

    /// Every tag's bottom centre. Tags are placed in the given order (the first keeps its own place); a tag
    /// that would overlap one already placed moves to the nearest free place just above or below the tags it
    /// meets, inside `minBottom…maxBottom`. When nothing is free it stays at its own place.
    static func layout(anchors: [CGPoint], sizes: [CGSize], in area: Area) -> [CGPoint] {
        var placed: [CGRect] = []
        var out: [CGPoint] = []
        for (i, a) in anchors.enumerated() {
            let size = i < sizes.count ? sizes[i] : CGSize(width: 80, height: 30)
            func free(_ y: CGFloat) -> Bool {
                let f = frame(bottomCenter: CGPoint(x: a.x, y: y), size: size).insetBy(dx: -gap / 2, dy: -gap / 2)
                return !placed.contains { $0.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(f) }
            }
            var y = a.y
            if !free(y) {
                var options: [CGFloat] = []
                for p in placed {
                    options.append(p.maxY + gap + 1 + size.height)   // just below that tag
                    options.append(p.minY - gap - 1)                 // just above it
                }
                let low = area.minBottom, high = max(area.maxBottom, a.y)
                let best = options
                    .filter { $0 >= low && $0 <= high && free($0) }
                    .min { abs($0 - a.y) < abs($1 - a.y) }
                if let best { y = best }
            }
            let p = CGPoint(x: a.x, y: y)
            out.append(p)
            placed.append(frame(bottomCenter: p, size: size))
        }
        return out
    }

    /// The object a tap at `p` (design points) means: of the objects whose box holds the point, the smallest
    /// (a small thing in front of a big one stays reachable); between boxes of about the same size, the one
    /// whose centre is nearest. nil = the tap is on no object.
    static func object(at p: CGPoint, rects: [CGRect]) -> Int? {
        let hits = rects.indices.filter { rects[$0].contains(p) }
        return hits.min { a, b in
            let ra = rects[a], rb = rects[b]
            let areaA = ra.width * ra.height, areaB = rb.width * rb.height
            if abs(areaA - areaB) > 0.1 * max(areaA, areaB) { return areaA < areaB }
            return distance(p, ra) < distance(p, rb)
        }
    }

    private static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = p.x - r.midX, dy = p.y - r.midY
        return dx * dx + dy * dy
    }
}
