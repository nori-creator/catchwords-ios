import CoreGraphics
import Foundation

/// 囲んで切り抜き直す (owner 2026-11-04: 「切り抜いたあとの画像を、指でその物体をサークルで囲うと切り抜きをその部分やり直す
/// 機能をつけて」): the learner draws a loop round the thing on the original photo, and the photo is cut along the loop
/// (`LassoCutout`). Owner 2026-11-09: the loop is the cut-out — 「どんな形でサークルを作っても切り抜きが一つにしかなってない」
/// (Vision's thing in the loop was kept, whatever the loop: the food in a stone bowl, never the bowl); 「自動で切り抜いて切り
/// 抜きが気に食わないから切り抜こうとしてんのに自動で切り抜くって意味がわからない」. The pure part (the loop's area, its
/// bounds, its smoothing), so CardCatchPickTests checks it.
nonisolated enum LassoCut {
    /// A loop smaller than this share of the photo is a slip of the finger, not a loop round a thing.
    static let minArea: CGFloat = 0.002
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

    /// The loop with each point moved to the average of its neighbours (`reach` on each side, the loop closed), `passes`
    /// times: a finger's wobble is not cut into the edge.
    static func smoothed(_ loop: [CGPoint], reach: Int = 2, passes: Int = 2) -> [CGPoint] {
        guard loop.count > reach * 2 + 2 else { return loop }
        var pts = loop
        let n = pts.count
        for _ in 0..<max(0, passes) {
            let src = pts
            for i in 0..<n {
                var x: CGFloat = 0, y: CGFloat = 0
                for k in -reach...reach {
                    let p = src[(i + k + n) % n]
                    x += p.x
                    y += p.y
                }
                let c = CGFloat(reach * 2 + 1)
                pts[i] = CGPoint(x: x / c, y: y / c)
            }
        }
        return pts
    }
}
