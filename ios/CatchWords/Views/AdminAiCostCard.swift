import SwiftUI

/// 設定 → 開発者 →「AI の設定（開発者）」の「AI の費用」(owner 2026-10-14 「全ての AI の機能を、開発者の私だけ…
/// 機能とモデルごとのコスト管理できるようにして」; web docs/admin-ai-api.md › adminGetAiCosts / adminSetAiPrice).
///
/// - The cost of every AI call = the tokens it used × the model's price per million tokens, summed by use, by model
///   and by day (Japan time). Prices come from the server's checked table; a model without one is shown as
///   「単価未登録」 and left out of the total until a price is typed in here.
/// - The yen figure uses the rate saved on the server (also changed here).
struct AdminAiCostCard: View {
    /// UIPreview only: numbers to show instead of asking the server (nothing is sent).
    var preview: AdminAiCosts? = nil

    @State private var days: String = "30"
    @State private var costs: AdminAiCosts?
    @State private var loadError: String?

    /// The model whose price is being typed in (a sheet).
    @State private var editing: PriceDraft?
    @State private var rateDraft: String = ""
    @State private var rateSaving: Bool = false
    @State private var rateError: String?

    struct PriceDraft: Identifiable {
        var id: String { model }
        let model: String
        var inUsd: String
        var outUsd: String
        let custom: Bool
    }

    var body: some View {
        SettingsCard(title: L("AI の費用")) {
            VStack(alignment: .leading, spacing: 12) {
                caption(L("AI を呼んだ1回ずつの使った量（トークン）× 単価で数えます。単価は 100 万トークンあたりの米ドルです。Google の無料枠で動いている間の実際の請求は 0 円です。日付は日本時間。"))
                ChoicePills(options: [("1", L("1日")), ("7", L("7日")), ("30", L("30日"))], selection: $days)
                if let loadError {
                    errorText(loadError)
                } else if let costs {
                    content(costs)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityIdentifier("adminAi.costs")
        .task(id: days) { await load() }
        .sheet(item: $editing) { draft in
            PriceSheet(draft: draft) { inUsd, outUsd in
                await savePrice(model: draft.model, inUsd: inUsd, outUsd: outUsd)
            } onRemove: {
                await removePrice(model: draft.model)
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ c: AdminAiCosts) -> some View {
        let rate = c.usdJpy
        if c.truncated {
            caption(L("記録が多いため、一部だけで数えています。"))
        }
        totalBlock(c.total, rate: rate)
        if c.total.unpricedCalls > 0 {
            Text(L("単価が未登録のモデルの \(c.total.unpricedCalls) 回は金額に入っていません。下の「モデルごと」で単価を入れてください。"))
                .scaledFont(size: 13, weight: .medium)
                .foregroundStyle(Theme.destructive)
                .fixedSize(horizontal: false, vertical: true)
        }
        if c.total.calls == 0 {
            caption(L("この期間の記録はまだありません。"))
        } else {
            dailyBars(c.daily, rate: rate)
            sectionTitle(L("機能ごと"))
            ForEach(c.tasks, id: \.task) { t in taskRow(t, rate: rate) }
            sectionTitle(L("モデルごと"))
            ForEach(c.models, id: \.model) { m in modelRow(m, rate: rate) }
        }
        rateBlock(rate)
    }

    private func totalBlock(_ t: AdminAiCostSum, rate: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Self.yen(t.usd, rate: rate))
                    .scaledFont(size: 30, weight: .bold, monospacedDigit: true)
                    .foregroundStyle(Theme.foreground)
                Text(Self.dollars(t.usd))
                    .scaledFont(size: 15, weight: .medium, monospacedDigit: true)
                    .foregroundStyle(Theme.muted)
            }
            Text(L("呼び出し \(t.calls) 回（失敗 \(t.failed) 回）・入力 \(Self.tokens(t.tokensIn))・出力 \(Self.tokens(t.tokensOut)) トークン"))
                .scaledFont(size: 13)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("adminAi.costs.total")
    }

    /// One bar per day (Japan time), the height by the day's cost (by the number of calls when nothing is priced).
    private func dailyBars(_ daily: [AdminAiCostDay], rate: Double) -> some View {
        let byCost = daily.contains { $0.usd > 0 }
        let values: [Double] = daily.map { d in byCost ? d.usd : Double(d.calls) }
        let top: Double = max(values.max() ?? 0, 0.000001)
        let peakIndex: Int? = values.indices.max { a, b in values[a] < values[b] }
        let peak: AdminAiCostDay? = peakIndex.map { daily[$0] }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: daily.count > 14 ? 2 : 4) {
                ForEach(Array(daily.enumerated()), id: \.offset) { i, _ in
                    let height = CGFloat(max(3, 64 * values[i] / top))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(values[i] > 0 ? Theme.primary : Theme.border)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
            .frame(height: 64, alignment: .bottom)
            .accessibilityHidden(true)
            HStack {
                Text(Self.shortDay(daily.first?.day ?? ""))
                Spacer()
                if let peak {
                    Text(byCost
                         ? L("最多: \(Self.shortDay(peak.day)) \(Self.yen(peak.usd, rate: rate))")
                         : L("最多: \(Self.shortDay(peak.day)) \(peak.calls) 回"))
                }
                Spacer()
                Text(Self.shortDay(daily.last?.day ?? ""))
            }
            .scaledFont(size: 11, monospacedDigit: true)
            .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
    }

    private func taskRow(_ t: AdminAiCostTask, rate: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.localized(t.label, fallback: t.task))
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Theme.foreground)
                if !t.ios {
                    Text(L("Web 版"))
                        .scaledFont(size: 11, weight: .semibold)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                }
                Spacer(minLength: 6)
                Text(Self.yen(t.sum.usd, rate: rate))
                    .scaledFont(size: 15, weight: .semibold, monospacedDigit: true)
                    .foregroundStyle(Theme.foreground)
            }
            Text(L("\(t.sum.calls) 回（失敗 \(t.sum.failed) 回）・入力 \(Self.tokens(t.sum.tokensIn))・出力 \(Self.tokens(t.sum.tokensOut))"))
                .scaledFont(size: 12, monospacedDigit: true)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(t.models, id: \.model) { m in
                Text(Self.modelLine(m, rate: rate))
                    .scaledFont(size: 12, monospacedDigit: true)
                    .foregroundStyle(m.usd == nil ? Theme.destructive : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func modelRow(_ m: AdminAiCostModel, rate: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(m.model)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 6)
                Text(m.price == nil ? L("単価未登録") : Self.yen(m.sum.usd, rate: rate))
                    .scaledFont(size: 14, weight: .semibold, monospacedDigit: true)
                    .foregroundStyle(m.price == nil ? Theme.destructive : Theme.foreground)
            }
            Text(L("\(m.sum.calls) 回（失敗 \(m.sum.failed) 回）・入力 \(Self.tokens(m.sum.tokensIn))・出力 \(Self.tokens(m.sum.tokensOut))"))
                .scaledFont(size: 12, monospacedDigit: true)
                .foregroundStyle(Theme.muted)
            if let p = m.price {
                Text(Self.priceLine(p))
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                editing = PriceDraft(model: m.model,
                                     inUsd: m.price.map { Self.price($0.inUsd) } ?? "",
                                     outUsd: m.price.map { Self.price($0.outUsd) } ?? "",
                                     custom: m.price?.custom ?? false)
            } label: {
                Text(m.price == nil ? L("単価を入れる") : L("単価を変える"))
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Theme.primaryInk)
                    .frame(minHeight: 44)
            }
            .disabled(preview != nil)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func rateBlock(_ rate: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L("為替"))
            Text(L("1 ドル = \(Self.price(rate)) 円で計算しています。"))
                .scaledFont(size: 14)
                .foregroundStyle(Theme.foreground)
            HStack(spacing: 10) {
                TextField(Self.price(rate), text: $rateDraft)
                    .keyboardType(.decimalPad)
                    .scaledFont(size: 15, monospacedDigit: true)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Theme.card, in: .rect(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    .accessibilityLabel(L("1 ドルあたりの円"))
                Button {
                    Task { await saveRate() }
                } label: {
                    HStack(spacing: 6) {
                        if rateSaving { ProgressView() }
                        Text(L("保存"))
                    }
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Theme.primaryInk)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Theme.secondary, in: Capsule())
                }
                .disabled(rateSaving || Self.number(rateDraft) == nil || preview != nil)
            }
            if let rateError {
                errorText(rateError)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Server

    private func load() async {
        if let preview {
            costs = preview
            return
        }
        do {
            let c = try await NativeAPI.call("adminGetAiCosts", ["days": Int(days) ?? 30], as: AdminAiCosts.self,
                                             timeout: 40)
            if c.isAdmin {
                costs = c
                loadError = nil
            } else {
                loadError = L("この画面は管理者だけが使えます。")
            }
        } catch {
            loadError = Self.message(error)
        }
    }

    /// Saves one model's price; the reason it failed, or nil.
    private func savePrice(model: String, inUsd: Double, outUsd: Double) async -> String? {
        do {
            _ = try await NativeAPI.call("adminSetAiPrice", ["model": model, "inUsd": inUsd, "outUsd": outUsd],
                                         timeout: 30)
            await load()
            return nil
        } catch {
            return Self.message(error)
        }
    }

    private func removePrice(model: String) async -> String? {
        do {
            _ = try await NativeAPI.call("adminSetAiPrice", ["model": model, "remove": true], timeout: 30)
            await load()
            return nil
        } catch {
            return Self.message(error)
        }
    }

    private func saveRate() async {
        guard let v = Self.number(rateDraft) else { return }
        rateSaving = true
        rateError = nil
        do {
            _ = try await NativeAPI.call("adminSetAiPrice", ["usdJpy": v], timeout: 30)
            rateDraft = ""
            await load()
        } catch {
            rateError = Self.message(error)
        }
        rateSaving = false
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 16, weight: .semibold)
            .foregroundStyle(Theme.foreground)
            .padding(.top, 6)
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

    // MARK: - Formatting

    /// "· google:gemini-3.8-flash  19 回  ¥6.4" (「単価未登録」 when the model has no price).
    static func modelLine(_ m: AdminAiCostTask.Model, rate: Double) -> String {
        let cost: String = m.usd.map { yen($0, rate: rate) } ?? L("単価未登録")
        return "· " + m.model + "  " + L("\(m.calls) 回") + "  " + cost
    }

    static func priceLine(_ p: AdminAiPrice) -> String {
        let head: String = L("単価: 入力 $\(price(p.inUsd)) / 出力 $\(price(p.outUsd))（100 万トークン）")
        let from: String = p.custom ? L("入力した値") : p.source
        return head + " · " + from
    }

    /// Dollars → yen at `rate`: "¥0", "¥0.42", "¥12.5", "¥1,234".
    static func yen(_ usd: Double, rate: Double) -> String {
        let y = usd * rate
        if y <= 0 { return "¥0" }
        if y < 1 { return String(format: "¥%.2f", y) }
        if y < 100 { return String(format: "¥%.1f", y) }
        return "¥" + Int(y.rounded()).formatted()
    }

    static func dollars(_ v: Double) -> String {
        if v <= 0 { return "$0" }
        return v < 0.01 ? String(format: "$%.4f", v) : String(format: "$%.2f", v)
    }

    /// 1234567 → "1.2M", 12345 → "12.3k", 980 → "980".
    static func tokens(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fk", v / 1_000) }
        return String(Int(v.rounded()))
    }

    /// A price without trailing zeros: 0.75 → "0.75", 4 → "4", 156 → "156".
    static func price(_ v: Double) -> String {
        var s = String(format: "%.4f", v)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// "2026-10-14" → "10/14".
    static func shortDay(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return day }
        return "\(m)/\(d)"
    }

    /// A typed number ("0.3", "0,3", "１５６") or nil.
    static func number(_ text: String) -> Double? {
        let t = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let v = Double(t.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        return v.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }

    private static func localized(_ texts: [String: String], fallback: String) -> String {
        // A language the server has no name in reads the neutral fallback (English), as everywhere else (L10n.text).
        for code in [L10n.lang, DisplayLanguages.fallback, DisplayLanguages.source] {
            if let t = texts[code], !t.isEmpty { return t }
        }
        return fallback
    }

    /// The server's own reason (the developer reads it). A server without these functions yet answers 404.
    static func message(_ error: Error) -> String {
        if let e = error as? APIError {
            switch e {
            case .server(404, _):
                return L("サーバがまだこの機能に対応していません（Web の更新を公開すると使えます）。")
            case .server(let code, let text):
                return text.isEmpty ? L("サーバーエラー（\(code)）") : text
            default:
                return e.errorDescription ?? L("うまくいきませんでした。もう一度お試しください。")
            }
        }
        return error.localizedDescription
    }
}

/// Typing in one model's price (US dollars per million tokens, input and output).
private struct PriceSheet: View {
    let draft: AdminAiCostCard.PriceDraft
    let onSave: (Double, Double) async -> String?
    let onRemove: () async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var inUsd: String = ""
    @State private var outUsd: String = ""
    @State private var busy: Bool = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(draft.model)
                        .scaledFont(size: 15, weight: .semibold)
                        .textSelection(.enabled)
                } footer: {
                    Text(L("各社の料金表の「100 万トークンあたり」の値を米ドルで入れます。Lovable・OpenRouter を通した呼び出しは、それぞれの請求画面の単価を入れてください。"))
                }
                Section(L("入力（100 万トークンあたり $）")) {
                    TextField("0.30", text: $inUsd)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("adminAi.price.in")
                }
                Section(L("出力（100 万トークンあたり $）")) {
                    TextField("2.50", text: $outUsd)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("adminAi.price.out")
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(Theme.destructive)
                    }
                }
                if draft.custom {
                    Section {
                        Button(L("入れた単価を消す"), role: .destructive) {
                            Task {
                                busy = true
                                error = await onRemove()
                                busy = false
                                if error == nil { dismiss() }
                            }
                        }
                        .disabled(busy)
                    }
                }
            }
            .navigationTitle(L("単価"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("閉じる")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("保存")) {
                        guard let i = AdminAiCostCard.number(inUsd), let o = AdminAiCostCard.number(outUsd) else { return }
                        Task {
                            busy = true
                            error = await onSave(i, o)
                            busy = false
                            if error == nil { dismiss() }
                        }
                    }
                    .disabled(busy || AdminAiCostCard.number(inUsd) == nil || AdminAiCostCard.number(outUsd) == nil)
                }
            }
            .onAppear {
                inUsd = draft.inUsd
                outUsd = draft.outUsd
            }
        }
    }
}
