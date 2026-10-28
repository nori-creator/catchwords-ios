import SwiftUI

/// FirstCatchFlow の体験段（撮る → 選ぶ → 図鑑 → 単語の頁 → 復習 → ホーム → 完了）。
/// Web 版は見本の画面を別に組むが、iOS 版はログイン後に始まるので**本物の画面の上に**案内を重ねる。
/// 撮った1枚は本物の図鑑に入る（登録後の引き継ぎが要らない）。
///
/// 2026-10-27（オーナー: 「チュートリアルが操作が分かりにくく…どうやってチュートリアルを進めたらいいか分からない」）:
/// どの段も「何をタップすればいいか」を言い、札にはいつも段（`TourPhase`）のどこにいるかを出し、押す所には手の印を重ね、
/// 暗い所を押したら光る所を知らせる。2026-10-28（「実際のアプリの画面を使ってチュートリアルを作って」「ユーザーが最初に
/// 体験すべき機能をチュートリアルですべて案内して」）: 作り物の紹介の頁はやめ、本物の画面で、単語の頁（項目への移動・表示する
/// 項目）とホームのアルバムまで案内する。説明はその画面に本当にある物だけを言う。
enum TourStep: String, Equatable {
    case off
    case tapCamera, shoot, pick, detail, peel
    case added
    case wordJump, wordSections
    case reviewPick, reviewNext
    case homeAlbum
    case complete

    var anchor: TourAnchor? {
        switch self {
        case .tapCamera: .cameraTab
        case .shoot: .shutter
        case .pick: .pick
        case .detail: .headword
        case .peel: .peel
        case .wordJump: .wordJump
        case .wordSections: .wordSections
        case .reviewPick: .quiz
        case .reviewNext: .reviewNext
        case .homeAlbum: .album
        case .off, .added, .complete: nil
        }
    }

    /// Which of the steps the card counts this one as (the home's album, the last look, counts none).
    var phase: TourPhase? {
        switch self {
        case .tapCamera, .shoot: .shoot
        case .pick, .detail, .peel: .pick
        case .added: .collect
        case .wordJump, .wordSections: .word
        case .reviewPick, .reviewNext: .review
        case .off, .homeAlbum, .complete: nil
        }
    }

    var title: String? {
        switch self {
        case .tapCamera: L("まず1枚、撮ってみよう")
        case .shoot: L("気になる物を撮る")
        case .pick: L("覚えたいことばを選ぶ")
        case .detail: L("発音を聞く")
        case .peel: L("図鑑に入れる")
        case .added: L("図鑑に追加しました！")
        case .wordJump: L("単語の頁")
        case .wordSections: L("表示する項目と順番")
        case .reviewPick: L("写真で思い出す")
        case .reviewNext: L("復習")
        case .homeAlbum: L("ホーム")
        default: nil
        }
    }

    /// What the step does for the learner — the hassle it takes away, what other ways of learning do not give (owner
    /// 2026-10-28: 「どんなところが優れていて、どんなペインを解除し、ほかのアプリとは違うのか」). Only what this screen
    /// really does.
    var benefit: String? {
        switch self {
        case .tapCamera: L("単語帳に書き写す手間はいりません。見つけた物を撮るだけで学べます。")
        case .shoot: L("名前を知らない物でも大丈夫。辞書で調べる前に、まず撮るだけ。")
        case .pick: L("AIが写真の中の物を見つけて、台湾華語の名前を付けます。")
        case .detail: L("その場で台湾華語の発音を聞けます。")
        case .peel: L("撮った写真と、出会った場所も一緒に残ります。")
        case .added: L("集めたことばは分類ごとに図鑑へ。影は、まだ集めていない物です。")
        case .wordJump: L("意味だけでなく、よく使う組み合わせ（チャンク）、例文、量詞、台湾メモまで1つの頁に。")
        case .wordSections: L("見たい項目だけを、見やすい大きさで。")
        case .reviewPick: L("単語だけの暗記ではなく、自分の写真で思い出すから記憶に残ります。")
        case .reviewNext: L("覚え具合に合わせて、忘れかけた頃にまた出題されます。")
        case .homeAlbum: L("毎日の発見が、日付ごとのアルバムになります。")
        default: nil
        }
    }

    /// What to do now.
    var text: String {
        switch self {
        case .tapCamera: L("下の青いカメラボタンをタップしてください。")
        case .shoot: L("身のまわりの物にカメラを向けて、シャッターをタップ。撮ってある写真は左下の「写真」から使えます。")
        case .pick: L("残したいことばのタグをタップしてください。")
        case .detail: L("スピーカーをタップして発音を聞いたら「次へ」。")
        case .peel: L("「図鑑に追加」をタップしてください。")
        case .added: L("撮ったことばを開いてみましょう。")
        case .wordJump: L("上の項目をタップすると、その場所へ移ります。")
        case .wordSections: L("このボタンで、表示する項目と順番、文字の大きさ、発音の速さを変えられます。")
        case .reviewPick: L("写真に合うことばをタップ。")
        case .reviewNext: L("答えを確かめたら「次へ」。")
        case .homeAlbum: L("撮った写真は、ホームに並びます。")
        default: ""
        }
    }

    /// Spotlight の `interactive`: 光っている所だけ押せる。false なら札のボタンで進む。
    var isInteractive: Bool {
        switch self {
        case .added, .homeAlbum: false
        default: true
        }
    }

    var nextLabel: String? {
        switch self {
        case .detail, .wordJump: L("次へ")
        case .added: L("ことばを開く")
        case .wordSections: L("復習してみる")
        case .homeAlbum: L("完了")
        default: nil
        }
    }

    /// How dark the screen around the lit place is: the camera's picture must stay visible to aim (撮る), the photo
    /// its tags sit on too (選ぶ).
    var dimOpacity: Double {
        switch self {
        case .shoot: 0.25
        case .pick: 0.42
        default: 0.58
        }
    }

    var isReview: Bool { self == .reviewPick || self == .reviewNext }
    var isCapture: Bool { self == .shoot || self == .pick || self == .detail || self == .peel }
    /// The steps shown over the word's page (its sheet has a guide layer of its own).
    var isWord: Bool { self == .wordJump || self == .wordSections }

    /// The old device-wide flag "the first tour is still to run". Now only a hand-over: kept per account
    /// (`tour.pending.<userId>`, R6-05) like `OnboardingState`, so one account's unfinished tour never opens
    /// for the next account on the same iPhone.
    static let pendingKey = "tour.pending"

    /// This account's flag (a local guest without an account keeps the device-wide one).
    static func pendingStorageKey(for userId: String?) -> String {
        guard let userId else { return pendingKey }
        return pendingKey + "." + userId
    }

    /// At sign-in: the account takes over a device-wide flag left from before it was kept per account (it
    /// is only ever set right after that account's onboarding), and clears it so no other account sees it.
    static func adoptDevicePending(userId: String?) {
        guard let userId else { return }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: pendingKey) != nil else { return }
        if defaults.bool(forKey: pendingKey) { defaults.set(true, forKey: pendingStorageKey(for: userId)) }
        defaults.removeObject(forKey: pendingKey)
    }

    /// Account deletion: that account's unfinished tour.
    static func removePending(userId: String?) {
        guard let userId else { return }
        UserDefaults.standard.removeObject(forKey: pendingStorageKey(for: userId))
    }
}

/// The guide's four steps, the same on the onboarding's last screen (what is coming) and on every card (where you are).
enum TourPhase: Int, CaseIterable {
    case shoot, pick, collect, word, review

    var label: String {
        switch self {
        case .shoot: L("撮る")
        case .pick: L("選ぶ")
        case .collect: L("図鑑")
        case .word: L("単語")
        case .review: L("復習")
        }
    }

    /// The tab bar's own icons where there is one (図鑑 book, 復習 sparkles), so the steps read like the app.
    var icon: String {
        switch self {
        case .shoot: "camera.fill"
        case .pick: "hand.tap.fill"
        case .collect: "book"
        case .word: "text.book.closed"
        case .review: "sparkles"
        }
    }
}

/// ① 撮る — ② 選ぶ — ③ 図鑑 — ④ 単語 — ⑤ 復習: the steps done ticked, the current one blue. With `current` nil (the
/// onboarding's preview) all are shown alike, coming in one after another once `shown`.
struct TourPhaseRow: View {
    let current: TourPhase?
    var shown: Bool = true
    var baseDelay: Double = 0
    var compact: Bool = false
    /// The items come in one after another once `shown` (the onboarding's preview); the guide's card instead fills the
    /// line up to the current step and pops its circle when it comes in.
    var stagger: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(TourPhase.allCases, id: \.self) { p in
                item(p)
                    .staggerIn(shown || !stagger, delay: baseDelay + Double(p.rawValue) * 0.08, distance: 8)
                if p != .review {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.border)
                        Capsule().fill(Theme.primary)
                            .scaleEffect(x: filled(p) ? 1 : 0, anchor: .leading)
                            .animation(.easeInOut(duration: 0.45).delay(0.1), value: shown)
                    }
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
                    .padding(.top, circle / 2 - 1)
                    .padding(.horizontal, 2)
                    .staggerIn(shown || !stagger, delay: baseDelay + Double(p.rawValue) * 0.08 + 0.04, distance: 0)
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TourPhase.allCases.map(\.label).joined(separator: ", "))
        .accessibilityValue(current.map { "\($0.rawValue + 1) / \(TourPhase.allCases.count)" } ?? "")
    }

    private var circle: CGFloat { compact ? 24 : 34 }

    private func done(_ p: TourPhase) -> Bool {
        guard let current else { return false }
        return p.rawValue < current.rawValue
    }

    /// The line after `p` is blue when the step after it is done or current; on the guide's card the last of them
    /// (the one reaching the current step) fills as the card comes in.
    private func filled(_ p: TourPhase) -> Bool {
        guard let current, p.rawValue < current.rawValue else { return false }
        return stagger || p.rawValue + 1 < current.rawValue || shown
    }

    private func item(_ p: TourPhase) -> some View {
        let isCurrent = p == current
        let isDone = done(p)
        let lit = isCurrent || isDone || current == nil
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isCurrent ? AnyShapeStyle(Theme.brandGradient)
                          : isDone ? AnyShapeStyle(Theme.primary)
                          : current == nil ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.secondary))
                Image(systemName: isDone ? "checkmark" : p.icon)
                    .font(.system(size: circle * 0.42, weight: .bold))
                    .foregroundStyle(isCurrent || isDone ? Color.white : lit ? Theme.primary : Theme.muted)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: circle, height: circle)
            .shadow(color: isCurrent ? Theme.primary.opacity(0.4) : .clear, radius: 6, y: 2)
            .scaleEffect(isCurrent ? (shown || stagger ? 1.08 : 0.7) : 1)
            .animation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.35), value: shown)
            Text(p.label)
                .scaledFont(size: compact ? 10 : 12, weight: isCurrent ? .bold : .semibold)
                .foregroundStyle(isCurrent ? Theme.primaryInk : lit ? Theme.foreground : Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: compact ? 50 : 60)
    }
}

enum TourAnchor: Hashable {
    case cameraTab, shutter, pick, headword, peel, wordJump, wordSections, quiz, reviewNext, album
}

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourAnchor: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourAnchor: Anchor<CGRect>], nextValue: () -> [TourAnchor: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// 案内の光を当てる所（Web の `data-tour`）。
    func tourAnchor(_ id: TourAnchor, if active: Bool = true) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { active ? [id: $0] : [:] }
    }
}

/// The dimmed screen with the lit place cut out. Animatable: the light glides from one place to the next.
private struct SpotlightDim: Shape {
    var hole: CGRect
    var radius: CGFloat

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(hole.animatableData, radius) }
        set {
            hole.animatableData = newValue.first
            radius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        return p
    }
}

/// Spotlight.tsx: 画面を暗くし、押す所だけ穴を開けて青く光らせる。説明の札は穴と反対側に出す。
/// 押す所が小さいときは手の印がそこをタップしてみせ、暗い所を押すと光る所が大きく光って札が揺れる。
struct TourLayer: View {
    let step: TourStep
    let anchors: [TourAnchor: Anchor<CGRect>]
    let onNext: () -> Void
    let onSkip: () -> Void
    /// Room kept under a card at the bottom: the tab bar's (84) over the tabs, little over the word's page (a sheet).
    var bottomClearance: CGFloat = 84

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false
    @State private var ripple: Bool = false
    /// Taps on the dark part during a step that wants a tap on the lit place.
    @State private var missed: Int = 0
    @State private var flash: Bool = false
    /// Each step's arrival (owner 2026-10-28: 「モーションデザインなどを用いて…クオリティ高く解説」): the light opens wide (1)
    /// and closes onto the place (0) like a camera focusing on it, one ring bursts out as it lands (`burst` 0 → 1), and
    /// the finger glides in after (`handIn`).
    @State private var iris: CGFloat = 0
    @State private var burst: CGFloat = 1
    @State private var handIn: Bool = true
    @State private var arrival: Int = 0

    var body: some View {
        let hasPlace = step.anchor.map { anchors[$0] != nil } ?? false
        // The safe area is read outside (the full-screen reader inside has none: the card sat under the clock, CI
        // 2026-10-27), the lit places in full-screen coordinates inside.
        GeometryReader { safe in
            let insets = safe.safeAreaInsets
            GeometryReader { geo in
                let full = CGRect(origin: .zero, size: geo.size)
                let hole: CGRect? = step.anchor.flatMap { anchors[$0] }.map { Self.holeRect(around: geo[$0], in: full) }
                let settled = hole.map(Self.radius(for:)) ?? 0
                // 押す所が画面に無い（表示を切り替えた等）ときは暗くせず、札だけ出して操作を妨げない。
                let shouldDim = hole != nil || !step.isInteractive
                let showsCard = shouldDim || step.nextLabel != nil
                // While it opens, the light is the place grown by up to the screen's size, rounder the wider it is.
                let open = iris * max(geo.size.width, geo.size.height)
                let lit = hole.map { $0.insetBy(dx: -open, dy: -open) } ?? CGRect(x: full.midX, y: full.midY, width: 0, height: 0)
                let radius = settled + (min(lit.width, lit.height) / 2 - settled) * iris
                let dim = SpotlightDim(hole: lit, radius: radius)
                ZStack {
                    if shouldDim {
                        dim
                            .fill(Color(hex: 0x0B1020, opacity: hole == nil ? 0.35 : step.dimOpacity), style: FillStyle(eoFill: true))
                            .contentShape(step.isInteractive && hole != nil ? dim.path(in: full) : Path(full), eoFill: true)
                            .onTapGesture { if step.isInteractive, hole != nil { missedTap() } }
                            .transition(.opacity)
                    }
                    if let hole {
                        ring(hole, radius: settled)
                            .opacity(Double(max(0, 1 - iris * 3)))
                        if step.isInteractive, hole.width < 200, hole.height < 200, !reduceMotion {
                            hand(on: hole, in: geo.size)
                        }
                    }
                    let cardOnTop = hole.map { $0.midY > geo.size.height * 0.5 } ?? false
                    if showsCard {
                        VStack {
                            if !cardOnTop { Spacer(minLength: 0) }
                            // A new card per step (its lines come in again, `shown`), the old one fading out.
                            TourCoachCard(step: step, missed: missed, onNext: onNext, onSkip: onSkip)
                                .id(step)
                                .padding(.horizontal, 16)
                                .padding(.top, cardOnTop ? insets.top + 12 : 0)
                                .padding(.bottom, cardOnTop ? 0 : max(insets.bottom, 12) + bottomClearance)
                            if cardOnTop { Spacer(minLength: 0) }
                        }
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.86), value: lit)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            arrive(hasPlace)
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { ripple = true }
        }
        .onChange(of: step) { _, _ in
            Haptics.selection()
            arrive(hasPlace)
        }
        // The place can come on screen after the step (the next screen still rising): the light lands when it does.
        .onChange(of: hasPlace) { _, now in if now { arrive(true) } }
    }

    /// A step comes in: the light opens and closes onto its place, a ring bursts as it lands, the finger glides in.
    private func arrive(_ hasPlace: Bool) {
        arrival += 1
        let token = arrival
        guard !reduceMotion, hasPlace else {
            iris = 0
            handIn = true
            return
        }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            iris = 1
            burst = 1
            handIn = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            guard token == arrival else { return }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.88)) { iris = 0 }
            try? await Task.sleep(for: .milliseconds(520))
            guard token == arrival else { return }
            withTransaction(still) { burst = 0 }
            withAnimation(.easeOut(duration: 0.8)) { burst = 1 }
            withAnimation(.spring(response: 0.65, dampingFraction: 0.78)) { handIn = true }
            Haptics.impact(.soft, intensity: 0.55)
        }
    }

    /// The lit place: the element with a margin; a round thing (the camera disc, the shutter, the speaker) a circle.
    /// A place as wide as the screen (the word page's jump bar, the home's album) stays inside it: its ring ran off
    /// both sides (CI 2026-10-28).
    static func holeRect(around r: CGRect, in screen: CGRect) -> CGRect {
        let padded = r.insetBy(dx: -8, dy: -8)
        guard abs(padded.width - padded.height) < 16 else {
            let inside = padded.intersection(screen.insetBy(dx: 6, dy: 6))
            return inside.isNull || inside.isEmpty ? padded : inside
        }
        let side = max(padded.width, padded.height)
        return CGRect(x: padded.midX - side / 2, y: padded.midY - side / 2, width: side, height: side)
    }

    static func radius(for hole: CGRect) -> CGFloat {
        hole.width == hole.height ? hole.width / 2 : min(22, hole.height / 2)
    }

    private func ring(_ hole: CGRect, radius: CGFloat) -> some View {
        // Growth in points, the same on every side: a wide place swelled by a share of its width went off screen.
        func grown(_ points: CGFloat) -> CGSize {
            CGSize(width: 1 + 2 * points / max(hole.width, 1), height: 1 + 2 * points / max(hole.height, 1))
        }
        let wide = hole.width > 200
        return ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Theme.primary, lineWidth: 3)
                .shadow(color: Theme.primary.opacity(pulse ? 0.9 : 0.4), radius: pulse ? 18 : 8)
                .scaleEffect(grown(flash ? 8 : pulse ? 2 : 0))
            // The landing: one wide ring bursting out of the place (a screen-wide place only a little: no room).
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Theme.primaryBright, lineWidth: 4)
                .scaleEffect(grown(burst * (wide ? 6 : 36)))
                .opacity(Double(1 - burst) * 0.9)
            // A ring spreading out from the place again and again: "here".
            if step.isInteractive && !reduceMotion {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.primaryBright, lineWidth: 2)
                    .scaleEffect(grown(ripple ? (wide ? 6 : 18) : 0))
                    .opacity(ripple ? 0 : 0.8)
            }
        }
        .frame(width: hole.width, height: hole.height)
        .position(x: hole.midX, y: hole.midY)
        .allowsHitTesting(false)
    }

    /// A finger tapping the place, at its lower right (kept on screen).
    private func hand(on hole: CGRect, in size: CGSize) -> some View {
        let x = min(hole.midX + hole.width * 0.28 + 10, size.width - 28)
        let y = min(hole.midY + hole.height * 0.28 + 16, size.height - 28)
        return Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 34))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            .scaleEffect(pulse ? 0.86 : 1, anchor: .topLeading)
            .offset(x: pulse ? -4 : 0, y: pulse ? -5 : 0)
            // Glides in from below right once the light has landed.
            .offset(x: handIn ? 0 : 46, y: handIn ? 0 : 84)
            .opacity(handIn ? 1 : 0)
            .position(x: x, y: y)
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    private func missedTap() {
        Haptics.impact(.rigid, intensity: 0.8)
        withAnimation(.linear(duration: 0.4)) { missed += 1 }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { flash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { flash = false }
        }
    }
}

/// A sideways shake (a tap that missed the lit place).
private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(amount * .pi * 4), y: 0))
    }
}

struct TourCoachCard: View {
    let step: TourStep
    var missed: Int = 0
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var hintPulse = false
    /// The card's lines come in one after another (the card is made anew for each step).
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let phase = step.phase {
                TourPhaseRow(current: phase, shown: shown, compact: true, stagger: false)
                    .padding(.bottom, 2)
            }
            if let title = step.title {
                Text(title).scaledFont(size: 19, weight: .heavy).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggerIn(shown, delay: 0.08, distance: 10)
            }
            if let benefit = step.benefit {
                Label {
                    Text(benefit)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.primary)
                        .symbolEffect(.bounce, value: shown)
                }
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Theme.primaryInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.primary.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
                .staggerIn(shown, delay: 0.18, distance: 10)
            }
            Text(step.text)
                .scaledFont(size: 15)
                .foregroundStyle(Theme.foreground.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .staggerIn(shown, delay: 0.28, distance: 10)
            HStack {
                Button(L("案内を終える"), action: onSkip)
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .frame(minHeight: 44)
                Spacer()
                if let next = step.nextLabel {
                    Button {
                        Haptics.impact(.light)
                        onNext()
                    } label: {
                        HStack(spacing: 6) {
                            Text(next)
                            Image(systemName: "arrow.right").scaledFont(size: 13, weight: .bold)
                        }
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Theme.brandGradient, in: Capsule())
                        .shadow(color: Theme.primary.opacity(0.4), radius: 10, y: 4)
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                    .accessibilityIdentifier("tour.next")
                } else if step.isInteractive {
                    // No button here: the step goes on when the lit place is tapped. Say so where the eye ends up.
                    Label(L("光っているところをタップ"), systemImage: "hand.tap.fill")
                        .scaledFont(size: 13, weight: .bold)
                        .foregroundStyle(Theme.primaryInk)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(Theme.primary.opacity(hintPulse ? 0.16 : 0.08), in: Capsule())
                        .scaleEffect(missed > 0 && hintPulse ? 1.04 : 1)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Theme.card, in: .rect(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .modifier(Shake(amount: CGFloat(missed)))
        .task { shown = true }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { hintPulse = true }
        }
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity).combined(with: .offset(y: 14)),
            removal: .opacity.combined(with: .scale(scale: 0.98))))
        .id(step)
    }
}

/// 「最初のキャッチ、完了！」— 撮った写真と紙吹雪、案内でやってみたこと。
struct TourCompleteView: View {
    let sticker: Sticker?
    let onDone: () -> Void

    @Environment(DexStore.self) private var dex
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var burst: Bool = false

    private static let confetti: [Color] = [Theme.primary, Color(hex: 0xF5B83D), Color(hex: 0xFF7A8A), Color(hex: 0x4FC3A1)]

    var body: some View {
        ZStack {
            OnboardingBackdrop()
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                ZStack {
                    ForEach(0..<18, id: \.self) { i in
                        let angle = Double(i) / 18 * 2 * .pi
                        let reach = 96 + Double(i % 3) * 16
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Self.confetti[i % Self.confetti.count])
                            .frame(width: 8, height: 14)
                            .rotationEffect(.degrees(Double(i) * 37 + (burst ? 200 : 0)))
                            .offset(x: burst ? cos(angle) * reach : 0, y: burst ? sin(angle) * reach : 0)
                            .opacity(burst ? 0.9 : 0)
                    }
                    Group {
                        if let path = sticker?.heroPath {
                            Color.white
                                .frame(width: 200, height: 200)
                                .overlay {
                                    StickerImage(path: path, url: dex.url(for: path, preferThumb: false), contentMode: .fit)
                                        .padding(10)
                                        .allowsHitTesting(false)
                                }
                                .clipShape(.rect(cornerRadius: 28, style: .continuous))
                        } else {
                            // No picture of the catch (not found): the app's mark, never an empty white card (CI 2026-10-28).
                            LogoMark(size: 150)
                        }
                    }
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                    .rotationEffect(.degrees(burst ? -3 : -12))
                    .scaleEffect(burst ? 1 : 0.6)
                }
                .frame(height: 270)
                if let head = sticker?.word?.headword {
                    Text(head)
                        .scaledFont(size: 30, weight: .bold)
                        .foregroundStyle(Theme.foreground)
                        .staggerIn(burst, delay: 0.25, distance: 10)
                }
                RevealHeadline(marked: L("最初のキャッチ、完了！"), size: 26, delay: 0.3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                VStack(alignment: .leading, spacing: 12) {
                    recap(L("撮って、ことばを見つけた"), icon: TourPhase.shoot.icon, delay: 0.85)
                    recap(L("図鑑に集めた"), icon: TourPhase.collect.icon, delay: 1.0)
                    recap(L("単語の頁で使い方を見た"), icon: TourPhase.word.icon, delay: 1.15)
                    recap(L("写真で思い出した"), icon: TourPhase.review.icon, delay: 1.3)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: .rect(cornerRadius: 22, style: .continuous))
                .shadow(color: Color(hex: 0x1C4A80).opacity(0.1), radius: 16, y: 6)
                .padding(.top, 18)
                Text(L("身のまわりから、ことばを増やしていこう。"))
                    .scaledFont(size: 14)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .staggerIn(burst, delay: 1.45, distance: 6)
                Spacer(minLength: 12)
                PrimaryButton(title: L("はじめる"), icon: "arrow.right", sheen: true, action: onDone)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            Haptics.success()
            SoundService.shared.play(.sting)
            if reduceMotion { burst = true } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { burst = true }
            }
        }
    }

    private func recap(_ text: String, icon: String, delay: Double) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.ok)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            .scaleEffect(burst ? 1 : 0.2)
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.55).delay(delay + 0.1), value: burst)
            Text(text)
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primary.opacity(0.6))
        }
        .staggerIn(burst, delay: delay, distance: 10)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
