import SwiftUI

/// FirstCatchFlow の体験段（撮る → 選ぶ → 図鑑 → 復習 → 完了）。
/// Web 版は見本の画面を別に組むが、iOS 版はログイン後に始まるので**本物の画面の上に**案内を重ねる。
/// 撮った1枚は本物の図鑑に入る（登録後の引き継ぎが要らない）。
///
/// 2026-10-27（オーナー: 「チュートリアルが操作が分かりにくく…どうやってチュートリアルを進めたらいいか分からない」）:
/// 説明だけの段（ホームの紹介・図鑑の表示の切り替え・復習の紹介）をやめ、どの段も「何をタップすればいいか」を言う。
/// 札にはいつも4つの段（`TourPhase`）のどこにいるかを出し、押す所には手の印を重ね、暗い所を押したら光る所を知らせる。
enum TourStep: String, Equatable {
    case off
    case tapCamera, shoot, pick, detail, peel
    case added, word
    case reviewPick, reviewNext
    case complete

    var anchor: TourAnchor? {
        switch self {
        case .tapCamera: .cameraTab
        case .shoot: .shutter
        case .pick: .pick
        case .detail: .headword
        case .peel: .peel
        case .reviewPick: .quiz
        case .reviewNext: .reviewNext
        case .off, .added, .word, .complete: nil
        }
    }

    /// Which of the four steps the card counts this one as.
    var phase: TourPhase? {
        switch self {
        case .tapCamera, .shoot: .shoot
        case .pick, .detail, .peel: .pick
        case .added, .word: .collect
        case .reviewPick, .reviewNext: .review
        case .off, .complete: nil
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
        case .word: L("意味と使い方")
        case .reviewPick: L("写真で思い出す")
        case .reviewNext: L("復習")
        default: nil
        }
    }

    var text: String {
        switch self {
        case .tapCamera: L("下の青いカメラボタンをタップ。名前を知らない物でも大丈夫です。")
        case .shoot: L("身のまわりの物にカメラを向けて、シャッターをタップ。AIが写真から学べることばを見つけます。")
        case .pick: L("写真の中のものに、AIが見つけたことばを付けました。残したいことばをタップしてください。")
        case .detail: L("スピーカーをタップすると、発音を聞けます。聞けたら「次へ」。")
        case .peel: L("「図鑑に追加」を押すと、撮った写真と一緒に図鑑に入ります。")
        case .added: L("撮った写真と一緒に、ことばが並びます。開いて、意味と使い方を見てみましょう。")
        case .word: L("意味も使い方も、この写真から。例文を確認したら、復習を試してみましょう。")
        case .reviewPick: L("自分の写真を手がかりに4択で思い出します。写真に合うことばをタップ。")
        case .reviewNext: L("答えを確かめたら「次へ」。")
        default: ""
        }
    }

    /// Spotlight の `interactive`: 光っている所だけ押せる。false なら札のボタンで進む。
    var isInteractive: Bool {
        switch self {
        case .added, .word: false
        default: true
        }
    }

    var nextLabel: String? {
        switch self {
        case .detail: L("次へ")
        case .added: L("ことばを開く")
        case .word: L("復習してみる")
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
    case shoot, pick, collect, review

    var label: String {
        switch self {
        case .shoot: L("撮る")
        case .pick: L("選ぶ")
        case .collect: L("図鑑")
        case .review: L("復習")
        }
    }

    var icon: String {
        switch self {
        case .shoot: "camera.fill"
        case .pick: "hand.tap.fill"
        case .collect: "book.closed.fill"
        case .review: "sparkles"
        }
    }
}

/// ① 撮る — ② 選ぶ — ③ 図鑑 — ④ 復習: the steps done ticked, the current one blue. With `current` nil (the onboarding's
/// preview) all four are shown alike, coming in one after another once `shown`.
struct TourPhaseRow: View {
    let current: TourPhase?
    var shown: Bool = true
    var baseDelay: Double = 0
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(TourPhase.allCases, id: \.self) { p in
                item(p)
                    .staggerIn(shown, delay: baseDelay + Double(p.rawValue) * 0.08, distance: 8)
                if p != .review {
                    Capsule()
                        .fill(done(p) ? Theme.primary : Theme.border)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, circle / 2 - 1)
                        .padding(.horizontal, 2)
                        .staggerIn(shown, delay: baseDelay + Double(p.rawValue) * 0.08 + 0.04, distance: 0)
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
            .scaleEffect(isCurrent ? 1.08 : 1)
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
    case cameraTab, shutter, pick, headword, peel, quiz, reviewNext
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

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false
    @State private var ripple: Bool = false
    /// Taps on the dark part during a step that wants a tap on the lit place.
    @State private var missed: Int = 0
    @State private var flash: Bool = false

    var body: some View {
        // The safe area is read outside (the full-screen reader inside has none: the card sat under the clock, CI
        // 2026-10-27), the lit places in full-screen coordinates inside.
        GeometryReader { safe in
            let insets = safe.safeAreaInsets
            GeometryReader { geo in
                let full = CGRect(origin: .zero, size: geo.size)
                let hole: CGRect? = step.anchor.flatMap { anchors[$0] }.map { Self.holeRect(around: geo[$0]) }
                let radius = hole.map(Self.radius(for:)) ?? 0
                // 押す所が画面に無い（表示を切り替えた等）ときは暗くせず、札だけ出して操作を妨げない。
                let shouldDim = hole != nil || !step.isInteractive
                let showsCard = shouldDim || step.nextLabel != nil
                let lit = hole ?? CGRect(x: full.midX, y: full.midY, width: 0, height: 0)
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
                        ring(hole, radius: radius)
                        if step.isInteractive, hole.width < 200, hole.height < 200, !reduceMotion {
                            hand(on: hole, in: geo.size)
                        }
                    }
                    let cardOnTop = hole.map { $0.midY > geo.size.height * 0.5 } ?? false
                    if showsCard {
                        VStack {
                            if !cardOnTop { Spacer(minLength: 0) }
                            TourCoachCard(step: step, missed: missed, onNext: onNext, onSkip: onSkip)
                                .padding(.horizontal, 16)
                                .padding(.top, cardOnTop ? insets.top + 12 : 0)
                                .padding(.bottom, cardOnTop ? 0 : max(insets.bottom, 12) + 84)
                            if cardOnTop { Spacer(minLength: 0) }
                        }
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.86), value: lit)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { ripple = true }
        }
    }

    /// The lit place: the element with a margin; a round thing (the camera disc, the shutter, the speaker) a circle.
    static func holeRect(around r: CGRect) -> CGRect {
        let padded = r.insetBy(dx: -8, dy: -8)
        guard abs(padded.width - padded.height) < 16 else { return padded }
        let side = max(padded.width, padded.height)
        return CGRect(x: padded.midX - side / 2, y: padded.midY - side / 2, width: side, height: side)
    }

    static func radius(for hole: CGRect) -> CGFloat {
        hole.width == hole.height ? hole.width / 2 : min(22, hole.height / 2)
    }

    private func ring(_ hole: CGRect, radius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Theme.primary, lineWidth: 3)
                .shadow(color: Theme.primary.opacity(pulse ? 0.9 : 0.4), radius: pulse ? 18 : 8)
                .scaleEffect(flash ? 1.14 : pulse ? 1.03 : 1)
            // A ring spreading out from the place again and again: "here".
            if step.isInteractive && !reduceMotion {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.primaryBright, lineWidth: 2)
                    .scaleEffect(ripple ? 1.35 : 1)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let phase = step.phase {
                TourPhaseRow(current: phase, compact: true)
                    .padding(.bottom, 2)
            }
            if let title = step.title {
                Text(title).scaledFont(size: 19, weight: .heavy).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(step.text)
                .scaledFont(size: 15)
                .foregroundStyle(Theme.foreground.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
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

/// 「最初のキャッチ、完了！」— 撮った写真と紙吹雪、いまできるようになった3つ。
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
                    let path = sticker?.heroPath
                    Color.white
                        .frame(width: 200, height: 200)
                        .overlay {
                            StickerImage(path: path, url: dex.url(for: path, preferThumb: false), contentMode: .fit)
                                .padding(10)
                                .allowsHitTesting(false)
                        }
                        .clipShape(.rect(cornerRadius: 28, style: .continuous))
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
                RevealHeadline(marked: L("最初のキャッチ、**完了**！"), size: 26, delay: 0.3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                VStack(alignment: .leading, spacing: 12) {
                    recap(L("撮って、ことばを見つけた"), icon: TourPhase.shoot.icon, delay: 0.85)
                    recap(L("図鑑に集めた"), icon: TourPhase.collect.icon, delay: 1.0)
                    recap(L("写真で思い出した"), icon: TourPhase.review.icon, delay: 1.15)
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
                    .staggerIn(burst, delay: 1.3, distance: 6)
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
