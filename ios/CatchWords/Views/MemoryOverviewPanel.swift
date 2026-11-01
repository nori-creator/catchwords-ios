import SwiftUI
import Charts

/// review.tsx MemoryOverviewPanel + MiniRetentionGraph: every reviewed word from weakest to
/// strongest (tap → forgetting curve), then 「全体の記憶率（前後2週間）」.
struct MemoryOverviewPanel: View {
    @Environment(DexStore.self) private var dex
    @Environment(AppRouter.self) private var router: AppRouter?
    let store: ReviewStore
    let onOpenWord: (Sticker) -> Void

    private var rows: [(Sticker, Int)] {
        dex.stickers.compactMap { s in dex.memoryPercent(for: s).map { (s, $0) } }
            .sorted { $0.1 == $1.1 ? ($0.0.word?.headword ?? "") < ($1.0.word?.headword ?? "") : $0.1 < $1.1 }
    }

    /// iPhone Duo open and held sideways: the words on the left, the overall chart on the right (owner 2026-10-30:
    /// 「記憶の状態…大きい画面を利用して右左に分けて見やすく表示して」).
    @State private var wide = false

    var body: some View {
        let list = rows
        Group {
            if wide || router?.isOpenSideways == true {
                HStack(alignment: .top, spacing: 20) {
                    wordList(list, height: 360).frame(maxWidth: .infinity)
                    overall.frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    wordList(list, height: 330)
                    Divider().overlay(Theme.border).padding(.vertical, 12)
                    overall
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 760 } action: { wide = $0 }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    @ViewBuilder
    private func wordList(_ list: [(Sticker, Int)], height: CGFloat) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(list, id: \.0.id) { s, pct in row(s, pct) }
                    }
                    .padding(.vertical, 6)
                }
                .frame(height: min(CGFloat(list.count) * 50 + 12, height))
                .scrollIndicators(.visible)

                Text(L("タップで単語ごとの忘却曲線と「いつ忘れるか」の予測が見られます"))
                    .scaledFont(size: 12).foregroundStyle(Theme.muted)
                    .padding(.top, 8)
            }
        }
    }

    private var overall: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("全体の記憶率（前後2週間）"))
                .scaledFont(size: 12, weight: .semibold).foregroundStyle(Theme.muted)
            RetentionMiniChart(data: store.retentionSeries(dex: dex))
                .padding(.top, 6)
        }
    }

    private func row(_ s: Sticker, _ pct: Int) -> some View {
        let lv = MemoryBadge.level(pct)
        let c = Theme.memoryLevels[lv]
        let ink = c.mix(with: Theme.foreground, by: 0.35)
        return Button { Haptics.selection(); onOpenWord(s) } label: {
            HStack(spacing: 10) {
                Text(s.word?.headword ?? "")
                    .scaledFont(size: 16, weight: .medium).foregroundStyle(Theme.foreground)
                    .lineLimit(1).minimumScaleFactor(0.45)
                    .frame(width: 76, alignment: .leading)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.secondary)
                        Capsule().fill(c).frame(width: g.size.width * CGFloat(pct) / 100)
                    }
                }
                .frame(height: 8)
                Text("\(pct)%").scaledFont(size: 12, weight: .semibold, monospacedDigit: true).foregroundStyle(ink)
                    .frame(width: 36, alignment: .trailing)
                Text(MemoryBadge.labels[lv])
                    .scaledFont(size: 11, weight: .medium).foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 60).padding(.vertical, 4)
                    .background(c.opacity(0.14), in: Capsule())
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityLabel("\(s.word?.headword ?? "") \(MemoryBadge.labels[lv]) \(pct)%")
    }
}

/// memory-chart-parts.tsx: what the two memory charts share (the overall retention chart here and each word's
/// forgetting curve) — the plot's ground painted in the memory levels' bands, the y ticks on the band edges
/// with the bottom pulled up to the data, one primary line (solid so far, dashed if not reviewed) and a legend.
enum MemoryChartStyle {
    /// memory-curve.ts LEVEL_EDGES (the same edges as `MemoryBadge.level`).
    static let edges: [Double] = [30, 50, 70, 85, 95]

    /// The y axis' bottom: the highest band edge at least 3 points under the lowest value.
    static func yMin(_ values: [Double]) -> Double {
        let low = min(values.min() ?? 100, 100)
        for b in [70.0, 50, 30] where b <= low - 3 { return b }
        return 0
    }

    struct Band: Identifiable {
        let level: Int
        let lo: Double
        let hi: Double
        var id: Int { level }
    }

    /// The level bands from `yMin` up to 100.
    static func bands(yMin: Double) -> [Band] {
        var all: [Double] = [0]
        all.append(contentsOf: edges)
        all.append(100)
        var out: [Band] = []
        for level in 0..<(all.count - 1) where all[level + 1] > yMin {
            out.append(Band(level: level, lo: max(all[level], yMin), hi: all[level + 1]))
        }
        return out
    }

    /// The y ticks: the band edges, minus any closer than 10% of the axis to the one above; the bottom always.
    static func ticks(yMin: Double) -> [Double] {
        let minGap = (100 - yMin) * 0.1
        var candidates: [Double] = [100]
        candidates.append(contentsOf: edges.reversed())
        candidates.append(0)
        var kept: [Double] = []
        for e in candidates where e > yMin {
            if let last = kept.last {
                if last - e >= minGap { kept.append(e) }
            } else {
                kept.append(e)
            }
        }
        if let last = kept.last, last - yMin < minGap { kept.removeLast() }
        kept.append(yMin)
        return kept.sorted()
    }

    /// `.mem-band`: the level's colour mixed into the card (opaque, so the bands read on a white screen).
    static func bandFill(_ level: Int) -> Color {
        Theme.memoryLevels[level].mix(with: Theme.card, by: 0.72)
    }

    /// `.mem-band-label`: the level's colour pulled toward the text colour.
    static func bandInk(_ level: Int) -> Color {
        Theme.memoryLevels[level].mix(with: Theme.foreground, by: 0.45)
    }

    /// The bands under the lines (drawn first), each named at its left when it is tall enough for the text.
    @ChartContentBuilder
    static func bandMarks(_ bands: [Band], from: Date, to: Date, yMin: Double, plotHeight: CGFloat) -> some ChartContent {
        ForEach(bands) { b in
            RectangleMark(xStart: .value("date", from), xEnd: .value("date", to),
                          yStart: .value("%", b.lo), yEnd: .value("%", b.hi))
                .foregroundStyle(bandFill(b.level))
                .annotation(position: .overlay, alignment: .leading, spacing: 0) {
                    if CGFloat((b.hi - b.lo) / max(1, 100 - yMin)) * plotHeight >= 11 {
                        Text(MemoryBadge.labels[b.level])
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(bandInk(b.level))
                            .lineLimit(1)
                            .padding(.leading, 6)
                    }
                }
        }
        // A thin line of the card's colour between two bands.
        ForEach(bands.filter { $0.hi < 100 }) { b in
            RuleMark(y: .value("%", b.hi))
                .foregroundStyle(Theme.card)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }
}

/// ChartLegend: so far (solid), if not reviewed (dashed), and — on a word's curve — the days it was reviewed.
struct MemoryChartLegend: View {
    var reviews: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            item(dashed: false, text: L("これまで"))
            item(dashed: true, text: L("復習しなかったら"))
            if reviews {
                HStack(spacing: 4) {
                    Circle().fill(Theme.card)
                        .overlay(Circle().stroke(Theme.primary, lineWidth: 2))
                        .frame(width: 8, height: 8)
                    Text(L("復習した日"))
                }
            }
        }
        .scaledFont(size: 12)
        .foregroundStyle(Theme.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityHidden(true)
    }

    private func item(dashed: Bool, text: String) -> some View {
        HStack(spacing: 4) {
            Path { p in
                p.move(to: CGPoint(x: 1, y: 3))
                p.addLine(to: CGPoint(x: 17, y: 3))
            }
            .stroke(Theme.primary, style: StrokeStyle(lineWidth: 2.5, dash: dashed ? [4, 3] : []))
            .frame(width: 18, height: 6)
            Text(text)
        }
    }
}

/// MiniRetentionGraph: 全体の記憶率（前後2週間）. The ground is painted in the memory bands; one primary line,
/// solid for the past (rebuilt from the record) and dashed for the projection; today's dot with 「今日 n%」.
/// A finger traces the line to read any day.
struct RetentionMiniChart: View {
    let data: (series: [RetentionPoint], today: Int?)
    var height: CGFloat = 176

    @State private var scrubDate: Date?
    @State private var lastScrubDay: Int?

    var body: some View {
        if data.series.isEmpty {
            Text(L("復習を始めると、ここに記憶率の推移が出ます"))
                .scaledFont(size: 13).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                MemoryChartLegend()
                chart.frame(height: height)
            }
        }
    }

    private static func nearest(_ d: Date, in pts: [RetentionPoint]) -> RetentionPoint? {
        pts.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) }
    }

    private var chart: some View {
        let past = data.series.filter { $0.dayOffset <= 0 && $0.value != nil }
        let future = data.series.filter { $0.dayOffset >= 0 && $0.value != nil }
        var values = data.series.compactMap(\.value)
        if let t = data.today { values.append(Double(t)) }
        let yMin = MemoryChartStyle.yMin(values)
        let bands = MemoryChartStyle.bands(yMin: yMin)
        let ticks = MemoryChartStyle.ticks(yMin: yMin)
        let first = data.series.first?.date ?? Date()
        let last = data.series.last?.date ?? Date()
        let todayDate = data.series.first(where: { $0.dayOffset == 0 })?.date ?? Date()
        let picked: RetentionPoint? = scrubDate.flatMap { Self.nearest($0, in: past + future) }
        let scrubbing = picked != nil
        return Chart {
            MemoryChartStyle.bandMarks(bands, from: first, to: last, yMin: yMin, plotHeight: height - 22)
            ForEach(future) { p in
                LineMark(x: .value("date", p.date), y: .value("%", p.value ?? 0), series: .value("s", "future"))
                    .foregroundStyle(Theme.primary)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 5]))
            }
            ForEach(past) { p in
                LineMark(x: .value("date", p.date), y: .value("%", p.value ?? 0), series: .value("s", "past"))
                    .foregroundStyle(Theme.primary)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            if let t = data.today {
                PointMark(x: .value("date", todayDate), y: .value("%", Double(t)))
                    .symbol {
                        Circle().fill(Theme.primary)
                            .overlay(Circle().stroke(Theme.card, lineWidth: 3))
                            .frame(width: 14, height: 14)
                    }
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        if !scrubbing {
                            Text(L("今日 \(t)%"))
                                .scaledFont(size: 12, weight: .bold)
                                .foregroundStyle(Theme.foreground)
                        }
                    }
            }
            if let picked {
                RuleMark(x: .value("date", picked.date))
                    .foregroundStyle(Theme.muted.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                PointMark(x: .value("date", picked.date), y: .value("%", picked.value ?? 0))
                    .symbol {
                        Circle().fill(Theme.primary)
                            .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                            .frame(width: 12, height: 12)
                    }
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        VStack(spacing: 1) {
                            Text(Calendar.current.isDateInToday(picked.date) ? L("今日") : JPDate.monthDay(picked.date))
                                .scaledFont(size: 11, weight: .semibold).foregroundStyle(Theme.muted)
                            Text("\(Int((picked.value ?? 0).rounded()))%")
                                .scaledFont(size: 15, weight: .heavy, monospacedDigit: true)
                                .foregroundStyle(Theme.foreground)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.card, in: .rect(cornerRadius: 9, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                    }
            }
        }
        // VoiceOver reads the chart as one element in the display language (each mark's own label would be the
        // plotted values' names — "date", "s", "future" — in English).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("記憶の曲線"))
        .accessibilityValue(data.today.map { L("今日 \($0)%") } ?? "")
        .chartXSelection(value: $scrubDate)
        .onChange(of: scrubDate) { _, new in
            // A light tick each time the finger crosses into another day.
            guard let new else { lastScrubDay = nil; return }
            let day = Calendar.current.ordinality(of: .day, in: .era, for: new)
            if day != lastScrubDay { Haptics.selection(); lastScrubDay = day }
        }
        .chartYScale(domain: yMin...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { v in
                AxisValueLabel {
                    Text("\(Int((v.as(Double.self) ?? 0).rounded()))%")
                        .scaledFont(size: 10).foregroundStyle(Theme.muted)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: [first, todayDate, last]) { v in
                AxisValueLabel(anchor: .top) {
                    if let d = v.as(Date.self) {
                        Text(Calendar.current.isDateInToday(d) ? L("今日") : JPDate.slash(d))
                            .scaledFont(size: 11).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }
}
