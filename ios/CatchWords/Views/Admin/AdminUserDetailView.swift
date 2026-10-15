import SwiftUI

/// One account in detail (web `/admin/users?u=…`, `getAdminUserDetail`): when it was last used, its catches, reviews,
/// how it uses the app, the estimated AI cost, speed, how it compares with everyone, and its settings.
struct AdminUserDetailView: View {
    let userId: String
    let name: String
    /// The account's picture as the list row had it (the detail's `profile.avatar_url` replaces it once read).
    var avatar: String? = nil

    @State private var answer: AdminAnalytics.Answer?
    /// 「日ごとの動き」: 14 / 30 / 90 days.
    @State private var span = 30

    /// The picture beside the name (owner 2026-10-15): the detail's own, else the list row's.
    private var avatarURL: String? {
        if case .success(let d)? = answer, let url = (d["profile"] ?? .null).text("avatar_url") ?? d.text("avatar_url") {
            return url
        }
        return avatar
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    AvatarView(url: avatarURL, size: 48)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name.isEmpty ? L("（名前なし）") : name)  // lang-ok: a person's own name
                            .scaledFont(size: 20, weight: .bold)
                        Text(userId).scaledFont(size: 11, monospacedDigit: true).foregroundStyle(Theme.muted).textSelection(.enabled)
                    }
                }
            }
            AdminLoadable(answer: answer, retry: { Task { await load() } }) { d in
                detail(d)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(name.isEmpty ? L("（名前なし）") : name)  // lang-ok: a person's own name
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if answer == nil { await load() } }
    }

    private func load() async {
        answer = await AdminAnalytics.userDetail(userId)
    }

    @ViewBuilder
    private func detail(_ d: JSONValue) -> some View {
        let catches = d["catches"] ?? .null
        let review = d["review"] ?? .null
        let streak = d["streak"] ?? .null
        Section {
            AdminTiles {
                AdminTile(title: L("最後に使った"), value: AdminFormat.ago(d.text("lastActive")))
                AdminTile(title: L("撮った語"), value: AdminFormat.int(catches.count("total")),
                          sub: L("この30日 \(catches.count("last30"))語"))
                AdminTile(title: L("続けた日（今）"), value: L("\(streak.count("current"))日"),
                          sub: L("最長 \(streak.count("best"))日"))
                AdminTile(title: L("復習の正答率"), value: AdminFormat.percent(review.num("correctPct")),
                          sub: L("直近180日 \(review.count("total180"))回"))
            }
            .padding(.vertical, 4)
        }
        dailySection(d.list("daily"))
        reviewSection(review, memory: d["memory"] ?? .null)
        usageSection(d["usage"] ?? .null)
        catchesSection(catches)
        aiSection(d["ai"] ?? .null, daily: d.list("daily"))
        speedSection(d["speed"] ?? .null)
        compareSection(d.list("compare"), base: d.count("compareBase"))
        settingsSection(d["profile"] ?? .null)
    }

    // MARK: 日ごとの動き

    private func dailySection(_ daily: [JSONValue]) -> some View {
        let days = Array(daily.suffix(span))
        func bars(_ key: String) -> [AdminBar] {
            days.map { AdminBar(label: AdminFormat.day($0.text("day") ?? ""), value: $0.num(key) ?? 0) }
        }
        let reviews = days.map {
            AdminBar(label: AdminFormat.day($0.text("day") ?? ""), value: $0.num("correct") ?? 0,
                     extra: max(0, ($0.num("reviews") ?? 0) - ($0.num("correct") ?? 0)))
        }
        let total = days.reduce(0) { $0 + ($1.num("reviews") ?? 0) }
        let right = days.reduce(0) { $0 + ($1.num("correct") ?? 0) }
        return Section(L("日ごとの動き")) {
            Picker(L("期間"), selection: $span) {
                ForEach([14, 30, 90], id: \.self) { n in Text(L("\(n)日")).tag(n) }
            }
            .pickerStyle(.segmented)
            AdminBarChart(title: L("撮った語"), bars: bars("catches"), color: Theme.ok)
            AdminBarChart(title: L("復習した回数"), bars: reviews)
            if total > 0 {
                Text(L("正答率 \(AdminFormat.percent(right * 100 / total))")).scaledFont(size: 12).foregroundStyle(Theme.muted)
            }
            AdminBarChart(title: L("アプリを開いた回数"), bars: bars("opens"), color: Theme.gold)
            AdminBarChart(title: L("使った時間（分）"), bars: bars("minutes"), color: Color(hex: 0x7C5CFA))
        }
    }

    // MARK: 復習

    private func reviewSection(_ r: JSONValue, memory: JSONValue) -> some View {
        let levels = memory.list("levels").map { $0.int ?? 0 }
        let schedule = memory["schedule"] ?? .null
        return Section(L("復習")) {
            AdminRow(label: L("札の数"), value: AdminFormat.int(r.count("cards")))
            AdminRow(label: L("いま期限"), value: AdminFormat.int(r.count("dueNow")))
            AdminRow(label: L("定着（間隔21日以上）"), value: AdminFormat.int(r.count("matured")))
            AdminRow(label: L("この30日"), value: L("\(r.count("last30"))回"))
            AdminRow(label: L("答えるまで（中央値）"), value: AdminFormat.ms(r.num("responseMsMedian")))
            AdminRow(label: L("正答率（180日）"), value: AdminFormat.percent(r.num("correctPct")))
            if levels.count == 6 {
                AdminBarChart(title: L("いまの記憶の段（札の数）"),
                              bars: levels.enumerated().map { AdminBar(label: MemoryBadge.labels[$0.offset], value: Double($0.element)) },
                              showTotal: false)
            }
            let byDay = schedule.list("byDay").map { AdminBar(label: AdminFormat.day($0.text("day") ?? ""), value: $0.num("n") ?? 0) }
            if !byDay.isEmpty {
                AdminBarChart(title: L("復習の予定（これから14日）"), bars: byDay, color: Theme.primary.opacity(0.7))
                AdminRow(label: L("期限切れ"), value: AdminFormat.int(schedule.count("overdue")))
            }
        }
    }

    // MARK: 使い方

    private func usageSection(_ u: JSONValue) -> some View {
        let sessions = u["sessions"] ?? .null
        let hours = u.list("hours").enumerated().map { AdminBar(label: "\($0.offset)", value: $0.element.double ?? 0) }
        let weekdayNames = [L("月"), L("火"), L("水"), L("木"), L("金"), L("土"), L("日")]
        let weekdays = u.list("weekdays").enumerated().map {
            AdminBar(label: weekdayNames[min($0.offset, 6)], value: $0.element.double ?? 0)
        }
        let save = u["saveFailures"] ?? .null
        let bg = u["backgroundFailures"] ?? .null
        return Section(L("使い方（直近180日）")) {
            AdminRow(label: L("開いた日"), value: L("\(u.count("openDays"))日"))
            AdminRow(label: L("1回の滞在（中央値）"),
                     value: L("\(AdminFormat.number(sessions.num("medianMin")))分 · \(sessions.count("sessions"))回 · 計\(sessions.count("totalMin"))分"))
            AdminRow(label: L("解説の作り直し"), value: L("\(u.count("regenerations"))回 · 報告 \(u.count("reportFixes"))回"))
            if !hours.isEmpty { AdminBarChart(title: L("開く時間帯（台湾時間）"), bars: hours, showTotal: false) }
            if !weekdays.isEmpty { AdminBarChart(title: L("開く曜日"), bars: weekdays, showTotal: false) }
            let buckets = u.list("sessionBuckets")
            if !buckets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("1回の滞在の長さ")).scaledFont(size: 13, weight: .semibold)
                    AdminRankList(rows: buckets.enumerated().map { (Self.bucketLabel($0.offset), $0.element.count("n")) })
                }
            }
            let leaves = u.list("leaves")
            if !leaves.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("離れる直前にいた画面")).scaledFont(size: 13, weight: .semibold)
                    AdminRankList(rows: leaves.map { (Self.screenLabel($0.text("screen")), $0.count("count")) })
                }
            }
            AdminRow(label: L("写真の保存の失敗"),
                     value: L("撮影 \(save.count("catch"))回、再会 \(save.count("reencounter"))回、登録前の1枚 \(save.count("firstTransfer"))回"))
            AdminRow(label: L("裏の処理の失敗"),
                     value: L("発音 \(bg.count("tts")) · 写真 \(bg.count("photoUpload")) · 縮小 \(bg.count("thumbUpload")) · 採点 \(bg.count("reviewGrade")) · 最初の分析 \(bg.count("firstCatchAi"))"))
        }
    }

    // MARK: 撮った単語

    private func catchesSection(_ c: JSONValue) -> some View {
        let types = (c["captureTypes"] ?? .null).object
            .map { (Self.captureLabel($0.key), $0.value.int ?? 0) }
            .sorted { $0.1 > $1.1 }
        let recent = c.list("recentWords")
        return Section(L("撮った単語")) {
            AdminRow(label: L("合計"), value: AdminFormat.int(c.count("total")))
            AdminRow(label: L("この30日"), value: AdminFormat.int(c.count("last30")))
            AdminRow(label: L("切り抜き"), value: AdminFormat.int(c.count("cutouts")))
            AdminRow(label: L("最初"), value: AdminFormat.dateTime(c.text("first")))
            AdminRow(label: L("最後"), value: AdminFormat.dateTime(c.text("last")))
            let places = c.pairs("topPlaces")
            if !places.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("よく撮る場所（地名まで）")).scaledFont(size: 13, weight: .semibold)
                    AdminRankList(rows: places)
                }
            }
            if !types.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("撮り方")).scaledFont(size: 13, weight: .semibold)
                    AdminRankList(rows: types)
                }
            }
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("最近の語")).scaledFont(size: 13, weight: .semibold)
                    FlowRow(spacing: 8) {
                        ForEach(Array(recent.enumerated()), id: \.offset) { _, w in
                            Text(w.text("word") ?? "—")  // lang-ok: a learning-language headword
                                .scaledFont(size: 13, weight: .semibold)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Theme.secondary, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    // MARK: AI の費用

    private func aiSection(_ ai: JSONValue, daily: [JSONValue]) -> some View {
        let last30 = daily.suffix(30)
        let usd30 = last30.reduce(0) { $0 + ($1.num("aiUsd") ?? 0) }
        let calls = last30.map { AdminBar(label: AdminFormat.day($0.text("day") ?? ""), value: $0.num("aiCalls") ?? 0) }
        return Section {
            AdminTiles {
                AdminTile(title: L("合計（記録のある分）"), value: L("約 \(AdminFormat.usd(ai.num("usd")))"))
                AdminTile(title: L("この30日"), value: L("約 \(AdminFormat.usd(usd30))"))
            }
            .padding(.vertical, 4)
            if !calls.isEmpty { AdminBarChart(title: L("AI の呼び出し（日ごと・30日）"), bars: calls, color: Color(hex: 0x7C5CFA)) }
            ForEach(Array(ai.list("byKind").enumerated()), id: \.offset) { _, k in
                AdminRow(label: Self.aiLabel(k.text("kind")),
                         value: AdminFormat.usd(k.num("usd"), digits: 3) + " · " + L("\(k.count("count"))回"))
            }
            AdminRow(label: L("記録のあるトークン"),
                     value: L("入力 \(AdminFormat.int(ai.count("tokensIn"))) / 出力 \(AdminFormat.int(ai.count("tokensOut")))"))
        } header: {
            Text(L("AI の費用（概算）"))
        } footer: {
            Text(L("呼び出し回数 × 仮の単価。正確な額は各 AI の管理画面で確かめてください。"))
        }
    }

    // MARK: 速さ

    private func speedSection(_ s: JSONValue) -> some View {
        Section(L("速さ（直近180日）")) {
            AdminRow(label: L("スキャン回数"), value: AdminFormat.int(s.count("scans")))
            AdminRow(label: L("見つけるまで（中央値）"), value: AdminFormat.ms(s.num("detectMsMedian")))
            AdminRow(label: L("押して音が出るまで"), value: AdminFormat.ms(s.num("tapToAudioMsMedian")))
            AdminRow(label: L("スキャン→図鑑に入るまで"), value: s.num("scanToDexSecMedian").map { AdminFormat.number($0) + " s" } ?? "—")
            AdminRow(label: L("候補を押した割合"), value: AdminFormat.percent(s.num("tapRate")))
        }
    }

    // MARK: ほかの利用者と比べて

    private func compareSection(_ rows: [JSONValue], base: Int) -> some View {
        // The server's labels are Japanese; the four rows come in this order (web getAdminUserDetail).
        let labels = [L("撮った語（合計）"), L("撮った語（30日）"), L("復習（30日）"), L("開いた日（30日）")]
        return Section(L("ほかの利用者と比べて（\(base)人の中）")) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                let top = r.num("pct").map { AdminFormat.percent(100 - $0) } ?? "—"
                AdminRow(label: labels[safe: i] ?? "—",
                         value: L("\(AdminFormat.number(r.num("value"))) / 中央値 \(AdminFormat.number(r.num("median"))) · 上位 \(top)"))
            }
        }
    }

    // MARK: 設定

    private func settingsSection(_ p: JSONValue) -> some View {
        let keys: [(String, String)] = [
            ("native_language", L("母語")), ("ui_language", L("表示言語")), ("target_language", L("学習言語")),
            ("level_goal", L("目標レベル")), ("current_level", L("今のレベル")), ("review_daily_limit", L("1日の復習数")),
            ("plan", L("プラン")), ("onboarded", L("初回設定済み")), ("created_at", L("登録日")),
        ]
        return Section(L("設定")) {
            ForEach(keys, id: \.0) { key, label in
                AdminRow(label: label, value: Self.value(p[key], key: key))
            }
        }
    }

    private static func value(_ v: JSONValue?, key: String) -> String {
        guard let v, !v.isNull else { return "—" }
        if key == "created_at" { return AdminFormat.date(v.string) }
        if let b = v.bool { return b ? L("はい") : L("いいえ") }
        if let n = v.int, v.string == nil { return AdminFormat.int(n) }
        return v.string ?? "—"
    }

    // MARK: Names

    private static func bucketLabel(_ i: Int) -> String {
        [L("1分未満"), L("1〜3分"), L("3〜5分"), L("5〜10分"), L("10〜20分"), L("20〜30分"), L("30分以上")][safe: i] ?? "—"
    }

    private static func screenLabel(_ key: String?) -> String {
        switch key {
        case "home": L("ホーム")
        case "dex": L("図鑑")
        case "capture": L("撮る")
        case "scan": L("スキャン")
        case "review": L("復習")
        case "settings": L("設定")
        default: L("その他")
        }
    }

    private static func captureLabel(_ key: String) -> String {
        switch key {
        case "photo": L("写真")
        case "text": L("文字")
        case "scan": L("スキャン")
        default: key
        }
    }

    private static func aiLabel(_ key: String?) -> String {
        switch key {
        case "scan_detect": L("スキャン（物を見つける）")
        case "scan_parts": L("スキャン（部分）")
        case "suggest": L("候補の提案")
        case "card": L("単語の解説")
        case "phrase_card": L("フレーズの解説")
        case "speaking_feedback": L("話す練習の評価")
        case "correction": L("添削")
        case "journal_prompt": L("日記のお題")
        case "wordbook": L("単語帳")
        case "quests": L("クエスト")
        case "tts": L("発音の音声")
        case "tts_pregen": L("発音の作り置き")
        case "removebg": L("切り抜き")
        default: key ?? "—"
        }
    }
}
