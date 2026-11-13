import SwiftUI

/// What 「AI を選ぶ」 is choosing for (`AdminAiSettingsView`).
enum AdminAiPickTarget: Identifiable, Hashable {
    /// 「使う AI」: every use at once (`adminSetAiAll`).
    case all
    /// 「落ちた時の控え」 of every use (`adminSetAiBackup`).
    case backup
    /// One use's own model (`adminSetAiTask` value).
    case task(String)
    /// One use's own backup (`adminSetAiTask` backup).
    case taskBackup(String)

    var id: String {
        switch self {
        case .all: return "all"
        case .backup: return "backup"
        case .task(let t): return "task." + t
        case .taskBackup(let t): return "taskBackup." + t
        }
    }

    var isBackup: Bool {
        switch self {
        case .backup, .taskBackup: return true
        default: return false
        }
    }

    var taskId: String? {
        switch self {
        case .task(let t), .taskBackup(let t): return t
        default: return nil
        }
    }
}

/// One model picked in the list, on its way to the confirm screen.
struct AdminAiChoice: Hashable, Identifiable {
    var provider: String
    var model: String
    var name: String
    var price: String
    var id: String { provider + ":" + model }
}

/// 「AI を選ぶ」: each provider's live models, newest first. A provider without a key is grey and cannot be chosen;
/// a model that cannot read photos cannot be chosen where a photo use needs it; previews, experiments and two
/// generations back are folded under 「古い版・試験版」. A model without a price can be given one here.
struct AdminAiModelPicker: View {
    let settings: AdminAiSettings
    let target: AdminAiPickTarget
    /// UIPreview: nothing is sent.
    var previewOnly: Bool = false
    /// Called after anything was saved (the settings screen reloads).
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var provider: String = ""
    @State private var query: String = ""
    @State private var showFolded: Bool = false
    @State private var chosen: AdminAiChoice?
    @State private var pricing: AdminAiChoice?
    @State private var priceIn: String = ""
    @State private var priceOut: String = ""
    @State private var priceError: String?
    @State private var savingSpecial: Bool = false
    @State private var specialError: String?

    private var task: AdminAiTaskSetting? {
        target.taskId.flatMap { id in settings.tasks.first { $0.id == id } }
    }

    /// Photo uses take only models that read photos (every use for 「使う AI」 and the shared backup).
    private var needsVision: Bool {
        switch target {
        case .all, .backup: return true
        case .task, .taskBackup: return task?.needsVision ?? false
        }
    }

    /// The `provider:model` this target uses now (nil: auto / off).
    private var current: String? {
        switch target {
        case .all: return settings.main?.value
        case .backup: return settings.backup.contains(":") ? settings.backup : nil
        case .task:
            guard let t = task, let p = t.provider else { return nil }
            return p + ":" + (t.resolved ?? t.model ?? "")
        case .taskBackup:
            guard let t = task, t.backup.contains(":") else { return nil }
            return t.backup
        }
    }

    private var title: String {
        switch target {
        case .all: return L("全部の用途")
        case .backup: return L("落ちた時の控え（全部の用途）")
        case .task:
            return task.map { AdminAiModelPicker.localized($0.label, fallback: $0.id) } ?? ""
        case .taskBackup:
            let name = task.map { AdminAiModelPicker.localized($0.label, fallback: $0.id) } ?? ""
            return L("\(name)の控え")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if target.isBackup {
                        specialRows
                    }
                    providerChips
                    searchField
                    if let priceError {
                        caption(priceError)
                    }
                    modelList
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle(L("AI を選ぶ"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("閉じる")) { dismiss() }
                }
            }
            .navigationDestination(item: $chosen) { c in
                AdminAiApplyView(settings: settings, target: target, choice: c, previewOnly: previewOnly,
                                 onChanged: onChanged) { dismiss() }
            }
            .alert(L("値段を入れる"), isPresented: Binding(get: { pricing != nil }, set: { if !$0 { pricing = nil } })) {
                TextField(L("入力（米ドル / 100万トークン）"), text: $priceIn)
                    .keyboardType(.decimalPad)
                TextField(L("出力（米ドル / 100万トークン）"), text: $priceOut)
                    .keyboardType(.decimalPad)
                Button(L("保存")) { Task { await savePrice() } }
                Button(L("キャンセル"), role: .cancel) { pricing = nil }
            } message: {
                Text(pricing?.name ?? "")
            }
        }
        .onAppear {
            if provider.isEmpty {
                let cur = current.map { AdminAiSettingsView.split($0).0 }
                provider = cur.flatMap { c in settings.catalog.first { $0.id == c && $0.hasKey }?.id }
                    ?? settings.catalog.first { $0.hasKey }?.id ?? settings.catalog.first?.id ?? ""
            }
        }
    }

    // MARK: - Backup: automatic / none

    private var specialRows: some View {
        let value: String = {
            switch target {
            case .backup: return settings.backup
            default: return task?.backup ?? "auto"
            }
        }()
        return VStack(alignment: .leading, spacing: 8) {
            specialRow(L("自動（既定の控え）"), on: value == "auto", id: "auto")
            specialRow(L("控えを使わない"), on: value == "off", id: "off")
            if let specialError {
                Text(specialError)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func specialRow(_ text: String, on: Bool, id: String) -> some View {
        Button {
            guard !on else { return }
            Haptics.selection()
            Task { await saveSpecial(id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Theme.primary : Theme.muted)
                    .accessibilityHidden(true)
                Text(text)
                    .scaledFont(size: 15, weight: .medium)
                    .foregroundStyle(Theme.foreground)
                Spacer()
                if savingSpecial && !on { ProgressView() }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Theme.card, in: .rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(savingSpecial)
        .accessibilityIdentifier("adminAi.pick.\(id)")
    }

    private func saveSpecial(_ value: String) async {
        guard !previewOnly else { return }
        savingSpecial = true
        specialError = nil
        do {
            switch target {
            case .backup:
                _ = try await NativeAPI.call("adminSetAiBackup", ["backup": value], timeout: 30)
            case .taskBackup(let t):
                _ = try await NativeAPI.call("adminSetAiTask", ["task": t, "backup": value], timeout: 30)
            default:
                break
            }
            await onChanged()
            dismiss()
        } catch {
            specialError = AdminAiModelPicker.message(error)
        }
        savingSpecial = false
    }

    // MARK: - Providers, search, models

    private var providerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(settings.catalog) { p in
                    let on = p.id == provider
                    Button {
                        Haptics.selection()
                        provider = p.id
                        showFolded = false
                    } label: {
                        Text(p.name)
                            .scaledFont(size: 14, weight: on ? .semibold : .regular)
                            .foregroundStyle(on ? Color.white : (p.hasKey ? Theme.foreground : Theme.muted.opacity(0.6)))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(on ? Theme.primary : Theme.secondary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!p.hasKey)
                    .accessibilityIdentifier("adminAi.pick.provider.\(p.id)")
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            TextField(L("モデルを探す"), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("adminAi.pick.search")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Theme.card, in: .rect(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var modelList: some View {
        let p = settings.catalog.first { $0.id == provider }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let models = (p?.models ?? []).filter {
            q.isEmpty || $0.id.lowercased().contains(q) || $0.name.lowercased().contains(q)
        }
        let open = models.filter { !$0.folded }
        let folded = models.filter(\.folded)
        if let p, !p.hasKey {
            caption(L("この会社の鍵がサーバにありません"))
        } else if let error = p?.error {
            caption(error)
        }
        if models.isEmpty, p?.hasKey == true {
            caption(L("使えるモデルがありません"))
        }
        if !open.isEmpty {
            Text(L("新しい順"))
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Theme.muted)
            listCard(open, provider: provider)
        }
        if !folded.isEmpty {
            Button {
                Haptics.selection()
                withAnimation(.snappy(duration: 0.25)) { showFolded.toggle() }
            } label: {
                HStack {
                    Text(L("古い版・試験版（\(folded.count)）"))
                        .scaledFont(size: 15, weight: .medium)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Image(systemName: showFolded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Theme.card, in: .rect(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("adminAi.pick.folded")
            if showFolded {
                listCard(folded, provider: provider)
            }
        }
    }

    private func listCard(_ models: [AdminAiCatalogModel], provider: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(models.enumerated()), id: \.element.id) { i, m in
                if i > 0 {
                    Divider().overlay(Theme.border)
                }
                modelRow(m, provider: provider)
            }
        }
        .padding(.horizontal, 14)
        .background(Theme.card, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func modelRow(_ m: AdminAiCatalogModel, provider: String) -> some View {
        let blocked = needsVision && !m.vision
        let isCurrent = current == provider + ":" + m.id
        let priceText = AdminAiSettingsView.priceText(m.price)
        return HStack(alignment: .center, spacing: 10) {
            Button {
                guard !blocked else { return }
                Haptics.selection()
                chosen = AdminAiChoice(provider: provider, model: m.id, name: m.name, price: priceText)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(m.name)
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundStyle(blocked ? Theme.muted : Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        if m.isNew { NewBadge() }
                        if isCurrent { InUseBadge() }
                    }
                    if m.name != m.id {
                        Text(m.id)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }
                    Text(blocked ? L("写真を読めないため、ここには選べません")
                         : m.vision ? L("\(priceText)　写真を読める") : priceText)
                        .scaledFont(size: 12)
                        .foregroundStyle(blocked ? Theme.destructive.opacity(0.8) : Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(blocked)
            .accessibilityIdentifier("adminAi.pick.model.\(m.id)")
            if m.price == nil {
                Button(L("値段を入れる")) {
                    priceIn = ""
                    priceOut = ""
                    priceError = nil
                    pricing = AdminAiChoice(provider: provider, model: m.id, name: m.name, price: "")
                }
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Theme.primaryInk)
                .buttonStyle(.plain)
            } else if !blocked {
                Image(systemName: "chevron.right")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
        }
    }

    private func savePrice() async {
        guard let p = pricing, !previewOnly else { pricing = nil; return }
        let i = Double(priceIn.replacingOccurrences(of: ",", with: "."))
        let o = Double(priceOut.replacingOccurrences(of: ",", with: "."))
        pricing = nil
        guard let i, let o else { return }
        do {
            _ = try await NativeAPI.call("adminSetAiPrice", ["model": p.id, "inUsd": i, "outUsd": o], timeout: 30)
            await onChanged()
        } catch {
            priceError = AdminAiModelPicker.message(error)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 13)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The server's name / description in the display language, else English, else Japanese.
    static func localized(_ texts: [String: String], fallback: String) -> String {
        for code in [L10n.lang, DisplayLanguages.fallback, DisplayLanguages.source] {
            if let t = texts[code], !t.isEmpty { return t }
        }
        return fallback
    }

    /// The server's own reason, as it is (the developer reads it).
    static func message(_ error: Error) -> String {
        if let e = error as? APIError {
            switch e {
            case .server(let code, let text):
                return text.isEmpty ? L("サーバーエラー（\(code)）") : text
            default:
                return e.errorDescription ?? L("うまくいきませんでした。もう一度お試しください。")
            }
        }
        return error.localizedDescription
    }
}

/// Before a model is applied: it is called once (only a model that answered can be applied), and the last 30 days'
/// tokens are priced now and with it. After 「全部の用途をこの AI にする」 the change can be undone here.
struct AdminAiApplyView: View {
    let settings: AdminAiSettings
    let target: AdminAiPickTarget
    let choice: AdminAiChoice
    var previewOnly: Bool = false
    let onChanged: () async -> Void
    let close: () -> Void

    @State private var testing: Bool = false
    @State private var test: AdminAiModelTest?
    @State private var testError: String?
    @State private var estimate: AdminAiCostEstimate?
    @State private var applying: Bool = false
    @State private var applied: Bool = false
    @State private var applyError: String?
    @State private var undoing: Bool = false

    private var taskName: String {
        guard let id = target.taskId, let t = settings.tasks.first(where: { $0.id == id }) else { return "" }
        return AdminAiModelPicker.localized(t.label, fallback: t.id)
    }

    /// Uses that run on another model than 「使う AI」 now (they change too).
    private var otherUses: Int { settings.tasks.filter { $0.ios && !$0.sameAsMain }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProviderMark(provider: choice.provider)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(choice.name)
                            .scaledFont(size: 19, weight: .bold)
                            .foregroundStyle(Theme.foreground)
                        Text(choice.model)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .textSelection(.enabled)
                        Text(choice.price)
                            .scaledFont(size: 12)
                            .foregroundStyle(Theme.muted)
                    }
                }
                testRow
                if !target.isBackup {
                    costCard
                }
                buttons
                if let applyError {
                    Text(applyError)
                        .scaledFont(size: 13)
                        .foregroundStyle(Theme.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(16)
        }
        .background(AppBackground())
        .navigationTitle(L("替える前の確認"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !previewOnly else { return }
            if !target.isBackup {
                Task { await runEstimate() }
            }
            await runTest()
        }
    }

    // MARK: - Test call

    @ViewBuilder
    private var testRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if testing {
                ProgressView()
                Text(L("試しに1回呼んでいます…"))
                    .scaledFont(size: 14)
                    .foregroundStyle(Theme.muted)
            } else if let test, test.ok {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.ok)
                    .accessibilityHidden(true)
                Text(L("試しに1回呼びました：成功・\(String(format: "%.1f", test.ms / 1000)) 秒"))
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Theme.ok)
            } else if previewOnly {
                Text(L("見本の画面では試しません"))
                    .scaledFont(size: 14)
                    .foregroundStyle(Theme.muted)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.destructive)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("このモデルは動きませんでした"))
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Theme.destructive)
                    if let msg = test?.error ?? testError {
                        Text(msg)
                            .scaledFont(size: 12)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    Button(L("もう一度試す")) { Task { await runTest() } }
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Theme.primaryInk)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("adminAi.apply.test")
    }

    private func runTest() async {
        testing = true
        testError = nil
        do {
            test = try await NativeAPI.call("adminTestAiModel", ["value": choice.id], as: AdminAiModelTest.self, timeout: 45)
        } catch {
            test = nil
            testError = AdminAiModelPicker.message(error)
        }
        testing = false
    }

    // MARK: - Cost now / after

    @ViewBuilder
    private var costCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("直近30日の量で比べた費用（月）"))
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Theme.muted)
            if let e = estimate {
                let after = e.afterJpy
                let top = max(e.nowJpy, after ?? 0, 1)
                costBar(L("今"), yen: e.nowJpy, share: e.nowJpy / top, color: Theme.muted.opacity(0.45))
                if let after {
                    costBar(L("替えた後"), yen: after, share: after / top, color: Theme.primary)
                } else {
                    Text(L("このモデルの値段が未登録のため、替えた後の費用は出せません"))
                        .scaledFont(size: 12)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if e.unpricedNow > 0 {
                    Text(L("今の費用には、値段未登録のモデルの \(e.unpricedNow) 回が入っていません"))
                        .scaledFont(size: 12)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if target.taskId != nil {
                    Text(L("全部の用途を替えた場合の費用です"))
                        .scaledFont(size: 12)
                        .foregroundStyle(Theme.muted)
                }
            } else if previewOnly {
                Text("—").foregroundStyle(Theme.muted)
            } else {
                ProgressView()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("adminAi.apply.cost")
    }

    private func costBar(_ label: String, yen: Double, share: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .scaledFont(size: 13)
                .foregroundStyle(Theme.foreground)
                .frame(width: 64, alignment: .leading)
            GeometryReader { g in
                Capsule()
                    .fill(color)
                    .frame(width: max(4, g.size.width * min(1, max(0, share))), height: 12)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)
            Text("¥" + Int(yen.rounded()).formatted())
                .scaledFont(size: 13, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(Theme.foreground)
        }
        .accessibilityElement(children: .combine)
    }

    private func runEstimate() async {
        estimate = try? await NativeAPI.call("adminEstimateAiCost", ["value": choice.id], as: AdminAiCostEstimate.self,
                                             timeout: 40)
    }

    // MARK: - Apply

    @ViewBuilder
    private var buttons: some View {
        let ready = test?.ok == true && !applying && !applied
        VStack(alignment: .leading, spacing: 10) {
            if applied {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.ok)
                        .accessibilityHidden(true)
                    Text(L("替えました"))
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Theme.ok)
                }
                if target == .all {
                    secondaryButton(L("前の設定に戻す"), busy: undoing) { Task { await undo() } }
                        .accessibilityIdentifier("adminAi.apply.undo")
                }
                primaryButton(L("閉じる"), busy: false, enabled: true) { close() }
            } else {
                switch target {
                case .all:
                    primaryButton(L("全部の用途をこの AI にする"), busy: applying, enabled: ready) {
                        Task { await apply(all: true) }
                    }
                    .accessibilityIdentifier("adminAi.apply.all")
                    if otherUses > 0 {
                        fine(L("別の AI にしている用途（\(otherUses) つ）も替わります。替えた後、前の設定に1回だけ戻せます。"))
                    } else {
                        fine(L("替えた後、前の設定に1回だけ戻せます。"))
                    }
                case .task:
                    primaryButton(L("この用途だけ（\(taskName)）"), busy: applying, enabled: ready) {
                        Task { await apply(all: false) }
                    }
                    .accessibilityIdentifier("adminAi.apply.one")
                    secondaryButton(L("全部の用途をこの AI にする"), busy: false) {
                        Task { await apply(all: true) }
                    }
                    .disabled(!ready)
                    .opacity(ready ? 1 : 0.45)
                case .backup:
                    primaryButton(L("控えにする"), busy: applying, enabled: ready) {
                        Task { await apply(all: false) }
                    }
                    .accessibilityIdentifier("adminAi.apply.backup")
                case .taskBackup:
                    primaryButton(L("この用途の控えにする（\(taskName)）"), busy: applying, enabled: ready) {
                        Task { await apply(all: false) }
                    }
                    .accessibilityIdentifier("adminAi.apply.taskBackup")
                }
                if test?.ok != true && !testing && !previewOnly {
                    fine(L("試しに呼んで動いたモデルだけ選べます。"))
                }
            }
        }
    }

    private func apply(all: Bool) async {
        guard !previewOnly else { return }
        applying = true
        applyError = nil
        do {
            if all {
                _ = try await NativeAPI.call("adminSetAiAll", ["value": choice.id], timeout: 30)
            } else {
                switch target {
                case .backup:
                    _ = try await NativeAPI.call("adminSetAiBackup", ["backup": choice.id], timeout: 30)
                case .task(let t):
                    _ = try await NativeAPI.call("adminSetAiTask", ["task": t, "value": choice.id], timeout: 30)
                case .taskBackup(let t):
                    _ = try await NativeAPI.call("adminSetAiTask", ["task": t, "backup": choice.id], timeout: 30)
                case .all:
                    _ = try await NativeAPI.call("adminSetAiAll", ["value": choice.id], timeout: 30)
                }
            }
            Haptics.success()
            applied = true
            await onChanged()
        } catch {
            applyError = AdminAiModelPicker.message(error)
        }
        applying = false
    }

    private func undo() async {
        undoing = true
        applyError = nil
        do {
            _ = try await NativeAPI.call("adminUndoAiModels", [:], timeout: 30)
            await onChanged()
            close()
        } catch {
            applyError = AdminAiModelPicker.message(error)
        }
        undoing = false
    }

    private func primaryButton(_ title: String, busy: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text(title)
                    .multilineTextAlignment(.center)
            }
            .scaledFont(size: 16, weight: .semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.primary.opacity(enabled ? 1 : 0.45), in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }

    private func secondaryButton(_ title: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView() }
                Text(title)
                    .multilineTextAlignment(.center)
            }
            .scaledFont(size: 15, weight: .semibold)
            .foregroundStyle(Theme.primaryInk)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(busy)
    }

    private func fine(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 12)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The green 「New」 mark of a model the server first saw in the last 14 days (shared term, not translated — R25).
struct NewBadge: View {
    var body: some View {
        Text(verbatim: "New")
            .scaledFont(size: 11, weight: .heavy)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.ok, in: Capsule())
            .accessibilityLabel(Text(verbatim: "New"))
    }
}

/// 「使用中」: the model the target runs on now.
struct InUseBadge: View {
    var body: some View {
        Text(L("使用中"))
            .scaledFont(size: 11, weight: .heavy)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.primary, in: Capsule())
    }
}

/// The provider's first letter in a rounded square (no logos: brand marks are not ours to draw).
struct ProviderMark: View {
    let provider: String

    var body: some View {
        Text(verbatim: String(provider.prefix(1)).uppercased())
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
                LinearGradient(colors: [Color(hex: 0x4F8DF7), Color(hex: 0x8E6CF0)], startPoint: .topLeading,
                               endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 12, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
