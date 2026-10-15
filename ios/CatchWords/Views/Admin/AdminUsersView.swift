import SwiftUI

/// 設定 › 開発者 › 利用者ごとの情報 (web `/admin/users`): the whole service's numbers, then every named account by its
/// last use, each opening its own page. As on the web, no email address, exact location, photo or diary text is shown.
struct AdminUsersView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var overview: AdminAnalytics.Answer?
    @State private var users: AdminAnalytics.Answer?
    @State private var query = ""

    var body: some View {
        List {
            Section {
                Text(L("見せるのは改善に要る数字だけです。メールアドレス、正確な位置（緯度経度）、写真、日記や一言の本文は出しません。"))
                    .scaledFont(size: 12).foregroundStyle(Theme.muted)
            }
            Section(L("全体")) {
                AdminLoadable(answer: overview, retry: { Task { await load() } }) { o in
                    overviewBody(o)
                }
            }
            Section {
                AdminLoadable(answer: users, retry: { Task { await load() } }) { u in
                    usersBody(u)
                }
            } header: {
                Text(L("ひとりずつ"))
            } footer: {
                Text(L("最後に使った順（開いた・撮った・復習した、のいちばん新しい時刻）。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("利用者ごとの情報"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button(L("閉じる")) { dismiss() } }
        }
        .searchable(text: $query, prompt: L("名前 または ID の頭"))
        .refreshable { await load() }
        .task { if overview == nil { await load() } }
    }

    private func load() async {
        async let o = AdminAnalytics.overview()
        async let u = AdminAnalytics.users()
        let (ov, us) = await (o, u)
        overview = ov
        users = us
    }

    // MARK: 全体 (web AdminOverview)

    @ViewBuilder
    private func overviewBody(_ o: JSONValue) -> some View {
        let t = o["totals"] ?? .null
        let users = max(1, t.count("users"))
        AdminTiles {
            AdminTile(title: L("利用者"), value: AdminFormat.int(t.count("users")), sub: L("この7日で +\(t.count("new7"))"))
            AdminTile(title: L("今日使った人"), value: AdminFormat.int(t.count("active1")),
                      sub: L("7日 \(t.count("active7")) · 30日 \(t.count("active30"))"))
            AdminTile(title: "Pro", value: AdminFormat.int(t.count("pro")),
                      sub: AdminFormat.percent(Double(t.count("pro")) * 100 / Double(users)))
            AdminTile(title: L("撮った語（全体）"), value: AdminFormat.int(t.count("catches")),
                      sub: L("復習 30日 \(t.count("reviews30"))回"))
        }
        .padding(.vertical, 4)
        let series = o["series"] ?? .null
        AdminBarChart(title: L("使った人（日ごと）"), bars: Self.dayBars(series.list("active")))
        AdminBarChart(title: L("撮った語（日ごと）"), bars: Self.dayBars(series.list("catches")), color: Theme.ok)
        AdminBarChart(title: L("新しく登録した人"), bars: Self.dayBars(series.list("signups")), color: Theme.gold)
        let r = o["retention"] ?? .null
        VStack(alignment: .leading, spacing: 8) {
            Text(L("続けて使っている割合（登録から N 日後にも使った人）")).scaledFont(size: 13, weight: .semibold)
            HStack(spacing: 10) {
                retention(L("翌日"), r["d1"])
                retention(L("7日後"), r["d7"])
                retention(L("30日後"), r["d30"])
            }
        }
        .padding(.vertical, 4)
        VStack(alignment: .leading, spacing: 8) {
            Text(L("1人あたりの撮った語（分布）")).scaledFont(size: 13, weight: .semibold)
            AdminRankList(rows: o.list("catchesBuckets").map { (L("\($0.text("bucket") ?? "—")語"), $0.count("n")) })
            let m = o["medians"] ?? .null
            Text(L("中央値: 撮った語 \(AdminFormat.number(m.num("catches"))) · 復習(30日) \(AdminFormat.number(m.num("reviews30")))回 · 開いた日(30日) \(AdminFormat.number(m.num("open30")))日"))
                .scaledFont(size: 12).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
        VStack(alignment: .leading, spacing: 8) {
            Text(L("学習言語 · プラン")).scaledFont(size: 13, weight: .semibold)
            AdminRankList(rows: o.pairs("languages"))
            Divider()
            AdminRankList(rows: o.pairs("plans"))
        }
        .padding(.vertical, 4)
    }

    private func retention(_ title: String, _ cell: JSONValue?) -> some View {
        let c = cell ?? .null
        return AdminTile(title: title, value: AdminFormat.percent(c.num("rate")), sub: L("\(c.count("eligible"))人中"))
    }

    /// `[{day, n}]` → bars labelled M/D.
    static func dayBars(_ rows: [JSONValue]) -> [AdminBar] {
        rows.map { AdminBar(label: AdminFormat.day($0.text("day") ?? ""), value: $0.num("n") ?? 0) }
    }

    // MARK: ひとりずつ (web adminUserList)

    @ViewBuilder
    private func usersBody(_ u: JSONValue) -> some View {
        let all = u.array
        let named = Self.sorted(all.filter { !($0.text("display_name") ?? "").trimmingCharacters(in: .whitespaces).isEmpty })
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = q.isEmpty ? named : named.filter {
            ($0.text("display_name") ?? "").lowercased().contains(q) || ($0.text("id") ?? "").lowercased().hasPrefix(q)
        }
        if all.count > named.count {
            Text(L("名前のない\(all.count - named.count)人は出していません（全体の数には入っています）。"))
                .scaledFont(size: 12).foregroundStyle(Theme.muted)
        }
        if shown.isEmpty {
            Text(L("該当する人はいません。")).scaledFont(size: 14).foregroundStyle(Theme.muted)
        }
        ForEach(Array(shown.enumerated()), id: \.offset) { _, row in
            NavigationLink {
                AdminUserDetailView(userId: row.text("id") ?? "", name: row.text("display_name") ?? "",
                                    avatar: row.text("avatar_url"))
            } label: {
                userRow(row)
            }
        }
    }

    private func userRow(_ r: JSONValue) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // The account's own picture beside its name (owner 2026-10-15); the grey person when it has none or the
            // server's row does not carry `avatar_url` yet.
            AvatarView(url: r.text("avatar_url"), size: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.text("display_name") ?? L("（名前なし）"))  // lang-ok: a person's own name
                    .scaledFont(size: 16, weight: .semibold).foregroundStyle(Theme.foreground).lineLimit(1)
                let id8 = String((r.text("id") ?? "").prefix(8))
                let signup = AdminFormat.date(r.text("created_at"))
                let langs = "\(r.text("target_language") ?? "—") / \(r.text("ui_language") ?? "—")"
                Text(L("\(id8) · 登録 \(signup) · \(langs) · \(r.text("plan") ?? "free")"))
                    .scaledFont(size: 11, monospacedDigit: true).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(AdminFormat.ago(r.text("last_active"))).scaledFont(size: 12).foregroundStyle(Theme.foreground)
                Text(L("\(r.count("stickers"))語")).scaledFont(size: 12, monospacedDigit: true).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 2)
    }

    /// Last used first; accounts with no record last, newest sign-up first among them (web `adminUserList`).
    static func sorted(_ rows: [JSONValue]) -> [JSONValue] {
        func time(_ s: String?) -> Date? { s.flatMap { SupabaseDate.parse($0) } }
        return rows.sorted { a, b in
            let la = time(a.text("last_active")), lb = time(b.text("last_active"))
            if (la != nil) != (lb != nil) { return la != nil }
            if let la, let lb, la != lb { return la > lb }
            return (time(a.text("created_at")) ?? .distantPast) > (time(b.text("created_at")) ?? .distantPast)
        }
    }
}
