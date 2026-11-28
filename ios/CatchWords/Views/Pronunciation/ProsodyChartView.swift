import SwiftUI

/// The coach's pitch chart. One column per syllable, as wide as the natives make it. The blue band is the natives'
/// range (mean ± spread of their recordings, on each speaker's own 1…5 scale), the dashed line its middle; the learner's
/// curve is drawn on their own scale over it, green inside the range, yellow close, red off. While recording, the live
/// curve runs across the whole chart.
struct ProsodyChartView: View {
    let syllables: [WordTones.Syllable]
    let band: ProsodyBand?
    /// The learner's take on their own scale (nil before the first try).
    var take: [NormalizedSyllable]? = nil
    /// Each syllable's score (colours the learner's curve).
    var totals: [Int]? = nil
    /// While recording: the live pitch as levels (nil = no voice).
    var live: [Double?]? = nil
    var height: CGFloat = 230

    private static let labelRow: CGFloat = 44
    private static let axis: CGFloat = 18

    var body: some View {
        Canvas { ctx, size in
            draw(&ctx, size: size)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(L("声の高さのグラフ"))
    }

    // MARK: - Layout

    private func columns(in plot: CGRect) -> [ClosedRange<CGFloat>] {
        let n = max(1, syllables.count)
        let gap: CGFloat = n > 1 ? 8 : 0
        var shares = band?.syllables.map(\.share) ?? []
        if shares.count != n { shares = Array(repeating: 1 / Double(n), count: n) }
        // Never so thin that the character under it does not fit.
        shares = shares.map { max($0, 0.6 / Double(n)) }
        let total = shares.reduce(0, +)
        let width = plot.width - gap * CGFloat(n - 1)
        var x = plot.minX
        return shares.map { s in
            let w = width * CGFloat(s / total)
            defer { x += w + gap }
            return x...(x + w)
        }
    }

    private func y(_ level: Double, _ plot: CGRect) -> CGFloat {
        let v = min(max(level, 0.5), 5.5)
        return plot.maxY - CGFloat((v - 0.5) / 5) * plot.height
    }

    private func x(_ column: ClosedRange<CGFloat>, _ k: Int) -> CGFloat {
        let t = 0.05 + 0.9 * Double(k) / Double(ProsodyAnalyzer.points - 1)
        return column.lowerBound + (column.upperBound - column.lowerBound) * CGFloat(t)
    }

    static func color(_ total: Int?) -> Color {
        guard let total else { return Theme.primaryInk }
        if total >= ProsodyScore.good { return Theme.ok }
        if total >= ProsodyScore.close { return Theme.gold }
        return Theme.destructive
    }

    // MARK: - Drawing

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let plot = CGRect(x: Self.axis, y: 6, width: size.width - Self.axis - 4, height: size.height - Self.labelRow - 6)
        let cols = columns(in: plot)

        // The five levels.
        for level in 1...5 {
            let yy = y(Double(level), plot)
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: yy))
            line.addLine(to: CGPoint(x: plot.maxX, y: yy))
            ctx.stroke(line, with: .color(Theme.border), style: StrokeStyle(lineWidth: 1, dash: level == 3 ? [] : [3, 4]))
            ctx.draw(Text(verbatim: "\(level)").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted),
                     at: CGPoint(x: plot.minX - 9, y: yy), anchor: .center)
        }

        // The natives' band, then its middle.
        let faded = live != nil
        if let band, band.syllables.count == cols.count {
            for (i, s) in band.syllables.enumerated() {
                let col = cols[i]
                let upper = (0..<s.levels.count).map { CGPoint(x: x(col, $0), y: y(s.levels[$0] + s.halfWidth($0), plot)) }
                let lower = (0..<s.levels.count).map { CGPoint(x: x(col, $0), y: y(s.levels[$0] - s.halfWidth($0), plot)) }
                var area = Self.smooth(upper)
                if let first = lower.last { area.addLine(to: first) }
                Self.append(lower.reversed(), to: &area)
                area.closeSubpath()
                ctx.fill(area, with: .color(Theme.primary.opacity(faded ? 0.08 : 0.16)))
                let middle = Self.smooth((0..<s.levels.count).map { CGPoint(x: x(col, $0), y: y(s.levels[$0], plot)) })
                ctx.stroke(middle, with: .color(Theme.primary.opacity(faded ? 0.3 : 0.6)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
            }
        }

        // The learner's curve, syllable by syllable.
        if live == nil, let take, take.count == cols.count {
            for (i, s) in take.enumerated() {
                let col = cols[i]
                let points = (0..<s.levels.count).map { CGPoint(x: x(col, $0), y: y(s.levels[$0], plot)) }
                let color = Self.color(totals?[safe: i])
                ctx.stroke(Self.smooth(points), with: .color(color),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                if let end = points.last {
                    ctx.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)), with: .color(color))
                }
            }
        }

        // The live curve.
        if let live, !live.isEmpty {
            let window = max(250, live.count)
            var segment: [CGPoint] = []
            func flush() {
                if segment.count > 1 {
                    ctx.stroke(Self.smooth(segment), with: .color(Theme.primaryInk),
                               style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                }
                segment.removeAll()
            }
            for (i, v) in live.enumerated() {
                guard let v else { flush(); continue }
                segment.append(CGPoint(x: plot.minX + plot.width * CGFloat(i) / CGFloat(window - 1), y: y(v, plot)))
            }
            flush()
        }

        // Each syllable: its character and pinyin under its column.
        for (i, s) in syllables.enumerated() where i < cols.count {
            let mid = (cols[i].lowerBound + cols[i].upperBound) / 2
            ctx.draw(Text(verbatim: s.char).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.foreground),
                     at: CGPoint(x: mid, y: plot.maxY + 16), anchor: .center)
            ctx.draw(Text(verbatim: s.pinyin).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted),
                     at: CGPoint(x: mid, y: plot.maxY + 35), anchor: .center)
        }
    }

    // MARK: - Smooth lines (Catmull–Rom through every point)

    static func smooth(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        append(points, to: &path)
        return path
    }

    /// Continues `path` (already at `points[0]`) through the rest of the points.
    static func append(_ points: [CGPoint], to path: inout Path) {
        guard points.count > 1 else { return }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[min(points.count - 1, i + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }
}

/// How long each syllable lasts, the natives' next to the learner's: two bars cut into syllables.
struct TimingBarsView: View {
    let syllables: [WordTones.Syllable]
    let band: ProsodyBand
    let take: [NormalizedSyllable]
    let score: ProsodyScore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(L("手本"), shares: band.syllables.map(\.share), colors: band.syllables.map { _ in Theme.primary.opacity(0.18) },
                ink: Theme.primaryInk)
            row(L("あなた"), shares: take.map(\.share),
                colors: score.syllables.map { ProsodyChartView.color(Int(($0.length * 100).rounded())).opacity(0.22) },
                ink: Theme.foreground)
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ title: String, shares: [Double], colors: [Color], ink: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Theme.muted)
                .frame(width: 52, alignment: .leading)
            GeometryReader { geo in
                let total = max(shares.reduce(0, +), 1e-6)
                let gap: CGFloat = 3
                let width = geo.size.width - gap * CGFloat(max(0, shares.count - 1))
                HStack(spacing: gap) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { i, s in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(colors[safe: i] ?? Theme.secondary)
                            .frame(width: max(18, width * CGFloat(s / total)))
                            .overlay(
                                Text(verbatim: syllables[safe: i]?.char ?? "")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(ink)
                            )
                    }
                }
            }
            .frame(height: 26)
        }
    }
}
