import SwiftUI

/// 設定 › 開発者 › 報告された誤り: what learners reported from a word page's 「誤りを報告」, newest first (owner 2026-10-15),
/// and what the server did about each (fixed automatically / needs a look). Read through `adminListEntryReports`
/// (admins only, server #187) and shown leniently from the JSON as it came — rows of `{id, headword, kind, item, note,
/// status, outcome, reporter_lang, word_id, created_at, outcome_at}`; a field the server adds or leaves out never breaks
/// the list, and a server without the function yet says so (`AdminAnalytics.Failure.notDeployed`). Each row's menu sets
/// its state (`adminSetEntryReportStatus`: open / resolved / dismissed).
struct AdminReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var answer: AdminAnalytics.Answer?
    /// 未対応だけ (open + needs_review, the server's default) or すべて.
    @State private var showAll = false
    /// States changed here, by report id, until the list is read again.
    @State private var changed: [String: String] = [:]
    @State private var failed = false
    /// DEBUG previews: rows shown instead of asking the server.
    var fixture: JSONValue? = nil

    var body: some View {
        List {
            Section {
                Picker(L("状態"), selection: $showAll) {
                    Text(L("未対応だけ")).tag(false)
                    Text(L("すべて")).tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("reports.filter")
            }
            Section {
                AdminLoadable(answer: answer, retry: { Task { await load() } }) { v in
                    content(v)
                }
            } footer: {
                Text(L("単語のページの「誤りを報告」から届いたものです。新しい順。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("報告された誤り"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button(L("閉じる")) { dismiss() } }
        }
        .alert(L("状態を変えられませんでした"), isPresented: $failed) { Button("OK", role: .cancel) {} }
        .refreshable { await load() }
        .task(id: showAll) { await load() }
    }

    private func load() async {
        if let fixture {
            answer = .success(fixture)
            return
        }
        let got = await AdminAnalytics.reports(all: showAll)
        changed = [:]
        answer = got
    }

    /// The rows, wherever the server puts them: the answer itself as a list, or under `reports` / `items`.
    static func rows(_ v: JSONValue) -> [JSONValue] {
        if case .array(let a) = v { return a }
        for key in ["reports", "items", "rows"] where !v.list(key).isEmpty { return v.list(key) }
        return []
    }

    @ViewBuilder
    private func content(_ v: JSONValue) -> some View {
        let rows = Self.rows(v)
        if rows.isEmpty {
            Text(L("報告はまだありません")).scaledFont(size: 14).foregroundStyle(Theme.muted)
        }
        ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
            row(r)
        }
    }

    private func row(_ r: JSONValue) -> some View {
        let id = r.text("id")
        let status = id.flatMap { changed[$0] } ?? r.text("status")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(r.text("headword") ?? "—")  // lang-ok: a learning-language headword
                    .scaledFont(size: 18, weight: .bold).foregroundStyle(Theme.foreground)
                if let kind = r.text("item") ?? r.text("kind") {
                    Text(Self.kindLabel(kind))
                        .scaledFont(size: 11, weight: .semibold).foregroundStyle(Theme.primaryInk)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.primary.opacity(0.1), in: Capsule())
                }
                Spacer(minLength: 4)
                Self.statusChip(status)
            }
            if let note = r.text("note") {
                Text(note)  // lang-ok: the reporter's own words
                    .scaledFont(size: 14).foregroundStyle(Theme.foreground.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let outcome = r.text("outcome") {
                Label {
                    Text(outcome)  // lang-ok: the server's one-line note for the developer (Japanese)
                } icon: {
                    Image(systemName: "wrench.and.screwdriver")
                }
                .scaledFont(size: 12).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text(AdminFormat.dateTime(r.text("created_at")))
                if let lang = r.text("reporter_lang") { Text(lang) }
                if let id { Text(String(id.prefix(8))) }
            }
            .scaledFont(size: 11, monospacedDigit: true).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("report.row")
        .contextMenu { if let id { actions(id: id, status: status) } }
        .swipeActions(edge: .trailing) {
            if let id, Self.normalized(status) != "resolved" {
                Button(L("対応済みにする")) { set(id, "resolved") }.tint(Theme.ok)
            }
            if let id, Self.normalized(status) != "dismissed" {
                Button(L("却下する")) { set(id, "dismissed") }.tint(Theme.muted)
            }
        }
    }

    @ViewBuilder
    private func actions(id: String, status: String?) -> some View {
        let now = Self.normalized(status)
        if now != "resolved" { Button(L("対応済みにする")) { set(id, "resolved") } }
        if now != "dismissed" { Button(L("却下する")) { set(id, "dismissed") } }
        if now != "open" { Button(L("未対応に戻す")) { set(id, "open") } }
    }

    private func set(_ id: String, _ status: String) {
        if fixture != nil {
            changed[id] = status
            return
        }
        Task {
            if await AdminAnalytics.setReportStatus(id: id, status: status) {
                Haptics.success()
                changed[id] = status
            } else {
                Haptics.warning()
                failed = true
            }
        }
    }

    /// The server's state, lower-cased (empty = open).
    static func normalized(_ status: String?) -> String {
        let s = (status ?? "").lowercased()
        return s.isEmpty ? "open" : s
    }

    /// The state of a report in the display language (server #187: open / needs_review / fixed / resolved /
    /// dismissed); an unknown one as the server named it.
    static func statusLabel(_ status: String?) -> String {
        switch normalized(status) {
        case "open", "new", "pending": L("未対応")
        case "needs_review": L("自動で直せず確認が必要")
        case "fixed": L("自動で直した")
        case "resolved": L("対応済み")
        case "dismissed": L("却下")
        default: status ?? ""
        }
    }

    private static func statusChip(_ status: String?) -> some View {
        let s = normalized(status)
        let color: Color = ["fixed", "resolved"].contains(s) ? Theme.ok : s == "needs_review" ? Theme.gold : Theme.muted
        return Text(statusLabel(status))
            .scaledFont(size: 11, weight: .semibold)
            .foregroundStyle(s == "needs_review" ? Color(hex: 0x8A5A00) : color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    /// What was reported as wrong (the report's `item`, else its `kind`); an unknown one as the server named it.
    static func kindLabel(_ kind: String) -> String {
        switch kind.lowercased() {
        case "meaning", "meaning_ja": L("意味")
        case "reading", "zhuyin", "pinyin", "pronunciation": L("読み方")
        case "example", "example_sentence": L("例文")
        case "headword", "word": L("単語")
        case "other": L("その他")
        default: kind
        }
    }
}
