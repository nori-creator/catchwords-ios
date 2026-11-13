import SwiftUI
import UIKit

/// 設定 → 開発者 →「AI の設定（開発者）」: admins only (`AdminAccess`), through the server's admin functions
/// (server/src/lib/admin-ai.server.ts). Rebuilt 2026-11-13 (owner: 「毎回 Google が新しいモデルを出すたびに AI の設定から
/// 変更できるように」, mock-up https://claude.ai/artifact/V6CDvMNQoRwVNVhqUQpdQm, A):
/// - the state of the last hour (successes, failures, average seconds);
/// - 「使う AI」: one model for every use of the AI. 「AI を選ぶ」 opens the live list of each provider, newest first
///   (`AdminAiModelPicker`), New marks for models the server first saw in the last 14 days; before applying, the model
///   is called once and the month's cost now and after is compared (`AdminAiApplyView`); one step can be undone.
///   The 「いつも最新（自動）」 choice is gone (Google's names no longer say flash / pro);
/// - 「落ちた時の控え」 for every use, and the 30 days' cost;
/// - 「用途ごと」: this app's uses folded into groups (写真・カード・復習・日記・報告と点検); a use can take its own model
///   or backup;
/// - 「ほかの AI」: the pronunciation voices and the AI images, each on its own screen;
/// - what the AI cost (`AdminAiCostCard`) and the speed and accuracy by model (`AdminAiStatsCard`).
/// Server messages are shown as they come (this screen is for the developer, not for learners).
struct AdminAiSettingsView: View {
    /// UIPreview only: settings to show instead of asking the server (nothing is sent).
    var preview: AdminAiSettings? = nil
    /// UIPreview only: the speed and accuracy numbers to show with them.
    var previewStats: AdminAiStats? = nil
    /// UIPreview only: the costs to show with them.
    var previewCosts: AdminAiCosts? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var settings: AdminAiSettings?
    @State private var loadError: String?
    /// What 「AI を選ぶ」 is open for.
    @State private var picking: AdminAiPickTarget?
    /// Group ids opened in 「用途ごと」.
    @State private var openGroups: Set<String> = []
    @State private var undoing: Bool = false
    @State private var undoError: String?

    @State private var imageProvider: String = ""
    @State private var imageModel: String = ""
    @State private var imageSaving: Bool = false
    @State private var imageNotice: String?
    @State private var imageError: String?
    @State private var testQuery: String = ""
    @State private var testing: Bool = false
    @State private var testResult: AdminAiImageTest?
    @State private var testError: String?
    @State private var testPicture: UIImage?
    @State private var testPictureURL: URL?

    @State private var voiceDrafts: [String: AdminVoiceDraft] = [:]
    @State private var voiceSaving: String?
    @State private var voiceNotices: [String: String] = [:]
    @State private var voiceErrors: [String: String] = [:]

    /// The learning languages, in the web's order.
    private static let ttsLanguages = ["zh-TW", "en", "ja"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let loadError {
                    errorBanner(loadError)
                }
                if let settings {
                    statusCard(settings)
                    mainCard(settings)
                    usesCard(settings)
                    othersCard(settings)
                    AdminAiCostCard(preview: previewCosts)
                    AdminAiStatsCard(settings: settings, preview: previewStats)
                } else if loadError == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .refreshable { await load() }
        .navigationTitle(L("AI の設定（開発者）"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("閉じる")) { dismiss() }
            }
        }
        .sheet(item: $picking) { target in
            if let settings {
                AdminAiModelPicker(settings: settings, target: target, previewOnly: preview != nil) {
                    await load()
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Status

    private func statusCard(_ s: AdminAiSettings) -> some View {
        let color: Color = s.status.ok ? Theme.ok : Theme.destructive
        let icon: String = s.status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        return SettingsCard(title: L("状態")) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: icon)
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(color)
                        .accessibilityHidden(true)
                    Text(s.status.ok ? L("AI は動いています") : (s.status.error ?? L("AI が動いていません")))
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(recentText(s.recent))
                    .scaledFont(size: 13)
                    .foregroundStyle(s.recent.failed > 0 ? Theme.destructive : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("adminAi.status")
        }
    }

    private func recentText(_ r: AdminAiRecent) -> String {
        if r.ok + r.failed == 0 {
            return L("直近1時間の呼び出しはありません")
        }
        let avg = r.avgMs.map { String(format: "%.1f", $0 / 1000) } ?? "—"
        return L("直近1時間　成功 \(r.ok) 回・失敗 \(r.failed) 回・平均 \(avg) 秒")
    }

    // MARK: - 使う AI

    private func mainCard(_ s: AdminAiSettings) -> some View {
        let newCount = s.catalog.filter(\.hasKey).flatMap(\.models).filter(\.isNew).count
        return SettingsCard(title: L("使う AI")) {
            VStack(alignment: .leading, spacing: 14) {
                if newCount > 0 {
                    Button {
                        Haptics.selection()
                        picking = .all
                    } label: {
                        HStack(spacing: 8) {
                            NewBadge()
                            Text(L("新しいモデルが \(newCount) つ出ました"))
                                .scaledFont(size: 14, weight: .semibold)
                                .foregroundStyle(Theme.primaryInk)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .scaledFont(size: 13, weight: .semibold)
                                .foregroundStyle(Theme.primaryInk)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Theme.accent, in: .rect(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("adminAi.newModels")
                }
                if let main = s.main {
                    HStack(alignment: .center, spacing: 12) {
                        ProviderMark(provider: main.provider)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(main.name)
                                .scaledFont(size: 19, weight: .bold)
                                .foregroundStyle(Theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(main.model)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                                .textSelection(.enabled)
                            Text(Self.priceText(main.price))
                                .scaledFont(size: 12)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("adminAi.main")
                } else {
                    caption(L("まだ選んでいません（サーバの既定の AI で動いています）"))
                }
                actionButton(L("AI を選ぶ"), busy: false, disabled: false) {
                    Haptics.selection()
                    picking = .all
                }
                .accessibilityIdentifier("adminAi.choose")
                if s.undoAvailable {
                    Button {
                        Task { await undo() }
                    } label: {
                        HStack(spacing: 6) {
                            if undoing { ProgressView() }
                            Text(L("前の設定に戻す"))
                        }
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Theme.primaryInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.secondary, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(undoing)
                    .accessibilityIdentifier("adminAi.undo")
                }
                if let undoError {
                    errorText(undoError)
                }
                Divider().overlay(Theme.border)
                Button {
                    Haptics.selection()
                    picking = .backup
                } label: {
                    keyValueRow(L("落ちた時の控え"), value: backupText(s), chevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("adminAi.backup")
                keyValueRow(L("直近30日の費用"), value: costText(s.cost30), chevron: false)
                    .accessibilityIdentifier("adminAi.cost30")
            }
        }
    }

    private func backupText(_ s: AdminAiSettings) -> String {
        switch s.backup {
        case "auto":
            if let a = s.backupAuto {
                return L("自動（\(Self.modelName(s, provider: a.provider, model: a.model))）")
            }
            return L("自動")
        case "off":
            return L("使わない")
        default:
            let (p, m) = Self.split(s.backup)
            return Self.modelName(s, provider: p, model: m)
        }
    }

    private func costText(_ c: AdminAiCost30) -> String {
        let yen = "¥" + Int(c.jpy.rounded()).formatted()
        if c.unpricedCalls > 0 {
            return L("\(yen)（値段未登録 \(c.unpricedCalls) 回）")
        }
        return yen
    }

    private func undo() async {
        guard preview == nil else { return }
        undoing = true
        undoError = nil
        do {
            _ = try await NativeAPI.call("adminUndoAiModels", [:], timeout: 30)
            Haptics.success()
            await load()
        } catch {
            undoError = Self.message(error)
        }
        undoing = false
    }

    // MARK: - 用途ごと

    /// The groups of uses, in the screen's order.
    private static let groups: [String] = ["photo", "card", "review", "journal", "report"]

    private static func groupName(_ id: String) -> String {
        switch id {
        case "photo": return L("写真")
        case "card": return L("カード")
        case "review": return L("復習")
        case "journal": return L("日記")
        default: return L("報告と点検")
        }
    }

    private func usesCard(_ s: AdminAiSettings) -> some View {
        let rows = s.tasks.filter(\.ios)
        return SettingsCard(title: L("用途ごと")) {
            VStack(alignment: .leading, spacing: 0) {
                caption(L("別の AI にした用途がある所だけ青い印が付きます。押すと中の用途が並び、1つずつ替えられます。"))
                    .padding(.bottom, 8)
                let present = Self.groups.filter { g in rows.contains { $0.group == g } }
                ForEach(Array(present.enumerated()), id: \.element) { i, g in
                    if i > 0 {
                        Divider().overlay(Theme.border)
                    }
                    groupRow(g, rows: rows.filter { $0.group == g }, settings: s)
                }
            }
        }
        .accessibilityIdentifier("adminAi.tasks")
    }

    private func groupRow(_ group: String, rows: [AdminAiTaskSetting], settings s: AdminAiSettings) -> some View {
        let own = rows.filter { !$0.sameAsMain }.count
        let open = openGroups.contains(group)
        let names = rows.map { Self.localized($0.label, fallback: $0.id) }.joined(separator: "・")
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(.snappy(duration: 0.25)) {
                    if open { openGroups.remove(group) } else { openGroups.insert(group) }
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("\(Self.groupName(group))（\(rows.count)）"))
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundStyle(Theme.foreground)
                        Text(names)
                            .scaledFont(size: 12)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(own == 0 || s.main == nil ? L("同じ") : L("\(own) つ別"))
                        .scaledFont(size: 13, weight: own == 0 ? .regular : .semibold)
                        .foregroundStyle(own == 0 || s.main == nil ? Theme.muted : Theme.primaryInk)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("adminAi.group.\(group)")
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows, id: \.id) { t in
                        taskRow(t, settings: s)
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    private func taskRow(_ t: AdminAiTaskSetting, settings s: AdminAiSettings) -> some View {
        let name = Self.localized(t.label, fallback: t.id)
        let current = t.provider.map { Self.modelName(s, provider: $0, model: t.resolved ?? t.model ?? "") } ?? "—"
        let backup: String = {
            if t.backup == "off" { return L("使わない") }
            if let p = t.backupProvider, let m = t.backupModel { return Self.modelName(s, provider: p, model: m) }
            return "—"
        }()
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                Haptics.selection()
                picking = .task(t.id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .scaledFont(size: 15, weight: .medium)
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Text(current)
                        .scaledFont(size: 13, weight: t.sameAsMain ? .regular : .semibold)
                        .foregroundStyle(t.sameAsMain ? Theme.muted : Theme.primaryInk)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 11, weight: .semibold)
                        .foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("adminAi.task.\(t.id)")
            Button {
                Haptics.selection()
                picking = .taskBackup(t.id)
            } label: {
                Text(L("控え: \(backup)"))
                    .scaledFont(size: 12)
                    .foregroundStyle(t.backup == "auto" ? Theme.muted : Theme.primaryInk)
                    .frame(minHeight: 28, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("adminAi.task.\(t.id).backup")
            if let error = t.error {
                errorText(error)
            }
        }
        .padding(12)
        .background(Theme.secondary.opacity(0.6), in: .rect(cornerRadius: 14, style: .continuous))
    }

    // MARK: - ほかの AI

    private func othersCard(_ s: AdminAiSettings) -> some View {
        SettingsCard(title: L("ほかの AI")) {
            VStack(alignment: .leading, spacing: 0) {
                if let tts = s.tts {
                    NavigationLink {
                        ScrollView {
                            ttsCard(tts)
                                .padding(16)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .background(AppBackground())
                        .navigationTitle(L("発音の声"))
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        keyValueRow(L("発音の声"), value: voiceSummary(tts), chevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("adminAi.voices")
                }
                if s.tts != nil, s.image != nil {
                    Divider().overlay(Theme.border).padding(.vertical, 6)
                }
                if let image = s.image {
                    NavigationLink {
                        ScrollView {
                            imageCard(image)
                                .padding(16)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .background(AppBackground())
                        .navigationTitle(L("画像（文字検索のAI画像）"))
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        keyValueRow(L("画像を作る"), value: image.provider == "off" ? L("オフ") : image.model.isEmpty ? image.provider : image.model,
                                    chevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("adminAi.images")
                }
            }
        }
    }

    private func voiceSummary(_ tts: AdminAiTts) -> String {
        guard let row = tts.languages["zh-TW"], row.provider != "default" else { return L("既定の声") }
        if !row.voice.isEmpty { return row.voice }
        return row.model ?? row.provider
    }

    private func keyValueRow(_ key: String, value: String, chevron: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .scaledFont(size: 15)
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            Text(value)
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            if chevron {
                Image(systemName: "chevron.right")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: - Names and prices

    /// `provider:model` → (provider, model).
    static func split(_ value: String) -> (String, String) {
        guard let i = value.firstIndex(of: ":") else { return ("", value) }
        return (String(value[..<i]), String(value[value.index(after: i)...]))
    }

    /// The provider's name for a model (`Gemini 4 Hydrogen`), else its id.
    static func modelName(_ s: AdminAiSettings, provider: String, model: String) -> String {
        s.catalog.first { $0.id == provider }?.models.first { $0.id == model }?.name ?? model
    }

    /// 「100万トークン　入力 $1.50・出力 $7.50」, or 「値段未登録」.
    static func priceText(_ p: AdminAiModelPrice?) -> String {
        guard let p else { return L("値段未登録") }
        let i = String(format: "$%.2f", p.inUsd)
        let o = String(format: "$%.2f", p.outUsd)
        return L("100万トークン　入力 \(i)・出力 \(o)")
    }

    // MARK: - Images

    private func imageCard(_ image: AdminAiImage) -> some View {
        let usable = image.providers.filter { $0.hasKey }
        let locked = image.providers.filter { !$0.hasKey }
        let chosen = image.providers.first { $0.id == imageProvider }
        let placeholder = chosen?.defaultModel ?? ""
        let current = image.model.isEmpty ? image.provider : image.provider + " / " + image.model
        let lockedNames = locked.map { $0.name }.joined(separator: ", ")
        return SettingsCard(title: L("画像（文字検索のAI画像）")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("いま: \(current)"))
                    .scaledFont(size: 14, weight: .medium)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if image.saved == nil {
                    caption(L("保存した設定はありません（サーバの既定で動いています）"))
                }
                HStack {
                    fieldLabel(L("会社"))
                    Spacer(minLength: 8)
                    Picker(L("会社"), selection: $imageProvider) {
                        ForEach(usable, id: \.id) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.primaryInk)
                }
                .frame(minHeight: 44)
                if !locked.isEmpty {
                    caption(L("鍵がありません: \(lockedNames)"))
                }
                if imageProvider != "off" {
                    fieldLabel(L("モデル"))
                    TextField(placeholder, text: $imageModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .scaledFont(size: 15)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Theme.card, in: .rect(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    caption(L("空ならその会社の既定のモデルを使います"))
                }
                actionButton(L("保存"), busy: imageSaving, disabled: imageProvider.isEmpty || imageSaving) {
                    Task { await saveImage() }
                }
                .accessibilityIdentifier("adminAi.image.save")
                if let imageNotice {
                    Text(imageNotice).scaledFont(size: 13).foregroundStyle(Theme.ok)
                }
                if let imageError {
                    errorText(imageError)
                }

                Divider().overlay(Theme.border).padding(.vertical, 4)

                fieldLabel(L("試しに1枚作る"))
                caption(L("保存した設定で本当に1枚作ります（その会社の残高を使います）。"))
                TextField(L("言葉（空なら「柚子」）"), text: $testQuery)
                    .scaledFont(size: 15)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Theme.card, in: .rect(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
                actionButton(L("試しに1枚作る"), busy: testing, disabled: testing) {
                    Task { await testImage() }
                }
                .accessibilityIdentifier("adminAi.image.test")
                if let testResult {
                    testResultView(testResult)
                }
                if let testError {
                    errorText(testError)
                }
                if let testPicture {
                    Image(uiImage: testPicture)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 280)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel(L("作った画像"))
                } else if let testPictureURL {
                    AsyncImage(url: testPictureURL) { img in
                        img.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel(L("作った画像"))
                }
            }
        }
    }

    private func testResultView(_ r: AdminAiImageTest) -> some View {
        let ms = String(Int(r.ms.rounded()))
        let color: Color = r.ok ? Theme.ok : Theme.destructive
        let headline: String = r.ok ? L("できました（\(ms) ms）") : L("作れませんでした（\(ms) ms）")
        let used = r.model.isEmpty ? r.provider : r.provider + " / " + r.model
        return VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(color)
            Text(used)
                .scaledFont(size: 13)
                .foregroundStyle(Theme.muted)
                .textSelection(.enabled)
            if let name = r.credentialName {
                Text(L("鍵の環境変数: \(name)"))
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.muted)
            }
            if let error = r.error {
                errorText(error)
            }
        }
    }

    private func saveImage() async {
        guard preview == nil, !imageProvider.isEmpty else { return }
        imageSaving = true
        imageNotice = nil
        imageError = nil
        let model = imageProvider == "off" ? "" : imageModel.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let saved = try await NativeAPI.call("adminSetImageConfig", ["provider": imageProvider, "model": model],
                                                 as: AdminAiImageChoice.self, timeout: 30)
            let what = saved.model.isEmpty ? saved.provider : saved.provider + " / " + saved.model
            imageNotice = L("保存しました: \(what)")
            await load()
        } catch {
            imageError = Self.message(error)
        }
        imageSaving = false
    }

    private func testImage() async {
        guard preview == nil else { return }
        testing = true
        testResult = nil
        testError = nil
        testPicture = nil
        testPictureURL = nil
        var data: [String: Any] = [:]
        let q = testQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            data["query"] = String(q.prefix(60))
        }
        do {
            let r = try await NativeAPI.call("adminTestImage", data, as: AdminAiImageTest.self, timeout: 150)
            testResult = r
            if let src = r.image {
                if let bytes = Self.dataURIBytes(src) {
                    testPicture = UIImage(data: bytes)
                } else if let url = URL(string: src), url.scheme == "https" || url.scheme == "http" {
                    testPictureURL = url
                }
            }
        } catch {
            testError = Self.message(error)
        }
        testing = false
    }

    /// `data:image/png;base64,…` → the bytes (nil for anything else).
    private static func dataURIBytes(_ s: String) -> Data? {
        guard s.hasPrefix("data:"), let comma = s.firstIndex(of: ",") else { return nil }
        let meta = s[s.startIndex..<comma]
        guard meta.hasSuffix(";base64") else { return nil }
        let payload = String(s[s.index(after: comma)...])
        return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
    }

    // MARK: - Voices

    private func ttsCard(_ tts: AdminAiTts) -> some View {
        SettingsCard(title: L("発音の声")) {
            VStack(alignment: .leading, spacing: 14) {
                if !tts.defaultEngine.isEmpty {
                    caption(L("既定の声: \(tts.defaultEngine)"))
                }
                ForEach(Array(Self.ttsLanguages.enumerated()), id: \.offset) { i, lang in
                    if i > 0 {
                        Divider().overlay(Theme.border)
                    }
                    voiceRow(lang, tts: tts)
                }
            }
        }
    }

    private func voiceRow(_ lang: String, tts: AdminAiTts) -> some View {
        let draft = voiceDrafts[lang] ?? AdminVoiceDraft()
        let row = tts.languages[lang]
        let usable = tts.providers.filter { $0.hasKey }
        let provider = tts.providers.first { $0.id == draft.provider }
        let voices = provider?.voices[lang] ?? []
        let models = provider?.models ?? []
        let saving = voiceSaving == lang
        return VStack(alignment: .leading, spacing: 8) {
            Text(Self.languageName(lang))
                .scaledFont(size: 17, weight: .semibold)
                .foregroundStyle(Theme.foreground)
            Text(L("いま: \(currentVoiceText(row))"))
                .scaledFont(size: 14, weight: .medium)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if row?.incomplete == true {
                caption(L("声が選ばれていないため、既定の声で鳴っています"))
            }
            HStack {
                fieldLabel(L("会社"))
                Spacer(minLength: 8)
                Picker(L("会社"), selection: providerBinding(lang)) {
                    Text(L("既定の声")).tag("default")
                    ForEach(usable, id: \.id) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.primaryInk)
            }
            .frame(minHeight: 44)
            if draft.provider != "default" {
                if lang == "zh-TW" && draft.provider == "gemini" {
                    ChoicePills(options: [("female", L("女性")), ("male", L("男性"))],
                                selection: draftBinding(lang).gender)
                }
                if voices.isEmpty {
                    fieldLabel(L("声の ID"))
                    TextField(L("声の ID"), text: draftBinding(lang).voice)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .scaledFont(size: 15)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Theme.card, in: .rect(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
                } else {
                    HStack {
                        fieldLabel(L("声"))
                        Spacer(minLength: 8)
                        Picker(L("声"), selection: draftBinding(lang).voice) {
                            Text("—").tag("")
                            ForEach(voices, id: \.self) { v in
                                Text(v).tag(v)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.primaryInk)
                    }
                    .frame(minHeight: 44)
                }
                if !models.isEmpty {
                    HStack {
                        fieldLabel(L("モデル"))
                        Spacer(minLength: 8)
                        Picker(L("モデル"), selection: draftBinding(lang).model) {
                            Text(L("既定")).tag("")
                            ForEach(models, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.primaryInk)
                    }
                    .frame(minHeight: 44)
                }
            }
            actionButton(L("保存"), busy: saving, disabled: voiceSaving != nil) {
                Task { await saveVoice(lang) }
            }
            .accessibilityIdentifier("adminAi.voice.\(lang).save")
            if let notice = voiceNotices[lang] {
                Text(notice).scaledFont(size: 13).foregroundStyle(Theme.ok)
            }
            if let error = voiceErrors[lang] {
                errorText(error)
            }
        }
    }

    private func currentVoiceText(_ row: AdminAiTtsRow?) -> String {
        guard let row, row.provider != "default" else { return L("既定の声") }
        var parts: [String] = [row.provider]
        if !row.voice.isEmpty {
            parts.append(row.voice)
        }
        if let model = row.model {
            parts.append(model)
        }
        if let gender = row.gender {
            parts.append(gender == "male" ? L("男性") : L("女性"))
        }
        return parts.joined(separator: " / ")
    }

    private func draftBinding(_ lang: String) -> Binding<AdminVoiceDraft> {
        Binding(
            get: { voiceDrafts[lang] ?? AdminVoiceDraft() },
            set: { voiceDrafts[lang] = $0 }
        )
    }

    /// Another provider: its voice and model start empty (the previous one's ids mean nothing there).
    private func providerBinding(_ lang: String) -> Binding<String> {
        Binding(
            get: { (voiceDrafts[lang] ?? AdminVoiceDraft()).provider },
            set: { value in
                var d = voiceDrafts[lang] ?? AdminVoiceDraft()
                guard d.provider != value else { return }
                d.provider = value
                d.voice = ""
                d.model = ""
                voiceDrafts[lang] = d
            }
        )
    }

    private func saveVoice(_ lang: String) async {
        guard preview == nil else { return }
        let d = voiceDrafts[lang] ?? AdminVoiceDraft()
        var data: [String: Any] = ["language": lang, "provider": d.provider]
        if d.provider != "default" {
            data["voice"] = d.voice.trimmingCharacters(in: .whitespacesAndNewlines)
            if !d.model.isEmpty {
                data["model"] = d.model
            }
            // The Taiwan Azure voice carries its own gender (the server reads it from the voice).
            if lang == "zh-TW" && d.provider == "gemini" {
                data["gender"] = d.gender
            }
        }
        voiceSaving = lang
        voiceNotices[lang] = nil
        voiceErrors[lang] = nil
        do {
            _ = try await NativeAPI.call("adminSetTtsVoice", data, timeout: 30)
            voiceNotices[lang] = L("保存しました")
            await load()
        } catch {
            voiceErrors[lang] = Self.message(error)
        }
        voiceSaving = nil
    }

    private static func languageName(_ lang: String) -> String {
        switch lang {
        case "en": return L("英語")
        case "ja": return L("日本語")
        default: return L("台湾華語")
        }
    }

    // MARK: - Loading

    private func load() async {
        if let preview {
            apply(preview)
            return
        }
        do {
            let s = try await NativeAPI.call("adminGetAiSettings", [:], as: AdminAiSettings.self, timeout: 40)
            AdminAccess.shared.update(isAdmin: s.isAdmin)
            if s.isAdmin {
                loadError = nil
                apply(s)
            } else {
                settings = nil
                loadError = L("この画面は管理者だけが使えます。")
            }
        } catch {
            loadError = Self.message(error)
        }
    }

    private func apply(_ s: AdminAiSettings) {
        settings = s
        if let image = s.image {
            imageProvider = image.provider
            imageModel = image.saved?.model ?? ""
        }
        if let tts = s.tts {
            var drafts: [String: AdminVoiceDraft] = [:]
            for lang in Self.ttsLanguages {
                var d = AdminVoiceDraft()
                if let row = tts.languages[lang] {
                    d.provider = row.provider
                    d.voice = row.voice
                    d.model = row.model ?? ""
                    d.gender = row.gender ?? "female"
                }
                drafts[lang] = d
            }
            voiceDrafts = drafts
        }
    }

    // MARK: - Pieces

    private func errorBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .scaledFont(size: 14)
                .foregroundStyle(Theme.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button(L("もう一度")) {
                Task { await load() }
            }
            .scaledFont(size: 14, weight: .semibold)
            .foregroundStyle(Theme.primaryInk)
            .frame(minHeight: 44)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.destructive.opacity(0.3), lineWidth: 1))
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

    /// The server's name / description in the display language, else English (the neutral fallback), else Japanese.
    private static func localized(_ texts: [String: String], fallback: String) -> String {
        for code in [L10n.lang, DisplayLanguages.fallback, DisplayLanguages.source] {
            if let t = texts[code], !t.isEmpty { return t }
        }
        return fallback
    }

    /// The server's own reason, as it is (the developer reads it; learners never see this screen).
    private static func message(_ error: Error) -> String {
        if let e = error as? APIError {
            switch e {
            case .server(let code, let text):
                if text.isEmpty {
                    return L("サーバーエラー（\(code)）")
                }
                return text
            default:
                return e.errorDescription ?? L("うまくいきませんでした。もう一度お試しください。")
            }
        }
        return error.localizedDescription
    }
}

/// What is being chosen for one learning language's voice (saved with 保存).
struct AdminVoiceDraft: Equatable {
    var provider: String = "default"
    var voice: String = ""
    var model: String = ""
    /// `female` | `male` (台湾華語 with Gemini).
    var gender: String = "female"
}
