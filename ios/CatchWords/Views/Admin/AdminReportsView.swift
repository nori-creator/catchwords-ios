import SwiftUI

/// 設定 › 開発者 › 報告された誤り: what learners reported from a word page's 「誤りを報告」, newest first (owner 2026-10-15).
/// Read through `adminListReports` (admins only) and shown leniently from the JSON as it came — rows of
/// `{id, headword, kind, note, status, reporter_lang, created_at}`; a field the server adds or leaves out never breaks
/// the list, and a server without the function yet says so (`AdminAnalytics.Failure.notDeployed`).
struct AdminReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var answer: AdminAnalytics.Answer?
    /// DEBUG previews: rows shown instead of asking the server.
    var fixture: JSONValue? = nil

    var body: some View {
        List {
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
        .refreshable { await load() }
        .task { if answer == nil { await load() } }
    }

    private func load() async {
        if let fixture {
            answer = .success(fixture)
            return
        }
        answer = await AdminAnalytics.reports()
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(r.text("headword") ?? "—")  // lang-ok: a learning-language headword
                    .scaledFont(size: 18, weight: .bold).foregroundStyle(Theme.foreground)
                if let kind = r.text("kind") {
                    Text(Self.kindLabel(kind))
                        .scaledFont(size: 11, weight: .semibold).foregroundStyle(Theme.primaryInk)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.primary.opacity(0.1), in: Capsule())
                }
                Spacer(minLength: 4)
                statusChip(r.text("status"))
            }
            if let note = r.text("note") {
                Text(note)  // lang-ok: the reporter's own words
                    .scaledFont(size: 14).foregroundStyle(Theme.foreground.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Text(AdminFormat.dateTime(r.text("created_at")))
                if let lang = r.text("reporter_lang") { Text(lang) }
                if let id = r.text("id") { Text(String(id.prefix(8))) }
            }
            .scaledFont(size: 11, monospacedDigit: true).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("report.row")
    }

    /// The state of a report, in the display language where the word is known; the server's word otherwise.
    private func statusChip(_ status: String?) -> some View {
        let s = (status ?? "").lowercased()
        let done = ["fixed", "resolved", "done", "closed", "applied"].contains(s)
        let text = s.isEmpty ? L("未対応") : done ? L("対応済み") : ["open", "new", "pending"].contains(s) ? L("未対応")
            : ["reviewing", "in_review", "checking"].contains(s) ? L("確認中") : (status ?? "")
        return Text(text)
            .scaledFont(size: 11, weight: .semibold)
            .foregroundStyle(done ? Theme.ok : Theme.muted)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background((done ? Theme.ok : Theme.muted).opacity(0.12), in: Capsule())
    }

    /// What was reported as wrong (the web's report kinds); an unknown kind is shown as the server named it.
    static func kindLabel(_ kind: String) -> String {
        switch kind.lowercased() {
        case "meaning", "meaning_ja": L("意味")
        case "reading", "zhuyin", "pinyin": L("読み方")
        case "example", "example_sentence": L("例文")
        case "headword", "word": L("単語")
        case "other": L("その他")
        default: kind
        }
    }
}
