import SwiftUI

/// FirstCatchFlow の体験段. iOS 版はログイン後に始まるので**本物の画面の上に**案内を重ねる。撮った1枚は本物の図鑑に入る。
///
/// 2026-10-27（オーナー: 「チュートリアルが操作が分かりにくく…どうやってチュートリアルを進めたらいいか分からない」）: 札には
/// いつも段（`TourPhase`）のどこにいるかを出し、押す所は光らせて手の印を重ね、暗い所を押したら光る所を知らせる。
/// 2026-10-28 の順番（オーナー）: 1枚撮る → 切り抜きがホームに貼られる → 図鑑の種類（カード・地図・ギャラリー）を実際に
/// 触る（影以外の物もキャッチできると短く）→ 図鑑の単語をタップ → 単語の頁の項目を1つずつ → 撮った語を復習 → その語の
/// 記憶の状態（忘却曲線）→ ホームで完了の祝福。札は押す所のすぐ隣に出し、文は短く: 見出し・要る時だけ1行・「次へ」・小さく
/// 「スキップ」。「〜をタップ」とは書かない（同日「そこだけ光らしたらユーザーもそこわかる」）。
enum TourStep: String, Equatable {
    case off
    case tapCamera, shoot, pick, detail, peel
    case homeAdded
    case dexTab, dexCover, dexMap, dexGrid, dexShadow, dexOpen
    case wordSection, wordSettings
    case reviewPick, reviewNext, memoryCurve
    case complete

    var anchor: TourAnchor? {
        switch self {
        case .tapCamera: .cameraTab
        case .shoot: .shutter
        case .pick: .pick
        case .detail: .headword
        case .peel: .peel
        case .homeAdded: .album
        case .dexTab: .dexTab
        case .dexMap: .dexMap
        case .dexGrid: .dexGrid
        case .dexOpen: .dexWord
        case .wordSection: .wordSection
        case .wordSettings: .wordSections
        case .reviewPick: .quiz
        case .reviewNext: .reviewNext
        case .memoryCurve: .memoryCurve
        case .off, .dexCover, .dexShadow, .complete: nil
        }
    }

    /// Which of the steps the card counts this one as.
    var phase: TourPhase? {
        switch self {
        case .tapCamera, .shoot, .pick, .detail, .peel: .shoot
        case .homeAdded: .home
        case .dexTab, .dexCover, .dexMap, .dexGrid, .dexShadow, .dexOpen: .dex
        case .wordSection, .wordSettings: .word
        case .reviewPick, .reviewNext, .memoryCurve: .review
        case .off, .complete: nil
        }
    }

    /// What to do, or what this is, in a few words. Owner 2026-10-28 (「チュートリアルのすべての文字文章が変だから一から
    /// 考え直して」「操作が明らかなところは…ここをタップって書かなくていい。そこだけ光らしたらユーザーもそこわかる」): the lit
    /// place shows where to tap, so no card says 「〜をタップ」.
    /// Rewritten 2026-10-29 (owner: 「全ての見出しや解説をプロのマーケター、心理学、セールス、行動経済学の研究から最適化して」).
    /// Each title is one action or one fact in the learner's own terms; the first one stays the owner's own words.
    var title: String? {
        switch self {
        case .tapCamera: L("目の前にある物を1枚撮ってみよう")
        case .shoot: L("撮りたい物を、画面の真ん中に")
        case .pick: L("覚えたいことばを1つ選ぼう")
        case .detail: L("聞いて、声に出してみよう")
        case .peel: L("あなたの単語帳に入れよう")
        case .homeAdded: L("今日のアルバムに貼られました")
        case .dexTab: L("集めたことばは、図鑑へ")
        case .dexCover: L("1語1枚のカードになります")
        case .dexMap: L("出会った場所も、残ります")
        case .dexGrid: L("分類ごとに、集まり具合が見えます")
        case .dexShadow: L("影は、まだ出会っていない物")
        case .dexOpen: L("あなたの1語目を開いてみよう")
        case .wordSection: L("単語の頁")
        case .wordSettings: L("見せ方は、あなた好みに")
        case .reviewPick: L("この写真のことばは、どれ？")
        case .reviewNext: L("答え合わせ")
        case .memoryCurve: L("このことばは、いつ忘れそう？")
        default: nil
        }
    }

    /// One line, only where it adds what the screen does not already show (the first step has none: owner
    /// 2026-10-28 「撮るだけで単語帳ができますって文字消して。いらない」). Each line names the gain or removes a worry.
    var benefit: String? {
        switch self {
        case .shoot: L("名前を知らなくて大丈夫。アプリが見つけます。")
        case .pick: L("写っている物に、台湾での呼び方が付きました。")
        case .detail: L("ネイティブの発音です。声に出すと、記憶に残ります。")
        case .peel: L("ここから、あなたのことばが増えていきます。")
        case .homeAdded: L("切り抜きが、日付ごとに残ります。あとで見返せます。")
        case .dexCover: L("左右にめくるだけで、思い出す練習になります。")
        case .dexMap: L("場所と一緒に覚えると、思い出しやすくなります。")
        case .dexGrid: L("飲み物、料理…。集めるほど、得意な分野が分かります。")
        case .dexShadow: L("影を埋めていこう。影にない物も、何でもキャッチできます。")
        case .wordSettings: L("見たい項目と順番、文字の大きさ、発音の速さをここで。")
        case .reviewPick: L("自分で撮った写真だから、思い出しやすい。")
        case .reviewNext: L("間違えても大丈夫。解説を読めば、次は思い出せます。")
        case .memoryCurve: L("忘れかける頃にお知らせ。復習は、必要な分だけ。")
        default: nil
        }
    }

    /// The word page's sections, one line each (the section's own name is the card's title): what the learner gets
    /// from it, not what it is called.
    static func sectionPoint(_ section: CardSection) -> String {
        switch section {
        case .meaning: L("まずはここだけ。意味を短く。")
        case .usageChunks: L("ネイティブがよく使う組み合わせ。この形のまま覚えると、すぐ使えます。")
        case .example: L("チャンクを使った例文。音声でそのまま聞けます。")
        case .measureWords: L("数えるときの言い方。注文のときに役立ちます。")
        case .relatedWords: L("一緒に覚えると、使える場面が広がります。")
        case .taiwanNote: L("台湾ならではの言い方や習慣。")
        case .realUsage: L("動画や検索で、本当に使われているか確かめられます。")
        default: L("このことばを深く知るための項目。")
        }
    }

    /// Spotlight の `interactive`: 光っている所だけ押せる。false なら札のボタンで進む。
    var isInteractive: Bool {
        switch self {
        case .homeAdded, .dexShadow, .wordSection, .wordSettings, .memoryCurve: false
        default: true
        }
    }

    var nextLabel: String? {
        switch self {
        case .detail, .homeAdded, .dexCover, .dexShadow, .wordSection: L("次へ")
        case .wordSettings: L("復習へ")
        case .memoryCurve: L("完了")
        default: nil
        }
    }

    /// How dark the screen around the lit place is: the camera's picture must stay visible to aim (撮る), the photo
    /// its tags sit on too (選ぶ), and the 図鑑's views while their buttons are lit.
    var dimOpacity: Double {
        switch self {
        case .shoot: 0.2
        case .pick: 0.3
        case .dexMap, .dexGrid: 0.25
        default: 0.35
        }
    }

    var isReview: Bool { self == .reviewPick || self == .reviewNext || self == .memoryCurve }
    var isCapture: Bool { self == .shoot || self == .pick || self == .detail || self == .peel }
    /// The steps shown over the word's page (its sheet has a guide layer of its own).
    var isWord: Bool { self == .wordSection || self == .wordSettings }

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

/// The guide's five steps, the same on the onboarding's last screen (what is coming) and on every card (where you are).
enum TourPhase: Int, CaseIterable {
    case shoot, home, dex, word, review

    var label: String {
        switch self {
        case .shoot: L("撮る")
        case .home: L("ホーム")
        case .dex: L("図鑑")
        case .word: L("単語")
        case .review: L("復習")
        }
    }

    /// The tab bar's own icons where there is one (ホーム house, 図鑑 book, 復習 sparkles), so the steps read like the app.
    var icon: String {
        switch self {
        case .shoot: "camera.fill"
        case .home: "house"
        case .dex: "book"
        case .word: "text.book.closed"
        case .review: "sparkles"
        }
    }
}

enum TourAnchor: Hashable {
    case cameraTab, shutter, pick, headword, peel, album
    case dexTab, dexMap, dexGrid, dexWord
    case wordJump, wordSection, wordSections
    case quiz, reviewNext, memoryCurve
}

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourAnchor: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourAnchor: Anchor<CGRect>], nextValue: () -> [TourAnchor: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// 案内の光を当てる所（Web の `data-tour`）。
    /// Added to what the view's content already marks (two marks on one view both count).
    func tourAnchor(_ id: TourAnchor, if active: Bool = true) -> some View {
        transformAnchorPreference(key: TourAnchorKey.self, value: .bounds) { marks, anchor in
            if active { marks[id] = anchor }
        }
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
    /// `.wordSection`: the word page's section the light is on (its card names it).
    var section: CardSection? = nil

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false
    @State private var ripple: Bool = false
    /// Taps on the dark part during a step that wants a tap on the lit place.
    @State private var missed: Int = 0
    @State private var flash: Bool = false
    /// Each step's arrival (owner 2026-10-28: 「モーションデザインなどを用いて…クオリティ高く解説」): the light opens wide (1)
    /// and closes onto the place (0) like a camera focusing on it, one ring bursts out as it lands (`burst` 0 → 1), and
    /// the blue strokes beside it draw themselves after (`strokes`).
    @State private var iris: CGFloat = 0
    @State private var burst: CGFloat = 1
    /// The blue strokes beside the lit place, drawn in (0 → 1) as the light lands.
    @State private var strokes: CGFloat = 1
    @State private var arrival: Int = 0
    /// The card's height, measured (it is placed beside the lit place).
    @State private var cardHeight: CGFloat = 170

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
                        if !reduceMotion { bursts(on: hole, in: geo.size) }
                    }
                    if showsCard {
                        // Right beside the lit place, pointing at it (owner 2026-10-28: 「次操作する場所の近くにその解説を
                        // 書いて」 — the camera's card sat at the top of the screen, its button at the bottom).
                        let place = Self.cardPlace(hole: hole, size: geo.size, insets: insets, height: cardHeight,
                                                   bottomClearance: bottomClearance)
                        if let hole, let down = place.pointsDown {
                            pointer(down: down, x: hole.midX, cardMidY: place.midY, in: geo.size)
                        }
                        // A new card per step (its lines come in again, `shown`), the old one fading out.
                        TourCoachCard(step: step, section: section, missed: missed, onNext: onNext, onSkip: onSkip)
                            .id("\(step.rawValue)-\(section?.rawValue ?? "")")
                            .padding(.horizontal, 16)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                            .frame(width: geo.size.width)
                            .position(x: geo.size.width / 2, y: place.midY)
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
        // The word page's next section: the light moves on like a new step.
        .onChange(of: section) { _, _ in
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
            strokes = 1
            return
        }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            iris = 1
            burst = 1
            strokes = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            guard token == arrival else { return }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.88)) { iris = 0 }
            try? await Task.sleep(for: .milliseconds(520))
            guard token == arrival else { return }
            withTransaction(still) { burst = 0 }
            withAnimation(.easeOut(duration: 0.8)) { burst = 1 }
            withAnimation(.easeOut(duration: 0.45)) { strokes = 1 }
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

    /// Where the card goes: just above a place in the lower half, just below one in the upper half (the other side
    /// when there is no room), and at the bottom (or top) edge over a place that fills the screen or when there is none.
    /// `pointsDown`: the card points at the place under it (true) or over it (false); nil, no pointer.
    static func cardPlace(hole: CGRect?, size: CGSize, insets: EdgeInsets, height h: CGFloat,
                          bottomClearance: CGFloat) -> (midY: CGFloat, pointsDown: Bool?) {
        let top = insets.top + 12
        let bottom = size.height - max(insets.bottom, 12) - bottomClearance
        let gap: CGFloat = 16
        guard let hole else { return (bottom - h / 2, nil) }
        let above = hole.minY - gap - h >= top
        // Below a place the card may reach over the tab bar (it is dimmed); at the edge it stays above it.
        let below = hole.maxY + gap + h <= size.height - max(insets.bottom, 12)
        let preferAbove = hole.midY > size.height * 0.5
        if (preferAbove && above) || (!preferAbove && !below && above) { return (hole.minY - gap - h / 2, true) }
        if below { return (hole.maxY + gap + h / 2, false) }
        let roomAbove = hole.minY - top
        let roomBelow = bottom - hole.maxY
        return roomAbove > roomBelow ? (top + h / 2, nil) : (bottom - h / 2, nil)
    }

    /// The card's little point toward the lit place (under the card, half showing).
    private func pointer(down: Bool, x: CGFloat, cardMidY: CGFloat, in size: CGSize) -> some View {
        let edge = cardMidY + (down ? cardHeight / 2 : -cardHeight / 2)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Theme.card)
            .frame(width: 20, height: 20)
            .rotationEffect(.degrees(45))
            .shadow(color: .black.opacity(0.18), radius: 6, y: down ? 4 : -2)
            .position(x: min(max(x, 44), size.width - 44), y: edge + (down ? -2 : 2))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
            // A soft white halo: the place looks lit, not only outlined (the reference pictures, 2026-10-28).
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 2)
                .shadow(color: .white.opacity(0.9), radius: 22)
                .scaleEffect(grown(4))
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

    /// The blue strokes at the place's upper corners (the welcome screen's mark), drawn in as the light lands; kept
    /// inside the screen.
    private func bursts(on hole: CGRect, in size: CGSize) -> some View {
        let side: CGFloat = 34
        let left = CGPoint(x: max(side / 2 + 4, hole.minX - 22), y: max(side / 2 + 4, hole.minY - 22))
        let right = CGPoint(x: min(size.width - side / 2 - 4, hole.maxX + 22), y: max(side / 2 + 4, hole.minY - 22))
        return ZStack {
            burstMark(side: side).position(left)
            burstMark(side: side).scaleEffect(x: -1).position(right)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func burstMark(side: CGFloat) -> some View {
        WelcomeBurst()
            .trim(from: 0, to: strokes)
            .stroke(Color(hex: 0x5AA4F8), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: side, height: side)
            .shadow(color: .white.opacity(0.8), radius: 2)
            .scaleEffect(pulse ? 1.06 : 1)
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
    var section: CardSection? = nil
    var missed: Int = 0
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.appReduceMotion) private var reduceMotion
    /// The card's lines come in one after another (the card is made anew for each step).
    @State private var shown = false

    private var title: String? {
        section.map { $0.shortTitle(for: NativeAPI.targetLanguage) } ?? step.title
    }

    private var point: String? {
        section.map(TourStep.sectionPoint) ?? step.benefit
    }

    /// Owner 2026-10-28 (「文字が多すぎて何したらいいかちょっと見にくい」): the steps on top, a title, at most one line, and
    /// 「次へ」 where the step goes on from the card; 「スキップ」 small and out of the way.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let phase = step.phase {
                // 「STEP n」 and 「n / 5」 are common notation, the same in every display language (like NEW and No.).
                HStack {
                    StepPill(text: "STEP \(phase.rawValue + 1)")  // l10n-ignore (common notation)
                    Spacer()
                    Text(verbatim: "\(phase.rawValue + 1) / \(TourPhase.allCases.count)")
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(Theme.muted)
                }
                .staggerIn(shown, delay: 0.02, distance: 6)
            }
            if let title {
                Text(title).scaledFont(size: 20, weight: .heavy).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggerIn(shown, delay: 0.08, distance: 10)
            }
            if let point {
                Text(point)
                    .scaledFont(size: 15)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggerIn(shown, delay: 0.18, distance: 10)
            }
            HStack(spacing: 10) {
                Button(L("スキップ"), action: onSkip)
                    .scaledFont(size: 15, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .accessibilityHint(L("案内を終える"))
                    .accessibilityIdentifier("tour.skip")
                Spacer(minLength: 0)
                if let next = step.nextLabel {
                    Button {
                        Haptics.impact(.light)
                        onNext()
                    } label: {
                        HStack(spacing: 6) {
                            Text(next)
                            Image(systemName: "arrow.right").scaledFont(size: 13, weight: .bold)
                        }
                        .scaledFont(size: 16, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 46)
                        .background(Theme.brandGradient, in: Capsule())
                        .shadow(color: Theme.primary.opacity(0.4), radius: 10, y: 4)
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                    .accessibilityIdentifier("tour.next")
                }
            }
            .staggerIn(shown, delay: 0.26, distance: 8)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Theme.card, in: .rect(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.primary.opacity(0.12), lineWidth: 1))
        // The small burst at the card's corner (the reference pictures).
        .overlay(alignment: .topTrailing) {
            WelcomeBurst()
                .trim(from: 0, to: shown ? 1 : 0)
                .stroke(Color(hex: 0x5AA4F8), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 26, height: 26)
                .scaleEffect(x: -1)
                .offset(x: 8, y: -12)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.3), value: shown)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .modifier(Shake(amount: CGFloat(missed)))
        .task { shown = true }
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity).combined(with: .offset(y: 14)),
            removal: .opacity.combined(with: .scale(scale: 0.98))))
    }
}

/// The end of the guide, over the home (frosted). Owner 2026-10-29: confetti over the whole screen, the catch's cut-out
/// itself, big and in the middle (no white card, no blue strokes), no list of what was done; a headline that sends
/// the learner off to collect, and 「はじめる」.
struct TourCompleteView: View {
    let sticker: Sticker?
    let onDone: () -> Void

    @Environment(DexStore.self) private var dex
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var burst: Bool = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Theme.background.opacity(burst ? 0.6 : 0).ignoresSafeArea()
            OnboardingBackdrop().opacity(0.6)
            ConfettiRain(running: burst)
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                RevealHeadline(marked: L("さあ、ことばを集めよう"), size: 28, delay: 0.25)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("撮るたびに、あなたの単語帳が育ちます。"))
                    .scaledFont(size: 15)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .staggerIn(burst, delay: 0.45, distance: 6)
                Spacer(minLength: 12)
                // The catch itself, its album tag across its foot.
                ZStack(alignment: .bottom) {
                    if let path = sticker?.heroPath {
                        StickerImage(path: path, url: dex.url(for: path, preferThumb: false), contentMode: .fit)
                            .frame(maxWidth: 280, maxHeight: 300)
                            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
                            .allowsHitTesting(false)
                    } else {
                        // No picture of the catch (not found): the app's mark, never an empty space.
                        LogoMark(size: 120)
                    }
                    if let w = sticker?.word {
                        WordTag(text: w.headword, zhuyin: w.readingZhuyin, pinyin: w.pinyin, tilt: -5, size: 22)
                            .offset(y: 14)
                            .staggerIn(burst, delay: 0.55, distance: 8)
                    }
                }
                .rotationEffect(.degrees(burst ? 0 : -10))
                .scaleEffect(burst ? 1 : 0.6)
                .opacity(burst ? 1 : 0)
                .padding(.bottom, 20)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(sticker?.word?.headword ?? "")
                Spacer(minLength: 16)
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
}

/// Paper falling over the whole screen (the complete screen's celebration): pieces of the app's colours drift down
/// from above the top edge, turning, each at its own pace. Still (scattered once) with reduced motion.
struct ConfettiRain: View {
    let running: Bool
    @Environment(\.appReduceMotion) private var reduceMotion
    /// When the paper started falling (the clock the pieces are timed from).
    @State private var start = Date()

    private struct Piece {
        let x: Double        // 0…1 of the width
        let delay: Double    // seconds before it enters
        let speed: Double    // points per second
        let sway: Double     // sideways drift amplitude, points
        let spin: Double     // turns per second
        let color: Color
        let size: CGSize
    }

    private static let colors: [Color] = [Theme.primary, Color(hex: 0xF5B83D), Color(hex: 0xFF7A8A), Color(hex: 0x4FC3A1), Color(hex: 0x8B7CF6)]

    private static let pieces: [Piece] = {
        var g = SystemRandomNumberGenerator()
        return (0..<42).map { i in
            Piece(x: Double(i % 14) / 13 + Double.random(in: -0.03...0.03, using: &g),
                  delay: Double.random(in: 0...1.6, using: &g),
                  speed: Double.random(in: 90...160, using: &g),
                  sway: Double.random(in: 8...26, using: &g),
                  spin: Double.random(in: 0.4...1.2, using: &g) * (Bool.random(using: &g) ? 1 : -1),
                  color: colors[i % colors.count],
                  size: CGSize(width: Double.random(in: 6...9, using: &g), height: Double.random(in: 10...15, using: &g)))
        }
    }()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            TimelineView(.animation(paused: !running || reduceMotion)) { ctx in
                let t = ctx.date.timeIntervalSince(start)
                Canvas { context, _ in
                    for p in Self.pieces {
                        let life = reduceMotion ? 1.0 : max(0, t - p.delay)
                        // Each piece falls through the screen again and again; still: scattered over the screen.
                        let y = reduceMotion ? p.x * 0.7 * h + p.delay * 120 : ((life * p.speed).truncatingRemainder(dividingBy: h + 60)) - 30
                        guard life > 0 || reduceMotion else { continue }
                        let x = p.x * w + sin(life * 1.7 + p.x * 10) * p.sway
                        let rect = CGRect(x: -p.size.width / 2, y: -p.size.height / 2, width: p.size.width, height: p.size.height)
                        var piece = context
                        piece.translateBy(x: x, y: y)
                        piece.rotate(by: .radians(life * p.spin * 2 * .pi + p.x * 6))
                        piece.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(p.color.opacity(0.9)))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
