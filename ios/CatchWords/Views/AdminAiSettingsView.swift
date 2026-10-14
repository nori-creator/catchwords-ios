import SwiftUI
import UIKit

/// 設定 → 開発者 →「AI の設定（開発者）」: admins only (`AdminAccess`). The same screen as the web's
/// `AdminAiSettingsCard`, through the functions of web docs/admin-ai-api.md:
/// - which AI each use of this app takes, and its backup when that AI fails (owner 2026-10-14 「iOS にない奴は
///   消して…全ての AI の機能を…モデル設定」), saved at once with `adminSetAiTask`. Only the uses this app has
///   (`ios`); a server without them yet shows the older per-feature list (`adminSetAiFeature`);
/// - what the AI cost, by use, by model and by day, with editable prices (`AdminAiCostCard`);
/// - the AI images of the text search (`adminSetImageConfig`, `adminTestImage`);
/// - the speed and accuracy of each feature's AI by model, and a fixed-photo test (`AdminAiStatsCard`);
/// - the pronunciation voice of each learning language (`adminSetTtsVoice`).
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
    @State private var savingFeature: String?
    @State private var featureErrors: [String: String] = [:]
    /// `"<task>.value"` / `"<task>.backup"` while it is being saved.
    @State private var savingTask: String?
    @State private var taskErrors: [String: String] = [:]

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
                    if settings.tasks.contains(where: \.ios) {
                        tasksCard(settings)
                    } else {
                        featuresCard(settings)
                    }
                    AdminAiCostCard(preview: previewCosts)
                    AdminAiStatsCard(settings: settings, preview: previewStats)
                    if let image = settings.image {
                        imageCard(image)
                    }
                    if let tts = settings.tts {
                        ttsCard(tts)
                    }
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
        .task { await load() }
    }

    // MARK: - Status

    private func statusCard(_ s: AdminAiSettings) -> some View {
        let color: Color = s.status.ok ? Theme.ok : Theme.destructive
        let icon: String = s.status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        return SettingsCard(title: L("状態")) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(statusText(s.status))
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("adminAi.status")
        }
    }

    private func statusText(_ status: AdminAiStatus) -> String {
        if status.ok {
            let provider = status.provider ?? "—"
            return L("AI は動いています（既定: \(provider)）")
        }
        if let error = status.error {
            return error
        }
        return L("AI が動いていません")
    }

    // MARK: - Features

    private func featuresCard(_ s: AdminAiSettings) -> some View {
        SettingsCard(title: L("機能ごとの AI")) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(s.features.enumerated()), id: \.offset) { i, f in
                    if i > 0 {
                        Divider().overlay(Theme.border)
                    }
                    featureRow(f, providers: s.providers)
                }
            }
        }
    }

    private func featureRow(_ f: AdminAiFeature, providers: [AdminAiProvider]) -> some View {
        let name = Self.localized(f.label, fallback: f.id)
        let detail = Self.localized(f.description, fallback: "")
        let error: String? = featureErrors[f.id] ?? f.error
        return VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .scaledFont(size: 17, weight: .semibold)
                .foregroundStyle(Theme.foreground)
            if !detail.isEmpty {
                Text(detail)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L("いま: \(currentText(f))"))
                .scaledFont(size: 14, weight: .medium)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let error {
                Text(error)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            featureMenu(f, providers: providers)
        }
    }

    /// 「自動（最新 Gemini Flash）→ gemini-3.8-flash」 / 「openrouter:anthropic/claude-sonnet-4.5 → …」.
    private func currentText(_ f: AdminAiFeature) -> String {
        var head: String
        if f.value == "auto" {
            head = autoText(f)
        } else {
            head = f.value
        }
        if let resolved = f.resolved {
            head += " → " + resolved
        }
        return head
    }

    private func autoText(_ f: AdminAiFeature) -> String {
        let family: String
        switch f.tier {
        case "flash-lite": family = "Gemini Flash-Lite"
        case "pro": family = "Gemini Pro"
        default: family = "Gemini Flash"
        }
        return L("自動（最新 \(family)）")
    }

    private func featureMenu(_ f: AdminAiFeature, providers: [AdminAiProvider]) -> some View {
        let usable = providers.filter { $0.hasKey }
        let locked = providers.filter { !$0.hasKey }
        let saving = savingFeature == f.id
        return Menu {
            Button {
                choose(f, value: "auto")
            } label: {
                menuItem(autoText(f), selected: f.value == "auto")
            }
            ForEach(usable, id: \.id) { p in
                Section(p.name) {
                    let models = f.needsVision ? p.visionModels : p.models
                    if models.isEmpty {
                        Button(p.error ?? L("使えるモデルがありません")) {}
                            .disabled(true)
                    } else {
                        ForEach(models, id: \.self) { m in
                            Button {
                                choose(f, value: p.id + ":" + m)
                            } label: {
                                menuItem(m, selected: f.value == p.id + ":" + m)
                            }
                        }
                    }
                }
            }
            if !locked.isEmpty {
                Section(L("鍵がありません")) {
                    ForEach(locked, id: \.id) { p in
                        Button(p.name) {}
                            .disabled(true)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if saving {
                    ProgressView()
                    Text(L("保存しています…"))
                } else {
                    Text(L("AI を選ぶ"))
                }
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
        .disabled(savingFeature != nil)
        .accessibilityIdentifier("adminAi.feature.\(f.id).menu")
    }

    @ViewBuilder
    private func menuItem(_ text: String, selected: Bool) -> some View {
        if selected {
            Label(text, systemImage: "checkmark")
        } else {
            Text(text)
        }
    }

    private func choose(_ f: AdminAiFeature, value: String) {
        guard value != f.value, savingFeature == nil else { return }
        Haptics.selection()
        Task { await saveFeature(f.id, value: value) }
    }

    private func saveFeature(_ id: String, value: String) async {
        guard preview == nil else { return }
        savingFeature = id
        featureErrors[id] = nil
        do {
            _ = try await NativeAPI.call("adminSetAiFeature", ["feature": id, "value": value], timeout: 30)
            await load()
        } catch {
            featureErrors[id] = Self.message(error)
        }
        savingFeature = nil
    }

    // MARK: - Each use of the AI, with its backup

    private func tasksCard(_ s: AdminAiSettings) -> some View {
        let rows = s.tasks.filter(\.ios)
        return SettingsCard(title: L("機能ごとの AI")) {
            VStack(alignment: .leading, spacing: 14) {
                caption(L("このアプリで AI を使う所だけを出しています。選んだ AI が失敗した時（残高切れ・回数制限・障害）は、同じ依頼を「控え」の AI へ1回だけ送り直します。"))
                ForEach(Array(rows.enumerated()), id: \.offset) { i, t in
                    if i > 0 {
                        Divider().overlay(Theme.border)
                    }
                    taskRow(t, providers: s.providers)
                }
            }
        }
        .accessibilityIdentifier("adminAi.tasks")
    }

    private func taskRow(_ t: AdminAiTaskSetting, providers: [AdminAiProvider]) -> some View {
        let name = Self.localized(t.label, fallback: t.id)
        let detail = Self.localized(t.description, fallback: "")
        let error: String? = taskErrors[t.id] ?? t.error
        return VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .scaledFont(size: 17, weight: .semibold)
                .foregroundStyle(Theme.foreground)
            if !detail.isEmpty {
                Text(detail)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L("いま: \(taskCurrentText(t))"))
                .scaledFont(size: 14, weight: .medium)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(L("控え: \(taskBackupText(t))"))
                .scaledFont(size: 14)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let error {
                Text(error)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            taskMenu(t, providers: providers, backup: false)
            taskMenu(t, providers: providers, backup: true)
        }
        .accessibilityIdentifier("adminAi.task.\(t.id)")
    }

    /// 「自動 → google:gemini-3.8-flash」 / 「anthropic:claude-sonnet-5-5」.
    private func taskCurrentText(_ t: AdminAiTaskSetting) -> String {
        let used = [t.provider, t.resolved ?? t.model].compactMap { $0 }.joined(separator: ":")
        if t.value == "auto" {
            return used.isEmpty ? L("自動") : L("自動 → \(used)")
        }
        return used.isEmpty || used == t.value ? t.value : t.value + " → " + used
    }

    private func taskBackupText(_ t: AdminAiTaskSetting) -> String {
        if t.backup == "off" {
            return L("なし（失敗したらそのまま）")
        }
        guard let p = t.backupProvider, let m = t.backupResolved ?? t.backupModel else {
            return L("なし（鍵のある別の会社がありません）")
        }
        return t.backup == "auto" ? L("自動 → \(p + ":" + m)") : p + ":" + m
    }

    private func taskMenu(_ t: AdminAiTaskSetting, providers: [AdminAiProvider], backup: Bool) -> some View {
        let usable = providers.filter { $0.hasKey }
        let locked = providers.filter { !$0.hasKey }
        let current = backup ? t.backup : t.value
        let key = t.id + (backup ? ".backup" : ".value")
        let saving = savingTask == key
        return Menu {
            Button {
                chooseTask(t, value: "auto", backup: backup)
            } label: {
                menuItem(backup ? L("自動（鍵のある別の会社）") : L("自動（機能の設定・既定）"), selected: current == "auto")
            }
            if backup {
                Button {
                    chooseTask(t, value: "off", backup: true)
                } label: {
                    menuItem(L("控えを使わない"), selected: current == "off")
                }
            }
            ForEach(usable, id: \.id) { p in
                Section(p.name) {
                    let models = t.needsVision ? p.visionModels : p.models
                    if models.isEmpty {
                        Button(p.error ?? L("使えるモデルがありません")) {}
                            .disabled(true)
                    } else {
                        ForEach(models, id: \.self) { m in
                            Button {
                                chooseTask(t, value: p.id + ":" + m, backup: backup)
                            } label: {
                                menuItem(m, selected: current == p.id + ":" + m)
                            }
                        }
                    }
                }
            }
            if !locked.isEmpty {
                Section(L("鍵がありません")) {
                    ForEach(locked, id: \.id) { p in
                        Button(p.name) {}
                            .disabled(true)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if saving {
                    ProgressView()
                    Text(L("保存しています…"))
                } else {
                    Text(backup ? L("控えを選ぶ") : L("AI を選ぶ"))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .accessibilityHidden(true)
            }
            .scaledFont(size: 15, weight: .semibold)
            .foregroundStyle(backup ? Theme.foreground : Theme.primaryInk)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(backup ? Theme.card : Theme.secondary, in: Capsule())
            .overlay(Capsule().stroke(backup ? Theme.border : .clear, lineWidth: 1))
        }
        .disabled(savingTask != nil)
        .accessibilityIdentifier("adminAi.task.\(t.id).\(backup ? "backup" : "menu")")
    }

    private func chooseTask(_ t: AdminAiTaskSetting, value: String, backup: Bool) {
        guard value != (backup ? t.backup : t.value), savingTask == nil else { return }
        Haptics.selection()
        Task { await saveTask(t.id, value: value, backup: backup) }
    }

    private func saveTask(_ id: String, value: String, backup: Bool) async {
        guard preview == nil else { return }
        savingTask = id + (backup ? ".backup" : ".value")
        taskErrors[id] = nil
        do {
            _ = try await NativeAPI.call("adminSetAiTask", ["task": id, (backup ? "backup" : "value"): value], timeout: 30)
            await load()
        } catch {
            taskErrors[id] = Self.message(error)
        }
        savingTask = nil
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

    /// The server's name / description in the display language, else Japanese.
    private static func localized(_ texts: [String: String], fallback: String) -> String {
        if let t = texts[L10n.lang], !t.isEmpty {
            return t
        }
        if let t = texts["ja"], !t.isEmpty {
            return t
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
