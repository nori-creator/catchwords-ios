import SwiftUI
import PhotosUI
import UserNotifications

/// settings.tsx: small grey section titles outside white cards; every choice is a row of pills with a
/// sliding blue capsule; language/level open a wheel card. Order matches the web app.
struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(PlanStore.self) private var plan
    @Environment(ProfileStore.self) private var profile
    @Environment(DexStore.self) private var dex
    @Environment(AppRouter.self) private var router

    @AppStorage("photos.sync") private var photoSync: Bool = true
    @AppStorage("haptics.enabled") private var haptics: Bool = true
    @AppStorage("sound.level") private var soundLevel: String = "subtle"
    @AppStorage("reading.pref") private var readingPref: String = "zhuyin"
    @AppStorage("reading.ja") private var readingJa: String = "kana"
    @AppStorage(Sticker.homePhotoKey) private var photoPref: String = "auto"
    @AppStorage("selfie.mode") private var selfieMode: Bool = false
    @AppStorage("theme.pref") private var themePref: String = "light"
    @AppStorage(MotionPreference.key) private var motionPref: String = MotionPreference.defaultValue
    /// What actually moves now (the switch shows this: 自動 follows the iPhone until the switch is used).
    @Environment(\.appReduceMotion) private var reduceMotion
    @AppStorage(ReminderService.modeKey) private var reminderMode: String = "off"
    @AppStorage(ReminderService.timesKey) private var reminderTimes: String = ReminderService.defaultTime
    @AppStorage(ReminderService.placeKey) private var placeRemind: Bool = false

    @State private var avatarItem: PhotosPickerItem?
    @State private var nameDraft: String = ""
    @FocusState private var nameFocused: Bool
    @State private var wheel: WheelField?
    @State private var notifyDenied: Bool = false
    @State private var deleteOpen: Bool = false
    @State private var deleteText: String = ""
    @State private var isDeleting: Bool = false
    @State private var deleteError: String?
    @State private var confirmSignOut: Bool = false
    @State private var showAIConsentSettings: Bool = false
    @State private var showAdminAi: Bool = false
    @State private var adminScreen: AdminScreen?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                profileSection
                languageSection
                studySection
                notifySection
                appearanceSection
                feelSection
                if PlanStore.paywallEnabled { proSection }
                // The AI consent sits with the terms and the privacy policy, as on the web (owner 2026-10-11).
                legalSection
                // Admins only (the server's answer for this account); nobody else ever sees this section.
                if AdminAccess.shared.isAdmin { developerSection }
                accountButtons
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 130)
        }
        .scrollDismissesKeyboard(.interactively)
        .statusBarScrim()
        // 「保存しました」 (web SaveStatusPill): top centre, over the scrolled content.
        .overlay(alignment: .top) { SaveStatusPill() }
        .background(AppBackground())
        .onDisappear { SaveStatus.shared.clear() }
        .overlay {
            if let wheel {
                // No insertion / removal transition: the card fades itself in and out and is taken out of the tree
                // only once it is invisible (owner 2026-10-15: a blurred blue ghost of its 「閉じる」 button stayed over
                // the 「今のレベル」 row after the 母語 card closed — the removal transition was still drawing the card
                // while the language switch redrew the page under it, and the half-faded button layer was left behind).
                WheelCard(field: wheel, profile: profile) { closeWheel() }
                    .transition(.identity)
                    .zIndex(3)
            }
        }
        .onAppear {
            nameDraft = profile.displayName
            SoundService.shared.warmTicks()   // a choice's sound must not be lost the first time
        }
        .task {
            // Reminders that are on (set at sign-in from the account, or before) while the iPhone's own
            // setting refuses them: say so, instead of a setting that silently never notifies.
            guard reminderMode != "off" || placeRemind else { return }
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            notifyDenied = status == .denied
        }
        // Is this account an admin? Asked once per account; any failure means "no" (AdminAccess).
        .task { await AdminAccess.shared.refresh() }
        .sheet(isPresented: $showAdminAi) {
            NavigationStack { AdminAiSettingsView() }
                .presentationBackground(Theme.background)
        }
        .sheet(item: $adminScreen) { screen in
            NavigationStack { screen.view }
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showAIConsentSettings) {
            AIConsentSettingsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .onChange(of: profile.displayName) { _, v in if !nameFocused { nameDraft = v } }
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = await ImageTools.downsampledInBackground(data, maxSide: 1024) {
                    await profile.uploadAvatar(img)
                    if profile.message == nil { SaveStatus.shared.saved() }
                } else {
                    profile.message = L("写真を読み込めませんでした。")
                }
                avatarItem = nil
            }
        }
        .confirmationDialog(L("サインアウトしますか？"), isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(L("サインアウト"), role: .destructive) { auth.signOut() }
                .accessibilityIdentifier("settings.signOut.confirm")
            // Without it the system adds its own "Cancel" in the iPhone's language, not the app's.
            Button(L("キャンセル"), role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        SettingsCard(title: L("プロフィール")) {
            VStack(alignment: .leading, spacing: 12) {
                label(L("プロフィール写真"))
                HStack(spacing: 14) {
                    AvatarView(url: profile.avatarURL, size: 60)
                        .overlay { if profile.isSavingAvatar { ProgressView() } }
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        Text(profile.avatarURL == nil ? L("選ぶ") : L("変更"))
                            .scaledFont(size: 16, weight: .medium).foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 18).frame(minHeight: 46)
                            .background(Theme.secondary, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    if profile.avatarURL != nil {
                        Button(L("外す")) { Task { await profile.clearAvatar() } }
                            .scaledFont(size: 16).foregroundStyle(Theme.muted)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
                label(L("表示名")).padding(.top, 4)
                TextField(L("名前"), text: $nameDraft)
                    .scaledFont(size: 17)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .background(Theme.card, in: .rect(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.05), radius: 3, y: 2)
                    .onSubmit(saveName)
                    .onChange(of: nameFocused) { _, f in if !f { saveName() } }
            }
        }
    }

    private var languageSection: some View {
        let isEnglish = profile.targetLanguage == "en"
        let levels = ProfileStore.levels(for: profile.targetLanguage)
        return SettingsCard(title: L("言語")) {
            VStack(alignment: .leading, spacing: 10) {
                label(L("母語"))
                // The display language itself (the screen's language), not the profile's copy: before the profile is read
                // (offline) that copy is still its default, Japanese — 「日本語」 on a Spanish screen.
                wheelRow(ProfileStore.nativeOptions.first { $0.value == L10n.lang }?.label ?? L10n.current.autonym) { openWheel(.native) }
                    .accessibilityIdentifier("settings.wheel.native")
                // 学習言語 is hidden while 繁體字（台灣） is the only language offered (owner 2026-10-20: 「設定の学習言語の設定欄
                // アプリから消して。ただいずれほかの言語にも対応させるためにコードは残しておいて」). It comes back by itself
                // when ProfileStore.offeredTargets offers more, and for an account still on a hidden language (it must be
                // able to switch away from it).
                if ProfileStore.targetChoices(current: profile.targetLanguage).count > 1 {
                    label(L("学習言語")).padding(.top, 6)
                    wheelRow(ProfileStore.targetLabel(profile.targetLanguage)) { openWheel(.target) }
                        .accessibilityIdentifier("settings.wheel.target")
                }
                label(L("今のレベル")).padding(.top, 6)
                wheelRow(levels.first { $0.value == profile.currentLevel }?.label ?? profile.currentLevel) { openWheel(.current) }
                    .accessibilityIdentifier("settings.wheel.current")
                label(L("目標レベル")).padding(.top, 6)
                wheelRow(levels.first { $0.value == profile.levelGoal }?.label ?? profile.levelGoal) { openWheel(.goal) }
                    .accessibilityIdentifier("settings.wheel.goal")
                // The learner's level has one use (owner 2026-10-03): the difficulty of the example sentences and
                // chunks. The server reads both values from the profile when it writes them.
                Text(L("例文とチャンクを、今のレベルから目標レベルのあいだの難しさで作ります。"))
                    .scaledFont(size: 12).foregroundStyle(Theme.muted)
                if !isEnglish { label(L("発音表記")).padding(.top, 6) }
                if profile.targetLanguage == "ja" {
                    ChoicePills(options: [("kana", L("あ ふりがな")), ("romaji", L("abc ローマ字"))], selection: saving($readingJa))
                } else if !isEnglish {
                    ChoicePills(options: [("zhuyin", L("ㄅㄆㄇ 注音")), ("pinyin", L("abc ピンイン"))], selection: saving($readingPref))
                }
                if let m = profile.message {
                    Text(m).font(.footnote).foregroundStyle(Theme.destructive)
                }
            }
        }
    }

    private var studySection: some View {
        SettingsCard(title: L("学習設定")) {
            VStack(alignment: .leading, spacing: 10) {
                label(L("ホームに表示する写真"))
                // The home album's picture only (owner 2026-10-11): the dex, the word page and the review always show
                // the cut-out. The default "auto" (never chosen) is the cut-out, so it lights 切り抜き (R6-10).
                ChoicePills(options: [("object", L("元の写真")), ("cutout", L("切り抜き")), ("selfie", L("自撮り"))],
                            selection: saving(Binding(get: { photoPref == "auto" ? "cutout" : photoPref }, set: { photoPref = $0 })))
                    .accessibilityIdentifier("settings.homePhoto")
                label(L("1日の復習枚数")).padding(.top, 6)
                ChoicePills(
                    options: [("10", "10"), ("20", "20"), ("30", "30"), ("50", "50"), ("0", L("無制限"))],
                    selection: Binding(
                        get: { String(profile.reviewDailyLimit) },
                        set: { v in
                            let n = Int(v) ?? 20
                            profile.reviewDailyLimit = n
                            Task { if await profile.update(["review_daily_limit": n]) { SaveStatus.shared.saved() } }
                        }
                    )
                )
                Divider().overlay(Theme.border).padding(.top, 8)
                SettingsToggle(title: L("自撮りモード"), detail: L("単語を撮ったあと、続けてその場の自分を撮る画面に進みます"), isOn: saving($selfieMode))
                Divider().overlay(Theme.border)
                SettingsToggle(title: L("カメラロールに保存"), detail: L("撮った写真をスマホの写真アプリにも残します"), isOn: saving($photoSync))
            }
        }
    }

    private var notifySection: some View {
        SettingsCard(title: L("通知")) {
            VStack(alignment: .leading, spacing: 10) {
                label(L("復習の通知"))
                ChoicePills(
                    options: [("off", L("オフ")), ("ai", L("自動")), ("custom", L("時刻を指定"))],
                    selection: Binding(get: { reminderMode }, set: { setReminderMode($0) })
                )
                if reminderMode == "custom" { timesEditor.transition(.opacity.combined(with: .move(edge: .top))) }
                if notifyDenied {
                    notice(L("通知が許可されていません。iPhoneの「設定」→「CatchWords」→「通知」から許可してください。"))
                }
                Divider().overlay(Theme.border).padding(.top, 8)
                SettingsToggle(
                    title: L("場所でリマインド"),
                    detail: L("単語を撮った場所の近くに来ると、その単語を通知で思い出させます"),
                    isOn: Binding(get: { placeRemind }, set: { setPlaceRemind($0) })
                )
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: reminderMode)
        }
    }

    private var appearanceSection: some View {
        SettingsCard(title: L("外観")) {
            VStack(alignment: .leading, spacing: 10) {
                label(L("画面の明るさ"))
                ChoicePills(
                    options: [("light", L("ライト")), ("dark", L("ダーク")), ("system", L("システム"))],
                    selection: Binding(get: { themePref }, set: { v in
                        withAnimation(.easeInOut(duration: 0.35)) { themePref = v }
                        SaveStatus.shared.saved()
                    })
                )
                Divider().overlay(Theme.border).padding(.top, 8)
                // A switch, as on the web (owner 2026-10-11: 「アニメーションはスライドのON/OFFに」): it shows what moves
                // now — the iPhone's Reduce Motion until it is used — and then keeps 見せる (on) or 減らす (off).
                SettingsToggle(title: L("アニメーション"), detail: nil, isOn: Binding(get: { !reduceMotion }, set: { on in
                    motionPref = on ? MotionPreference.full : MotionPreference.reduce
                    SaveStatus.shared.saved()
                }))
                .accessibilityIdentifier("settings.motion")
            }
        }
    }

    private var feelSection: some View {
        SettingsCard(title: L("音と手ざわり")) {
            VStack(alignment: .leading, spacing: 10) {
                label(L("効果音"))
                // Its own preview (the land bounce) is its sound: no choice tick on top of it.
                ChoicePills(
                    options: [("off", L("オフ")), ("subtle", L("控えめ")), ("full", L("しっかり"))],
                    sounds: false,
                    selection: Binding(get: { soundLevel }, set: { v in
                        soundLevel = v
                        if v != "off" { SoundService.shared.play(.landBounce) }
                        SaveStatus.shared.saved()
                    })
                )
                SettingsToggle(title: L("振動"), detail: nil, isOn: Binding(get: { haptics }, set: { v in
                    haptics = v
                    if v { Haptics.impact(.medium) }
                    SaveStatus.shared.saved()
                }))
                .padding(.top, 6)
            }
        }
    }

    /// 開発者 (admins only, the server's answer for this account): the users and the numbers the web shows its admin
    /// (owner 2026-10-11: 「開発者の私だけ…web版と同じように、利用者やアプリの詳しい情報、分析が見えるように」),
    /// this app's own details, and the AI settings (web docs/admin-ai-api.md).
    private var developerSection: some View {
        SettingsCard(title: L("開発者専用（あなたにしか表示されません）")) {
            VStack(spacing: 0) {
                devRow(icon: "person.2", title: L("利用者ごとの情報"), id: "settings.adminUsers") { adminScreen = .users }
                Divider().overlay(Theme.border)
                devRow(icon: "chart.bar.xaxis", title: L("KPIダッシュボード"), id: "settings.adminMetrics") { adminScreen = .metrics }
                Divider().overlay(Theme.border)
                devRow(icon: "waveform.path.ecg", title: L("ベータの指標"), id: "settings.adminBeta") { adminScreen = .beta }
                Divider().overlay(Theme.border)
                devRow(icon: "iphone", title: L("アプリの情報"), id: "settings.appInfo") { adminScreen = .appInfo }
                Divider().overlay(Theme.border)
                devRow(icon: "exclamationmark.bubble", title: L("報告された誤り"), id: "settings.adminReports") { adminScreen = .reports }
                Divider().overlay(Theme.border)
                devRow(icon: "cpu", title: L("AI の設定（開発者）"), id: "settings.adminAi") { showAdminAi = true }
                Divider().overlay(Theme.border).padding(.bottom, 8)
                developerTrials
            }
        }
    }

    @AppStorage(DevChoices.tabBarKey) private var tabBarVariant: String = DevChoices.tabBarDefault

    /// 開発者の試し (owner 2026-10-15): the camera tab's look to compare on the device — the original one, shipped, or
    /// B, kept for a later release (owner 2026-10-16). The 設定 sound (A), the app's own wheel (owner 2026-10-20) and the
    /// shutter sound (B, owner 2026-10-21) were decided and left the trials.
    private var developerTrials: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("開発者の試し（端末で比べて選ぶ）")).scaledFont(size: 15, weight: .bold).foregroundStyle(Theme.foreground)
            label(L("下のバーのカメラ"))
            ChoicePills(options: [(DevChoices.tabBarDefault, L("元のデザイン")), (DevChoices.tabBarRaised, L("B 浮いた丸（将来）"))],
                        selection: Binding(get: { tabBarVariant == DevChoices.tabBarRaised ? DevChoices.tabBarRaised : DevChoices.tabBarDefault },
                                           set: { tabBarVariant = $0 }))
                .accessibilityIdentifier("settings.dev.tabbar")
        }
    }

    private func devRow(icon: String, title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).scaledFont(size: 17, weight: .semibold).foregroundStyle(Theme.primary)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text(title).scaledFont(size: 17, weight: .semibold).foregroundStyle(Theme.foreground)
                Spacer()
                Image(systemName: "chevron.right").scaledFont(size: 13, weight: .semibold).foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// 規約と表記 (web `LegalLinksCard`): the terms, the privacy policy, the AI consent right after it (as on the web,
    /// owner 2026-10-11), the commerce notice and support — one wrapping row of links.
    private var legalSection: some View {
        SettingsCard(title: L("規約と表記")) {
            FlowRow(spacing: 18) {
                Link(destination: AppConfig.termsURL) { legalLabel(L("利用規約")) }
                Link(destination: AppConfig.privacyURL) { legalLabel(L("プライバシーポリシー")) }
                Button { showAIConsentSettings = true } label: { legalLabel(L("AIへのデータ送信")) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.aiConsent")
                Link(destination: AppConfig.tokushohoURL) { legalLabel(L("特定商取引法に基づく表記")) }
                // Google's consent choices for ads, where the learner's region needs them (EEA/UK).
                if RewardedAds.shared.privacyOptionsRequired {
                    Button { RewardedAds.shared.presentPrivacyOptions() } label: { legalLabel(L("広告のプライバシー設定")) }
                        .buttonStyle(.plain)
                }
                Link(destination: AppConfig.supportURL) { legalLabel(L("お問い合わせ・サポート")) }
                    .accessibilityIdentifier("settings.support")
            }
        }
    }

    private func legalLabel(_ title: String) -> some View {
        Text(title)
            .scaledFont(size: 14, weight: .medium)
            .underline()
            .foregroundStyle(Theme.primaryInk)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private var proSection: some View {
        SettingsCard(title: "CatchWords Pro") {
            VStack(alignment: .leading, spacing: 10) {
                if plan.isPro {
                    Text(L("Pro をご利用中です")).scaledFont(size: 17, weight: .bold).foregroundStyle(Theme.foreground)
                    Text(L("撮影は無制限です")).scaledFont(size: 13).foregroundStyle(Theme.muted)
                } else {
                    Text(PlanStore.catchLimitEnabled ? L("今日あと\(plan.remainingToday)回撮れます") : L("ベータ期間中は撮影回数の制限はありません"))
                        .scaledFont(size: 15).foregroundStyle(Theme.muted)
                    Button { router.showPaywall = true } label: {
                        Text(L("Proにアップグレード")).scaledFont(size: 17, weight: .semibold).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(pillFill, in: Capsule())
                            .shadow(color: Theme.primary.opacity(0.35), radius: 10, y: 5)
                    }
                    .buttonStyle(PressableStyle())
                }
                // The terms, privacy policy and support are in 規約と表記 below.
                Button(L("購入を復元")) { Task { await plan.restore() } }
                    .scaledFont(size: 14, weight: .medium).foregroundStyle(Theme.primaryInk)
                    .frame(minHeight: 44)
                if let msg = plan.message { Text(msg).font(.footnote).foregroundStyle(Theme.muted) }
            }
        }
    }

    private var accountButtons: some View {
        VStack(spacing: 20) {
            Button { confirmSignOut = true } label: {
                Label(L("サインアウト"), systemImage: "rectangle.portrait.and.arrow.right")
                    .scaledFont(size: 17, weight: .semibold).foregroundStyle(Theme.foreground)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("settings.signOut")

            deleteZone

            Text(L("CatchWords iPhone版 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")（\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")）"))
                .scaledFont(size: 12).foregroundStyle(Theme.muted)
        }
    }

    private var deleteZone: some View {
        // The confirm word in any display language (and DELETE), so a switched language never locks the button.
        let accepted = Set(L10n.supported.map { L("削除", in: $0).uppercased() } + ["DELETE"])
        let armed = accepted.contains(deleteText.trimmingCharacters(in: .whitespaces).uppercased())
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { deleteOpen.toggle() }
            } label: {
                HStack {
                    Text(L("アカウントを削除")).scaledFont(size: 17, weight: .semibold).foregroundStyle(Color(light: 0xB42329, dark: 0xF87171))
                    Spacer()
                    Image(systemName: "chevron.down").scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(Color(light: 0xB42329, dark: 0xF87171).opacity(0.7))
                        .rotationEffect(.degrees(deleteOpen ? 180 : 0))
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if deleteOpen {
                Text(L("撮った写真・図鑑・復習の記録がすべて消え、元に戻せません。Web版のデータも同じく消えます。"))
                    .scaledFont(size: 13).foregroundStyle(Theme.muted)
                // Apple's account-deletion guidance: an App Store subscription keeps billing until it is cancelled
                // in the Apple ID settings. Always shown (whether this person has one is not known here).
                Text(L("App Store で購入したサブスクリプションは、アカウントを削除しても自動では解約されません。先に iPhone の「設定」→ Apple ID →「サブスクリプション」から解約してください。"))
                    .scaledFont(size: 13).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Link(L("サブスクリプションを管理"), destination: AppConfig.manageSubscriptionsURL)
                    .scaledFont(size: 14, weight: .medium).foregroundStyle(Theme.primaryInk)
                    .frame(minHeight: 44)
                Text(L("確認のため「削除」と入力してください")).scaledFont(size: 14, weight: .semibold).foregroundStyle(Theme.foreground)
                TextField(L10n.current.script == .latin ? L("削除").uppercased() : L("削除"), text: $deleteText)  // the confirm word itself
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.horizontal, 14).frame(minHeight: 46)
                    .background(Theme.card, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
                Button { Task { await deleteAccount() } } label: {
                    HStack(spacing: 8) {
                        if isDeleting { ProgressView().tint(.white) } else { Image(systemName: "trash") }
                        Text(isDeleting ? L("削除しています…") : L("完全に削除する"))
                    }
                    .scaledFont(size: 16, weight: .semibold).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.destructive.opacity(armed ? 1 : 0.4), in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .disabled(!armed || isDeleting)
                if let deleteError { Text(deleteError).font(.footnote).foregroundStyle(Theme.destructive) }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Theme.card, in: .rect(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.destructive.opacity(0.3), lineWidth: 1))
    }

    private var timesEditor: some View {
        let times = ReminderService.parseTimes(reminderTimes)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(times.enumerated()), id: \.offset) { i, t in
                HStack {
                    DatePicker(L("通知の時刻"), selection: Binding(
                        get: { Self.date(from: t) },
                        set: { d in
                            var list = times
                            list[i] = Self.hhmm(d)
                            saveTimes(list)
                        }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    if times.count > 1 {
                        Button { var list = times; list.remove(at: i); saveTimes(list) } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(L("この時刻を消す"))
                    }
                    Spacer()
                }
            }
            if times.count < 3 {
                Button { saveTimes(times + [ReminderService.defaultTime]) } label: {
                    Label(L("時刻を追加"), systemImage: "plus").scaledFont(size: 14, weight: .semibold).foregroundStyle(Theme.primary)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    // MARK: - Pieces

    private var pillFill: LinearGradient {
        LinearGradient(colors: [Theme.primaryBright, Theme.primaryDeep], startPoint: .top, endPoint: .bottom)
    }

    private func label(_ t: String) -> some View {
        Text(t).scaledFont(size: 17, weight: .semibold).foregroundStyle(Theme.foreground)
    }

    private func notice(_ t: String) -> some View {
        Text(t).scaledFont(size: 12).foregroundStyle(Color(light: 0x7A4B00, dark: 0xFCD34D))
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(light: 0xFFF5DB, dark: 0x2A2210), in: .rect(cornerRadius: 12))
    }

    /// A device setting that says 「保存しました」 when it changes (web: `settingsSaveStatus.saved()`).
    private func saving<T: Equatable>(_ binding: Binding<T>) -> Binding<T> {
        Binding(get: { binding.wrappedValue }, set: { v in
            guard v != binding.wrappedValue else { return }
            binding.wrappedValue = v
            SaveStatus.shared.saved()
        })
    }

    /// `interactive: false`: only one choice exists, so the row names it without a chevron and opens nothing.
    private func wheelRow(_ value: String, interactive: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(value).scaledFont(size: 18).foregroundStyle(Theme.foreground)
                Spacer()
                if interactive {
                    Image(systemName: "chevron.down").scaledFont(size: 14, weight: .semibold).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20).frame(minHeight: 56)
            .background(LinearGradient(colors: [Theme.card, Color(light: 0xEEF5FF, dark: 0x132032)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.primary.opacity(0.2), lineWidth: 1))
            .shadow(color: Theme.primary.opacity(0.06), radius: 6, y: 3)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .disabled(!interactive)
    }

    // MARK: - Actions

    private func openWheel(_ f: WheelField) {
        Haptics.selection()
        // Not animated here: the card springs in by itself (`WheelCard.appeared`) and fades out by itself before it
        // asks to be removed, so nothing of it is ever drawn by a transition.
        wheel = f
    }

    private func closeWheel() {
        // Out of the tree with no animation of any kind: nothing of the card may be drawn on its way out.
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { wheel = nil }
    }

    private func saveName() {
        let v = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, v != profile.displayName else { return }
        profile.displayName = v
        Task { if await profile.update(["display_name": v]) { SaveStatus.shared.saved() } }
    }

    private func setReminderMode(_ mode: String) {
        Task {
            if mode != "off", reminderMode == "off" {
                guard await ReminderService.requestPermission() else {
                    withAnimation { notifyDenied = true }
                    return
                }
            }
            notifyDenied = false
            reminderMode = mode
            SaveStatus.shared.saved()
            let times = ReminderService.parseTimes(reminderTimes)
            await ReminderService.applyReview(mode: mode, times: times, due: dex.upcomingDueTimes)
            await ReminderService.saveToAccount(mode: mode, times: times)
        }
    }

    private func saveTimes(_ list: [String]) {
        reminderTimes = list.joined(separator: ",")
        SaveStatus.shared.saved()
        Task {
            await ReminderService.applyReview(mode: reminderMode, times: list, due: dex.upcomingDueTimes)
            await ReminderService.saveToAccount(mode: reminderMode, times: list)
        }
    }

    private func setPlaceRemind(_ on: Bool) {
        Task {
            if on, !(await ReminderService.requestPermission()) {
                withAnimation { notifyDenied = true }
                placeRemind = false
                return
            }
            placeRemind = on
            SaveStatus.shared.saved()
            await ReminderService.applyPlaces(enabled: on, stickers: dex.stickers)
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        deleteError = nil
        let deletedId = SupabaseClient.shared.userId
        do {
            let uid = SupabaseClient.shared.userId
            try await profile.deleteAccount()
            await AccountCleanup.accountDeleted(userId: deletedId)
            isDeleting = false
            // Nothing of the deleted account stays on this device (waiting photos).
            if let uid {
                PendingQueue.shared.removeAll(ownerId: uid)
            }
            auth.signOut()
        } catch APIError.message(let text) {
            isDeleting = false
            deleteError = text
        } catch {
            isDeleting = false
            deleteError = L("削除できませんでした。通信を確かめて、もう一度お試しください。")
        }
    }

    private static func date(from hhmm: String) -> Date {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: p.first ?? 20, minute: p.last ?? 0, second: 0, of: Date()) ?? Date()
    }

    private static func hhmm(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 20, c.minute ?? 0)
    }
}

// MARK: - Building blocks

/// Section title (small, grey, outside) + white rounded card.
struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).scaledFont(size: 14, weight: .semibold).foregroundStyle(Theme.muted).padding(.leading, 6)
            content
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: .rect(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
    }
}

/// ChoiceRow: equal-width pills; the selected one is a glowing blue capsule that slides between them.
struct ChoicePills: View {
    let options: [(value: String, label: String)]
    /// A choice plays the 設定 choice sound (`SoundService.settingChanged`), owner 2026-10-20.
    var sounds: Bool = true
    @Binding var selection: String
    @Namespace private var ns
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.value) { o in
                let on = o.value == selection
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    if sounds { SoundService.shared.settingChanged() }
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72)) { selection = o.value }
                } label: {
                    Text(o.label)
                        .scaledFont(size: 16, weight: on ? .bold : .regular)
                        .foregroundStyle(on ? .white : Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.horizontal, 4)
                        .background {
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.card, Color(light: 0xF1F6FD, dark: 0x16202F)], startPoint: .top, endPoint: .bottom))
                                .overlay(Capsule().stroke(Color(hex: 0xC9DDF5), lineWidth: 1))
                            if on {
                                Capsule()
                                    .fill(LinearGradient(colors: [Theme.primaryBright, Theme.primaryDeep], startPoint: .top, endPoint: .bottom))
                                    .shadow(color: Theme.primary.opacity(0.4), radius: 10, y: 6)
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// ToggleRow: title, optional grey one-liner, blue switch.
struct SettingsToggle: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { v in
            Haptics.selection()
            SoundService.shared.settingChanged(on: v)
            isOn = v
        })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).scaledFont(size: 17, weight: .semibold).foregroundStyle(Theme.foreground)
                if let detail {
                    Text(detail).scaledFont(size: 13).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.primary)
        .frame(minHeight: 48)
    }
}

/// The developer screens opened from 設定 › 開発者 (each a sheet with its own navigation).
enum AdminScreen: String, Identifiable {
    case users, metrics, beta, appInfo, reports
    var id: String { rawValue }

    @ViewBuilder
    var view: some View {
        switch self {
        case .users: AdminUsersView()
        case .metrics: AdminMetricsView()
        case .beta: AdminBetaView()
        case .appInfo: AppInfoView()
        case .reports: AdminReportsView()
        }
    }
}

enum WheelField: Identifiable {
    case native, target, current, goal
    var id: Self { self }
    var title: String {
        switch self {
        case .native: L("母語")
        case .target: L("学習言語")
        case .current: L("今のレベル")
        case .goal: L("目標レベル")
        }
    }
}

/// WheelPicker: dimmed backdrop, centred white card with title, ×, wheel and 「閉じる」.
/// It fades and springs in on its own and fades out on its own before `onClose` removes it (no transition: see
/// SettingsView's overlay), and the choice is saved only once it is gone — a language switch redraws the whole page,
/// which must never happen while the card is still half drawn.
struct WheelCard: View {
    let field: WheelField
    let profile: ProfileStore
    let onClose: () -> Void
    @Environment(DexStore.self) private var dex
    @State private var value: String = ""
    @State private var appeared: Bool = false
    /// 「閉じる」 was tapped: the card is fading out and takes no more taps.
    @State private var closing: Bool = false

    /// Every display language, the learning language too (owner 2026-10-20: 繁體字（台灣） may be both; the
    /// learner's own language for the AI, `native_language`, is then the one saved before — ReaderLanguage.l1).
    private var options: [(value: String, label: String)] {
        switch field {
        case .native: ProfileStore.nativeOptions
        case .target: ProfileStore.targetChoices(current: profile.targetLanguage)
        case .current, .goal: ProfileStore.levels(for: profile.targetLanguage)
        }
    }

    private var initial: String {
        switch field {
        case .native: L10n.lang
        case .target: profile.targetLanguage
        case .current: profile.currentLevel
        case .goal: profile.levelGoal
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(field.title).scaledFont(size: 18, weight: .bold).foregroundStyle(Theme.foreground)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.foreground)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L("閉じる"))
                }
                // The app's own wheel (`TickWheel`): one tick per row as it crosses the centre line, from the first
                // scroll on. The system wheel's click came late and its first scroll was silent (owner 2026-10-20: this
                // wheel chosen over the system one).
                TickWheel(title: field.title, options: options, selection: $value)
                Button(action: close) {
                    Text(L("閉じる")).scaledFont(size: 17, weight: .bold).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.primary, in: Capsule())
                }
                // A press that ends in a plain fade: the springy press (scale + brightness, still swinging after the
                // finger lifts) outlived the card that faded out around it and left a ghost of the button over the
                // page (owner 2026-10-20: 「閉じるボタンの残像がある」). Hidden at once when tapped.
                .buttonStyle(FadePressStyle())
                .opacity(closing ? 0 : 1)
                .animation(nil, value: closing)
                .accessibilityIdentifier("wheel.close")
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .background(Theme.card, in: .rect(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
            .padding(.horizontal, 20)
            .scaleEffect(appeared ? 1 : 0.94)
        }
        .opacity(appeared ? 1 : 0)
        .allowsHitTesting(!closing)
        .onAppear {
            value = initial
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { appeared = true }
        }
    }

    /// The choice is saved once, when the card closes — not on every tick of the wheel (each save
    /// switches the app's language and reloads the dex). The card fades out first (0.18 s), is removed once it is
    /// invisible, and only then is the choice saved: the page under it redraws with nothing of the card left.
    private func close() {
        guard !closing else { return }
        closing = true
        let chosen = value
        withAnimation(.easeOut(duration: 0.18)) { appeared = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            onClose()
            commit(chosen)
        }
    }

    private func commit(_ v: String) {
        guard !v.isEmpty, v != initial, options.contains(where: { $0.value == v }) else { return }
        switch field {
        case .native:
            profile.nativeLanguage = v
            withAnimation(.easeInOut(duration: 0.25)) { L10n.set(v) }   // the whole app switches now
            // The web derives native_language from ui_language (readerL1: never the learning language)
            // and saves both (settings.tsx).
            let l1 = ReaderLanguage.l1(native: ReaderLanguage.native, target: profile.targetLanguage)
            ReaderLanguage.native = l1
            Task { if await profile.update(["native_language": l1, "ui_language": v]) { SaveStatus.shared.saved() } }
        case .target:
            profile.targetLanguage = v
            profile.currentLevel = ProfileStore.remap(profile.currentLevel, to: v)
            profile.levelGoal = ProfileStore.remap(profile.levelGoal, to: v)
            Task {
                // Language first, on its own (web: a rejected level column must not undo the language).
                let l1 = ReaderLanguage.l1(native: ReaderLanguage.native, target: v)
                ReaderLanguage.native = l1
                let saved = await profile.update(["native_language": l1, "target_language": v])
                await profile.update(["current_level": profile.currentLevel, "level_goal": profile.levelGoal])
                if saved { SaveStatus.shared.saved() }
                // The dex, album and review show only the words of the language being learned.
                await dex.load()
            }
        case .current:
            profile.currentLevel = v
            Task { if await profile.update(["current_level": v]) { SaveStatus.shared.saved() } }
        case .goal:
            profile.levelGoal = v
            Task { if await profile.update(["level_goal": v]) { SaveStatus.shared.saved() } }
        }
    }
}


/// A wheel of choices that ticks as each row crosses its centre line (`SoundService.tick(.wheel)` and a selection tap),
/// from the very first scroll: the system wheel's own click could not be made to come on time (owner 2026-10-20:
/// 「カチカチとなる効果音が滑らかにならない…はじめにスクロールしたときに音が鳴らない」). The rows snap to the centre;
/// VoiceOver and UI tests see a standard wheel picker (`accessibilityRepresentation`).
struct TickWheel: View {
    let title: String
    let options: [(value: String, label: String)]
    @Binding var selection: String

    static let rowHeight: CGFloat = 34
    static let visibleRows: CGFloat = 5
    private var height: CGFloat { Self.rowHeight * Self.visibleRows }
    private static let space = "tick.wheel"

    @State private var position: String?
    /// The row on the centre line now (ticks when it changes).
    @State private var centred: String?
    /// The first layout puts the chosen row on the centre line by itself: no tick for that.
    @State private var quietUntil: Date = .distantFuture
    @State private var feedback = UISelectionFeedbackGenerator()

    var body: some View {
        let h = height
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(options, id: \.value) { o in
                    Text(o.label)
                        .font(.system(size: 21, weight: o.value == selection ? .semibold : .regular))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.snappy(duration: 0.25)) { position = o.value } }
                        .scrollTransition(axis: .vertical) { content, phase in
                            content
                                .opacity(1 - min(1, abs(phase.value)) * 0.65)
                                .scaleEffect(1 - min(1, abs(phase.value)) * 0.1)
                        }
                        .onGeometryChange(for: Bool.self) { geo in
                            abs(geo.frame(in: .named(Self.space)).midY - h / 2) < Self.rowHeight / 2
                        } action: { onLine in
                            if onLine { reached(o.value) }
                        }
                        .id(o.value)
                }
            }
            .scrollTargetLayout()
        }
        .coordinateSpace(.named(Self.space))
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position, anchor: .center)
        .contentMargins(.vertical, (h - Self.rowHeight) / 2, for: .scrollContent)
        .background {
            // The centre band, like the system wheel's.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.secondary)
                .frame(height: Self.rowHeight)
        }
        .frame(height: h)
        .clipped()
        .onChange(of: position) { _, v in if let v, v != selection { selection = v } }
        // Set from outside (VoiceOver, a UI test adjusting the wheel): the rows follow.
        .onChange(of: selection) { _, v in if position != v { position = v } }
        .onAppear {
            centred = selection
            position = selection
            feedback.prepare()
            SoundService.shared.warmTicks()
            quietUntil = Date().addingTimeInterval(0.35)
        }
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { o in Text(o.label).tag(o.value) }
            }
            .pickerStyle(.wheel)
        }
    }

    private func reached(_ value: String) {
        guard value != centred else { return }
        centred = value
        guard Date() >= quietUntil else { return }
        SoundService.shared.tick(.wheel)
        if Haptics.isEnabled {
            feedback.selectionChanged()
            feedback.prepare()
        }
    }
}


/// A press that dims a little and comes straight back with a short ease (no spring, no brightness filter): nothing of it
/// is still moving once the finger is up (the 設定 wheel card's 「閉じる」, which fades out right after the tap).
struct FadePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.impact(.light, intensity: 0.6) }
            }
    }
}
