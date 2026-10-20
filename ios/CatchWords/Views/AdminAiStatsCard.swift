import SwiftUI

/// 設定 → 開発者 →「AI の設定（開発者）」の「速さと正確さ（モデルごと）」と「固定の写真で試す」
/// (the web's `AdminAiStatsSection`; docs/admin-ai-api.md › adminGetAiStats / adminTestPhotoCandidates).
///
/// - The numbers come from real use: feature → use → model, so switching a model in 「機能ごとの AI」 adds a row
///   that can be compared with the previous one. Times run from the request to the AI until its answer.
/// - 「固定の写真で試す」 sends the labelled photos to a chosen model without changing the live setting, two at a
///   time, and the server keeps each result for the table above.
struct AdminAiStatsCard: View {
    let settings: AdminAiSettings
    /// UIPreview only: numbers to show instead of asking the server (nothing is sent).
    var preview: AdminAiStats? = nil

    @State private var days: String = "7"
    @State private var mine: Bool = false
    @State private var stats: AdminAiStats?
    @State private var loadError: String?

    @State private var testValue: String = "auto"
    @State private var testLanguage: String = NativeAPI.targetLanguage
    @State private var testNoThinking: Bool = false
    @State private var testRunning: Bool = false
    @State private var testStop: Bool = false
    @State private var testTotal: Int = 0
    @State private var testRows: [TestRow] = []

    nonisolated struct TestRow: Identifiable, Sendable {
        let id = UUID()
        let photo: String
        let result: AdminAiTestResult?
        let error: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsCard(title: L("速さと正確さ（モデルごと）")) { statsContent }
                .accessibilityIdentifier("adminAi.stats")
            SettingsCard(title: L("固定の写真で試す")) { testContent }
                .accessibilityIdentifier("adminAi.test")
        }
        .task(id: "\(days)-\(mine)") { await load() }
    }

    // MARK: - Speed and accuracy

    private var statsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            caption(L("実際に使われた分から数えます（機能 → 用途 → モデル）。モデルを切り替えると行が増えるので、前後を見比べられます。時間は AI に頼んでから答えが返るまで。写真・語・文は記録しません。"))
            ChoicePills(options: [("1", L("1日")), ("7", L("7日")), ("30", L("30日"))], selection: $days)
            Toggle(L("自分の分だけ"), isOn: $mine)
                .scaledFont(size: 15)
                .tint(Theme.primary)
                .frame(minHeight: 44)
            if let loadError {
                errorText(loadError)
            } else if let stats {
                statsBody(stats)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }

    private struct FeatureGroup {
        let id: String
        let name: String
        let tasks: [AdminAiTaskStats]
    }

    /// The features in the order of 「機能ごとの AI」, then any use without a known feature.
    private func groups(_ s: AdminAiStats) -> [FeatureGroup] {
        var out: [FeatureGroup] = []
        var known: Set<String> = []
        for f in settings.features {
            known.insert(f.id)
            let tasks = s.tasks.filter { $0.feature == f.id }
            if !tasks.isEmpty {
                out.append(FeatureGroup(id: f.id, name: Self.localized(f.label, fallback: f.id), tasks: tasks))
            }
        }
        let others = s.tasks.filter { t in t.feature.map { !known.contains($0) } ?? true }
        if !others.isEmpty {
            out.append(FeatureGroup(id: "other", name: L("その他"), tasks: others))
        }
        return out
    }

    /// Each feature's model in use now (`provider:resolved`), to mark its row with 「いま」.
    private var currentModels: [String: String] {
        var out: [String: String] = [:]
        for f in settings.features {
            if let p = f.provider, let m = f.resolved ?? f.model {
                out[f.id] = p + ":" + m
            }
        }
        return out
    }

    @ViewBuilder
    private func statsBody(_ s: AdminAiStats) -> some View {
        let list = groups(s)
        let current = currentModels
        if s.truncated {
            caption(L("記録が多いため、一部だけで数えています。"))
        }
        if list.isEmpty && s.tests.isEmpty {
            caption(L("この期間の記録はまだありません。AI を使う機能を使うと、ここに数が出ます（この画面ができた後の分から）。"))
        }
        ForEach(list, id: \.id) { g in
            VStack(alignment: .leading, spacing: 8) {
                Text(g.name)
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(Theme.foreground)
                ForEach(g.tasks, id: \.task) { t in
                    taskBlock(t, current: current[g.id])
                }
            }
        }
        if !s.tests.isEmpty {
            testsBlock(s.tests)
        }
    }

    private func taskBlock(_ t: AdminAiTaskStats, current: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AdminAiTest.taskName(t.task))
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Theme.foreground)
            ForEach(t.models, id: \.model) { m in
                modelRow(m, isCurrent: m.model == current)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func modelRow(_ m: AdminAiModelStat, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(m.model)
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if isCurrent {
                    Text(L("いま"))
                        .scaledFont(size: 11, weight: .semibold)
                        .foregroundStyle(Theme.primaryInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.secondary, in: Capsule())
                }
            }
            if m.calls > 0 {
                line(speedText(m), strong: false)
            }
            if let p = m.picks {
                line(L("候補の当たり: 1番目 \(Self.pct(p.top1Pct))% · 3番目まで \(Self.pct(p.top3Pct))%（選んだ \(p.n) 回）"),
                     strong: true)
            }
            if let u = m.unusable {
                line(L("使えない返事 \(Self.pct(u.pct))%（\(u.n)/\(u.of)）"), strong: true)
            }
            if m.avgIn != nil || m.costUsd != nil {
                line(costText(cost: m.costUsd, tokensIn: m.avgIn, tokensOut: m.avgOut), strong: false)
            }
        }
    }

    private func speedText(_ m: AdminAiModelStat) -> String {
        var parts = [L("\(m.calls)回 · 成功 \(Self.pct(m.okPct))% · 中央値 \(Self.sec(m.p50))秒 · 90% \(Self.sec(m.p90))秒")]
        if m.timeouts > 0 { parts.append(L("時間切れ \(m.timeouts)")) }
        if m.failed > 0 { parts.append(L("失敗 \(m.failed)")) }
        if m.cancelled > 0 { parts.append(L("追いかけで取り消し \(m.cancelled)")) }
        return parts.joined(separator: " · ")
    }

    private func costText(cost: Double?, tokensIn: Double?, tokensOut: Double?) -> String {
        var parts: [String] = []
        if let c = Self.usd(cost) { parts.append(L("1回 約 $\(c)")) }
        if tokensIn != nil || tokensOut != nil {
            parts.append(L("入力 \(Self.count(tokensIn)) · 出力 \(Self.count(tokensOut)) トークン"))
        }
        return parts.joined(separator: " · ")
    }

    private func testsBlock(_ tests: [AdminAiTestStat]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("固定の写真の試し（モデルごと）"))
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(Theme.foreground)
            ForEach(Array(tests.enumerated()), id: \.offset) { _, x in
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.testTitle(x))
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(Theme.foreground)
                        .textSelection(.enabled)
                    line(L("正解が1番目 \(Self.pct(x.top1Pct))% · 3番目まで \(Self.pct(x.top3Pct))%（\(x.n) 枚）"), strong: true)
                    line(L("答えた写真の時間: 中央値 \(Self.sec(x.p50))秒 · 90% \(Self.sec(x.p90))秒")
                         + (x.failed > 0 ? " · " + L("答えなし \(x.failed) 枚（時間切れ・失敗。時間には入れず、正解の率では外れ）") : "")
                         + (Self.usd(x.costUsd).map { " · " + L("1回 約 $\($0)") } ?? ""), strong: false)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
            }
        }
    }

    /// The model, how it was called and the language its photos were tested in (each its own row).
    private static func testTitle(_ x: AdminAiTestStat) -> String {
        var parts = [x.model]
        if x.variant == "thinking-off" { parts.append(L("考えない")) }
        switch x.lang {
        case "zh-TW"?: parts.append(L("台湾華語"))
        case "en"?: parts.append(L("英語"))
        case "ja"?: parts.append(L("日本語"))
        case let other?: parts.append(other)
        case nil: break
        }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        if let preview {
            stats = preview
            return
        }
        do {
            let s = try await NativeAPI.call("adminGetAiStats", ["days": Int(days) ?? 7, "mine": mine],
                                             as: AdminAiStats.self, timeout: 40)
            if s.isAdmin {
                stats = s
                loadError = nil
            } else {
                loadError = L("この画面は管理者だけが使えます。")
            }
        } catch {
            loadError = Self.message(error)
        }
    }

    // MARK: - Fixed-photo test

    private var testContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption(L("本番の設定は変えずに、選んだモデルへ正解の付いた写真を流し、撮った後の候補と同じ指示で、正解が何番目に出るかと時間を測ります。利用者には影響しません。1日 300 枚まで。"))
            testModelMenu
            HStack {
                fieldLabel(L("学習言語"))
                Spacer(minLength: 8)
                Picker(L("学習言語"), selection: $testLanguage) {
                    Text(L("台湾華語")).tag("zh-TW")
                    Text(L("英語")).tag("en")
                    Text(L("日本語")).tag("ja")
                }
                .pickerStyle(.menu)
                .tint(Theme.primaryInk)
                .disabled(testRunning)
            }
            .frame(minHeight: 44)
            if testIsClaude {
                Toggle(L("Claude に考えさせない（速い方）"), isOn: $testNoThinking)
                    .scaledFont(size: 15)
                    .tint(Theme.primary)
                    .frame(minHeight: 44)
                    .disabled(testRunning)
                caption(L("選ばないと、Claude 5 は考えてから答えます（いまの本番の呼び方と同じ）。"))
            }
            if testRunning {
                HStack(spacing: 10) {
                    actionButton(L("試しています… \(testRows.count)/\(testTotal)"), busy: true, disabled: true) {}
                    Button(L("止める")) { testStop = true }
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Theme.primaryInk)
                        .frame(minHeight: 44)
                }
            } else {
                actionButton(L("試す"), busy: false, disabled: preview != nil) {
                    Task { await runTest() }
                }
                .accessibilityIdentifier("adminAi.test.run")
            }
            if !testRows.isEmpty {
                testRowsView
            }
        }
    }

    /// A Claude 5 model is chosen (the Opus 5 models always think, so they get no switch).
    private var testIsClaude: Bool {
        testValue.hasPrefix("anthropic:claude-") && !testValue.hasPrefix("anthropic:claude-opus-5")
    }

    private var testModelMenu: some View {
        let usable = settings.providers.filter { $0.hasKey && !$0.visionModels.isEmpty }
        return Menu {
            Button {
                testValue = "auto"
            } label: {
                menuItem(L("いまのスキャンの AI"), selected: testValue == "auto")
            }
            ForEach(usable, id: \.id) { p in
                Section(p.name) {
                    ForEach(p.visionModels, id: \.self) { m in
                        Button {
                            testValue = p.id + ":" + m
                        } label: {
                            menuItem(m, selected: testValue == p.id + ":" + m)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(testValue == "auto" ? L("いまのスキャンの AI") : testValue)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .accessibilityHidden(true)
            }
            .scaledFont(size: 15, weight: .semibold)
            .foregroundStyle(Theme.primaryInk)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Theme.secondary, in: Capsule())
        }
        .disabled(testRunning)
        .accessibilityLabel(L("試すモデル"))
    }

    @ViewBuilder
    private func menuItem(_ text: String, selected: Bool) -> some View {
        if selected {
            Label(text, systemImage: "checkmark")
        } else {
            Text(text)
        }
    }

    /// The rates count the photos the server answered (as it records them, a failed answer included); a photo that
    /// never got there (loading, the network, a refusal) is not the model's miss, so it is only counted apart.
    private var testRowsView: some View {
        let answered = testRows.filter { $0.result != nil }
        let top1 = answered.filter { $0.result?.rank == 1 }.count
        let top3 = answered.filter { ($0.result?.rank ?? Int.max) <= 3 }.count
        let n = answered.count
        let unsent = testRows.count - n
        return VStack(alignment: .leading, spacing: 4) {
            Text(L("正解が1番目 \(Self.share(top1, of: n))% · 3番目まで \(Self.share(top3, of: n))%（\(n) 枚）"))
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Theme.foreground)
            if unsent > 0 {
                Text(L("届かなかった \(unsent) 枚は数えていません（写真の読み込み・通信・権限の失敗。下の ! の行）"))
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(testRows) { row in
                Text(rowText(row))
                    .scaledFont(size: 12)
                    .foregroundStyle(row.result == nil ? Theme.destructive : Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private func rowText(_ row: TestRow) -> String {
        guard let r = row.result else { return "! " + row.photo + " — " + (row.error ?? "") }
        let mark = r.rank == 1 ? "◎" : (r.rank != nil ? "○" : "×")
        var text = mark + " " + row.photo + " — " + (r.heads.first ?? "—")
        if r.rank != 1 { text += " (" + L("正解") + ": " + r.want + ")" }
        text += " · " + Self.sec(r.ms) + "s"
        if let code = r.code { text += " · " + code }
        return text
    }

    private func runTest() async {
        guard preview == nil, !testRunning else { return }
        testRunning = true
        testStop = false
        testRows = []
        testTotal = 0
        defer { testRunning = false }
        let list: AdminAiTestPhotos
        do {
            list = try await NativeAPI.call("adminGetAiTestPhotos", [:], as: AdminAiTestPhotos.self, timeout: 30)
        } catch {
            testRows = [TestRow(photo: "—", result: nil, error: Self.message(error))]
            return
        }
        let photos = list.photos
        testTotal = photos.count
        let value = testValue
        let language = testLanguage
        let thinkingOff = testIsClaude && testNoThinking
        var i = 0
        // Two at a time: the free tier's per-minute limit is rarely reached, and a run of 33 takes about a minute.
        while i < photos.count, !testStop {
            async let a = Self.attempt(photos[i], value: value, language: language, thinkingOff: thinkingOff)
            async let b = Self.attempt(i + 1 < photos.count ? photos[i + 1] : nil, value: value, language: language,
                                       thinkingOff: thinkingOff)
            let done = await [a, b].compactMap { $0 }
            testRows.append(contentsOf: done)
            // A refusal for every photo (the daily limit, not an admin, no key) stops the run.
            if done.contains(where: { Self.stopsRun($0.error) }) { testStop = true }
            i += 2
        }
        await load()
    }

    private static func attempt(_ photo: AdminAiTestPhoto?, value: String, language: String,
                                thinkingOff: Bool) async -> TestRow? {
        guard let photo else { return nil }
        do {
            let r = try await AdminAiTest.run(photo: photo, value: value, language: language, thinkingOff: thinkingOff)
            return TestRow(photo: photo.id, result: r, error: nil)
        } catch {
            return TestRow(photo: photo.id, result: nil, error: message(error))
        }
    }

    private static func stopsRun(_ error: String?) -> Bool {
        guard let error else { return false }
        return ["AI_TEST_DAILY_LIMIT", "Forbidden", "鍵"].contains { error.contains($0) }  // l10n-ignore (matching the server text)
    }

    // MARK: - Pieces

    private func line(_ text: String, strong: Bool) -> some View {
        Text(text)
            .scaledFont(size: 12, weight: strong ? .medium : .regular)
            .foregroundStyle(strong ? Theme.foreground : Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 15, weight: .semibold)
            .foregroundStyle(Theme.foreground)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 12)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func errorText(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 13)
            .foregroundStyle(Theme.destructive)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func actionButton(_ title: String, busy: Bool, disabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().tint(.white)
                }
                Text(title)
            }
            .scaledFont(size: 16, weight: .semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Theme.primary.opacity(disabled ? 0.45 : 1), in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled)
    }

    // MARK: - Formatting

    /// 72.5 → "72.5", 100 → "100", nil → "—".
    private static func pct(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private static func share(_ part: Int, of whole: Int) -> String {
        whole > 0 ? pct((Double(part) * 1000 / Double(whole)).rounded() / 10) : "—"
    }

    /// Milliseconds as seconds with one decimal.
    private static func sec(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        return String(format: "%.1f", ms / 1000)
    }

    private static func usd(_ v: Double?) -> String? {
        guard let v else { return nil }
        if v >= 0.01 { return String(format: "%.3f", v) }
        if v >= 0.0001 { return String(format: "%.4f", v) }
        return String(format: "%.1e", v)
    }

    private static func count(_ v: Double?) -> String {
        guard let v else { return "—" }
        return Int(v.rounded()).formatted()
    }

    /// The server's name in the display language, else English, else Japanese.
    private static func localized(_ texts: [String: String], fallback: String) -> String {
        // A language the server has no name in reads the neutral fallback (English), as everywhere else (L10n.text).
        for code in [L10n.lang, DisplayLanguages.fallback, DisplayLanguages.source] {
            if let t = texts[code], !t.isEmpty { return t }
        }
        return fallback
    }

    /// The server's own reason, as it is (the developer reads it). A server without these functions yet
    /// (the web update is not published) answers 404.
    private static func message(_ error: Error) -> String {
        if let e = error as? APIError {
            switch e {
            case .server(404, _):
                return L("サーバがまだこの機能に対応していません（Web の更新を公開すると使えます）。")
            case .server(let code, let text):
                return text.isEmpty ? L("サーバーエラー（\(code)）") : text
            case .limit(let text):
                return text
            default:
                return e.errorDescription ?? L("うまくいきませんでした。もう一度お試しください。")
            }
        }
        return error.localizedDescription
    }
}
