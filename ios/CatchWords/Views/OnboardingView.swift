import SwiftUI

/// First-run setup (FirstCatchIntro / FirstCatchQuestions / FirstCatchNotifications / FirstCatchReady).
/// intro → 5 questions (display, target, time, goals, interests) → notifications → ready.
/// Language / target go to `profiles`; goals, interests, minutes and reminders to auth user_metadata
/// (same keys the web writes: learning_preferences / notification_preferences).
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(ProfileStore.self) private var profile
    @Environment(AuthStore.self) private var auth
    @Environment(\.appReduceMotion) private var reduceMotion

    enum Stage: Int { case intro, questions, notifications, ready }

    @State private var stage: Stage = .intro
    @State private var step: Int = 0
    @State private var forward: Bool = true
    @State private var uiLanguage: String = L10n.lang
    @State private var targetLanguage: String = OnboardingView.fixedTarget
    @State private var minutes: Int = 10
    @State private var goals: Set<String> = []
    @State private var interests: Set<String> = []
    @State private var reminderMode: String = "ai"
    @State private var isSaving: Bool = false
    /// The profile could not be saved on 「はじめる」: shown on the ready screen, which stays so it can be retried.
    @State private var saveError: String?
    @State private var showMenu: Bool = false
    @AppStorage("reading.pref") private var readingPref: String = "zhuyin"
    @AppStorage("reading.ja") private var readingJa: String = "kana"
    @AppStorage("sound.level") private var soundLevel: String = "subtle"
    @AppStorage("haptics.enabled") private var hapticsOn: Bool = true

    static var goalList: [(id: String, label: String, icon: String)] { [
        ("conversation", L("日常会話"), "bubble.left.and.bubble.right"),
        ("travel", L("旅行・留学"), "airplane"),
        ("work", L("仕事・キャリア"), "briefcase"),
        ("exams", L("試験対策"), "graduationcap"),
        ("culture", L("趣味・教養"), "book"),
        ("other", L("その他"), "ellipsis"),
    ] }
    static var interestList: [(id: String, label: String)] { [
        ("food", L("食べ物")), ("travel", L("旅行")), ("animals", L("動物")),
        ("nature", L("自然")), ("city", L("建物・街")), ("fashion", L("ファッション")),
        ("business", L("ビジネス")), ("music", L("音楽・映画")), ("sports", L("スポーツ")),
    ] }
    // label = in the display language, native = the language's own name (never translated). Every display language
    // in languages.json, in its order.
    static var uiLanguages: [(id: String, label: String, native: String, flag: String)] {
        DisplayLanguages.all.map { ($0.code, L10n.text($0.nameJa), $0.autonym, $0.flag) }
    }
    static var targets: [(id: String, label: String, native: String, flag: String)] { [
        ("zh-TW", L("繁體字（台灣）"), "繁體字（台灣）", "🇹🇼"), ("en", L("英語"), "English", "🇺🇸"), ("ja", L("日本語"), "日本語", "🇯🇵")  // l10n-ignore (autonyms)
    ] }
    /// The learning-language question (step 1). Hidden while only 繁體字（台灣） is offered (owner 2026-10-11: 「新規
    /// ユーザーの質問の学習言語の選択のものをコードから隠して。コードを削除する必要はない」): every new account learns
    /// `fixedTarget`, and the display languages offered are the others (the two are never the same). Turn it back on
    /// when another learning language is offered.
    static let showsTargetStep = false
    /// The learning language while the question is hidden.
    static let fixedTarget = "zh-TW"

    /// The questions asked, in order (step numbers: 0 display, 1 learning language, 2 time, 3 goals, 4 interests).
    static var questionSteps: [Int] { showsTargetStep ? [0, 1, 2, 3, 4] : [0, 2, 3, 4] }
    /// Every screen the progress bar counts: the questions, the reminders and the ready screen.
    static var totalSteps: Int { questionSteps.count + 2 }

    /// The display languages offered: all of them, the learning language too (owner 2026-10-20: 繁體字（台灣） as the
    /// display language while learning it — explanations are then written in Mandarin).
    static var uiChoices: [(id: String, label: String, native: String, flag: String)] {
        uiLanguages
    }

    /// The learning languages offered (only 繁體字（台灣） for now: `ProfileStore.offeredTargets`), never the display
    /// language itself. Someone whose display language is the only offered one still gets a choice (the hidden
    /// ones) instead of an empty step.
    /// The offered learning languages, the display language left out when another one is offered (owner 2026-10-20:
    /// 繁體字（台灣） may be the display language while it is the only language to learn).
    static func targetChoices(ui: String) -> [(id: String, label: String, native: String, flag: String)] {
        let offered = targets.filter { ProfileStore.offeredTargets.contains($0.id) }
        let others = offered.filter { $0.id != ui }
        return others.isEmpty ? offered : others
    }

    var body: some View {
        ZStack {
            AppBackground()
            Group {
                switch stage {
                case .intro: intro
                case .questions: questions
                case .notifications: notifications
                case .ready: ready
                }
            }
            .id("\(stage.rawValue)-\(step)")
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: stage)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: step)
        .sheet(isPresented: $showMenu) { menu.presentationDetents([.large]) }
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                LogoMark(size: 40)
                Text("CatchWords").scaledFont(size: 26, weight: .heavy).foregroundStyle(Theme.foreground)
            }
            .padding(.top, 24)
            Spacer(minLength: 12)
            IntroBouquet(labels: targetLanguage == "en" ? ["coffee", "flower", "cat", "sea"] : targetLanguage == "ja" ? ["コーヒー", "花", "猫", "海"] : ["咖啡", "花", "貓", "海"])  // l10n-ignore (target words)
                .frame(maxHeight: 420)
                .padding(.horizontal, 24)
            Spacer(minLength: 12)
            Text(L("見つけたものが、\nあなたのことばになる。"))
                .font(AppFont.hand(24))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: 0x33291F))
                .padding(.bottom, 24)
            VStack(spacing: 10) {
                PrimaryButton(title: L("はじめる"), icon: "arrow.right", sheen: true) { go(.questions, step: 0) }
                Button(L("アカウントをお持ちの方はログイン")) { finishToLogin() }
                    .scaledFont(size: 15, weight: .medium)
                    .foregroundStyle(Theme.primaryInk)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Questions

    private var questions: some View {
        VStack(alignment: .leading, spacing: 0) {
            progressHeader(index: (Self.questionSteps.firstIndex(of: step) ?? 0) + 1) {
                if let i = Self.questionSteps.firstIndex(of: step), i > 0 {
                    go(.questions, step: Self.questionSteps[i - 1], back: true)
                } else {
                    go(.intro, step: 0, back: true)
                }
            }
            Text(questionTitle)
                .scaledFont(size: 28, weight: .heavy)
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 24)
                .padding(.top, 20)
            Text(questionHint)
                .scaledFont(size: 14)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 24)
                .padding(.top, 8)
            ScrollView {
                questionBody
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            PrimaryButton(title: L("次へ"), icon: "arrow.right") {
                if let i = Self.questionSteps.firstIndex(of: step), i + 1 < Self.questionSteps.count {
                    go(.questions, step: Self.questionSteps[i + 1])
                } else {
                    go(.notifications, step: 0)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private var questionTitle: String {
        [L("表示言語を\n選んでください"), L("学びたい言語は？"), L("1日、どれくらい\n学びたい？"), L("学ぶ目的を\n教えてください"), L("好きなことから、\nことばを広げよう")][step]
    }

    private var questionHint: String {
        [L("メニューや説明に使う言語です。"), L("街で出会ったことばを、この言語で学びます。"), L("あなたのペースで。あとから変更できます。"),
         L("いくつでも選べます。例文の場面をあなたに合わせます。"), L("興味のあるテーマを選んでください（複数選択可）。")][step]
    }

    @ViewBuilder
    private var questionBody: some View {
        switch step {
        case 0:
            VStack(spacing: 10) {
                ForEach(Self.uiChoices, id: \.id) { l in
                    ChoiceRow(leading: .flag(l.flag), title: l.label, sub: l.native == l.label ? nil : l.native, isOn: uiLanguage == l.id) {
                        uiLanguage = l.id
                        if !Self.targetChoices(ui: l.id).contains(where: { $0.id == targetLanguage }) {
                            targetLanguage = Self.targetChoices(ui: l.id).first?.id ?? "zh-TW"
                        }
                        withAnimation(.easeInOut(duration: 0.25)) { L10n.set(l.id) }
                    }
                }
            }
        case 1:
            VStack(spacing: 10) {
                // Your own language is not offered as the one to learn (web l1ChoicesFor).
                ForEach(Self.targetChoices(ui: uiLanguage), id: \.id) { l in
                    ChoiceRow(leading: .flag(l.flag), title: l.label, sub: l.native == l.label ? nil : l.native, isOn: targetLanguage == l.id) {
                        targetLanguage = l.id
                    }
                }
            }
        case 2:
            VStack(spacing: 22) {
                Image(systemName: "clock")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(Theme.primary)
                    .symbolEffect(.bounce, value: minutes)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { m in
                        Button {
                            Haptics.selection()
                            minutes = m
                        } label: {
                            Text(L("\(m)分"))
                                .scaledFont(size: 18, weight: .bold)
                                .foregroundStyle(minutes == m ? .white : Theme.foreground)
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .background(minutes == m ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.white), in: .rect(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(minutes == m ? .clear : Theme.border))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityAddTraits(minutes == m ? .isSelected : [])
                    }
                }
                Text(L("短い時間でも大丈夫。あなたのペースで続けましょう。"))
                    .scaledFont(size: 13).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
        case 3:
            VStack(spacing: 10) {
                ForEach(Self.goalList, id: \.id) { g in
                    ChoiceRow(leading: .icon(g.icon), title: g.label,
                              sub: g.id == "exams" ? (targetLanguage == "en" ? "TOEFL · IELTS" : targetLanguage == "ja" ? "JLPT" : "TOCFL") : nil,
                              isOn: goals.contains(g.id)) { toggle(&goals, g.id) }
                }
            }
        default:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                ForEach(Self.interestList, id: \.id) { i in
                    InterestTile(id: i.id, label: i.label, isOn: interests.contains(i.id)) { toggle(&interests, i.id) }
                }
            }
        }
    }

    private func toggle(_ set: inout Set<String>, _ v: String) {
        Haptics.selection()
        if set.contains(v) { set.remove(v) } else { set.insert(v) }
    }

    // MARK: - Notifications

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 0) {
            progressHeader(index: Self.questionSteps.count + 1) { go(.questions, step: Self.questionSteps.last ?? 4, back: true) }
            Text(L("学習の通知を\n設定しますか？"))
                .scaledFont(size: 28, weight: .heavy)
                .padding(.horizontal, 24).padding(.top, 20)
            Text(L("次の画面で通知を許可するか選べます。あとから設定で変更できます。"))
                .scaledFont(size: 14).foregroundStyle(Theme.muted)
                .padding(.horizontal, 24).padding(.top, 8)
            VStack(spacing: 10) {
                ChoiceRow(leading: .icon("sparkles"), title: L("おまかせ"), sub: L("忘れかける頃に1日1回お知らせ"), isOn: reminderMode == "ai") { reminderMode = "ai" }
                ChoiceRow(leading: .icon("clock"), title: L("朝と夜"), sub: L("8:00 と 20:00"), isOn: reminderMode == "custom") { reminderMode = "custom" }
            }
            .padding(20)
            Spacer()
            PrimaryButton(title: L("次へ"), icon: "arrow.right") {
                Task {
                    // Always hands over to the system sheet (no in-app way to skip it, Guideline 5.1.1);
                    // "Don't Allow" there turns the reminders off.
                    if reminderMode == "off" { reminderMode = "ai" }
                    if await !ReminderService.requestPermission() { reminderMode = "off" }
                    go(.ready, step: 0)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
    }

    // MARK: - Ready

    private var ready: some View {
        VStack(spacing: 0) {
            progressHeader(index: Self.totalSteps) { go(.notifications, step: 0, back: true) }
            Spacer()
            OnboardingPrint(name: "first_catch_ready", label: targetLanguage == "en" ? "sea" : "海", ratio: 1)  // l10n-ignore (target word)
                .frame(width: 230)
                .rotationEffect(.degrees(-3))
                .shadow(color: .black.opacity(0.15), radius: 18, y: 10)
            Text(L("最初の発見は、もうすぐ。"))
                .font(AppFont.hand(18)).foregroundStyle(Theme.muted).padding(.top, 18)
            Text(L("準備ができました！"))
                .scaledFont(size: 30, weight: .heavy).padding(.top, 26)
            Text(L("まずはアプリを見て回って、\n気になるものをひとつ撮ってみましょう。"))
                .scaledFont(size: 15).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center).padding(.top, 10)
            Spacer()
            if let saveError {
                Text(saveError).font(.footnote).foregroundStyle(Theme.destructive)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.bottom, 10)
            }
            PrimaryButton(title: L("はじめる"), icon: "arrow.right", isLoading: isSaving, sheen: true) {
                Task { await finish() }
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
    }

    // MARK: - Shared chrome

    private func progressHeader(index: Int, back: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Button(action: back) {
                Image(systemName: "arrow.left").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("戻る"))
            GeometryReader { geo in
                Capsule().fill(Theme.secondary)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.brandGradient).frame(width: geo.size.width * CGFloat(index) / CGFloat(Self.totalSteps))
                    }
            }
            .frame(height: 8)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: index)
            Text("\(index) / \(Self.totalSteps)").font(AppFont.mono(13, weight: .semibold)).foregroundStyle(Theme.muted)
            Button { showMenu = true } label: {
                Image(systemName: "gearshape").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.muted).frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("設定"))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// TutorialSettings: the same settings a signed-up user has, limited to what can be decided before
    /// finishing. Values stay in the tutorial draft and are saved to the account on finish.
    private var menu: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L("案内中の設定です。案内を終えると、そのままあなたのアカウントに引き継がれます。"))
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                Section(L("言語")) {
                    Picker(L("表示言語"), selection: Binding(get: { uiLanguage }, set: { picked in
                        uiLanguage = picked
                        if !Self.targetChoices(ui: picked).contains(where: { $0.id == targetLanguage }) {
                            targetLanguage = Self.targetChoices(ui: picked).first?.id ?? "zh-TW"
                        }
                        L10n.set(picked)
                    })) {
                        ForEach(Self.uiChoices, id: \.id) { Text($0.native).tag($0.id) }
                    }
                    if Self.showsTargetStep {
                        Picker(L("学ぶ言語"), selection: $targetLanguage) {
                            ForEach(Self.targetChoices(ui: uiLanguage), id: \.id) { Text($0.label).tag($0.id) }
                        }
                    }
                    // The same choices as 設定 › 発音表記 for each learning language (English has none).
                    if targetLanguage == "zh-TW" {
                        Picker(L("読みの表記"), selection: $readingPref) {
                            Text(L("ㄅㄆㄇ 注音")).tag("zhuyin")
                            Text(L("abc ピンイン")).tag("pinyin")
                        }
                    } else if targetLanguage == "ja" {
                        Picker(L("読みの表記"), selection: $readingJa) {
                            Text(L("あ ふりがな")).tag("kana")
                            Text(L("abc ローマ字")).tag("romaji")
                        }
                    }
                }
                Section(L("学習")) {
                    Picker(L("1日の学習時間"), selection: $minutes) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { Text(L("\($0)分")).tag($0) }
                    }
                    Picker(L("通知"), selection: $reminderMode) {
                        Text(L("おまかせ")).tag("ai")
                        Text(L("朝と夜")).tag("custom")
                        // Not before the system sheet: 「次へ」 always hands over to it (no in-app way to skip it,
                        // Guideline 5.1.1), so an "off" picked here would only be overridden there. Once it has
                        // been shown (ready screen, or after "Don't Allow") turning them off is a real choice.
                        if stage == .ready || reminderMode == "off" {
                            Text(L("通知しない")).tag("off")
                        }
                    }
                }
                Section(L("効果音と振動")) {
                    Picker(L("効果音"), selection: $soundLevel) {
                        Text(L("なし")).tag("off")
                        Text(L("控えめ")).tag("subtle")
                        Text(L("しっかり")).tag("full")
                    }
                    Toggle(L("振動"), isOn: $hapticsOn)
                }
                Section {
                    Button(L("最初の質問に答え直す"), systemImage: "list.bullet.clipboard") {
                        showMenu = false
                        go(.questions, step: 0, back: true)
                    }
                    Button(L("最初の画面に戻る"), systemImage: "arrow.counterclockwise") {
                        showMenu = false
                        go(.intro, step: 0, back: true)
                    }
                    Button(L("ログインする"), systemImage: "person.crop.circle") {
                        showMenu = false
                        finishToLogin()
                    }
                }
            }
            .navigationTitle(L("設定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("案内に戻る")) { showMenu = false } } }
        }
    }

    private func go(_ next: Stage, step nextStep: Int, back: Bool = false) {
        Haptics.impact(.light)
        forward = !back
        stage = next
        step = nextStep
    }

    // MARK: - Finish

    /// 「ログイン」: leave the session this guide was running in and open the sign-in screen, so the
    /// learner can enter the account they already have.
    /// The account signing in next is one the learner already has, so it skips the guide too (it adopts the
    /// device-wide flag once, see `OnboardingState.isDone`).
    private func finishToLogin() {
        OnboardingState.markDone(userId: SupabaseClient.shared.userId)
        UserDefaults.standard.set(true, forKey: OnboardingState.doneKey)
        onFinish()
        auth.signOut(keepLanguage: true)
    }

    private func finish() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        saveError = nil
        let times = reminderMode == "custom" ? ["08:00", "20:00"] : []
        UserDefaults.standard.set(reminderMode, forKey: ReminderService.modeKey)
        if !times.isEmpty { UserDefaults.standard.set(times.joined(separator: ","), forKey: ReminderService.timesKey) }
        await ReminderService.applyReview(mode: reminderMode, times: times)

        let level = ProfileStore.remap(profile.levelGoal, to: targetLanguage)
        // native_language as the web writes it (readerL1 from the display and learning languages).
        let l1 = ReaderLanguage.l1(native: ReaderLanguage.native, target: targetLanguage)
        // The languages first, on their own: a save that fails keeps this screen (with the reason) so
        // 「はじめる」 can be tried again, instead of finishing with the chosen languages lost.
        await profile.update(["native_language": l1, "target_language": targetLanguage, "ui_language": uiLanguage])
        if let failed = profile.message { saveError = failed; return }
        ReaderLanguage.native = l1
        profile.targetLanguage = targetLanguage
        await profile.update(["level_goal": level, "onboarded": true])
        if let failed = profile.message { saveError = failed; return }
        profile.levelGoal = level
        profile.onboarded = true
        let prefs: [String: Any] = [
            "learning_preferences": ["dailyMinutes": minutes, "goals": Array(goals), "interests": Array(interests)],
            "notification_preferences": ["mode": reminderMode, "times": times],
        ]
        try? await SupabaseClient.shared.updateUserMetadata(prefs)
        OnboardingState.markDone(userId: SupabaseClient.shared.userId)
        // 質問の後は、本物の画面で「撮る → 図鑑 → 復習」を体験する（FirstCatchFlow の home 段から）。
        UserDefaults.standard.set(true, forKey: TourStep.pendingStorageKey(for: SupabaseClient.shared.userId))
        Haptics.success()
        SoundService.shared.play(.sting)
        onFinish()
    }
}

/// Onboarding is done per account on this device (`doneKey.<userId>`): a second account on the same
/// iPhone gets its own guide. The server's `profiles.onboarded` (and a non-empty dex) still skips it too.
enum OnboardingState {
    /// The old device-wide flag. Now only a hand-over: the next account that signs in adopts it once, so
    /// people who finished onboarding before it was kept per account never see it again.
    static let doneKey = "onboarding.done"

    private static func key(for userId: String?) -> String {
        guard let userId else { return doneKey }   // a local guest (no account) keeps the device-wide flag
        return doneKey + "." + userId
    }

    /// Whether this account has finished (or left) onboarding on this device. Adopts the device-wide flag
    /// the first time an account asks, and clears it so the next account is asked on its own.
    static func isDone(userId: String?) -> Bool {
        let defaults = UserDefaults.standard
        guard let userId else { return defaults.bool(forKey: doneKey) }
        if defaults.bool(forKey: key(for: userId)) { return true }
        guard defaults.bool(forKey: doneKey) else { return false }
        defaults.set(true, forKey: key(for: userId))
        defaults.removeObject(forKey: doneKey)
        return true
    }

    static func markDone(userId: String?) {
        UserDefaults.standard.set(true, forKey: key(for: userId))
    }
}

// MARK: - Pieces

private enum ChoiceLeading { case flag(String), icon(String) }

private struct ChoiceRow: View {
    let leading: ChoiceLeading
    let title: String
    let sub: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 14) {
                switch leading {
                case .flag(let f):
                    Text(f).font(.system(size: 28)).frame(width: 44, height: 44)
                case .icon(let name):
                    Image(systemName: name).font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(isOn ? .white : Theme.primary)
                        .frame(width: 44, height: 44)
                        .background(isOn ? Theme.primary : Theme.accent, in: Circle())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).scaledFont(size: 17, weight: .semibold).foregroundStyle(Theme.foreground)
                    if let sub { Text(sub).scaledFont(size: 13).foregroundStyle(Theme.muted) }
                }
                Spacer()
                ZStack {
                    Circle().stroke(isOn ? Theme.primary : Theme.border, lineWidth: 2).frame(width: 26, height: 26)
                    if isOn {
                        Circle().fill(Theme.primary).frame(width: 26, height: 26)
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 70)
            .background(.white, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isOn ? Theme.primary : Theme.border, lineWidth: isOn ? 2 : 1))
            .shadow(color: isOn ? Theme.primary.opacity(0.15) : .clear, radius: 10, y: 4)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct InterestTile: View {
    let id: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            OnboardingPrint(name: "first_catch_interest_\(id)", label: label, ratio: 1)
                .overlay(alignment: .topTrailing) {
                    if isOn {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22)).foregroundStyle(.white, Theme.primary)
                            .padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .scaleEffect(isOn ? 0.96 : 1)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(isOn ? Theme.primary : .clear, lineWidth: 3))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Album-style print (white paper + word in the bottom margin), photo kept at its own ratio.
struct OnboardingPrint: View {
    let name: String
    let label: String
    let ratio: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            Color(hex: 0xEEE8DC)
                .aspectRatio(1 / ratio, contentMode: .fit)
                .overlay {
                    if let img = OnboardingImage.load(name) {
                        Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).allowsHitTesting(false)
                    }
                }
                .clipped()
            Text(label)
                .font(AppFont.hand(15))
                .foregroundStyle(Color(hex: 0x33291F))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding([.horizontal, .top], 6)
        .padding(.bottom, 8)
        .background(Color(hex: 0xFFFDF8))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}

enum OnboardingImage {
    private static var cache: [String: UIImage] = [:]
    static func load(_ name: String) -> UIImage? {
        if let c = cache[name] { return c }
        guard let path = Bundle.main.path(forResource: name, ofType: "webp"),
              let img = UIImage(contentsOfFile: path) else { return nil }
        cache[name] = img
        return img
    }
}

/// Welcome "bouquet" layout (DEFAULT_WELCOME_LAYOUT = C): cat in front, flower and sea tilted
/// symmetrically either side, coffee standing at the back centre.
private struct IntroBouquet: View {
    let labels: [String]
    @State private var appeared: Bool = false
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                print("first_catch_cafe", labels[0], 1.5, width: w * 0.40, x: 0, y: -geo.size.height * 0.16, angle: 0, delay: 0)
                print("first_catch_flower", labels[1], 1, width: w * 0.40, x: -w * 0.28, y: geo.size.height * 0.02, angle: -8, delay: 0.08)
                print("first_catch_ready", labels[3], 1, width: w * 0.40, x: w * 0.28, y: geo.size.height * 0.02, angle: 8, delay: 0.16)
                print("first_catch_cat", labels[2], 1, width: w * 0.46, x: 0, y: geo.size.height * 0.2, angle: -2, delay: 0.24)
            }
            .frame(width: w, height: geo.size.height)
        }
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.8, dampingFraction: 0.75)) { appeared = true }
        }
    }

    private func print(_ name: String, _ label: String, _ ratio: CGFloat, width: CGFloat, x: CGFloat, y: CGFloat, angle: Double, delay: Double) -> some View {
        OnboardingPrint(name: name, label: label, ratio: ratio)
            .frame(width: width)
            .rotationEffect(.degrees(appeared ? angle : 0))
            .offset(x: x, y: appeared ? y : y + 40)
            .opacity(appeared ? 1 : 0)
            .animation(reduceMotion ? .none : .spring(response: 0.8, dampingFraction: 0.75).delay(delay), value: appeared)
    }
}
