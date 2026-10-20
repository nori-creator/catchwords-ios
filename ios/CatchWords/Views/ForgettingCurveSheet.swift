import SwiftUI
import Charts

/// ForgettingCurveChart.tsx: the ground painted in the memory bands (MemoryChartStyle), one primary line —
/// solid so far (it jumps back up at each review), dashed "if not reviewed" — review points (hollow), today's
/// dot, and a "now is the time" callout.
struct ForgettingCurveSheet: View {
    @Environment(DexStore.self) private var dex
    let sticker: Sticker
    let store: ReviewStore
    let onReviewNow: () -> Void
    /// Set when shown as the centred card on the review screen (instead of a system sheet).
    var onClose: (() -> Void)? = nil

    /// This word's reviews, oldest first; nil until known. Seeded from the rows the review screen has already read,
    /// so the real curve is drawn at once — never a stand-in line first (owner 2026-10-11: 「グラフを開くときに関係のない
    /// 青いグラフが瞬間的に表示される」).
    @State private var history: [ReviewHistoryRow]?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    /// The day under the finger while tracing the curve (nil when not touching).
    @State private var scrubDate: Date?
    @State private var lastScrubDay: Int?
    /// 0→1 as the curve draws itself from left to right when the sheet opens.
    @State private var reveal: CGFloat = 0

    private struct Pt: Identifiable {
        let date: Date
        let value: Double
        let series: String
        /// Stable across redraws (the same point keeps its identity when the rows are read again).
        var id: String { "\(series)-\(date.timeIntervalSince1970)" }
    }

    init(sticker: Sticker, store: ReviewStore, onReviewNow: @escaping () -> Void, onClose: (() -> Void)? = nil) {
        self.sticker = sticker
        self.store = store
        self.onReviewNow = onReviewNow
        self.onClose = onClose
        let known = store.allHistory.filter { $0.stickerId == sticker.id }.sorted { $0.reviewedAt < $1.reviewedAt }
        _history = State(initialValue: store.historyLoaded || !known.isEmpty ? known : nil)
    }

    private var review: ReviewState? { dex.reviews[sticker.id] }

    var body: some View {
        let pct = dex.memoryPercent(for: sticker) ?? 100
        let lv = MemoryBadge.level(pct)
        ViewThatFits(in: .vertical) {
            sheetContent(pct: pct, lv: lv)
            ScrollView { sheetContent(pct: pct, lv: lv) }
        }
        .task(id: sticker.id) {
            // The word's own read (newer than the screen's when it was just reviewed). An empty answer can also mean
            // the read failed, so it never replaces rows already shown.
            let fresh = await store.history(stickerId: sticker.id)
            if !fresh.isEmpty || history == nil { history = fresh }
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func sheetContent(pct: Int, lv: Int) -> some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(sticker.word?.headword ?? "").scaledFont(size: 26, weight: .heavy).foregroundStyle(Theme.foreground)
                    Spacer()
                    Button { close() } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L("閉じる"))
                }
                HStack(spacing: 12) {
                    HStack(spacing: 5) {
                        Circle().fill(Theme.memoryLevels[lv]).frame(width: 8, height: 8)
                        Text("\(MemoryBadge.labels[lv]) · \(pct)%").scaledFont(size: 15, weight: .bold)
                    }
                    .foregroundStyle(Theme.memoryLevels[lv].mix(with: Theme.foreground, by: 0.3))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.memoryLevels[lv].opacity(0.14), in: Capsule())
                    Text(LocalizedStringKey(L("復習 **\(history?.count ?? 0)** 回"))).scaledFont(size: 15).foregroundStyle(Theme.muted)
                }
                Text(L("縦軸＝いま思い出せる確率（写真の右上の%と同じ）")).scaledFont(size: 13).foregroundStyle(Theme.muted)
                MemoryChartLegend(reviews: true)

                Group {
                    if let history {
                        chart(history)
                            .onAppear {
                                if reduceMotion { reveal = 1 } else { withAnimation(.easeOut(duration: 0.9).delay(0.1)) { reveal = 1 } }
                            }
                    } else {
                        // Nothing until the word's reviews are known (the curve depends on every one of them).
                        Color.clear
                    }
                }
                .frame(height: Self.chartHeight)
                Text(L("グラフを指でなぞると、その日の記憶率が見られます"))
                    .scaledFont(size: 12).foregroundStyle(Theme.muted)

                callout(pct: pct)
            }
            .padding(22)
    }

    private static let chartHeight: CGFloat = 240

    private typealias CurveData = (past: [Pt], future: [Pt], reviews: [Pt], jumps: [Pt], today: Pt)

    private func curveData(_ history: [ReviewHistoryRow]) -> CurveData {
        let now = Date()
        let origin = sticker.takenAt
        var past: [Pt] = []
        var marks: [Pt] = []
        /// Where the line stood just before each review (the review lifts it back to 100%).
        var jumps: [Pt] = []
        var segStart = origin
        var ease = 2.5
        var interval = 0
        var segIndex = 0
        func sample(from a: Date, to b: Date, seg: Int) {
            let span = b.timeIntervalSince(a)
            let steps = max(2, Int(span / 86_400 * 2))
            for i in 0...steps {
                let t = a.addingTimeInterval(span * Double(i) / Double(steps))
                past.append(Pt(date: t, value: Double(MemoryMath.percent(intervalDays: interval, ease: ease, last: a, now: t)), series: "past\(seg)"))
            }
        }
        for h in history where h.reviewedAt <= now {
            sample(from: segStart, to: h.reviewedAt, seg: segIndex)
            jumps.append(Pt(date: h.reviewedAt, value: past.last?.value ?? 0, series: "jump"))
            segIndex += 1
            marks.append(Pt(date: h.reviewedAt, value: 100, series: "mark"))
            segStart = h.reviewedAt
            ease = h.easeAfter ?? ease
            interval = h.intervalDaysAfter ?? interval
        }
        if let r = review { ease = r.ease; interval = r.intervalDays; segStart = r.lastReviewedAt ?? segStart }
        sample(from: segStart, to: now, seg: segIndex)
        let todayVal = Double(MemoryMath.percent(intervalDays: interval, ease: ease, last: segStart, now: now))
        let horizon = max(7.0, now.timeIntervalSince(origin) / 86_400)
        var future: [Pt] = []
        for i in 0...24 {
            let t = now.addingTimeInterval(horizon * 86_400 * Double(i) / 24)
            future.append(Pt(date: t, value: Double(MemoryMath.percent(intervalDays: interval, ease: ease, last: segStart, now: t)), series: "future"))
        }
        return (past, future, marks, jumps, Pt(date: now, value: todayVal, series: "today"))
    }

    /// The curve's value on a day: the nearest sampled point of the past or "if not reviewed" line.
    private func value(at date: Date, in d: CurveData) -> Pt? {
        let pts = date <= d.today.date ? d.past : d.future
        return pts.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func chart(_ history: [ReviewHistoryRow]) -> some View {
        let d = curveData(history)
        let picked = scrubDate.flatMap { value(at: $0, in: d) }
        let scrubbing = picked != nil
        var values: [Double] = d.past.map { $0.value }
        values.append(contentsOf: d.future.map { $0.value })
        values = values.filter { $0 > 0 }
        values.append(d.today.value)
        let yMin = MemoryChartStyle.yMin(values)
        // Room above 100 %: the review points, the rises and today's dot sit exactly on 100 % right after a review,
        // and the 「100%」 label is centred on that line — at the very top edge they were cut in half (2026-10-11:
        // 「記憶の状態の100％付近のグラフが見切れてる」).
        let yTop = 100 + max(3, (100 - yMin) * 0.08)
        let bands = MemoryChartStyle.bands(yMin: yMin)
        let ticks = MemoryChartStyle.ticks(yMin: yMin)
        let start = d.past.first?.date ?? sticker.takenAt
        let end = d.future.last?.date ?? d.today.date
        return Chart {
            MemoryChartStyle.bandMarks(bands, from: start, to: end, yMin: yMin, plotHeight: Self.chartHeight - 24)
            ForEach(d.future) { p in
                LineMark(x: .value("date", p.date), y: .value("%", max(yMin, p.value)), series: .value("s", "future"))
                    .foregroundStyle(Theme.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 5]))
            }
            // The rise at each review, drawn from where the line was (never under the axis) to 100%, in the line's
            // own blue (owner 2026-10-16).
            ForEach(d.jumps) { j in
                RuleMark(x: .value("date", j.date), yStart: .value("%", max(yMin, j.value)), yEnd: .value("%", 100))
                    .foregroundStyle(Theme.primary)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            ForEach(d.past) { p in
                LineMark(x: .value("date", p.date), y: .value("%", max(yMin, p.value)), series: .value("s", p.series))
                    .foregroundStyle(Theme.primary)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            ForEach(d.reviews) { p in
                PointMark(x: .value("date", p.date), y: .value("%", p.value))
                    .symbol {
                        Circle().fill(Theme.card)
                            .overlay(Circle().stroke(Theme.primary, lineWidth: 2))
                            .frame(width: 9, height: 9)
                    }
            }
            if let picked {
                RuleMark(x: .value("date", picked.date))
                    .foregroundStyle(Theme.muted.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                PointMark(x: .value("date", picked.date), y: .value("%", max(yMin, picked.value)))
                    .symbol { Circle().fill(Theme.primary).overlay(Circle().stroke(Theme.card, lineWidth: 2)).frame(width: 14, height: 14) }
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        VStack(spacing: 1) {
                            Text(Calendar.current.isDateInToday(picked.date) ? L("今日") : JPDate.monthDay(picked.date))
                                .scaledFont(size: 12, weight: .semibold).foregroundStyle(Theme.muted)
                            Text("\(Int(picked.value))%").scaledFont(size: 17, weight: .heavy, monospacedDigit: true)
                                .foregroundStyle(Theme.foreground)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.card, in: .rect(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    }
            }
            PointMark(x: .value("date", d.today.date), y: .value("%", max(yMin, d.today.value)))
                .symbol { Circle().fill(Theme.primary).overlay(Circle().stroke(Theme.card, lineWidth: 3)).frame(width: 16, height: 16) }
                .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    if !scrubbing {
                        Text(L("今日 \(Int(d.today.value))%")).scaledFont(size: 12, weight: .bold).foregroundStyle(Theme.foreground)
                    }
                }
        }
        // VoiceOver reads the chart as one element in the display language (each mark's own label would be the
        // plotted values' names — "date", "s", "future" — in English).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("記憶の曲線"))
        .accessibilityValue(L("今日 \(Int(d.today.value))%"))
        .chartXSelection(value: $scrubDate)
        .onChange(of: scrubDate) { _, new in
            // A light tick each time the finger crosses into another day.
            guard let new else { lastScrubDay = nil; return }
            let day = Calendar.current.ordinality(of: .day, in: .era, for: new)
            if day != lastScrubDay { Haptics.selection(); lastScrubDay = day }
        }
        // The curve draws itself from left to right; the mask only hides sideways (it reaches past the top and the
        // bottom, so nothing at the edges is cut).
        .mask(alignment: .leading) {
            GeometryReader { geo in
                Rectangle()
                    .frame(width: geo.size.width * reveal, height: geo.size.height + 48)
                    .offset(y: -24)
            }
        }
        .chartYScale(domain: yMin...yTop)
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { v in
                AxisValueLabel {
                    Text("\(Int((v.as(Double.self) ?? 0).rounded()))%").scaledFont(size: 10).foregroundStyle(Theme.muted)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisValueLabel {
                    if let date = v.as(Date.self) {
                        Text(Calendar.current.isDateInToday(date) ? L("今日") : JPDate.slash(date)).scaledFont(size: 11)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func callout(pct: Int) -> some View {
        let r = review
        let interval = r?.intervalDays ?? 0
        let ease = r?.ease ?? 2.5
        let last = r?.lastReviewedAt ?? sticker.takenAt
        // Day when retention falls under 70% (うろ覚え).
        let stability = max(0.5, Double(max(1, interval)) * max(1, ease) / (2.5 * log(1 / 0.9)))
        let dropDate = last.addingTimeInterval(stability * log(100.0 / 70.0) * 86_400)
        let daysLeft = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: dropDate)).day ?? 0)
        let isTime = pct < 95
        VStack(alignment: .leading, spacing: 10) {
            Text(isTime ? L("今が復習どき") : L("まだしっかり覚えています")).scaledFont(size: 18, weight: .bold).foregroundStyle(Theme.foreground)
            if pct >= 70 {
                Text(L("復習しないと \(JPDate.slash(dropDate))（\(daysLeft)日後）に「うろ覚え」になります"))
                    .scaledFont(size: 16, weight: .medium).foregroundStyle(Theme.foreground)
            }
            if isTime {
                Button {
                    close()
                    onReviewNow()
                } label: {
                    Text(L("いま復習する")).scaledFont(size: 17, weight: .bold).foregroundStyle(.white)
                        .padding(.horizontal, 26).frame(minHeight: 50)
                        .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isTime ? Color(light: 0xFFEBDD, dark: 0x3A2414) : Color(light: 0xE6F4EA, dark: 0x13291A), in: .rect(cornerRadius: 24))
    }
}
