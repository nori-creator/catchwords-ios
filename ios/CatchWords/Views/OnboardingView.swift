import SwiftUI

/// First-run setup (FirstCatchIntro / FirstCatchQuestions / FirstCatchNotifications / FirstCatchReady).
/// intro (3 pages: 撮る → 図鑑 → 思い出す) → 3 questions (display, time, goals) → notifications → ready.
/// Language / target go to `profiles`; goals, minutes and reminders to auth user_metadata
/// (same keys the web writes: learning_preferences / notification_preferences).
///
/// Owner 2026-10-27: the question about favourite photo themes (interests) is gone, and the intro shows what the app
/// does before anything is asked (「アプリの面白さ凄さが伝わらない」). The server reads no interests as everyday life.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(ProfileStore.self) private var profile
    @Environment(AuthStore.self) private var auth
    @Environment(\.appReduceMotion) private var reduceMotion

    enum Stage: Int { case intro, questions, notifications, ready }

    @State private var stage: Stage = .intro
    @State private var step: Int = 0
    @State private var introPage: Int = 0
    @State private var forward: Bool = true
    @State private var uiLanguage: String = L10n.lang
    @State private var targetLanguage: String = OnboardingView.fixedTarget
    @State private var minutes: Int = 10
    @State private var goals: Set<String> = []
    @State private var reminderMode: String = "ai"
    @State private var isSaving: Bool = false
    /// The profile could not be saved on 「はじめる」: shown on the ready screen, which stays so it can be retried.
    @State private var saveError: String?
    @State private var showMenu: Bool = false
    @AppStorage("reading.pref") private var readingPref: String = "zhuyin"
    @AppStorage("reading.ja") private var readingJa: String = "kana"
    @AppStorage("sound.level") private var soundLevel: String = "subtle"
    @AppStorage("haptics.enabled") private var hapticsOn: Bool = true

    /// `start`/`step`/`page`: where it opens (the simulator check's pictures of the later screens, `UIPreview`).
    init(start: Stage = .intro, step: Int = 0, page: Int = 0, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _stage = State(initialValue: start)
        _step = State(initialValue: step)
        _introPage = State(initialValue: page)
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

    /// The questions asked, in order (step numbers: 0 display, 1 learning language, 2 time, 3 goals).
    static var questionSteps: [Int] { showsTargetStep ? [0, 1, 2, 3] : [0, 2, 3] }
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
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: stage)
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: step)
        .sheet(isPresented: $showMenu) { menu.presentationDetents([.large]) }
    }

    // MARK: - Intro

    /// Three pages that show the app before it asks anything: a photo gets its word, the words gather in the 図鑑, and
    /// the learner's own photo brings the word back. Swiped, or 「次へ」; 「スキップ」 goes straight to the questions.
    private var intro: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                LogoMark(size: 28)
                Text(verbatim: "CatchWords")
                    .scaledFont(size: 18, weight: .heavy)
                    .foregroundStyle(Theme.foreground)
                Spacer()
                if introPage < IntroStory.pages - 1 {
                    Button(L("スキップ")) { go(.questions, step: Self.questionSteps[0]) }
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Theme.muted)
                        .frame(minWidth: 44, minHeight: 44)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .animation(.easeOut(duration: 0.2), value: introPage)
            TabView(selection: $introPage) {
                ForEach(0..<IntroStory.pages, id: \.self) { i in
                    IntroStory(page: i, active: introPage == i, zhuyin: readingPref != "pinyin")
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: introPage) { _, _ in Haptics.selection() }
            IntroDots(count: IntroStory.pages, index: introPage)
                .padding(.bottom, 18)
            let last = introPage == IntroStory.pages - 1
            PrimaryButton(title: last ? L("はじめる") : L("次へ"), icon: "arrow.right", sheen: last) {
                if last {
                    go(.questions, step: Self.questionSteps[0])
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { introPage += 1 }
                }
            }
            .padding(.horizontal, 24)
            .accessibilityIdentifier("onboarding.next")
            Button(L("アカウントをお持ちの方はログイン")) { finishToLogin() }
                .scaledFont(size: 14, weight: .medium)
                .foregroundStyle(Theme.primaryInk)
                .frame(minHeight: 44)
                .padding(.bottom, 8)
                .opacity(last ? 1 : 0)
                .allowsHitTesting(last)
                .animation(.easeOut(duration: 0.25), value: last)
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
        [L("表示言語を\n選んでください"), L("学びたい言語は？"), L("1日、どれくらい\n学びたい？"), L("学ぶ目的を\n教えてください")][step]
    }

    private var questionHint: String {
        [L("メニューや説明に使う言語です。"), L("街で出会ったことばを、この言語で学びます。"), L("あなたのペースで。あとから変更できます。"),
         L("いくつでも選べます。例文の場面をあなたに合わせます。")][step]
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
                            Haptics.selection()
                            minutes = m
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

    private func toggle(_ set: inout Set<String>, _ v: String) {
        Haptics.selection()
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
            Appearing { shown in
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Theme.primary.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 160))
                        .frame(width: 320, height: 320)
                        .scaleEffect(shown ? 1 : 0.6)
                        .opacity(shown ? 1 : 0)
                        .animation(.easeOut(duration: 0.9), value: shown)
                    OnboardingPrint(name: "first_catch_cafe", label: "咖啡", ratio: 1.25)  // l10n-ignore (target word)
                        .frame(width: 150)
                        .rotationEffect(.degrees(shown ? -9 : -2))
                        .offset(x: shown ? -62 : 0, y: shown ? 6 : 20)
                        .staggerIn(shown, delay: 0.12)
                    OnboardingPrint(name: "first_catch_ready", label: "海", ratio: 1)  // l10n-ignore (target word)
                        .frame(width: 170)
                        .rotationEffect(.degrees(shown ? 5 : 0))
                        .offset(x: shown ? 56 : 0, y: shown ? -4 : 20)
                        .staggerIn(shown, delay: 0.2)
                }
                .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
                .animation(.spring(response: 0.8, dampingFraction: 0.72).delay(0.1), value: shown)
            }
            .frame(height: 250)
            RevealHeadline(marked: L("準備ができました！"), size: 30, delay: 0.25)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 18)
            Appearing { shown in
                VStack(spacing: 18) {
                    Text(L("このあと、実際に1枚撮りながら使い方を案内します。"))
                        .scaledFont(size: 15).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .staggerIn(shown, delay: 0.55, distance: 8)
                    TourPhaseRow(current: nil, shown: shown, baseDelay: 0.7)
                    Label(L("約1分"), systemImage: "clock")
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

    private func progressHeader(index: Int, back: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("戻る"))
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
                .scaledFont(size: 15)
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

/// The intro's page dots: the current one a longer blue capsule.
private struct IntroDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.foreground.opacity(0.15)))
                    .frame(width: i == index ? 24 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(index + 1) / \(count)")
    }
}

/// One page of the intro: its scene, the headline with its keyword on a pill, one line under it.
private struct IntroStory: View {
    static let pages = 3
    let page: Int
    let active: Bool
    let zhuyin: Bool

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: IntroCatchScene(active: active, zhuyin: zhuyin)
                case 1: IntroDexScene(active: active)
                default: IntroQuizScene(active: active)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            RevealHeadline(marked: title, size: 30, active: active, delay: 0.3, duration: 1.1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 22)
            Text(sub)
                .scaledFont(size: 15)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 10)
                .staggerIn(active, delay: 0.75, distance: 8)
        }
        .padding(.bottom, 14)
    }

    private var title: String {
        [L("撮るだけで、\n**ことば**になる"), L("集めたことばは\n**図鑑**に並ぶ"), L("自分の写真で\n**思い出す**")][page]
    }

    private var sub: String {
        [L("気になる物を撮るだけ。AIが写真の中の物の名前と発音を教えてくれます。"),
         L("撮った写真と出会った場所ごと、あなただけの単語帳に。"),
         L("忘れかけた頃に、自分の写真で4択の復習。出会った場面ごと覚えられます。")][page]
    }
}

/// A scene's own timeline: `run` when its page comes in; put back to the start (`reset`) a moment after it left, once
/// it has slid out of sight, so it plays again next time.
private extension View {
    func introTimeline(active: Bool, reduceMotion: Bool, finish: @escaping () -> Void, reset: @escaping () -> Void,
                       run: @escaping () async -> Void) -> some View {
        task(id: active) {
            if !active {
                try? await Task.sleep(for: .milliseconds(600))
                if !Task.isCancelled { reset() }
                return
            }
            if reduceMotion { finish() } else { await run() }
        }
    }
}

/// Page 1: a photo of a café table; a scan passes over it, the cup is framed, and its word pops up on a tag (a tap on
/// the tag says it, as in the app).
private struct IntroCatchScene: View {
    let active: Bool
    let zhuyin: Bool

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var scan: CGFloat = 0
    @State private var scanning = false
    @State private var found = false
    @State private var said = 0

    /// The cup in first_catch_cafe, as fractions of the picture.
    private static let cup = CGRect(x: 0.32, y: 0.63, width: 0.49, height: 0.21)
    private static let word = "咖啡"  // l10n-ignore (target word)

    var body: some View {
        GeometryReader { geo in
            let h = min(geo.size.height * 0.96, geo.size.width * 0.62 * 1.5)
            let w = h / 1.5
            card(w: w, h: h)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .introTimeline(active: active, reduceMotion: reduceMotion, finish: {
            shown = true
            found = true
        }, reset: {
            shown = false
            found = false
            scanning = false
            scan = 0
        }, run: run)
    }

    private func card(w: CGFloat, h: CGFloat) -> some View {
        let cup = Self.cup
        return ZStack(alignment: .topLeading) {
            Group {
                if let img = OnboardingImage.load("first_catch_cafe") {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Theme.secondary
                }
            }
            .frame(width: w, height: h)
            .clipped()
            LinearGradient(colors: [.clear, Theme.cyan.opacity(0.5), .white.opacity(0.9), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: w, height: h * 0.2)
                .offset(y: scan * h * 1.2 - h * 0.2)
                .opacity(scanning ? 1 : 0)
                .blendMode(.plusLighter)
            ViewfinderCorners()
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: cup.width * w + 14, height: cup.height * h + 14)
                .shadow(color: .black.opacity(0.25), radius: 4)
                .scaleEffect(found ? 1 : 1.3)
                .opacity(found ? 1 : 0)
                .position(x: cup.midX * w, y: cup.midY * h)
        }
        .frame(width: w, height: h)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .padding(6)
        .background(.white, in: .rect(cornerRadius: 28, style: .continuous))
        .shadow(color: Color(hex: 0x1C4A80).opacity(0.18), radius: 22, y: 12)
        .overlay(alignment: .topLeading) {
            tag
                .scaleEffect(found ? 1 : 0.3, anchor: .bottom)
                .opacity(found ? 1 : 0)
                .position(x: 6 + cup.midX * w, y: 6 + cup.minY * h - 34)
        }
        .rotationEffect(.degrees(shown ? -2 : -7))
        .scaleEffect(shown ? 1 : 0.88)
        .blur(radius: shown ? 0 : 14)
        .opacity(shown ? 1 : 0)
    }

    /// The word's tag, as the app's tags: reading over the word, a speaker beside it, a point under it.
    private var tag: some View {
        Button {
            said += 1
            SoundService.shared.speak(Self.word)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    VStack(spacing: 0) {
                        Text(verbatim: zhuyin ? "ㄎㄚ ㄈㄟ" : "kāfēi")  // l10n-ignore (reading)
                            .scaledFont(size: 11, weight: .medium)
                            .foregroundStyle(Theme.muted)
                        Text(verbatim: Self.word)
                            .scaledFont(size: 22, weight: .bold)
                            .foregroundStyle(Theme.foreground)
                    }
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.primary, in: Circle())
                        .symbolEffect(.bounce, value: said)
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .padding(.vertical, 7)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                TagPoint()
                    .fill(.white)
                    .frame(width: 14, height: 8)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(L("発音を聞く"))
    }

    private func run() async {
        withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { shown = true }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        scan = 0
        scanning = true
        withAnimation(.easeInOut(duration: 0.95)) { scan = 1 }
        try? await Task.sleep(for: .milliseconds(850))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) { scanning = false }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { found = true }
        Haptics.impact(.light, intensity: 0.7)
    }
}

/// Four corner brackets, as a camera frames what it found.
private struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let l = min(rect.width, rect.height) * 0.28
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}

/// The small point under a tag.
private struct TagPoint: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Page 2: a 図鑑 page filling up — six caught words drop into their squares one after another, the newest marked NEW.
private struct IntroDexScene: View {
    let active: Bool

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var filled = 0

    private static let items: [(image: String, word: String)] = [
        ("first_catch_cat", "貓"), ("first_catch_flower", "花"), ("first_catch_ready", "海"),  // l10n-ignore (target words)
        ("first_catch_interest_music", "吉他"), ("first_catch_interest_sports", "球鞋"), ("first_catch_cafe", "咖啡"),  // l10n-ignore (target words)
    ]
    private static let tilts: [Double] = [-10, 8, -6, 9, -8, 6]

    var body: some View {
        GeometryReader { geo in
            let cardW = min(geo.size.width, 330, geo.size.height * 1.05)
            let pad: CGFloat = 14
            let gap: CGFloat = 10
            let tile = (cardW - pad * 2 - gap * 2) / 3
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed.fill").font(.system(size: 13, weight: .bold))
                    Text(L("図鑑")).scaledFont(size: 14, weight: .bold)
                    Spacer()
                    Text(verbatim: "\(filled)")
                        .scaledFont(size: 14, weight: .bold, monospacedDigit: true)
                        .contentTransition(.numericText())
                        .foregroundStyle(Theme.primaryInk)
                }
                .foregroundStyle(Theme.foreground)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile), spacing: gap), count: 3), spacing: gap) {
                    ForEach(0..<Self.items.count, id: \.self) { i in
                        cell(i, size: tile)
                    }
                }
            }
            .padding(pad)
            .frame(width: cardW)
            .background(Theme.card, in: .rect(cornerRadius: 26, style: .continuous))
            .shadow(color: Color(hex: 0x1C4A80).opacity(0.16), radius: 24, y: 12)
            .rotation3DEffect(.degrees(shown ? 0 : 22), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .scaleEffect(shown ? 1 : 0.9)
            .opacity(shown ? 1 : 0)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .introTimeline(active: active, reduceMotion: reduceMotion, finish: {
            shown = true
            filled = Self.items.count
        }, reset: {
            shown = false
            filled = 0
        }, run: run)
    }

    private func cell(_ i: Int, size: CGFloat) -> some View {
        let item = Self.items[i]
        let isIn = i < filled
        return VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.secondary)
                if let img = OnboardingImage.load(item.image) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        .scaleEffect(isIn ? 1 : 0.4)
                        .rotationEffect(.degrees(isIn ? 0 : Self.tilts[i]))
                        .opacity(isIn ? 1 : 0)
                }
            }
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                if i == Self.items.count - 1 && isIn {
                    Text(verbatim: "NEW")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.primary, in: Capsule())
                        .offset(x: 6, y: -6)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            Text(verbatim: item.word)
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
                .opacity(isIn ? 1 : 0.25)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.66), value: isIn)
    }

    private func run() async {
        withAnimation(.spring(response: 0.8, dampingFraction: 0.82)) { shown = true }
        try? await Task.sleep(for: .milliseconds(380))
        for _ in Self.items {
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.66)) { filled += 1 }
            Haptics.impact(.soft, intensity: 0.45)
            try? await Task.sleep(for: .milliseconds(140))
        }
    }
}

/// Page 3: the learner's own photo and four words; a finger picks the right one and it turns green.
private struct IntroQuizScene: View {
    let active: Bool

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var handIn = false
    @State private var pressed = false
    @State private var answered = false

    private static let choices = ["狗", "貓", "鳥", "魚"]  // l10n-ignore (target words)
    private static let correct = 1

    var body: some View {
        GeometryReader { geo in
            let cardW = min(geo.size.width * 0.86, 300, geo.size.height * 0.78)
            VStack(spacing: 12) {
                Group {
                    if let img = OnboardingImage.load("first_catch_cat") {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        Theme.secondary
                    }
                }
                .frame(width: cardW - 24, height: (cardW - 24) * 0.78)
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(0..<Self.choices.count, id: \.self) { i in choice(i) }
                }
            }
            .padding(12)
            .frame(width: cardW)
            .background(Theme.card, in: .rect(cornerRadius: 28, style: .continuous))
            .shadow(color: Color(hex: 0x1C4A80).opacity(0.16), radius: 24, y: 12)
            .rotationEffect(.degrees(shown ? 2 : 7))
            .scaleEffect(shown ? 1 : 0.88)
            .blur(radius: shown ? 0 : 12)
            .opacity(shown ? 1 : 0)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .introTimeline(active: active, reduceMotion: reduceMotion, finish: {
            shown = true
            answered = true
        }, reset: {
            shown = false
            handIn = false
            pressed = false
            answered = false
        }, run: run)
    }

    private func choice(_ i: Int) -> some View {
        let right = answered && i == Self.correct
        return HStack(spacing: 6) {
            Text(verbatim: Self.choices[i])
                .scaledFont(size: 20, weight: .bold)
            if right {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .foregroundStyle(right ? .white : Theme.foreground)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(right ? AnyShapeStyle(Theme.ok) : AnyShapeStyle(Theme.card), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(right ? .clear : Theme.border, lineWidth: 1.5))
        .opacity(answered && !right ? 0.45 : 1)
        .scaleEffect(i == Self.correct && pressed ? 0.94 : 1)
        .overlay(alignment: .bottomTrailing) {
            if i == Self.correct {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, Theme.foreground)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .scaleEffect(pressed ? 0.86 : 1)
                    .offset(x: handIn ? -14 : 40, y: handIn ? 26 : 90)
                    .opacity(handIn && !answered ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: answered)
        .zIndex(i == Self.correct ? 1 : 0)
    }

    private func run() async {
        withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { shown = true }
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { handIn = true }
        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.12)) { pressed = true }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pressed = false }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { answered = true }
        Haptics.correct()
    }
}
