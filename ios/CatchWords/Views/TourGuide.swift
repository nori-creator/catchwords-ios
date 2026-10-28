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
    var title: String? {
        switch self {
        case .tapCamera: L("目の前にある物を1枚撮ってみよう")
        case .shoot: L("撮りたい物を画面に入れよう")
        case .pick: L("覚えたいことばを選ぼう")
        case .detail: L("発音を聞いてみよう")
        case .peel: L("図鑑に入れよう")
        case .homeAdded: L("ホームに貼られました")
        case .dexTab: L("次は、図鑑を見てみよう")
        case .dexCover: L("集めたことばのカード")
        case .dexMap: L("地図でも見られます")
        case .dexGrid: L("分類ごとにも見られます")
        case .dexShadow: L("影は、まだ集めていない物")
        case .dexOpen: L("撮ったことばを開いてみよう")
        case .wordSection: L("単語の頁")
        case .wordSettings: L("項目は自由に並べ替えられます")
        case .reviewPick: L("写真に合うことばを選ぼう")
        case .reviewNext: L("答え合わせ")
        case .memoryCurve: L("このことばの記憶の状態")
        default: nil
        }
    }

    /// One line, only where it tells something the screen does not already show (the first step has none: owner
    /// 2026-10-28 「撮るだけで単語帳ができますって文字消して。いらない」).
    var benefit: String? {
        switch self {
        case .shoot: L("名前を知らない物でも大丈夫。")
        case .pick: L("写っている物に、台湾華語の名前が付きました。")
        case .detail: L("ネイティブの発音です。まねして言ってみましょう。")
        case .homeAdded: L("撮った物は切り抜かれ、日付ごとのアルバムに残ります。")
        case .dexCover: L("左右にめくって見返せます。")
        case .dexMap: L("どこで出会ったことばか、場所から思い出せます。")
        case .dexGrid: L("飲み物や料理など、分類ごとに集まり具合が分かります。")
        case .dexShadow: L("影にない物も、何でも撮って集められます。")
        case .wordSettings: L("表示する項目と順番、文字の大きさ、発音の速さをここで変えられます。")
        case .reviewPick: L("自分で撮った写真だから、思い出しやすい。")
        case .reviewNext: L("間違えても、解説を読めば覚え直せます。")
        case .memoryCurve: L("色で記憶の段階が分かります。忘れかける頃に、復習をお知らせします。")
        default: nil
        }
    }

    /// The word page's sections, one line each (the section's own name is the card's title).
    static func sectionPoint(_ section: CardSection) -> String {
        switch section {
        case .meaning: L("このことばの意味を、短く説明します。")
        case .usageChunks: L("ネイティブがよく一緒に使う組み合わせ。この形のまま覚えると、すぐ話せます。")
        case .example: L("チャンクを使った例文。音声でも聞けます。")
        case .measureWords: L("この物を数えるときのことば（量詞）。")
        case .relatedWords: L("一緒に覚えると便利なことば。")
        case .taiwanNote: L("台湾での言い方や習慣のメモ。")
        case .realUsage: L("動画や検索で、実際の使われ方を確かめられます。")
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
        case .shoot: 0.25
        case .pick: 0.42
        case .dexMap, .dexGrid: 0.32
        default: 0.58
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

/// ① 撮る — ② ホーム — ③ 図鑑 — ④ 単語 — ⑤ 復習: the steps done ticked, the current one blue. With `current` nil (the
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
    /// the finger glides in after (`handIn`).
    @State private var iris: CGFloat = 0
    @State private var burst: CGFloat = 1
    @State private var handIn: Bool = true
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
                        if step.isInteractive, hole.width < 200, hole.height < 200, !reduceMotion {
                            hand(on: hole, in: geo.size)
                        }
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
                TourPhaseRow(current: phase, shown: shown, compact: true, stagger: false)
                    .padding(.bottom, 2)
            }
            if let title {
                Text(title).scaledFont(size: 20, weight: .heavy).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggerIn(shown, delay: 0.08, distance: 10)
            }
            if let point {
                Label {
                    Text(point)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.primary)
                        .symbolEffect(.bounce, value: shown)
                }
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(Theme.primaryInk)
                .staggerIn(shown, delay: 0.18, distance: 10)
            }
            HStack(spacing: 10) {
                Button(L("スキップ"), action: onSkip)
                    .scaledFont(size: 13, weight: .medium)
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
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .modifier(Shake(amount: CGFloat(missed)))
        .task { shown = true }
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity).combined(with: .offset(y: 14)),
            removal: .opacity.combined(with: .scale(scale: 0.98))))
    }
}

/// 「チュートリアル完了！」— 撮った写真と紙吹雪、案内でやってみたこと。Owner 2026-10-28: back on the home screen, the
/// end is said and celebrated there (the home shows through, frosted).
struct TourCompleteView: View {
    let sticker: Sticker?
    let onDone: () -> Void

    @Environment(DexStore.self) private var dex
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var burst: Bool = false

    private static let confetti: [Color] = [Theme.primary, Color(hex: 0xF5B83D), Color(hex: 0xFF7A8A), Color(hex: 0x4FC3A1)]

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Theme.background.opacity(burst ? 0.55 : 0).ignoresSafeArea()
            OnboardingBackdrop().opacity(0.6)
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
                RevealHeadline(marked: L("チュートリアル完了！"), size: 26, delay: 0.3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                VStack(alignment: .leading, spacing: 12) {
                    recap(L("撮って、ホームに貼った"), icon: TourPhase.shoot.icon, delay: 0.85)
                    recap(L("図鑑の見方を知った"), icon: TourPhase.dex.icon, delay: 1.0)
                    recap(L("単語の頁で学んだ"), icon: TourPhase.word.icon, delay: 1.15)
                    recap(L("復習して、記憶の状態を見た"), icon: TourPhase.review.icon, delay: 1.3)
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
