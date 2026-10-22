import SwiftUI

/// FirstCatchFlow の体験段（ホーム → 撮る → 候補 → 発音 → 図鑑に追加 → 図鑑 → ことば → 復習 → 完了）。
/// Web 版は見本の画面を別に組むが、iOS 版はログイン後に始まるので**本物の画面の上に**案内を重ねる。
/// 撮った1枚は本物の図鑑に入る（登録後の引き継ぎが要らない）。
enum TourStep: String, Equatable {
    case off
    case home, tapCamera, shoot, pick, detail, peel
    case added, dexTypes, dexOpen, word
    case review, reviewPick, reviewNext
    case complete

    var anchor: TourAnchor? {
        switch self {
        case .home: .album
        case .tapCamera: .cameraTab
        case .shoot: .shutter
        case .pick: .pick
        case .detail: .headword
        case .peel: .peel
        case .dexTypes: .dexModes
        case .review, .reviewPick: .quiz
        case .reviewNext: .reviewNext
        case .off, .added, .dexOpen, .word, .complete: nil
        }
    }

    var title: String? {
        switch self {
        case .home: L("ホーム")
        case .tapCamera, .shoot: L("1枚撮ってみましょう")
        case .pick: L("覚えたいことばを選ぶ")
        case .detail, .word: L("発音と意味")
        case .peel: L("図鑑に入れる")
        case .added: L("図鑑に追加しました！")
        case .dexTypes, .dexOpen: L("図鑑")
        case .review: L("復習")
        default: nil
        }
    }

    var text: String {
        switch self {
        case .home: L("見つけた場面ごと、今日のアルバムに。単語帳へ書き写す手間がなくなります。")
        case .tapCamera: L("下のカメラを押して、気になるものを撮ってみましょう。名前を知らなくても大丈夫。")
        case .shoot: L("知らないものも、撮るだけ。AIが写真の中から学べることばを提案します。")
        case .pick: L("写真の中のものに、AIが見つけたことばを付けました。残したいことばをタップしてください。")
        case .detail: L("スピーカーを押すと、発音を聞けます。")
        case .peel: L("「図鑑に追加」を押すと、撮った写真と一緒に図鑑に入ります。")
        case .added: L("集めたことばが、撮った写真と一緒に並びます。")
        case .dexTypes: L("上のアイコンで、写真一覧・地図・リストへ切り替えられます。探し方も自分に合わせて。")
        case .dexOpen: L("追加した単語を開いて、意味や使い方を見てみましょう。")
        case .word: L("意味も使い方も、この写真から。例文を確認したら、復習を試してみましょう。")
        case .review: L("自分の写真を手がかりに4択で思い出す。単語だけの暗記より、出会った場面から思い出せます。")
        case .reviewPick: L("写真に合うことばを選んでください。")
        case .reviewNext: L("答えを確かめたら「次へ」。")
        default: ""
        }
    }

    /// 5 つの段のどこにいるか（札の点で見せる）。撮る段の途中（撮る・選ぶ・発音・追加）も 2 のまま。
    var phase: Int? {
        switch self {
        case .home: 1
        case .tapCamera, .shoot, .pick, .detail, .peel, .added: 2
        case .dexTypes, .dexOpen: 3
        case .word: 4
        case .review, .reviewPick, .reviewNext: 5
        case .off, .complete: nil
        }
    }

    static let phaseCount = 5

    /// Spotlight の `interactive`: 光っている所だけ押せる。false なら「次へ」で進む。
    var isInteractive: Bool {
        switch self {
        case .home, .added, .review: false
        default: true
        }
    }

    var nextLabel: String? {
        switch self {
        case .home, .detail, .added, .review: L("次へ")
        case .dexOpen: L("追加した単語を見てみる")
        case .word: L("復習してみる")
        default: nil
        }
    }

    var isReview: Bool { self == .review || self == .reviewPick || self == .reviewNext }
    var isCapture: Bool { self == .shoot || self == .pick || self == .detail || self == .peel }

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

enum TourAnchor: Hashable {
    case album, cameraTab, shutter, pick, headword, peel, dexModes, quiz, reviewNext
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

/// Spotlight.tsx: 画面を暗くし、押す所だけ穴を開けて青く光らせる。説明の札は穴と反対側に出す。
struct TourLayer: View {
    let step: TourStep
    let anchors: [TourAnchor: Anchor<CGRect>]
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false

    var body: some View {
        GeometryReader { geo in
            let full = CGRect(origin: .zero, size: geo.size)
            let hole: CGRect? = step.anchor.flatMap { anchors[$0] }.map { geo[$0].insetBy(dx: -8, dy: -8) }
            let dim = holePath(full: full, hole: hole)
            // 押す所が画面に無い（表示を切り替えた等）ときは暗くせず、札だけ出して操作を妨げない。
            let shouldDim = hole != nil || !step.isInteractive
            let showsCard = shouldDim || step.nextLabel != nil
            ZStack {
                if shouldDim {
                    dim
                        .fill(Color(hex: 0x0B1020, opacity: 0.58), style: FillStyle(eoFill: true))
                        .contentShape(step.isInteractive && hole != nil ? dim : Path(full), eoFill: true)
                        .onTapGesture {}
                        .transition(.opacity)
                }
                if let hole {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Theme.primary, lineWidth: 3)
                        .shadow(color: Theme.primary.opacity(pulse ? 0.9 : 0.4), radius: pulse ? 18 : 8)
                        .frame(width: hole.width, height: hole.height)
                        .scaleEffect(pulse ? 1.03 : 1)
                        .position(x: hole.midX, y: hole.midY)
                        .allowsHitTesting(false)
                    // 押す所: 指が軽くたたく動きと、広がる輪。どこを押せばよいか、読まなくても分かるように。
                    if step.isInteractive {
                        TourTapHint(animate: !reduceMotion)
                            .position(x: hole.midX, y: hole.midY)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                let cardOnTop = (hole?.midY ?? geo.size.height) > geo.size.height * 0.5
                if showsCard {
                    VStack {
                        if !cardOnTop { Spacer(minLength: 0) }
                        TourCoachCard(step: step, onNext: onNext, onSkip: onSkip)
                            .padding(.horizontal, 16)
                            .padding(.top, cardOnTop ? geo.safeAreaInsets.top + 12 : 0)
                            .padding(.bottom, cardOnTop ? 0 : max(geo.safeAreaInsets.bottom, 12) + 84)
                        if cardOnTop { Spacer(minLength: 0) }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func holePath(full: CGRect, hole: CGRect?) -> Path {
        var p = Path(full)
        if let hole { p.addRoundedRect(in: hole, cornerSize: CGSize(width: 22, height: 22), style: .continuous) }
        return p
    }
}

struct TourCoachCard: View {
    let step: TourStep
    let onNext: () -> Void
    let onSkip: () -> Void

    /// 「案内を終える」は一度確かめる（押し間違いで案内が消えると、戻す方法が無い）。
    @State private var confirmSkip: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if let title = step.title {
                    Text(title).scaledFont(size: 18, weight: .heavy).foregroundStyle(Theme.foreground)
                }
                Spacer()
                if let phase = step.phase {
                    TourPhaseDots(phase: phase)
                }
            }
            Text(step.text)
                .scaledFont(size: 15)
                .foregroundStyle(Theme.foreground.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("案内を終える")) { confirmSkip = true }
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .frame(minHeight: 44)
                    .confirmationDialog(L("案内を終えますか？"), isPresented: $confirmSkip, titleVisibility: .visible) {
                        Button(L("案内を終える"), role: .destructive, action: onSkip)
                        Button(L("続ける"), role: .cancel) {}
                    } message: {
                        Text(L("撮った写真と単語は、そのまま残ります。"))
                    }
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
                        .background(Theme.primary, in: Capsule())
                        .shadow(color: Theme.primary.opacity(0.4), radius: 10, y: 4)
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Theme.card, in: .rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity).combined(with: .offset(y: 12)),
                                removal: .opacity))
        .id(step)
    }
}

/// Five dots: the guide's parts done (filled), the one now (a longer bar), the ones to come (pale).
private struct TourPhaseDots: View {
    let phase: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...TourStep.phaseCount, id: \.self) { i in
                Capsule()
                    .fill(i <= phase ? Theme.primary : Theme.primary.opacity(0.18))
                    .frame(width: i == phase ? 16 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(phase) / \(TourStep.phaseCount)"))
    }
}

/// A finger that taps the lit place, with a ring spreading from it at each tap (still with reduced motion).
private struct TourTapHint: View {
    let animate: Bool

    var body: some View {
        if animate {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                // 0–0.25 指が下りる、0.25 でたたく、そのあと輪が広がって消える
                let press = t < 0.25 ? t / 0.25 : max(0, 1 - (t - 0.25) / 0.2)
                let ring = t < 0.25 ? 0 : min(1, (t - 0.25) / 0.6)
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 30 + 46 * ring, height: 30 + 46 * ring)
                        .opacity(t < 0.25 ? 0 : (1 - ring) * 0.9)
                    hand
                        .scaleEffect(1 - 0.12 * press)
                        .offset(x: 14, y: 22 - 6 * press)
                }
            }
        } else {
            hand.offset(x: 14, y: 22)
        }
    }

    private var hand: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 34))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            .accessibilityHidden(true)
    }
}

/// 「最初のキャッチ、完了！」— 撮った写真と紙吹雪。
struct TourCompleteView: View {
    let sticker: Sticker?
    let onDone: () -> Void

    @Environment(DexStore.self) private var dex
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var burst: Bool = false
    @State private var floating: Bool = false

    private static let confetti: [Color] = [Theme.primary, Color(hex: 0xF5B83D), Color(hex: 0xFF7A8A), Color(hex: 0x4FC3A1)]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 18) {
                Spacer(minLength: 20)
                Text(L("最初のキャッチ、完了！"))
                    .scaledFont(size: 28, weight: .heavy)
                    .foregroundStyle(Theme.foreground)
                Text(L("撮って、意味を知って、思い出す。\n身のまわりから、ことばを増やしていこう。"))
                    .scaledFont(size: 15)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.muted)
                ZStack {
                    ForEach(0..<14, id: \.self) { i in
                        let angle = Double(i) / 14 * 2 * .pi
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Self.confetti[i % Self.confetti.count])
                            .frame(width: 8, height: 14)
                            .rotationEffect(.degrees(Double(i) * 37 + (burst ? 180 : 0)))
                            .offset(x: burst ? cos(angle) * 150 : 0, y: burst ? sin(angle) * 150 : 0)
                            .opacity(burst ? 0.9 : 0)
                    }
                    // 撮った物を切り抜いたステッカーとして（白いふちは、切り抜きの形を白でずらして重ねて描く）。
                    let path = sticker?.heroPath
                    VStack(spacing: -12) {
                        StickerImage(path: path, url: dex.url(for: path, preferThumb: false), contentMode: .fit)
                            .frame(width: 210, height: 210)
                            .modifier(WhiteDieCut(width: 5))
                            .shadow(color: Color(hex: 0x1C4A80).opacity(0.22), radius: 16, y: 10)
                            .allowsHitTesting(false)
                        if let head = sticker?.word?.headword {
                            WordTag(text: head, zhuyin: sticker?.word?.readingZhuyin, pinyin: sticker?.word?.pinyin,
                                    tilt: -4, size: 26)
                        }
                    }
                    .rotationEffect(.degrees(burst ? -3 : -14))
                    .scaleEffect(burst ? 1 : 0.6)
                    .offset(y: floating ? -6 : 0)
                }
                .frame(height: 340)
                Spacer()
                PrimaryButton(title: L("はじめる"), icon: "arrow.right", sheen: true, action: onDone)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            Haptics.success()
            SoundService.shared.play(.sting)
            if reduceMotion { burst = true } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { burst = true }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(0.8)) { floating = true }
            }
        }
    }
}

/// A white die-cut border round a cut-out: the picture's shape repeated in white a little off-centre in eight
/// directions (shadows with no blur), under the picture.
struct WhiteDieCut: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: .white, radius: 0, x: width, y: 0)
            .shadow(color: .white, radius: 0, x: -width, y: 0)
            .shadow(color: .white, radius: 0, x: 0, y: width)
            .shadow(color: .white, radius: 0, x: 0, y: -width)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
