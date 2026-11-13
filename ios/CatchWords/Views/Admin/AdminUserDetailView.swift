import SwiftUI
import Charts

/// One person in the developer's 分析 (owner 2026-11-13: 「ユーザーのすごい細かいデータをグラフやそのアプリ改善に使える
/// データを一から…見やすいグラフに…ユーザーがどこで取ったとかの位置が見えない…表示言語と母語の2つは1つに統一してる」,
/// then 「今のプライバシーポリシーに反さないように設計して」).
///
/// From the top: who and how they are doing (status, since when, last time, the settings as chips — no 母語, which was
/// joined with the display language on 2026-08-25), four numbers, the days used as a calendar, where they take photos
/// (circles per city and district on a map — never a street or a point), when in the week they use the app, how their
/// memory and answers go, then what helps improve the app: how far the tutorial went, the screens and features used,
/// the screen before leaving, and what went wrong. Numbers only (privacy policy §2): no e-mail, no exact place, no
/// photo, no word, no text the person wrote.
struct AdminUserDetailView: View {
    let userId: String
    let name: String
    /// The account's picture as the list row had it (the detail's own replaces it once read).
    var avatar: String? = nil
    /// A fixed answer for the simulator's previews (`-uiPreview analytics-person`); no network.
    var fixture: AdminUserDetail? = nil

    @State private var answer: Result<AdminUserDetail, AdminAnalytics.Failure>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch answer {
                case nil:
                    header(nil)
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L("読み込み中")).scaledFont(size: 14).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                case .failure(let f)?:
                    header(nil)
                    AnalyticsCard {
                        Label(AdminAnalytics.message(f), systemImage: "exclamationmark.triangle")
                            .scaledFont(size: 14).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L("もう一度読み込む")) { Task { await load() } }
                            .scaledFont(size: 14, weight: .semibold).foregroundStyle(Theme.primaryInk)
                            .frame(minHeight: 44)
                    }
                case .success(let d)?:
                    content(d)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .padding(.top, 6)
        }
        .background(Theme.background)
        .navigationTitle(name.isEmpty ? L("（名前なし）") : name)  // lang-ok: a person's own name
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if answer == nil { await load() } }
    }

    private func load() async {
        if let fixture {
            answer = .success(fixture)
            return
        }
        answer = await AdminAnalytics.person(userId)
    }

    @ViewBuilder
    private func content(_ d: AdminUserDetail) -> some View {
        header(d)
        numbers(d)
        calendarCard(d)
        placesCard(d)
        hoursCard(d)
        memoryCard(d)
        categoriesCard(d)
        Text(L("アプリの改善に使う"))
            .scaledFont(size: 13, weight: .bold).foregroundStyle(Theme.muted)
            .padding(.top, 6)
        tutorialCard(d)
        usedCard(d)
        troubleCard(d)
        Text(L("出すのは数だけです。メールアドレス・正確な位置・写真・撮った語・本人の書いた文は出しません。場所は市と区まで。日付は台湾時間。"))
            .scaledFont(size: 11).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: Who

    private func header(_ d: AdminUserDetail?) -> some View {
        let p: AdminUserDetail.Profile? = d?.profile
        let status: String? = d?.status
        return AnalyticsCard {
            HStack(spacing: 12) {
                AvatarView(url: p?.avatarUrl ?? avatar, size: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(name.isEmpty ? L("（名前なし）") : name)  // lang-ok: a person's own name
                            .scaledFont(size: 19, weight: .bold).foregroundStyle(Theme.foreground)
                            .lineLimit(1)
                        if let status {
                            Text(AnalyticsText.status(status))
                                .scaledFont(size: 11, weight: .bold)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .foregroundStyle(Color.white)
                                .background(AnalyticsText.statusColor(status), in: Capsule())
                        }
                    }
                    if let d {
                        Text(Self.sinceLine(d)).scaledFont(size: 12).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if let d {
                FlowRow(spacing: 6) {
                    ForEach(Self.chips(d), id: \.self) { chip in
                        Text(chip)
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.secondary, in: Capsule())
                    }
                }
            }
        }
    }

    /// 「登録 9/25（49日目）· 最後 2時間前」.
    private static func sinceLine(_ d: AdminUserDetail) -> String {
        var parts: [String] = []
        if let created = d.profile?.createdAt {
            let day: String = AdminFormat.date(created)
            if let n = d.dayNumber {
                parts.append(L("登録 \(day)（\(n)日目）"))
            } else {
                parts.append(L("登録 \(day)"))
            }
        }
        parts.append(L("最後 \(AdminFormat.ago(d.lastActive))"))
        return parts.joined(separator: " · ")
    }

    /// The settings as short chips: the display language by its name, the levels, the plan, how they sign in, the
    /// device and the app's version (from the app's own records).
    private static func chips(_ d: AdminUserDetail) -> [String] {
        let p: AdminUserDetail.Profile? = d.profile
        var out: [String] = []
        if let lang = AnalyticsText.language(p?.uiLanguage) { out.append(lang) }
        if let level = AnalyticsText.level(now: p?.currentLevel, goal: p?.levelGoal) { out.append(level) }
        out.append(AnalyticsText.plan(p?.plan))
        if let provider = AnalyticsText.provider(d.provider) { out.append(provider) }
        let device: AdminUserDetail.Device? = d.app?.device
        var phone: [String] = []
        if let kind = AnalyticsText.device(device?.device) { phone.append(kind) }
        if let os = device?.os { phone.append("iOS \(os)") }
        if !phone.isEmpty { out.append(phone.joined(separator: " · ")) }
        if let v = device?.appVersion { out.append(L("アプリ \(v)")) }
        if let limit = p?.reviewDailyLimit { out.append(L("1日の復習 \(limit)")) }
        if p?.onboarded == false { out.append(L("最初の質問の途中")) }
        return out
    }

    // MARK: Four numbers

    private func numbers(_ d: AdminUserDetail) -> some View {
        let total: Int = d.catches?.total ?? 0
        let last30: Int = d.catches?.last30 ?? 0
        let again: Int = d.catches?.again ?? 0
        let streak: Int = d.streak?.current ?? 0
        let best: Int = d.streak?.best ?? 0
        let usedDays: Int = (d.daily ?? []).filter { $0.activity > 0 }.count
        let review: AdminUserDetail.Review? = d.review
        let sessions: AdminUserDetail.Sessions? = d.usage?.sessions
        return AdminTiles {
            AdminTile(title: L("撮った語"), value: AdminFormat.int(total),
                      sub: L("この30日 \(last30) · 再会 \(again)"))
            AdminTile(title: L("学んだ日（13週）"), value: L("\(usedDays)日"),
                      sub: L("続けて \(streak)日 · 最長 \(best)日"))
            AdminTile(title: L("復習の正答率"), value: AdminFormat.percent(review?.correctPct),
                      sub: L("直近180日 \(review?.total180 ?? 0)回"))
            AdminTile(title: L("1回の滞在"), value: L("\(AdminFormat.number(sessions?.medianMin))分"),
                      sub: L("\(sessions?.sessions ?? 0)回 · 開いた日 \(d.usage?.openDays ?? 0)日"))
        }
    }

    // MARK: Days used

    private func calendarCard(_ d: AdminUserDetail) -> some View {
        let days: [AdminDayValue] = (d.daily ?? []).map { AdminDayValue(day: $0.day, value: $0.activity) }
        return AnalyticsCard {
            CardTitle(title: L("使った日"), sub: L("13週。色が濃いほど、その日に撮った語と復習が多い。"))
            if days.isEmpty {
                EmptyChart(text: L("まだ記録がありません"))
            } else {
                AdminActivityCalendar(days: days)
            }
        }
    }

    // MARK: Where

    private func placesCard(_ d: AdminUserDetail) -> some View {
        let areas: [AdminUserDetail.Area] = d.areas ?? []
        return AnalyticsCard {
            CardTitle(title: L("撮った場所"), sub: L("市と区ごとの枚数。番地や正確な位置は出しません。円の位置は地名から決めています。"))
            if areas.isEmpty {
                EmptyChart(text: L("場所のある写真はまだありません"))
            } else {
                AdminAreaMap(spots: areas.map { AdminAreaSpot(name: $0.name, n: $0.n) })
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(areas.prefix(6)) { a in
                        AreaRow(area: a, top: areas.first?.n ?? 1)
                    }
                }
                HStack(spacing: 12) {
                    legendDot(Self.morning, L("朝"))
                    legendDot(Self.day, L("昼"))
                    legendDot(Self.night, L("夜"))
                }
            }
        }
    }

    static let morning = Color(hex: 0x4FB3FF)
    static let day = Color(hex: 0xF0A13C)
    static let night = Color(hex: 0x7C5CFA)

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).scaledFont(size: 11).foregroundStyle(Theme.muted)
        }
    }

    // MARK: When

    private func hoursCard(_ d: AdminUserDetail) -> some View {
        AnalyticsCard {
            CardTitle(title: L("使う時間帯"), sub: L("曜日と時刻（台湾時間、3時間ごと）。開いた・撮った・復習した回数。"))
            if let heat = d.heat, heat.flatMap({ $0 }).contains(where: { $0 > 0 }) {
                AdminHourGrid(grid: heat)
            } else {
                EmptyChart(text: L("まだ記録がありません"))
            }
        }
    }

    // MARK: Memory

    private func memoryCard(_ d: AdminUserDetail) -> some View {
        let levels: [Int] = d.memory?.levels ?? []
        let names: [String] = MemoryBadge.labels
        let parts: [AdminPart] = levels.enumerated().map { i, n in
            AdminPart(label: names[safe: i] ?? "\(i)", value: n, color: Theme.memoryLevels[safe: i] ?? Theme.primary)
        }
        let weeks: [AdminUserDetail.Week] = Array((d.weekly ?? []).suffix(13)).filter { $0.accuracy != nil }
        return AnalyticsCard {
            CardTitle(title: L("記憶の段"), sub: L("いま覚えている語の数を、記憶の段ごとに。"))
            if parts.reduce(0, { $0 + $1.value }) == 0 {
                EmptyChart(text: L("まだ記録がありません"))
            } else {
                AdminStackBar(parts: parts)
            }
            CardTitle(title: L("正答率の推移"), sub: L("週ごと（直近13週）"))
            if weeks.count < 2 {
                EmptyChart(text: L("2週分の復習がたまると出ます"))
            } else {
                accuracyChart(weeks)
            }
        }
    }

    private func accuracyChart(_ weeks: [AdminUserDetail.Week]) -> some View {
        Chart {
            ForEach(weeks) { w in
                LineMark(x: .value("week", w.to), y: .value("pct", w.accuracy ?? 0))
                    .foregroundStyle(Theme.ok)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("week", w.to), y: .value("pct", w.accuracy ?? 0))
                    .foregroundStyle(Theme.ok)
                    .symbolSize(16)
            }
        }
        .chartYScale(domain: 0.0...100.0)
        .chartXAxis {
            AxisMarks(values: AdminBarChart.ticks(weeks.map(\.to), n: 4)) { v in
                AxisValueLabel { Text(AdminFormat.day(v.as(String.self) ?? "")).font(.system(size: 10)) }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 50.0, 100.0]) { v in
                AxisGridLine()
                AxisValueLabel { Text(AdminFormat.percent(v.as(Double.self))).font(.system(size: 10)) }
            }
        }
        .frame(height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("正答率の推移"))
    }

    // MARK: Categories

    @ViewBuilder
    private func categoriesCard(_ d: AdminUserDetail) -> some View {
        let rows: [(String, Int)] = Self.categoryRows(d.categories ?? [])
        if !rows.isEmpty {
            AnalyticsCard {
                CardTitle(title: L("図鑑の分類"), sub: L("撮った語の数を、図鑑の分類ごとに（語そのものは出しません）。"))
                AdminRankList(rows: Array(rows.prefix(8)))
            }
        }
    }

    /// The server's category keys, gathered into the dex's categories (several keys share one).
    static func categoryRows(_ counts: [AdminUserDetail.Count]) -> [(String, Int)] {
        var byNo: [Int: Int] = [:]
        for c in counts { byNo[DexCatalog.category(forKey: c.key), default: 0] += c.n }
        return byNo.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .map { (DexCatalog.label($0.key), $0.value) }
    }

    // MARK: For improving the app

    private func tutorialCard(_ d: AdminUserDetail) -> some View {
        let t: AdminUserDetail.Tutorial? = d.app?.tutorial
        let passed: Set<String> = Set(t?.parts ?? [])
        return AnalyticsCard {
            CardTitle(title: L("チュートリアル"), sub: L("どこまで進んだか"))
            if t?.lastStep == nil, passed.isEmpty {
                EmptyChart(text: L("まだ記録がありません（アプリの次の版から集まります）"))
            } else {
                HStack(spacing: 3) {
                    ForEach(AnalyticsText.tourParts, id: \.self) { part in
                        VStack(spacing: 4) {
                            Capsule()
                                .fill(passed.contains(part) ? Theme.ok : Theme.border)
                                .frame(height: 8)
                            Text(AnalyticsText.tourPart(part))
                                .scaledFont(size: 10).foregroundStyle(Theme.muted)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if let at = t?.lastAt {
                    Text(L("最後の記録 \(AdminFormat.dateTime(at))")).scaledFont(size: 12).foregroundStyle(Theme.muted)
                }
                if let ended = t?.ended, ended > 0 {
                    Text(L("途中で「終了」を押した \(ended)回")).scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(Theme.destructive)
                }
            }
        }
    }

    @ViewBuilder
    private func usedCard(_ d: AdminUserDetail) -> some View {
        let app: AdminUserDetail.App? = d.app
        let features: [AdminUserDetail.Count] = app?.features30 ?? []
        let byFeature: [String: Int] = Dictionary(features.map { ($0.key, $0.n) }, uniquingKeysWith: +)
        let featureRows: [(String, Int)] = AnalyticsText.features.map { (AnalyticsText.feature($0), byFeature[$0] ?? 0) }
        let screens: [(String, Int)] = (app?.screens30 ?? []).map { (AnalyticsText.screen($0.key), $0.n) }
        let leaves: [(String, Int)] = (app?.lastScreens ?? []).map { (AnalyticsText.screen($0.key), $0.n) }
        AnalyticsCard {
            CardTitle(title: L("使った機能"), sub: L("直近30日の回数"))
            if features.isEmpty {
                EmptyChart(text: L("まだ記録がありません（アプリの次の版から集まります）"))
            } else {
                AdminRankList(rows: featureRows)
            }
        }
        AnalyticsCard {
            CardTitle(title: L("開いた画面"), sub: L("直近30日の回数"))
            if screens.isEmpty {
                EmptyChart(text: L("まだ記録がありません（アプリの次の版から集まります）"))
            } else {
                AdminRankList(rows: screens)
            }
            CardTitle(title: L("離れる直前の画面"), sub: L("アプリを閉じる前に最後に開いていた画面"))
            if leaves.isEmpty {
                EmptyChart(text: L("まだ記録がありません"))
            } else {
                AdminRankList(rows: leaves)
            }
        }
    }

    private func troubleCard(_ d: AdminUserDetail) -> some View {
        let t: AdminUserDetail.Trouble? = d.trouble
        return AnalyticsCard {
            CardTitle(title: L("困ったこと"), sub: L("直近30日"))
            AdminRow(label: L("AI の失敗"), value: L("\(t?.aiFailures30 ?? 0)回（\(t?.aiCalls30 ?? 0)回中）"))
            AdminRow(label: L("保存・裏の処理の失敗"), value: L("\(t?.failures30 ?? 0)回"))
            AdminRow(label: L("報告した間違い"), value: L("\(t?.reports30 ?? 0)件"))
            AdminRow(label: L("AI の費用"), value: AdminFormat.usd(t?.aiUsd30 ?? 0, digits: 3))
        }
    }
}

/// An area's row: its name, how many, and morning / day / night as one small stacked bar.
private struct AreaRow: View {
    let area: AdminUserDetail.Area
    let top: Int

    var body: some View {
        let total: Int = max(1, area.n)
        let parts: [(Int, Color)] = [
            (area.morning ?? 0, AdminUserDetailView.morning),
            (area.day ?? 0, AdminUserDetailView.day),
            (area.night ?? 0, AdminUserDetailView.night),
        ]
        HStack(spacing: 8) {
            Text(area.name)  // lang-ok: a place's own name
                .scaledFont(size: 13).foregroundStyle(Theme.foreground)
                .lineLimit(1).frame(width: 118, alignment: .leading)
            GeometryReader { g in
                let width: CGFloat = g.size.width * CGFloat(area.n) / CGFloat(max(1, top))
                HStack(spacing: 0) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                        Rectangle().fill(p.1).frame(width: max(0, width * CGFloat(p.0) / CGFloat(total)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            Text(L("\(area.n)枚")).scaledFont(size: 12, monospacedDigit: true).foregroundStyle(Theme.muted)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
