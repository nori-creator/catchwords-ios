import SwiftUI
import Charts

/// 設定 › 開発者 › 分析 (owner 2026-11-05: 「プロのマーケターが使うような分析データを表示にして、C みたいな感じだけど
/// もっとクオリティをあげて…そこから言える分析解説を書いて、パッと一発でそのデータが何を示しているかを分かるように」).
/// It replaces 利用者ごとの情報 · KPIダッシュボード · ベータの指標 (server `adminGetAnalytics`, `analytics.ts`).
///
/// One period (7 / 30 / 90 days, compared with the same span before), five tabs. Every chart says in one line what it
/// shows (`AnalyticsText.sentence`, judged on the server: good / warn / bad / info), every number and bar opens the
/// people in it (「誰？」), and every person opens their own page (`AdminUserDetailView`). Anonymous, admin, test-mail
/// and flagged accounts are left out and listed last; a long press on a person flags or unflags them.
struct AdminAnalyticsView: View {
    @Environment(\.dismiss) private var dismiss
    /// A fixed answer for the simulator's previews (`-uiPreview analytics…`); no network.
    var fixture: AnalyticsReport? = nil
    var startTab: AnalyticsTab = .overview

    @State private var range = 30
    @State private var answer: Result<AnalyticsReport, AdminAnalytics.Failure>?
    @State private var tab: AnalyticsTab = .overview
    @State private var people: AnalyticsPeople?
    @State private var day: String?
    @State private var userFilter = "all"
    @State private var started = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                switch answer {
                case nil:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L("読み込み中")).scaledFont(size: 14).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                case .failure(let f)?:
                    AnalyticsCard {
                        Label(AdminAnalytics.message(f), systemImage: "exclamationmark.triangle")
                            .scaledFont(size: 14).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L("もう一度読み込む")) { Task { await load() } }
                            .scaledFont(size: 14, weight: .semibold).foregroundStyle(Theme.primaryInk)
                            .frame(minHeight: 44)
                    }
                case .success(let r)?:
                    content(r)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .navigationTitle(L("分析"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button(L("閉じる")) { dismiss() } }
        }
        .refreshable { await load() }
        .task {
            guard !started else { return }
            started = true
            tab = startTab
            await load()
        }
        .sheet(item: $people) { list in
            NavigationStack { AnalyticsPeopleView(list: list, report: report) }
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.background)
        }
    }

    private var report: AnalyticsReport? {
        if case .success(let r)? = answer { return r }
        return nil
    }

    private func load() async {
        if let fixture {
            answer = .success(fixture)
            return
        }
        // The period can change while an answer is on its way: a slower answer for the period left behind (30 days
        // after 7 was picked) is dropped, not shown under the new period.
        let asked = range
        let got = await AdminAnalytics.report(range: asked)
        guard asked == range else { return }
        answer = got
        day = nil
    }

    // MARK: Header — period, who is counted, tabs

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L("期間"), selection: Binding(get: { range }, set: { v in
                range = v
                answer = nil
                Task { await load() }
            })) {
                Text(L("7日")).tag(7)
                Text(L("30日")).tag(30)
                Text(L("90日")).tag(90)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("analytics.range")
            if let r = report {
                Text(L("\(AdminFormat.day(r.window.from))〜\(AdminFormat.day(r.window.to)) を、その前の\(r.range)日と比べています · 数えている人 \(r.counted)人（外した人 \(r.excluded)人）"))
                    .scaledFont(size: 12).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AnalyticsTab.allCases) { t in
                        Button {
                            Haptics.selection()
                            withAnimation(.snappy(duration: 0.25)) { tab = t }
                        } label: {
                            Text(t.title)
                                .scaledFont(size: 14, weight: .semibold)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 38)
                                .foregroundStyle(tab == t ? Color.white : Theme.foreground)
                                .background(tab == t ? Theme.primary : Theme.secondary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tab == t ? .isSelected : [])
                        .accessibilityIdentifier("analytics.tab.\(t.rawValue)")
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func content(_ r: AnalyticsReport) -> some View {
        if r.appEventsSince == nil {
            AnalyticsNote(icon: "info.circle", text: L("アプリを開いた回数・見た画面・チュートリアルの段・広告は、記録を送る 1.0.5 から数えます。今の数は、撮った・復習した・登録した記録から出しています。"))
        }
        ForEach(r.insights(for: "sample"), id: \.code) { InsightLine(insight: $0) }
        switch tab {
        case .overview: overview(r)
        case .first: firstSteps(r)
        case .retention: retention(r)
        case .users: usersTab(r)
        case .quality: quality(r)
        }
        Text(L("メールアドレス・正確な場所・写真・本人の書いた文は出しません。場所は市と区まで。日付は台湾時間。"))
            .scaledFont(size: 11).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private func show(_ title: String, _ ids: [String]?) {
        guard let ids, !ids.isEmpty else { return }
        Haptics.selection()
        people = AnalyticsPeople(title: title, ids: ids)
    }

    // MARK: 概要

    @ViewBuilder
    private func overview(_ r: AnalyticsReport) -> some View {
        let o = r.overview
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                KpiTile(title: L("学習者"), hint: L("撮ったか復習した人"), metric: o.learners, unit: .people) {
                    show(L("学習者"), o.learners.users)
                }
                KpiTile(title: L("新しい登録"), hint: L("この期間にアカウントを作った人"), metric: o.newUsers, unit: .people) {
                    show(L("新しい登録"), o.newUsers.users)
                }
            }
            GridRow {
                KpiTile(title: L("撮った数"), hint: L("新しい語と再会"), metric: o.catches, unit: .count, action: nil)
                KpiTile(title: L("復習した数"), hint: L("答えた問題"), metric: o.reviews, unit: .count, action: nil)
            }
            GridRow {
                KpiTile(title: L("登録した日に撮った"), hint: L("新しく登録した人のうち"), metric: o.firstDayCatch, unit: .rate) {
                    show(L("登録した日に撮った"), o.firstDayCatch.users)
                }
                KpiTile(title: L("7日以内に戻った"), hint: L("登録の次の日〜7日後に学習"), metric: o.weekReturn, unit: .rate) {
                    show(L("7日以内に戻った"), o.weekReturn.users)
                }
            }
        }
        ForEach(r.insights(for: "kpis"), id: \.code) { InsightLine(insight: $0) }

        AnalyticsCard {
            CardTitle(title: L("学習者の推移"), sub: L("日ごとの人数。棒を押すと、その日の内訳と人が出ます。"))
            learnersChart(r)
            if let d = day, let row = r.daily.first(where: { $0.day == d }) {
                dayDetail(row)
            }
            ForEach(r.insights(for: "learners"), id: \.code) { InsightLine(insight: $0) }
        }
    }

    private func learnersChart(_ r: AnalyticsReport) -> some View {
        let days = r.daily
        let most: Int = days.map { $0.learners.count }.max() ?? 0
        let top: Double = Double(max(3, most))
        let lift: Double = top * 0.12
        return Chart {
            ForEach(days) { d in
                BarMark(x: .value("day", d.day), y: .value("learners", Double(d.learners.count)))
                    .foregroundStyle(barColor(d.day))
                    .cornerRadius(3)
                if !d.signups.isEmpty {
                    PointMark(x: .value("day", d.day), y: .value("learners", Double(d.learners.count) + lift))
                        .symbol(.circle).symbolSize(28)
                        .foregroundStyle(Theme.gold)
                }
            }
            if let day {
                RuleMark(x: .value("day", day))
                    .foregroundStyle(Theme.primaryDeep.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0.0...(top * 1.25))
        .chartXAxis {
            AxisMarks(values: AdminBarChart.ticks(days.map(\.day), n: 6)) { v in
                AxisValueLabel { Text(AdminFormat.day(v.as(String.self) ?? "")).font(.system(size: 10)) }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel().font(.system(size: 10))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let x = location.x - geo[plot].origin.x
                        guard let picked: String = proxy.value(atX: x) else { return }
                        Haptics.selection()
                        withAnimation(.snappy(duration: 0.2)) { day = (day == picked) ? nil : picked }
                    }
            }
        }
        .frame(height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("学習者の推移"))
        .accessibilityIdentifier("analytics.learnersChart")
    }

    private func barColor(_ key: String) -> Color {
        if key == day { return Theme.primaryDeep }
        return Theme.primary.opacity(day == nil ? 0.85 : 0.35)
    }

    private func dayDetail(_ d: AnalyticsReport.Day) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(AnalyticsText.dayWithWeekday(d.day)).scaledFont(size: 15, weight: .bold).foregroundStyle(Theme.foreground)
                Spacer()
                Text(L("学習者 \(d.learners.count)人")).scaledFont(size: 15, weight: .bold, monospacedDigit: true)
                    .foregroundStyle(Theme.primaryInk)
            }
            HStack(spacing: 14) {
                Stat(label: L("撮った"), value: d.catches)
                Stat(label: L("復習"), value: d.reviews)
                Stat(label: L("登録"), value: d.signups.count)
            }
            HStack(spacing: 8) {
                if !d.learners.isEmpty {
                    WhoButton(title: L("学んだ人 \(d.learners.count)")) { show(AnalyticsText.dayWithWeekday(d.day), d.learners) }
                }
                if !d.signups.isEmpty {
                    WhoButton(title: L("登録した人 \(d.signups.count)")) { show(L("\(AnalyticsText.dayWithWeekday(d.day)) の登録"), d.signups) }
                }
            }
        }
        .padding(12)
        .background(Theme.inset, in: .rect(cornerRadius: 14, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: 最初の体験

    @ViewBuilder
    private func firstSteps(_ r: AnalyticsReport) -> some View {
        AnalyticsCard {
            CardTitle(title: L("登録から次の日まで"),
                      sub: L("この\(r.range)日に登録した \(r.funnel.cohort)人の道のり。前の段を通った人だけを次の段で数えます。段を押すと人が出ます。"))
            if r.funnel.cohort == 0 {
                EmptyChart(text: L("この期間に登録した人はいません"))
            } else {
                FunnelBars(steps: r.funnel.steps) { step, stopped in
                    if stopped.isEmpty {
                        show(AnalyticsText.step(step.key), step.users)
                    } else {
                        people = AnalyticsPeople(title: AnalyticsText.step(step.key), ids: step.users,
                                                 secondTitle: L("ここで止まった人"), secondIds: stopped)
                    }
                }
            }
            ForEach(r.insights(for: "funnel"), id: \.code) { InsightLine(insight: $0) }
        }
        AnalyticsCard {
            CardTitle(title: L("チュートリアルのどの段で止まったか"), sub: L("1.0.5 から数えます（チュートリアルの段と「スキップ」の記録）。"))
            EmptyChart(text: L("まだ記録がありません"))
        }
    }

    // MARK: 続ける

    @ViewBuilder
    private func retention(_ r: AnalyticsReport) -> some View {
        AnalyticsCard {
            CardTitle(title: L("登録した週ごとの続き方"),
                      sub: L("行 = 登録した週（月曜から）、列 = 何週目。数は、その週に撮るか復習した人の割合（%）。濃いほど多い。押すと人が出ます。"))
            CohortGrid(cohorts: r.cohorts) { c, k, cell in
                show(L("\(AdminFormat.day(c.week))の週に登録 · \(k)週目"), cell.users)
            }
            ForEach(r.insights(for: "cohorts"), id: \.code) { InsightLine(insight: $0) }
        }
        Grid(horizontalSpacing: 10) {
            GridRow {
                KpiTile(title: L("7日以内に戻った"), hint: L("登録の次の日〜7日後に学習"), metric: r.overview.weekReturn, unit: .rate) {
                    show(L("7日以内に戻った"), r.overview.weekReturn.users)
                }
                KpiTile(title: L("学習者"), hint: L("撮ったか復習した人"), metric: r.overview.learners, unit: .people) {
                    show(L("学習者"), r.overview.learners.users)
                }
            }
        }
    }

    // MARK: 利用者

    @ViewBuilder
    private func usersTab(_ r: AnalyticsReport) -> some View {
        let counted = r.users.filter { $0.excluded == nil }
        AnalyticsCard {
            CardTitle(title: L("状態ごとの人数"), sub: L("新しい = 登録から7日未満 · 続けている = 7日以内に来た · 離れそう = 8〜21日来ていない · 離れた = 22日以上"))
            StatusBar(users: counted)
            ForEach(r.insights(for: "users"), id: \.code) { InsightLine(insight: $0) }
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.filterKeys, id: \.self) { key in
                    FilterChip(title: AnalyticsText.filterTitle(key), count: Self.filterCount(key, in: r),
                               selected: userFilter == key) {
                        Haptics.selection()
                        userFilter = key
                    }
                }
            }
        }
        let shown: [AnalyticsReport.User] = Self.users(in: r, filter: userFilter)
        AnalyticsCard(padding: 0) {
            if shown.isEmpty {
                EmptyChart(text: L("当てはまる人はいません")).padding(16)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, u in
                NavigationLink {
                    AdminUserDetailView(userId: u.id, name: u.name ?? L("名前なし"), avatar: u.avatarUrl)
                } label: {
                    UserRow(user: u, range: r.range)
                }
                .buttonStyle(.plain)
                .contextMenu { excludeButton(u) }
                if i < shown.count - 1 { Divider().overlay(Theme.border).padding(.leading, 62) }
            }
        }
        Text(L("長押しで「数えない」の印を付け外しできます（あなたの試験用の別アカウントなど）。匿名・管理者・試験用のメールは自動で外します。"))
            .scaledFont(size: 11).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Long press on a person: leave them out of the numbers, or count them again. Automatic reasons (anonymous,
    /// admin, test mail) cannot be undone here.
    @ViewBuilder
    private func excludeButton(_ u: AnalyticsReport.User) -> some View {
        let flagged: Bool = u.excluded == "flagged"
        let title: String = flagged ? L("数に入れる") : L("数えない（試験用など）")
        let icon: String = flagged ? "person.badge.plus" : "person.badge.minus"
        Button(title, systemImage: icon) {
            Task {
                if await AdminAnalytics.setExcluded(userId: u.id, excluded: !flagged) {
                    await load()
                }
            }
        }
        .disabled(u.excluded != nil && !flagged)
    }

    private static let filterKeys: [String] = ["all"] + AnalyticsText.statuses + ["excluded"]

    private static func filterCount(_ key: String, in r: AnalyticsReport) -> Int {
        let counted: [AnalyticsReport.User] = r.users.filter { $0.excluded == nil }
        switch key {
        case "all": return counted.count
        case "excluded": return r.users.count - counted.count
        default: return counted.filter { $0.status == key }.count
        }
    }

    private static func users(in r: AnalyticsReport, filter: String) -> [AnalyticsReport.User] {
        r.users.filter { (u: AnalyticsReport.User) -> Bool in
            switch filter {
            case "all": return u.excluded == nil
            case "excluded": return u.excluded != nil
            default: return u.excluded == nil && u.status == filter
            }
        }
    }

    // MARK: 品質

    @ViewBuilder
    private func quality(_ r: AnalyticsReport) -> some View {
        let q = r.quality
        AnalyticsCard {
            CardTitle(title: L("撮ってから候補が出るまで"), sub: L("サーバーで測った時間。ふつう = 真ん中の値、遅い1割 = 10回に1回はこれより遅い。"))
            SpeedGauge(p50: q.suggestS.p50, p90: q.suggestS.p90, target: 2.5)
            HStack(spacing: 14) {
                Stat(label: L("回数"), value: q.suggestS.n)
                if let prev = q.suggestS.prevP50 {
                    Text(L("前の期間のふつう \(AdminFormat.number(prev))秒")).scaledFont(size: 12).foregroundStyle(Theme.muted)
                }
            }
            ForEach(r.insights(for: "speed"), id: \.code) { InsightLine(insight: $0) }
        }
        AnalyticsCard {
            CardTitle(title: L("AI"), sub: L("候補・カード・発音などの呼び出し。費用は登録した単価で計算（Google の無料枠の間の請求は 0）。"))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                BigStat(label: L("カードを作る時間（ふつう）"), value: q.cardS.p50.map { L("\(AdminFormat.number($0))秒") } ?? "—",
                        sub: q.cardS.p90.map { L("遅い1割 \(AdminFormat.number($0))秒") })
                BigStat(label: L("1番目の候補が選ばれた"), value: AdminFormat.percent(q.firstPick.pct), sub: L("\(q.firstPick.n)回中"))
                BigStat(label: L("失敗した呼び出し"), value: AdminFormat.percent(q.aiErrors.pct), sub: L("\(q.aiErrors.n)回中"))
                BigStat(label: L("費用"), value: AdminFormat.usd(q.aiCostUsd.total, digits: 3),
                        sub: q.aiCostUsd.perLearner.map { L("学習者1人あたり \(AdminFormat.usd($0, digits: 3))") })
            }
            if q.aiCostUsd.unpriced > 0 {
                Text(L("単価が分からない呼び出し \(q.aiCostUsd.unpriced)回は費用に入っていません（AI の設定 › 費用 で単価を入れられます）。"))
                    .scaledFont(size: 11).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(r.insights(for: "ai") + r.insights(for: "pick"), id: \.code) { InsightLine(insight: $0) }
        }
        AnalyticsCard {
            CardTitle(title: L("どこで撮っているか"), sub: L("市と区まで。番地や1人ずつの場所は出しません。"))
            if q.places.isEmpty {
                EmptyChart(text: L("この期間に場所のある写真はありません"))
            } else {
                AdminRankList(rows: q.places.map { ($0.name, $0.n) })
            }
            ForEach(r.insights(for: "places"), id: \.code) { InsightLine(insight: $0) }
        }
        AnalyticsCard {
            CardTitle(title: L("広告と上限"), sub: L("1日の上限に届いた → 広告を出した → 見終えた。"))
            AdsFlow(ads: r.ads)
            AdminRow(label: L("保存・裏の処理の失敗"), value: AdminFormat.int(q.failures))
            ForEach(r.insights(for: "ads"), id: \.code) { InsightLine(insight: $0) }
        }
    }
}

// MARK: - Tabs and people

enum AnalyticsTab: String, CaseIterable, Identifiable {
    case overview, first, retention, users, quality
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: L("概要")
        case .first: L("最初の体験")
        case .retention: L("続ける")
        case .users: L("利用者")
        case .quality: L("品質")
        }
    }
}

/// The people behind a number (「誰？」).
struct AnalyticsPeople: Identifiable {
    let id = UUID()
    let title: String
    let ids: [String]
    var secondTitle: String? = nil
    var secondIds: [String] = []
}

private struct AnalyticsPeopleView: View {
    @Environment(\.dismiss) private var dismiss
    let list: AnalyticsPeople
    let report: AnalyticsReport?

    var body: some View {
        List {
            section(L("\(list.ids.count)人"), list.ids)
            if let t = list.secondTitle, !list.secondIds.isEmpty {
                section(L("\(t) \(list.secondIds.count)人"), list.secondIds)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(list.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L("閉じる")) { dismiss() } } }
    }

    private func section(_ title: String, _ ids: [String]) -> some View {
        Section(title) {
            ForEach(ids, id: \.self) { id in
                if let u = report?.user(id) {
                    NavigationLink {
                        AdminUserDetailView(userId: u.id, name: u.name ?? L("名前なし"), avatar: u.avatarUrl)
                    } label: {
                        UserRow(user: u, range: report?.range ?? 30, compact: true)
                    }
                } else {
                    Text(String(id.prefix(8))).scaledFont(size: 13, monospacedDigit: true).foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

// MARK: - Words

enum AnalyticsText {
    static let statuses = ["new", "active", "at_risk", "lapsed", "never"]

    static func step(_ key: String) -> String {
        switch key {
        case "signup": L("登録した")
        case "onboarded": L("最初の質問に答えた")
        case "first_catch": L("1語目を撮った")
        case "first_review": L("1回目の復習をした")
        case "came_back": L("次の日以降も来た")
        default: key
        }
    }

    static func status(_ key: String) -> String {
        switch key {
        case "new": L("新しい")
        case "active": L("続けている")
        case "at_risk": L("離れそう")
        case "lapsed": L("離れた")
        case "never": L("まだ撮っていない")
        default: key
        }
    }

    static func statusColor(_ key: String) -> Color {
        switch key {
        case "new": Theme.primary
        case "active": Theme.ok
        case "at_risk": Theme.gold
        case "lapsed": Theme.destructive
        default: Theme.muted
        }
    }

    static func filterTitle(_ key: String) -> String {
        switch key {
        case "all": L("全員")
        case "excluded": L("外した人")
        default: status(key)
        }
    }

    static func excluded(_ key: String) -> String {
        switch key {
        case "anonymous": L("匿名")
        case "admin": L("管理者")
        case "test_email": L("試験用のメール")
        case "flagged": L("数えない印")
        default: key
        }
    }

    static func stopped(_ key: String?) -> String? {
        switch key {
        case "onboarding": L("最初の質問で止まった")
        case "first_catch": L("1語目の前で止まった")
        default: nil
        }
    }

    /// "2026-11-03" → 11/3 (月) in the display language.
    static func dayWithWeekday(_ key: String) -> String {
        guard let d = SupabaseDate.parse("\(key)T12:00:00+08:00") else { return AdminFormat.day(key) }
        return d.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated).locale(L10n.locale))
    }

    static func toneColor(_ tone: String) -> Color {
        switch tone {
        case "good": Theme.ok
        case "warn": Theme.gold
        case "bad": Theme.destructive
        default: Theme.primary
        }
    }

    static func toneIcon(_ tone: String) -> String {
        switch tone {
        case "good": "checkmark.circle.fill"
        case "warn": "exclamationmark.triangle.fill"
        case "bad": "xmark.octagon.fill"
        default: "info.circle.fill"
        }
    }

    private static func pct(_ v: Double) -> String { AdminFormat.percent(v) }
    private static func sec(_ v: Double) -> String { AdminFormat.number(v) }

    /// What a chart shows, in one line (server `insightsFor`). The judgement (tone) is the server's; the words are here.
    static func sentence(_ i: AnalyticsReport.Insight) -> String {
        let n = i.int("n")
        switch i.code {
        case "learners_up":
            return L("学習者は\(i.int("now"))人で、前の\(i.int("days"))日より\(i.int("diff"))人増えました。")
        case "learners_down":
            return L("学習者は\(i.int("now"))人で、前の\(i.int("days"))日より\(i.int("diff"))人減りました。戻るきっかけ（通知・復習の期限）が届いているかを見る時です。")
        case "learners_flat":
            return L("学習者は\(i.int("now"))人で、前の\(i.int("days"))日と同じです。")
        case "learners_none":
            return L("この\(i.int("days"))日、撮った人も復習した人もいません。新しい人を呼ぶことが先です。")
        case "no_signups":
            return L("この\(i.int("days"))日、新しい登録がありません。数を伸ばすには、まずアプリを知ってもらう所（ストアの頁・紹介）から。")
        case "first_day_catch":
            switch i.tone {
            case "good": return L("登録した日に1語撮った人は\(pct(i.num("pct")))（\(n)人中）。最初の体験はうまく動いています。")
            default: return L("登録した日に1語撮った人は\(pct(i.num("pct")))（\(n)人中）。登録から1語目までの道を短くすると伸びます。")
            }
        case "small_sample":
            return L("数えている学習者が\(n)人だけなので、% は1人で大きく動きます。傾きは参考に見てください。")
        case "funnel_empty":
            return L("この\(i.int("days"))日に登録した人がいないので、道のりはまだ出ません。期間を90日にすると見られます。")
        case "funnel_no_drop":
            return L("登録した人は全員、最後の段まで進んでいます。")
        case "funnel_drop":
            return L("一番多く止まったのは「\(step(i.text("from")))」→「\(step(i.text("to")))」で、\(i.int("of"))人中\(i.int("lost"))人（\(pct(i.num("pct")))）。ここを直すのが一番効きます。")
        case "cohort_wait":
            return L("登録から1週間たった組がまだ無いので、続き方はまだ言えません。")
        case "cohort_week1":
            switch i.tone {
            case "good": return L("登録の次の週にも学んだ人は\(pct(i.num("pct")))（\(n)人中）。習慣になり始めています。")
            case "warn": return L("登録の次の週にも学んだ人は\(pct(i.num("pct")))（\(n)人中）。2週目に戻るきっかけ（復習の通知など）を強めると伸びます。")
            default: return L("登録の次の週にも学んだ人は\(pct(i.num("pct")))（\(n)人中）。多くの人が1週目で離れています。最初の週の体験を見直す時です。")
            }
        case "users_at_risk":
            return L("\(n)人が8〜21日来ていません。離れる前に、戻るきっかけが要ります。")
        case "users_never":
            return L("\(n)人がまだ1語も撮っていません（最初の質問で止まった\(i.int("onboarding"))人・質問の後で止まった\(i.int("first"))人）。")
        case "users_ok":
            return L("数えている\(n)人に、離れそうな人はいません。")
        case "speed_none":
            return L("この\(i.int("days"))日、写真から候補を出した記録がありません。")
        case "speed_ok":
            return L("撮ってから候補が出るまで、ふつう\(sec(i.num("p50")))秒・遅い1割で\(sec(i.num("p90")))秒。目標の\(sec(i.num("target")))秒以内です。")
        case "speed_slow":
            return L("撮ってから候補が出るまで、ふつう\(sec(i.num("p50")))秒・遅い1割で\(sec(i.num("p90")))秒。目標の\(sec(i.num("target")))秒を超えていて、待つ間に閉じる人が出やすい速さです。")
        case "ai_backup_refused":
            return L("予備の AI が\(n)回、残高不足などで断りました。予備の口（OpenRouter）の残高を確かめてください。")
        case "ai_errors":
            return L("AI の呼び出しの\(pct(i.num("pct")))が失敗しています（\(n)回中）。")
        case "ai_ok":
            return L("AI の失敗は\(pct(i.num("pct")))（\(n)回中）、費用は\(AdminFormat.usd(i.num("usd"), digits: 3))です。")
        case "first_pick":
            switch i.tone {
            case "good": return L("AI の1番目の候補がそのまま選ばれたのは\(pct(i.num("pct")))（\(n)回中）。候補の並びは合っています。")
            default: return L("AI の1番目の候補がそのまま選ばれたのは\(pct(i.num("pct")))（\(n)回中）。1番目の当たりを上げる余地があります。")
            }
        case "places_top":
            return L("一番多く撮られているのは\(i.text("name"))（\(n)回）。\(i.int("areas"))か所の地域で撮られています。")
        case "ads_no_data":
            return L("広告と上限の記録は 1.0.5 から集まります（AdMob の承認待ち）。")
        case "ads_watch_rate":
            return L("広告を出した\(i.int("offered"))回のうち、\(i.int("watched"))回見終えました（\(pct(i.num("pct")))）。")
        default:
            return i.code
        }
    }
}

// MARK: - Pieces

private struct AnalyticsCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

private struct CardTitle: View {
    let title: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).scaledFont(size: 16, weight: .bold).foregroundStyle(Theme.foreground)
            if let sub {
                Text(sub).scaledFont(size: 12).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AnalyticsNote: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(Theme.primaryInk)
            Text(text).scaledFont(size: 12).foregroundStyle(Theme.foreground).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.inset, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// The one-line reading under a chart, with its judgement as a coloured mark.
private struct InsightLine: View {
    let insight: AnalyticsReport.Insight

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: AnalyticsText.toneIcon(insight.tone))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AnalyticsText.toneColor(insight.tone))
                .padding(.top, 1)
            Text(AnalyticsText.sentence(insight))
                .scaledFont(size: 14, weight: .medium)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AnalyticsText.toneColor(insight.tone).opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analytics.insight.\(insight.code)")
    }
}

private enum KpiUnit { case people, count, rate }

/// A number, its change against the span before, and 「誰？」 when the people are known.
private struct KpiTile: View {
    let title: String
    let hint: String?
    let metric: AnalyticsReport.Metric
    let unit: KpiUnit
    let action: (() -> Void)?

    init(title: String, hint: String?, metric: AnalyticsReport.Metric, unit: KpiUnit, action: (() -> Void)?) {
        self.title = title
        self.hint = hint
        self.metric = metric
        self.unit = unit
        self.action = action
    }

    /// Who is in the number can be shown.
    private var opens: Bool { action != nil && !(metric.users ?? []).isEmpty }

    var body: some View {
        if opens, let action {
            Button(action: action) { tile }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
        } else {
            tile.accessibilityElement(children: .combine)
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).scaledFont(size: 12, weight: .semibold).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer(minLength: 2)
                if opens {
                    Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 12))
                        .foregroundStyle(Theme.primaryInk)
                }
            }
            Text(valueText).scaledFont(size: 28, weight: .heavy, monospacedDigit: true)
                .foregroundStyle(Theme.foreground).lineLimit(1).minimumScaleFactor(0.6)
            delta
            if let hint {
                Text(hint).scaledFont(size: 10).foregroundStyle(Theme.muted).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private static func deltaColor(up: Bool, down: Bool) -> Color {
        if up { return Theme.ok }
        if down { return Theme.destructive }
        return Theme.muted
    }

    private var valueText: String {
        guard let v = metric.value else { return "—" }
        switch unit {
        case .people: return L("\(Int(v))人")
        case .count: return AdminFormat.int(Int(v))
        case .rate: return AdminFormat.percent(v)
        }
    }

    @ViewBuilder
    private var delta: some View {
        if let v = metric.value, let p = metric.prev, (unit != .rate || (metric.prevN ?? 0) > 0) {
            let d = v - p
            let up = d > 0.05
            let down = d < -0.05
            let amount = unit == .rate ? L("\(AdminFormat.number(abs(d)))pt") : AdminFormat.number(abs(d), digits: 0)
            HStack(spacing: 4) {
                Image(systemName: up ? "arrowtriangle.up.fill" : down ? "arrowtriangle.down.fill" : "equal")
                    .font(.system(size: 9, weight: .bold))
                Text(up || down ? amount : L("変わらず")).scaledFont(size: 12, weight: .bold, monospacedDigit: true)
                Text(L("前の期間比")).scaledFont(size: 10).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Self.deltaColor(up: up, down: down))
        } else {
            Text(unit == .rate && metric.n == 0 ? L("対象の人がまだいません") : L("前の期間 —"))
                .scaledFont(size: 11).foregroundStyle(Theme.muted)
        }
    }
}

private struct Stat: View {
    let label: String
    let value: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).scaledFont(size: 12).foregroundStyle(Theme.muted)
            Text(AdminFormat.int(value)).scaledFont(size: 14, weight: .bold, monospacedDigit: true).foregroundStyle(Theme.foreground)
        }
    }
}

private struct BigStat: View {
    let label: String
    let value: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).scaledFont(size: 11, weight: .semibold).foregroundStyle(Theme.muted).lineLimit(2)
            Text(value).scaledFont(size: 22, weight: .heavy, monospacedDigit: true).foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let sub { Text(sub).scaledFont(size: 11).foregroundStyle(Theme.muted).lineLimit(2) }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FilterChip: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let ink: Color = selected ? Color.white : Theme.foreground
        let fill: Color = selected ? Theme.foreground.opacity(0.85) : Theme.secondary
        Button(action: action) {
            Text("\(title) \(count)")
                .scaledFont(size: 13, weight: .semibold, monospacedDigit: true)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .foregroundStyle(ink)
                .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct WhoButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "person.2.fill")
                .scaledFont(size: 13, weight: .semibold)
                .padding(.horizontal, 12).frame(minHeight: 34)
                .foregroundStyle(Theme.primaryInk)
                .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyChart: View {
    let text: String

    var body: some View {
        Text(text).scaledFont(size: 13).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.secondary.opacity(0.5), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

/// The first steps as bars that shrink step by step, with how many were lost between each.
private struct FunnelBars: View {
    let steps: [AnalyticsReport.Step]
    let onTap: (AnalyticsReport.Step, [String]) -> Void

    var body: some View {
        let first = max(1, steps.first?.users.count ?? 1)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, s in
                let stopped: [String] = Self.stopped(at: i, in: steps)
                if i > 0, !stopped.isEmpty {
                    Text(L("−\(stopped.count)人"))
                        .scaledFont(size: 11, weight: .bold, monospacedDigit: true)
                        .foregroundStyle(Theme.destructive)
                        .padding(.leading, 4)
                }
                Button { onTap(s, stopped) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(AnalyticsText.step(s.key)).scaledFont(size: 13, weight: .semibold).foregroundStyle(Theme.foreground)
                            Spacer()
                            Text(L("\(s.users.count)人 · \(Self.share(s.users.count, of: first))"))
                                .scaledFont(size: 13, weight: .bold, monospacedDigit: true).foregroundStyle(Theme.foreground)
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.secondary)
                                Capsule().fill(LinearGradient(colors: [Theme.primaryBright, Theme.primaryDeep], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: Self.barWidth(g.size.width, s.users.count, first))
                            }
                        }
                        .frame(height: 12)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

extension FunnelBars {
    static func stopped(at i: Int, in steps: [AnalyticsReport.Step]) -> [String] {
        guard i > 0 else { return [] }
        let now = Set(steps[i].users)
        return steps[i - 1].users.filter { !now.contains($0) }
    }

    static func share(_ n: Int, of first: Int) -> String {
        AdminFormat.percent(Double(n) * 100 / Double(max(1, first)))
    }

    static func barWidth(_ width: CGFloat, _ n: Int, _ first: Int) -> CGFloat {
        max(6, width * CGFloat(n) / CGFloat(max(1, first)))
    }
}

/// Weekly cohorts: one row per sign-up week, one cell per week since, shaded by the share who learned that week.
private struct CohortGrid: View {
    let cohorts: [AnalyticsReport.Cohort]
    let onTap: (AnalyticsReport.Cohort, Int, AnalyticsReport.Cell) -> Void

    var body: some View {
        let columns = cohorts.map(\.cells.count).max() ?? 1
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    Text(L("登録週")).scaledFont(size: 10, weight: .semibold).foregroundStyle(Theme.muted)
                        .frame(width: 58, alignment: .leading)
                    Text(L("人数")).scaledFont(size: 10, weight: .semibold).foregroundStyle(Theme.muted).frame(width: 30)
                    ForEach(0..<columns, id: \.self) { k in
                        Text(L("\(k)週")).scaledFont(size: 10, weight: .semibold).foregroundStyle(Theme.muted).frame(width: 40)
                    }
                }
                ForEach(cohorts) { c in
                    GridRow {
                        Text(L("\(AdminFormat.day(c.week))〜")).scaledFont(size: 11, monospacedDigit: true).foregroundStyle(Theme.foreground)
                            .frame(width: 58, alignment: .leading)
                        Text(AdminFormat.int(c.size)).scaledFont(size: 11, weight: .semibold, monospacedDigit: true)
                            .foregroundStyle(c.size == 0 ? Theme.muted : Theme.foreground).frame(width: 30)
                        ForEach(0..<columns, id: \.self) { k in
                            cell(c, k)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ c: AnalyticsReport.Cohort, _ k: Int) -> some View {
        if k < c.cells.count, let cell = c.cells[k] {
            Button { onTap(c, k, cell) } label: {
                let alpha: Double = 0.06 + 0.9 * min(1.0, cell.pct / 100.0)
                let ink: Color = cell.pct >= 75 ? Color.white : Theme.foreground
                Text("\(Int(cell.pct.rounded()))")
                    .scaledFont(size: 11, weight: .bold, monospacedDigit: true)
                    .foregroundStyle(ink)
                    .frame(width: 40, height: 28)
                    .background(Theme.primaryBright.opacity(alpha), in: .rect(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(cell.users.isEmpty)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(k < c.cells.count ? Theme.secondary.opacity(0.6) : Color.clear)
                .frame(width: 40, height: 28)
        }
    }
}

/// How many people are in each state, as one stacked bar with a legend.
private struct StatusBar: View {
    let users: [AnalyticsReport.User]

    var body: some View {
        let total = max(1, users.count)
        let parts = AnalyticsText.statuses.map { s in (s, users.filter { $0.status == s }.count) }
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(parts.filter { $0.1 > 0 }, id: \.0) { s, n in
                        Rectangle().fill(AnalyticsText.statusColor(s))
                            .frame(width: max(4, (g.size.width - 8) * CGFloat(n) / CGFloat(total)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            FlowLegend(parts: parts)
        }
    }
}

private struct FlowLegend: View {
    let parts: [(String, Int)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(parts, id: \.0) { s, n in
                HStack(spacing: 6) {
                    Circle().fill(AnalyticsText.statusColor(s)).frame(width: 8, height: 8)
                    Text(AnalyticsText.status(s)).scaledFont(size: 12).foregroundStyle(Theme.foreground)
                    Text(L("\(n)人")).scaledFont(size: 12, weight: .bold, monospacedDigit: true).foregroundStyle(Theme.foreground)
                }
            }
        }
    }
}

private struct UserRow: View {
    let user: AnalyticsReport.User
    let range: Int
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(AnalyticsText.statusColor(user.status).opacity(0.18))
                Text(String((user.name ?? "?").prefix(1))).scaledFont(size: 16, weight: .bold)
                    .foregroundStyle(AnalyticsText.statusColor(user.status))
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user.name ?? L("名前なし")).scaledFont(size: 15, weight: .semibold).foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    chip
                }
                Text(line).scaledFont(size: 12, monospacedDigit: true).foregroundStyle(Theme.muted).lineLimit(compact ? 1 : 2)
            }
            Spacer(minLength: 4)
            if !compact {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, compact ? 0 : 14)
        .padding(.vertical, compact ? 2 : 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var chip: some View {
        let text = user.excluded.map { AnalyticsText.excluded($0) } ?? AnalyticsText.status(user.status)
        let color = user.excluded == nil ? AnalyticsText.statusColor(user.status) : Theme.muted
        Text(text).scaledFont(size: 10, weight: .bold)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var line: String {
        var parts = [L("撮った \(user.catches)"), L("復習 \(user.reviews)")]
        if let a = user.accuracy { parts.append(L("正答 \(Int(a))%")) }
        parts.append(L("最後 \(user.lastActive.map(AdminFormat.day) ?? "—")"))
        if let s = AnalyticsText.stopped(user.stoppedAt) { parts.append(s) }
        if let lang = user.uiLanguage { parts.append(lang) }
        return parts.joined(separator: " · ")
    }
}

/// The wait from shutter to candidates: the usual time and the slow tenth on a scale with the target marked.
private struct SpeedGauge: View {
    let p50: Double?
    let p90: Double?
    let target: Double

    var body: some View {
        let slow: Double = (p90 ?? 0) * 1.15
        let top: Double = max(target * 2, max(slow, 1))
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                big(L("ふつう"), p50)
                big(L("遅い1割"), p90)
                Spacer()
                Text(L("目標 \(AdminFormat.number(target))秒以内")).scaledFont(size: 12, weight: .semibold).foregroundStyle(Theme.muted)
            }
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.secondary).frame(height: 10)
                    Capsule().fill(Theme.ok.opacity(0.25)).frame(width: w * CGFloat(target / top), height: 10)
                    if let p90 {
                        Capsule().fill(Theme.gold.opacity(0.8)).frame(width: max(6, w * CGFloat(p90 / top)), height: 10)
                    }
                    if let p50 {
                        Capsule().fill(p50 <= target ? Theme.ok : Theme.destructive)
                            .frame(width: max(6, w * CGFloat(p50 / top)), height: 10)
                    }
                    Rectangle().fill(Theme.foreground).frame(width: 2, height: 18)
                        .offset(x: w * CGFloat(target / top) - 1)
                }
            }
            .frame(height: 18)
        }
    }

    private func big(_ label: String, _ v: Double?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).scaledFont(size: 11, weight: .semibold).foregroundStyle(Theme.muted)
            Text(v.map { L("\(AdminFormat.number($0))秒") } ?? "—")
                .scaledFont(size: 24, weight: .heavy, monospacedDigit: true).foregroundStyle(Theme.foreground)
        }
    }
}

private struct AdsFlow: View {
    let ads: AnalyticsReport.Ads

    var body: some View {
        HStack(spacing: 6) {
            box(L("上限に届いた"), ads.limitHit)
            arrow
            box(L("広告を出した"), ads.offered)
            arrow
            box(L("見終えた"), ads.watched)
        }
        if ads.failed > 0 {
            AdminRow(label: L("広告の失敗"), value: AdminFormat.int(ads.failed))
        }
    }

    private var arrow: some View {
        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
    }

    private func box(_ label: String, _ n: Int) -> some View {
        VStack(spacing: 2) {
            Text(AdminFormat.int(n)).scaledFont(size: 20, weight: .heavy, monospacedDigit: true).foregroundStyle(Theme.foreground)
            Text(label).scaledFont(size: 10).foregroundStyle(Theme.muted).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Theme.secondary.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
    }
}
