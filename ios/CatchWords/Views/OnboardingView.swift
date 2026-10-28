import SwiftUI

/// First-run setup (FirstCatchQuestions / FirstCatchNotifications / FirstCatchReady).
/// 4 questions (display, TOCFL level, time, goals) → notifications → ready; then the guide over the real screens
/// (`TourStep`).
/// Language / target go to `profiles`; goals, minutes and reminders to auth user_metadata
/// (same keys the web writes: learning_preferences / notification_preferences).
///
/// Owner 2026-10-27: the question about favourite photo themes (interests) is gone (the server reads no interests as
/// everyday life). Owner 2026-10-28: no pages of their own before the questions (「実際のアプリの画面を使ってチュートリアルを
/// 作って」): what the app does is shown on its real screens by the guide that follows. Owner 2026-10-28: the TOCFL level
/// now and the goal are asked (「わからない」 = level 1 now, level 2 the goal) and set as the account's first levels.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(ProfileStore.self) private var profile
    @Environment(AuthStore.self) private var auth
    @Environment(\.appReduceMotion) private var reduceMotion

    enum Stage: Int { case questions, notifications, ready }

    @State private var stage: Stage = .questions
    @State private var step: Int = 0
    @State private var forward: Bool = true
    @State private var uiLanguage: String = L10n.lang
    @State private var targetLanguage: String = OnboardingView.fixedTarget
    @State private var minutes: Int = 10
    @State private var goals: Set<String> = []
    /// The TOCFL level now and the goal (1…6), nil = 「わからない」 (`OnboardingLevels.resolve`).
    @State private var levelNow: Int?
    @State private var levelGoal: Int?
    @State private var reminderMode: String = "ai"
    @State private var isSaving: Bool = false
    /// The profile could not be saved on 「はじめる」: shown on the ready screen, which stays so it can be retried.
    @State private var saveError: String?
    @State private var showMenu: Bool = false
    @AppStorage("reading.pref") private var readingPref: String = "zhuyin"
    @AppStorage("reading.ja") private var readingJa: String = "kana"
    @AppStorage("sound.level") private var soundLevel: String = "subtle"
    @AppStorage("haptics.enabled") private var hapticsOn: Bool = true

    /// `start`/`step`: where it opens (the simulator check's pictures of the later screens, `UIPreview`).
    init(start: Stage = .questions, step: Int = OnboardingView.questionSteps[0], onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _stage = State(initialValue: start)
        _step = State(initialValue: step)
    }

    static var goalList: [(id: String, label: String, icon: String)] { [
        ("conversation", L("日常会話"), "bubble.left.and.bubble.right"),
        ("travel", L("旅行・留学"), "airplane"),
        ("work", L("仕事・キャリア"), "briefcase"),
        ("exams", L("試験対策"), "graduationcap"),
        ("culture", L("趣味・教養"), "book"),
        ("other", L("その他"), "ellipsis"),
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

    /// The questions asked, in order (step numbers: 0 display, 1 learning language, 2 time, 3 goals, 4 TOCFL level).
    static var questionSteps: [Int] { showsTargetStep ? [0, 1, 4, 2, 3] : [0, 4, 2, 3] }
    /// Every screen the progress bar counts: the questions, the reminders and the ready screen.
    static var totalSteps: Int { questionSteps.count + 2 }

    /// The display languages offered: all of them, the learning language too (owner 2026-10-20: 繁體字（台灣） as the
    /// display language while learning it — explanations are then written in Mandarin).
    static var uiChoices: [(id: String, label: String, native: String, flag: String)] {
        uiLanguages
    }

    /// The offered learning languages, the display language left out when another one is offered (owner 2026-10-20:
    /// 繁體字（台灣） may be the display language while it is the only language to learn). Someone whose display language
    /// is the only offered one still gets a choice (the hidden ones) instead of an empty step.
    static func targetChoices(ui: String) -> [(id: String, label: String, native: String, flag: String)] {
        let offered = targets.filter { ProfileStore.offeredTargets.contains($0.id) }
        let others = offered.filter { $0.id != ui }
        return others.isEmpty ? offered : others
    }

    var body: some View {
        ZStack {
            OnboardingBackdrop()
            Group {
                switch stage {
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
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: stage)
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: step)
        .sheet(isPresented: $showMenu) { menu.presentationDetents([.large]) }
        // The pick tick must sound the first time too (as in 設定).
        .onAppear { SoundService.shared.warmTicks() }
    }

    // MARK: - Questions

    private var questions: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The first question has nothing before it (the guide's start is after the questions).
            let at = Self.questionSteps.firstIndex(of: step) ?? 0
            progressHeader(index: at + 1, back: at > 0 ? { go(.questions, step: Self.questionSteps[at - 1], back: true) } : nil)
            RevealHeadline(marked: questionTitle, size: 28, alignment: .leading, duration: 0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 22)
            Appearing { shown in
                Text(questionHint)
                    .scaledFont(size: 14)
                    .foregroundStyle(Theme.muted)
                    .staggerIn(shown, delay: 0.2, distance: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            ScrollView {
                Appearing { shown in questionBody(shown) }
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
        [L("表示言語を\n選んでください"), L("学びたい言語は？"), L("1日、どれくらい\n学びたい？"), L("学ぶ目的を\n教えてください"),
         L("TOCFLのレベルは？")][step]
    }

    private var questionHint: String {
        [L("メニューや説明に使う言語です。"), L("街で出会ったことばを、この言語で学びます。"), L("あなたのペースで。あとから変更できます。"),
         L("いくつでも選べます。例文の場面をあなたに合わせます。"),
         L("例文やチャンクの難しさを合わせます。あとから設定で変更できます。")][step]
    }

    /// The rows of the question, coming in one after another once `shown`.
    @ViewBuilder
    private func questionBody(_ shown: Bool) -> some View {
        switch step {
        case 0:
            VStack(spacing: 10) {
                ForEach(Array(Self.uiChoices.enumerated()), id: \.element.id) { i, l in
                    ChoiceRow(leading: .flag(l.flag), title: l.label, sub: l.native == l.label ? nil : l.native, isOn: uiLanguage == l.id) {
                        uiLanguage = l.id
                        if !Self.targetChoices(ui: l.id).contains(where: { $0.id == targetLanguage }) {
                            targetLanguage = Self.targetChoices(ui: l.id).first?.id ?? "zh-TW"
                        }
                        withAnimation(.easeInOut(duration: 0.25)) { L10n.set(l.id) }
                    }
                    .staggerIn(shown, delay: 0.15 + Double(i) * 0.04)
                }
            }
        case 1:
            VStack(spacing: 10) {
                // Your own language is not offered as the one to learn (web l1ChoicesFor).
                ForEach(Array(Self.targetChoices(ui: uiLanguage).enumerated()), id: \.element.id) { i, l in
                    ChoiceRow(leading: .flag(l.flag), title: l.label, sub: l.native == l.label ? nil : l.native, isOn: targetLanguage == l.id) {
                        targetLanguage = l.id
                    }
                    .staggerIn(shown, delay: 0.15 + Double(i) * 0.04)
                }
            }
        case 2:
            VStack(spacing: 22) {
                Image(systemName: "clock")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(Theme.primary)
                    .symbolEffect(.bounce, value: minutes)
                    .staggerIn(shown, delay: 0.1)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array([5, 10, 15, 30, 60].enumerated()), id: \.element) { i, m in
                        Button {
                            guard minutes != m else { return }
                            OnboardingPick.choose(reduceMotion: reduceMotion) { minutes = m }
                        } label: {
                            Text(L("\(m)分"))
                                .scaledFont(size: 18, weight: .bold)
                                .foregroundStyle(minutes == m ? .white : Theme.foreground)
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .background(minutes == m ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.white), in: .rect(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(minutes == m ? .clear : Theme.border))
                                .shadow(color: minutes == m ? Theme.primary.opacity(0.3) : .clear, radius: 10, y: 4)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityAddTraits(minutes == m ? .isSelected : [])
                        .staggerIn(shown, delay: 0.18 + Double(i) * 0.04)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: minutes)
                Text(L("短い時間でも大丈夫。あなたのペースで続けましょう。"))
                    .scaledFont(size: 13).foregroundStyle(Theme.muted)
                    .staggerIn(shown, delay: 0.4)
            }
            .frame(maxWidth: .infinity)
        case 4:
            VStack(alignment: .leading, spacing: 22) {
                levelPicker(L("いまのレベル"), selection: $levelNow, lowest: 1, shown: shown, delay: 0.12)
                levelPicker(L("目標のレベル"), selection: $levelGoal, lowest: levelNow ?? 1, shown: shown, delay: 0.3)
                    .onChange(of: levelNow) { _, now in
                        // The goal is never below the level now.
                        if let now, let goal = levelGoal, goal < now { levelGoal = now }
                    }
            }
        default:
            VStack(spacing: 10) {
                ForEach(Array(Self.goalList.enumerated()), id: \.element.id) { i, g in
                    ChoiceRow(leading: .icon(g.icon), title: g.label,
                              sub: g.id == "exams" ? (targetLanguage == "en" ? "TOEFL · IELTS" : targetLanguage == "ja" ? "JLPT" : "TOCFL") : nil,
                              isOn: goals.contains(g.id)) { toggle(&goals, g.id) }
                        .staggerIn(shown, delay: 0.15 + Double(i) * 0.04)
                }
            }
        }
    }

    /// 「わからない」 and TOCFL Level 1…6 (levels under `lowest` can't be picked: a goal below the level now).
    private func levelPicker(_ title: String, selection: Binding<Int?>, lowest: Int, shown: Bool, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .scaledFont(size: 15, weight: .bold)
                .foregroundStyle(Theme.foreground)
                .staggerIn(shown, delay: delay)
            LevelChip(top: nil, title: L("わからない"), isOn: selection.wrappedValue == nil, enabled: true) {
                selection.wrappedValue = nil
            }
            .staggerIn(shown, delay: delay + 0.04)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(1...6, id: \.self) { n in
                    LevelChip(top: "TOCFL Level", title: "\(n)", isOn: selection.wrappedValue == n, enabled: n >= lowest) {  // l10n-ignore (TOCFL Level n is shared, CLAUDE.md)
                        selection.wrappedValue = n
                    }
                    .staggerIn(shown, delay: delay + 0.06 + Double(n) * 0.03)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selection.wrappedValue)
    }

    private func toggle(_ set: inout Set<String>, _ v: String) {
        if set.contains(v) { set.remove(v) } else { set.insert(v) }
    }

    // MARK: - Notifications

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 0) {
            progressHeader(index: Self.questionSteps.count + 1) { go(.questions, step: Self.questionSteps.last ?? 3, back: true) }
            RevealHeadline(marked: L("学習の通知を\n設定しますか？"), size: 28, alignment: .leading, duration: 0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24).padding(.top, 22)
            Appearing { shown in
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("次の画面で通知を許可するか選べます。あとから設定で変更できます。"))
                        .scaledFont(size: 14).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 24).padding(.top, 8)
                        .staggerIn(shown, delay: 0.2, distance: 8)
                    VStack(spacing: 10) {
                        ChoiceRow(leading: .icon("sparkles"), title: L("おまかせ"), sub: L("忘れかける頃に1日1回お知らせ"), isOn: reminderMode == "ai") { reminderMode = "ai" }
                            .staggerIn(shown, delay: 0.15)
                        ChoiceRow(leading: .icon("clock"), title: L("朝と夜"), sub: L("8:00 と 20:00"), isOn: reminderMode == "custom") { reminderMode = "custom" }
                            .staggerIn(shown, delay: 0.19)
                    }
                    .padding(20)
                }
            }
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

    /// Says what comes next: the guide over the real screens, one photo, about a minute, in four steps (the same four
    /// the guide's cards count, `TourPhase`). Not knowing what the guide wanted was the first complaint (2026-10-27).
    private var ready: some View {
        VStack(spacing: 0) {
            progressHeader(index: Self.totalSteps) { go(.notifications, step: 0, back: true) }
            Spacer(minLength: 8)
            // The app's own mark, no photos (owner 2026-10-28: 「海とかコーヒーの写真…昔のものを使い回さないで」).
            Appearing { shown in
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Theme.primary.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 130))
                        .frame(width: 260, height: 260)
                        .scaleEffect(shown ? 1 : 0.6)
                        .opacity(shown ? 1 : 0)
                        .animation(.easeOut(duration: 0.9), value: shown)
                    LogoMark(size: 96)
                        .scaleEffect(shown ? 1 : 0.6)
                        .opacity(shown ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.62).delay(0.1), value: shown)
                }
            }
            .frame(height: 200)
            RevealHeadline(marked: L("準備ができました！"), size: 30, delay: 0.25)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 18)
            Appearing { shown in
                VStack(spacing: 18) {
                    Text(L("このあと、実際に1枚撮りながら、このアプリでできることを案内します。"))
                        .scaledFont(size: 15).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .staggerIn(shown, delay: 0.55, distance: 8)
                    TourPhaseRow(current: nil, shown: shown, baseDelay: 0.7)
                    Label(L("約3分"), systemImage: "clock")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(Theme.primaryInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.primary.opacity(0.1), in: Capsule())
                        .staggerIn(shown, delay: 1.0, distance: 8)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            Spacer(minLength: 8)
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

    private func progressHeader(index: Int, back: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Button { back?() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("戻る"))
            .opacity(back == nil ? 0 : 1)
            .disabled(back == nil)
            // One segment per screen, the ones done filled (the count reads at a glance, no numbers to read).
            HStack(spacing: 5) {
                ForEach(1...Self.totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.secondary))
                        .frame(height: 6)
                        .scaleEffect(y: i == index ? 1.25 : 1)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: index)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(index) / \(Self.totalSteps)")
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

        let picked = OnboardingLevels.resolve(now: levelNow, goal: levelGoal)
        let current = ProfileStore.remap("TOCFL-\(picked.now)", to: targetLanguage)
        let level = ProfileStore.remap("TOCFL-\(picked.goal)", to: targetLanguage)
        // native_language as the web writes it (readerL1 from the display and learning languages).
        let l1 = ReaderLanguage.l1(native: ReaderLanguage.native, target: targetLanguage)
        // The languages first, on their own: a save that fails keeps this screen (with the reason) so
        // 「はじめる」 can be tried again, instead of finishing with the chosen languages lost.
        await profile.update(["native_language": l1, "target_language": targetLanguage, "ui_language": uiLanguage])
        if let failed = profile.message { saveError = failed; return }
        ReaderLanguage.native = l1
        profile.targetLanguage = targetLanguage
        await profile.update(["current_level": current, "level_goal": level, "onboarded": true])
        if let failed = profile.message { saveError = failed; return }
        profile.currentLevel = current
        profile.levelGoal = level
        profile.onboarded = true
        let prefs: [String: Any] = [
            "learning_preferences": ["dailyMinutes": minutes, "goals": Array(goals)],
            "notification_preferences": ["mode": reminderMode, "times": times],
        ]
        try? await SupabaseClient.shared.updateUserMetadata(prefs)
        OnboardingState.markDone(userId: SupabaseClient.shared.userId)
        // 質問の後は、本物の画面で「撮る → 選ぶ → 図鑑 → 復習」を体験する（TourStep の tapCamera から）。
        UserDefaults.standard.set(true, forKey: TourStep.pendingStorageKey(for: SupabaseClient.shared.userId))
        Haptics.success()
        SoundService.shared.play(.sting)
        onFinish()
    }
}

/// The onboarding's TOCFL answers as the account's first levels (owner 2026-10-28: 「わからないと答えたら、現状レベル1、
/// 目標レベル2に自動設定」). An unknown goal is one above the level now (6 stays 6); the goal is never below it.
enum OnboardingLevels {
    static func resolve(now: Int?, goal: Int?) -> (now: Int, goal: Int) {
        let n = min(max(now ?? 1, 1), 6)
        let g = goal.map { min(max($0, n), 6) } ?? min(n + 1, 6)
        return (n, g)
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

/// A pick in the first questions sounds and moves like a choice in 設定 (owner 2026-10-28: 「ユーザーが選択するとき、効果音や
/// アニメーションをアプリ内の設定のものと同じにして」): the 設定 pick tick (`SoundService.settingChanged`), a selection tap,
/// and the 設定 pills' spring (0.3 / 0.72).
enum OnboardingPick {
    static func choose(reduceMotion: Bool, _ change: () -> Void) {
        Haptics.selection()
        SoundService.shared.settingChanged()
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72)) { change() }
    }
}

private enum ChoiceLeading { case flag(String), icon(String) }

/// One answer of the TOCFL question: 「わからない」 across the row, or a level (「TOCFL Level」 over its number).
private struct LevelChip: View {
    let top: String?
    let title: String
    let isOn: Bool
    let enabled: Bool
    let action: () -> Void
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            guard !isOn else { return }
            OnboardingPick.choose(reduceMotion: reduceMotion, action)
        } label: {
            VStack(spacing: 0) {
                if let top {
                    Text(top)
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(isOn ? Color.white.opacity(0.85) : Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(title)
                    .scaledFont(size: top == nil ? 16 : 22, weight: .bold)
                    .foregroundStyle(isOn ? .white : Theme.foreground)
            }
            .frame(maxWidth: .infinity, minHeight: top == nil ? 50 : 62)
            .background(isOn ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.white), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isOn ? .clear : Theme.border))
            .shadow(color: isOn ? Theme.primary.opacity(0.3) : .clear, radius: 10, y: 4)
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct ChoiceRow: View {
    let leading: ChoiceLeading
    let title: String
    let sub: String?
    let isOn: Bool
    let action: () -> Void
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            OnboardingPick.choose(reduceMotion: reduceMotion, action)
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
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
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



// MARK: - Motion pieces

/// Hands its content `shown`: false on the first frame, true right after, so `staggerIn` children come in one after
/// another each time the screen appears.
struct Appearing<Content: View>: View {
    @ViewBuilder var content: (Bool) -> Content
    @State private var shown = false

    var body: some View {
        content(shown).task { shown = true }
    }
}

/// The page colour with two soft lights drifting slowly behind (still with reduced motion).
struct OnboardingBackdrop: View {
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Theme.primary.opacity(0.13))
                .frame(width: 380, height: 380)
                .blur(radius: 80)
                .offset(x: drift ? 130 : 70, y: drift ? -250 : -310)
            Circle()
                .fill(Theme.cyan.opacity(0.16))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: drift ? -100 : -160, y: drift ? 260 : 330)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
