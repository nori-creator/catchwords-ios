import SwiftUI

/// First-run setup (FirstCatchQuestions / FirstCatchNotifications / FirstCatchReady).
/// 4 questions (display, goals, TOCFL level, time) → notifications → ready; then the guide over the real screens
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
    /// Whether each was answered (an answer of 「わからない」 is nil too): the row says 「選択してください」 until then.
    @State private var answeredNow: Bool = false
    @State private var answeredGoal: Bool = false
    /// The level wheel open over the question (like 設定's `WheelCard`), nil when none.
    @State private var levelWheel: LevelWheelField?
    @State private var reminderMode: String = "ai"
    @State private var isSaving: Bool = false
    /// The profile could not be saved on 「チュートリアルを始める」: shown on the ready screen, which stays so it can be retried.
    @State private var saveError: String?
    @State private var showMenu: Bool = false
    @AppStorage("reading.pref") private var readingPref: String = "zhuyin"
    @AppStorage("reading.ja") private var readingJa: String = "kana"
    @AppStorage("sound.level") private var soundLevel: String = "subtle"
    @AppStorage("haptics.enabled") private var hapticsOn: Bool = true

    /// `start`/`step`: where it opens (the simulator check's pictures of the later screens, `UIPreview`).
    init(start: Stage = .questions, step: Int = OnboardingView.questionSteps[0], levelWheel: LevelWheelField? = nil,
         onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _stage = State(initialValue: start)
        _step = State(initialValue: step)
        _levelWheel = State(initialValue: levelWheel)
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
    /// Owner 2026-10-28: display language, goals, TOCFL level, then the daily time.
    static var questionSteps: [Int] { showsTargetStep ? [0, 1, 3, 4, 2] : [0, 3, 4, 2] }
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
            // iPhone Duo held sideways: the questions in a column in the middle (`readableColumn`).
            .readableColumn()
            .id("\(stage.rawValue)-\(step)")
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: stage)
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: step)
        .overlay {
            if let field = levelWheel {
                // Fades itself in and out and leaves the tree only once invisible, like 設定's card.
                LevelSheet(field: field, value: field == .now ? levelNow : levelGoal,
                           lowest: field == .goal ? (levelNow ?? 1) : 1) { picked in
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) { levelWheel = nil }
                    guard let picked else { return }   // closed with ×: nothing changes
                    if field == .now {
                        levelNow = picked.level
                        answeredNow = true
                        // The goal is never below the level now.
                        if let n = picked.level, let goal = levelGoal, goal < n { levelGoal = n }
                    } else {
                        levelGoal = picked.level
                        answeredGoal = true
                    }
                }
                .transition(.identity)
                .zIndex(3)
            }
        }
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
         L("TOCFLのレベルを\n教えてください")][step]
    }

    private var questionHint: String {
        [L("メニューや説明に使う言語です。"), L("街で出会ったことばを、この言語で学びます。"), L("あなたのペースで。あとから変更できます。"),
         L("いくつでも選べます。例文の場面をあなたに合わせます。"),
         L("いまのレベルと目標に、例文やチャンクの難しさを合わせます。あとから設定で変更できます。")][step]
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
                // Why it is asked, in the learner's terms (the reference picture's blue strip).
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.7), in: .rect(cornerRadius: 12, style: .continuous))
                    Text(L("あなたに合った難しさで出すので、ムダなく覚えられます。"))
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Theme.primaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent, in: .rect(cornerRadius: 18, style: .continuous))
                .staggerIn(shown, delay: 0.1)
                levelRow(.now, value: levelNow, answered: answeredNow, shown: shown, delay: 0.18)
                levelRow(.goal, value: levelGoal, answered: answeredGoal, shown: shown, delay: 0.28)
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

    /// One level answer: a row that opens the sheet of levels (owner 2026-10-29, the reference picture: a row with
    /// 「選択してください」 and a helper line, the levels with a line each on a sheet, 「決定する」).
    private func levelRow(_ field: LevelWheelField, value: Int?, answered: Bool, shown: Bool, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(field.title)
                .scaledFont(size: 15, weight: .bold)
                .foregroundStyle(Theme.foreground)
            Button {
                Haptics.selection()
                levelWheel = field
            } label: {
                HStack(spacing: 10) {
                    if answered, let value { LevelBadge(level: value) }
                    Text(answered ? LevelWheelField.label(value) : L("選択してください"))
                        .scaledFont(size: 18, weight: answered ? .semibold : .regular)
                        .foregroundStyle(answered ? Theme.foreground : Theme.muted)
                    Spacer()
                    Image(systemName: "chevron.down").scaledFont(size: 14, weight: .semibold).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 20).frame(minHeight: 56)
                .background(LinearGradient(colors: [Theme.card, Color(light: 0xEEF5FF, dark: 0x132032)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: .rect(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.primary.opacity(0.2), lineWidth: 1))
                .shadow(color: Theme.primary.opacity(0.06), radius: 6, y: 3)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .accessibilityIdentifier(field == .now ? "onboarding.levelNow" : "onboarding.levelGoal")
            Text(field.hint)
                .scaledFont(size: 13)
                .foregroundStyle(Theme.muted)
        }
        .staggerIn(shown, delay: delay)
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
    /// The last screen before the guide, in the shape of the owner's reference picture (2026-10-28): the icon and name,
    /// 「はじめに」, the sample 珍珠奶茶 cut-out with its real album tag, what the app is in one line, and the way in. 「あとで
    /// 始める」 finishes without the guide.
    private var ready: some View {
        VStack(spacing: 0) {
            progressHeader(index: Self.totalSteps) { go(.notifications, step: 0, back: true) }
            Spacer(minLength: 4)
            Appearing { shown in
                // The icon and the name small at the top; the picture is the screen (owner 2026-10-29: 「もっと画像を
                // 大きく中心にして」, the blue strokes gone).
                HStack(spacing: 10) {
                    LogoMark(size: 40)
                        .scaleEffect(shown ? 1 : 0.6)
                        .opacity(shown ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.62).delay(0.1), value: shown)
                    Text(verbatim: "CatchWords")  // l10n-ignore (the app's name)
                        .scaledFont(size: 20, weight: .heavy)
                        .foregroundStyle(Theme.foreground)
                        .staggerIn(shown, delay: 0.25, distance: 6)
                }
            }
            RevealHeadline(marked: L("撮るだけで、\n単語が覚えられる"), size: 28, delay: 0.35)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 14)
            Appearing { shown in
                Text(L("物を撮ると、台湾華語の名前と発音が出ます。\nまずは1枚、撮ってみよう。"))
                    .scaledFont(size: 15).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggerIn(shown, delay: 0.7, distance: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            OnboardingHero()
                .frame(maxWidth: .infinity)
                .frame(minHeight: 260, maxHeight: 340)
                .padding(.top, 10)
            Spacer(minLength: 8)
            if let saveError {
                Text(saveError).font(.footnote).foregroundStyle(Theme.destructive)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.bottom, 10)
            }
            PrimaryButton(title: L("チュートリアルを始める"), icon: "arrow.right", isLoading: isSaving, sheen: true) {
                Task { await finish() }
            }
            .padding(.horizontal, 24)
            Button {
                Task { await finish(startTour: false) }
            } label: {
                Text(L("あとで始める"))
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Theme.primaryInk)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
            }
            .disabled(isSaving)
            .accessibilityIdentifier("onboarding.later")
            .padding(.horizontal, 24).padding(.bottom, 12)
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

    /// `startTour`: false for 「あとで始める」 — onboarding is done, the guide is not started (the sample word is added
    /// either way).
    private func finish(startTour: Bool = true) async {
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
        // 「チュートリアルを始める」 can be tried again, instead of finishing with the chosen languages lost.
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
        // The sample 珍珠奶茶 is this account's from now (put in the dex by RootView once this screen is gone).
        SampleSticker.markAdded(userId: SupabaseClient.shared.userId)
        // 質問の後は、本物の画面で「撮る → 選ぶ → 図鑑 → 復習」を体験する（TourStep の tapCamera から）。
        if startTour { UserDefaults.standard.set(true, forKey: TourStep.pendingStorageKey(for: SupabaseClient.shared.userId)) }
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

/// The two TOCFL answers of the onboarding (the level now and the goal).
enum LevelWheelField: Identifiable {
    case now, goal
    var id: Self { self }

    var title: String {
        switch self {
        case .now: L("いまのレベル")
        case .goal: L("目標のレベル")
        }
    }

    /// Under the row: what to pick.
    var hint: String {
        switch self {
        case .now: L("今の実力に近いレベルを選んでください。")
        case .goal: L("目指したいレベルを選んでください。")
        }
    }

    /// 「わからない」 for none, else the shared notation 「TOCFL Level n」 (never translated, CLAUDE.md).
    static func label(_ level: Int?) -> String {
        level.map { "TOCFL Level \($0)" } ?? L("わからない")  // l10n-ignore (TOCFL Level n is shared)
    }
}

/// What the onboarding's level sheet hands back: a level, or 「わからない」 (nil level).
struct LevelPick {
    let level: Int?
}

/// The TOCFL levels as the sheet shows them (owner 2026-10-29: 「それぞれのレベルはどんな状態か TOCFL の公式から調べて」): the
/// test's three bands and six levels (國家華語測驗推動工作委員會), each level's CEFR equivalent and one line of what a
/// learner there can do, after the test's guidelines (Level 1, 2 and 6 from the guidelines' own descriptions; 3–5
/// from their CEFR level). 「TOCFL Level n」, 「Lv.n」 and the CEFR names are shared notation (CLAUDE.md, R25).
enum TOCFLLevel {
    static let cefr = ["A1", "A2", "B1", "B2", "C1", "C2"]

    static func describe(_ level: Int) -> String {
        switch level {
        case 1: L("数字や基本の単語、短く簡単な文がわかる")
        case 2: L("日常や仕事でよく使う語の、短い文章が読める")
        case 3: L("身近な話題なら、文脈から内容がつかめる")
        case 4: L("幅広い話題で、要点をつかんで話せる")
        case 5: L("専門的な内容も、流ちょうにやりとりできる")
        default: L("専門用語の混じった講演や放送も聞き取れる")
        }
    }

    /// One colour a level, warming up the ladder (the reference picture).
    static func tint(_ level: Int) -> (ink: Color, fill: Color) {
        switch level {
        case 1: (Color(hex: 0x1A6FE0), Color(hex: 0xE4EFFF))
        case 2: (Color(hex: 0x0E9A8A), Color(hex: 0xDDF6F1))
        case 3: (Color(hex: 0xB58A00), Color(hex: 0xFFF4D1))
        case 4: (Color(hex: 0xD96A14), Color(hex: 0xFFEADB))
        case 5: (Color(hex: 0xD93A6E), Color(hex: 0xFFE2EB))
        default: (Color(hex: 0x7A4DD6), Color(hex: 0xEDE5FF))
        }
    }
}

/// 「Lv.n」 in the level's colour (「?」 for 「わからない」).
struct LevelBadge: View {
    let level: Int?

    var body: some View {
        let tint = level.map(TOCFLLevel.tint) ?? (ink: Theme.muted, fill: Theme.secondary)
        Text(verbatim: level.map { "Lv.\($0)" } ?? "?")  // l10n-ignore (shared notation)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(tint.ink)
            .frame(width: 64, height: 44)
            .background(tint.fill, in: .rect(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The sheet of levels for one onboarding answer (owner 2026-10-29, the reference picture): the page dims, a white
/// sheet rises from the bottom with the title, ×, one line of help, 「わからない」 and the levels as rows (badge, name,
/// what you can do there, a check), and 「決定する」. A goal below the level now is not offered. Closing with × keeps
/// the answer as it was (nil is handed back); 「決定する」 hands back the pick.
private struct LevelSheet: View {
    let field: LevelWheelField
    let value: Int?
    let lowest: Int
    let onClose: (LevelPick?) -> Void
    @Environment(\.appReduceMotion) private var reduceMotion
    /// nil: 「わからない」.
    @State private var selection: Int?
    @State private var appeared: Bool = false
    @State private var closing: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { close(nil) }
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(Theme.border).frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity).padding(.top, 10)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.title).scaledFont(size: 22, weight: .heavy).foregroundStyle(Theme.foreground)
                        Text(field.hint).scaledFont(size: 14).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button { close(nil) } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.foreground)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L("閉じる"))
                    .accessibilityIdentifier("onboarding.levelClose")
                }
                .padding(.horizontal, 20).padding(.top, 10)
                ScrollView {
                    VStack(spacing: 10) {
                        row(level: nil)
                        ForEach(lowest...6, id: \.self) { row(level: $0) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                }
                .scrollBounceBehavior(.basedOnSize)
                Button {
                    Haptics.impact(.light)
                    close(LevelPick(level: selection))
                } label: {
                    Text(L("決定する")).scaledFont(size: 17, weight: .bold).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.brandGradient, in: Capsule())
                        .shadow(color: Theme.primary.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 14)
                .accessibilityIdentifier("wheel.close")
            }
            .frame(maxHeight: 560)
            .background(Theme.card, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 30, y: -6)
            .offset(y: appeared ? 0 : 500)
        }
        .ignoresSafeArea(edges: .bottom)
        .opacity(appeared ? 1 : 0)
        .allowsHitTesting(!closing)
        .onAppear {
            selection = value.map { max($0, lowest) }
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.86)) { appeared = true }
        }
    }

    private func row(level: Int?) -> some View {
        let on = selection == level
        return Button {
            guard selection != level else { return }
            OnboardingPick.choose(reduceMotion: reduceMotion) { selection = level }
        } label: {
            HStack(spacing: 14) {
                LevelBadge(level: level)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(LevelWheelField.label(level)).scaledFont(size: 16, weight: .bold).foregroundStyle(Theme.foreground)
                        if let level {
                            Text(verbatim: TOCFLLevel.cefr[level - 1])  // l10n-ignore (CEFR, shared)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.secondary, in: Capsule())
                        }
                    }
                    Text(level.map(TOCFLLevel.describe) ?? L("TOCFLを受けたことがない、よく知らない"))
                        .scaledFont(size: 13).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(on ? Theme.primary : Theme.border, lineWidth: 2).frame(width: 26, height: 26)
                    if on {
                        Circle().fill(Theme.primary).frame(width: 26, height: 26)
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Theme.accent : Color.white, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(on ? Theme.primary : Theme.border, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(PressableStyle(scale: 0.985))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(level.map { "onboarding.level.\($0)" } ?? "onboarding.level.unknown")
    }

    private func close(_ pick: LevelPick?) {
        guard !closing else { return }
        closing = true
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) { appeared = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            onClose(pick)
        }
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
/// The sample 珍珠奶茶's cut-out on a soft blue blob, its album tag (`WordTag`) tilted beside it, and the blue camera disc
/// of the tab bar at its corner: what the app does, in one picture (owner 2026-10-28, picture 1; 2026-10-29: bigger,
/// no blue strokes).
struct OnboardingHero: View {
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Ellipse()
                    .fill(Theme.accent)
                    .frame(width: min(w * 0.72, 290), height: h * 0.78)
                    .rotationEffect(.degrees(-8))
                    .scaleEffect(shown ? 1 : 0.7)
                    .opacity(shown ? 1 : 0)
                if let img = SampleSticker.image() {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: h * 0.98)
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                        .rotationEffect(.degrees(shown ? 0 : -12))
                        .scaleEffect(shown ? 1 : 0.6)
                        .opacity(shown ? 1 : 0)
                        .accessibilityLabel(SampleSticker.headword)
                    WordTag(text: SampleSticker.headword, zhuyin: SampleSticker.zhuyin, pinyin: SampleSticker.pinyin, tilt: -8, size: 21)
                        .position(x: w / 2 - min(w, 330) * 0.28, y: h * 0.82)
                        .scaleEffect(shown ? 1 : 0.5)
                        .opacity(shown ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6).delay(0.45), value: shown)
                } else {
                    LogoMark(size: 96)
                }
                ZStack {
                    Circle().fill(Theme.brandGradient)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
                .shadow(color: Theme.primary.opacity(0.4), radius: 10, y: 4)
                .position(x: w / 2 + min(w, 330) * 0.34, y: h * 0.8)
                .scaleEffect(shown ? 1 : 0.3)
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55).delay(0.65), value: shown)
            }
            .frame(width: w, height: h)
        }
        .onAppear {
            if reduceMotion { shown = true } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.62).delay(0.2)) { shown = true }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

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
