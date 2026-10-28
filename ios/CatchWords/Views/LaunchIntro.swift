import SwiftUI

/// The app's opening, every launch, for everyone (owner 2026-10-28: 「アプリを開いた時に…美しいアニメーションを出して…新規ユーザーも
/// ログインするユーザーも全て」「アイコンのデザインの中から、C と W の文字が出現し、アプリの CatchWords の名前が出る」; the
/// reference films: a drop that floods the screen in the brand colour, the mark, the name growing out of its letter, and the
/// colour lifting away to the app).
///
/// One clock drives it all (`TimelineView`, like the catch's films), so every part stays in step:
///  0.00 a blue drop falls into the middle of the paper
///  0.28 it floods the screen in the icon's own blue (the icon's gradient, so the app seems to open out of its icon)
///  0.62 the icon's white mark draws itself round, a little big, and settles
///  1.30 the mark lets go of its letters: C from its left loop, W from its right
///  1.62 「atch」 and 「ords」 unfold out of C and W: CatchWords, a light passing over it
///  2.42 the blue lifts off upwards and the app is there (the sign-in screen or the home)
/// A tap moves straight on to the lift. Reduce Motion: the name on the blue, faded in and out.
struct LaunchIntro: View {
    let onDone: () -> Void

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var skipAt: Double?
    @State private var atchWidth: CGFloat = 0
    @State private var ordsWidth: CGFloat = 0
    @State private var cues: Set<Int> = []

    /// When the lift starts and when it is over.
    static let liftAt: Double = 2.42
    static let endAt: Double = 2.95

    /// The icon's own blue, top to bottom (sampled from AppIcon).
    static let top = Color(hex: 0x0589FE)
    static let bottom = Color(hex: 0x0040DA)

    // MARK: Once per launch

    /// Played once per launch of the app, never in the UI tests (they tap at once).
    @MainActor static var shouldPlay: Bool {
        #if DEBUG
        if DemoBackend.isOn { return false }
        #endif
        return !played
    }
    @MainActor private(set) static var played = false
    /// The lift has started (or there is no opening): the screen under it may begin its own entrance.
    @MainActor private(set) static var revealed = false

    /// The welcome screen waits for the lift before its stickers and words come in (at most 3.5 s).
    @MainActor static func waitForReveal() async {
        for _ in 0..<220 where !revealed {
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(paused: start == nil)) { ctx in
                let t = elapsed(at: ctx.date)
                scene(t: t, size: size)
                    .onChange(of: Int(t * 20)) { _, _ in cue(t) }
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        // Over the sign-in screen or the home, which appear under it while it plays (and ask for dark text).
        .statusBarTone(.light, covering: true)
        .accessibilityElement()
        .accessibilityLabel("CatchWords")
        .accessibilityAddTraits(.isImage)
        .onAppear {
            Self.played = true
            start = Date()
            if reduceMotion { Task { await finishCalm() } }
        }
    }

    private func elapsed(at date: Date) -> Double {
        guard let start else { return 0 }
        let raw = date.timeIntervalSince(start)
        // A tap jumps to the lift (keeping time running from there).
        if let skipAt, raw >= skipAt { return Self.liftAt + (raw - skipAt) }
        return raw
    }

    @ViewBuilder
    private func scene(t: Double, size: CGSize) -> some View {
        if reduceMotion {
            calmScene(t: t)
        } else {
            let lift = Ease.inOutCubic(Ease.seg(t, Self.liftAt, Self.endAt))
            ZStack {
                // The paper the drop falls on, gone with the lift too.
                Theme.background.opacity(1 - Ease.seg(t, 0.6, 0.9))
                flood(t: t, size: size)
                VStack(spacing: 0) {
                    ZStack {
                        glyph(t: t)
                        wordmark(t: t)
                    }
                }
                .frame(width: size.width, height: size.height)
                .offset(y: -lift * 60)
                .opacity(1 - Ease.seg(t, Self.liftAt, Self.liftAt + 0.3))
            }
            // The blue lifts off upwards, its lower edge rounding as it goes.
            .mask {
                UnevenRoundedRectangle(bottomLeadingRadius: 40 * lift, bottomTrailingRadius: 40 * lift, style: .continuous)
                    .offset(y: -lift * (size.height + 60))
            }
            .shadow(color: .black.opacity(0.25 * lift * (1 - lift) * 4), radius: 30, y: 12)
            .onChange(of: t >= Self.endAt) { _, over in if over { onDone() } }
        }
    }

    /// The drop, then the flood: a circle of the icon's blue from the middle.
    private func flood(t: Double, size: CGSize) -> some View {
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let fall = Ease.outCubic(Ease.seg(t, 0, 0.3))
        let grow = Ease.inOutCubic(Ease.seg(t, 0.28, 0.82))
        let drop: CGFloat = 22 * Ease.outBack(Ease.seg(t, 0, 0.3))
        let d = drop + (diagonal * 1.05 - drop) * grow
        return LinearGradient(colors: [Self.top, Self.bottom], startPoint: .top, endPoint: .bottom)
            .mask {
                Circle()
                    .frame(width: d, height: d)
                    .offset(y: (1 - fall) * -120)
            }
            // The ripple ring the drop leaves as it lands.
            .overlay {
                let r = Ease.outCubic(Ease.seg(t, 0.26, 0.9))
                Circle()
                    .stroke(Self.top.opacity(0.5 * (1 - r)), lineWidth: 2 + 6 * (1 - r))
                    .frame(width: 30 + diagonal * 0.6 * r, height: 30 + diagonal * 0.6 * r)
                    .opacity(t < 0.26 ? 0 : 1)
            }
    }

    /// The icon's white mark: drawn round from the top (a sweep mask), a little big, settling; then it lets go of its
    /// letters, shrinking and blurring away.
    private func glyph(t: Double) -> some View {
        let appear = Ease.seg(t, 0.62, 1.12)
        let settle = Ease.outBack(appear, overshoot: 1.25)
        let away = Ease.inOutCubic(Ease.seg(t, 1.3, 1.62))
        let sweep = Ease.inOutCubic(Ease.seg(t, 0.62, 1.02))
        return Image("AppGlyph")
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(.white)
            .aspectRatio(656.0 / 503.0, contentMode: .fit)
            .frame(width: 168)
            .mask {
                // A sweep round the middle, like a pen going round the two loops.
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(style: StrokeStyle(lineWidth: 400))
                    .frame(width: 400, height: 400)
                    .rotationEffect(.degrees(-90))
            }
            .scaleEffect((0.62 + 0.38 * settle) * (1 - 0.45 * away))
            .blur(radius: 10 * (1 - appear) + 8 * away)
            .opacity(Ease.seg(t, 0.62, 0.8) * (1 - away))
            .shadow(color: .white.opacity(0.35 * (1 - away)), radius: 18)
    }

    /// C and W out of the mark's loops, then 「atch」 and 「ords」 unfolding from them; a light passes over the name.
    private func wordmark(t: Double) -> some View {
        let letters = Ease.outCubic(Ease.seg(t, 1.32, 1.66))
        let together = Ease.inOutCubic(Ease.seg(t, 1.36, 1.74))
        let unfold = Ease.inOutCubic(Ease.seg(t, 1.62, 2.12))
        let shine = Ease.seg(t, 2.02, 2.5)
        let font = Font.system(size: 46, weight: .heavy)
        return HStack(spacing: 0) {
            // C starts where the mark's left loop was, W at its right one.
            letter("C", font: font)
                .offset(x: -34 * (1 - together))
            tail("atch", font: font, width: atchWidth, open: unfold)
            letter("W", font: font)
                .offset(x: 34 * (1 - together))
            tail("ords", font: font, width: ordsWidth, open: unfold)
        }
        .tracking(-0.8)
        .scaleEffect(0.7 + 0.3 * letters)
        .blur(radius: 8 * (1 - letters))
        .opacity(letters)
        .overlay {
            // The light: a bright band sweeping left to right across the letters.
            GeometryReader { g in
                LinearGradient(colors: [.clear, .white.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 70)
                    .rotationEffect(.degrees(18))
                    .offset(x: -80 + (g.size.width + 160) * shine)
                    .opacity(shine > 0 && shine < 1 ? 1 : 0)
            }
            .mask {
                HStack(spacing: 0) {
                    Text(verbatim: "C").font(font)
                    Text(verbatim: "atch").font(font)
                    Text(verbatim: "W").font(font)
                    Text(verbatim: "ords").font(font)
                }
                .tracking(-0.8)
            }
            .blendMode(.plusLighter)
        }
        .background {
            // The tails' own widths, measured once.
            HStack {
                Text(verbatim: "atch").font(font).tracking(-0.8).fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { atchWidth = $0 }
                Text(verbatim: "ords").font(font).tracking(-0.8).fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ordsWidth = $0 }
            }
            .hidden()
        }
    }

    private func letter(_ s: String, font: Font) -> some View {
        Text(verbatim: s).font(font).foregroundStyle(.white).fixedSize()
    }

    /// 「atch」 / 「ords」: its room opens from nothing and the letters slide out from behind the capital before it.
    private func tail(_ s: String, font: Font, width: CGFloat, open: Double) -> some View {
        Text(verbatim: s).font(font).foregroundStyle(.white).fixedSize()
            .offset(x: -18 * (1 - open))
            .opacity(Ease.seg(open, 0.15, 0.85))
            .frame(width: width * open, alignment: .leading)
            .clipped()
    }

    /// Reduce Motion: the name on the blue, in and out, no movement.
    private func calmScene(t: Double) -> some View {
        ZStack {
            LinearGradient(colors: [Self.top, Self.bottom], startPoint: .top, endPoint: .bottom)
            Text(verbatim: "CatchWords")
                .font(.system(size: 46, weight: .heavy))
                .tracking(-0.8)
                .foregroundStyle(.white)
                .opacity(Ease.seg(t, 0, 0.3))
        }
        .opacity(1 - Ease.seg(t, 1.0, 1.3))
    }

    private func finishCalm() async {
        try? await Task.sleep(for: .milliseconds(1000))
        Self.revealed = true
        try? await Task.sleep(for: .milliseconds(320))
        onDone()
    }

    private func skip() {
        guard !reduceMotion, skipAt == nil, let start else { return }
        let now = Date().timeIntervalSince(start)
        guard now < Self.liftAt else { return }
        skipAt = now
    }

    /// The touches and the hand-over, each once: a soft tap as the drop lands and as the name is whole, and the screen
    /// under it is told when the lift starts.
    private func cue(_ t: Double) {
        func once(_ id: Int, at time: Double, _ action: () -> Void) {
            guard t >= time, !cues.contains(id) else { return }
            cues.insert(id)
            action()
        }
        once(0, at: 0.28) { Haptics.impact(.soft, intensity: 0.5) }
        once(1, at: 2.1) { Haptics.impact(.light, intensity: 0.7) }
        once(2, at: Self.liftAt) { Self.revealed = true }
    }
}

/// The opening's easings (seconds in, 0…1 out).
private enum Ease {
    static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { min(1, max(0, (t - a) / (b - a))) }
    static func outCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func inOutCubic(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    /// Past 1 and back (a settle).
    static func outBack(_ x: Double, overshoot s: Double = 1.70158) -> Double {
        let c3 = s + 1
        return 1 + c3 * pow(x - 1, 3) + s * pow(x - 1, 2)
    }
}
