import SwiftUI

/// The waiting star of a catch, handed from the camera screen to the landing (global coordinates).
struct CatchStar: Equatable {
    var center: CGPoint
    var size: CGFloat
    /// The card-catch screen's scale (design points → points), for the prototype's fixed offsets.
    var k: CGFloat
    /// Film v6: the sticker itself flies into the slot (its cut-out, or the photo round the thing), drawn at `box`.
    /// nil = the prototype's star (a re-encounter).
    var image: UIImage? = nil
    var box: CGSize = .zero
}

/// The second half of the prototype's `sendToDex` (docs/prototype/cardcatch-src.html): after the save, the dex
/// opens in ギャラリー (forced, like `S.view = "grid"`), scrolled to the word's place. Owner 2026-10-11
/// (「古い単語を横切るアニメーションではなく、…事前にもとの古い番号が高い単語の位置を1つ右に移動し、新しい単語はその
/// 左に入るようにして」): once the page has risen the gallery makes room for the word first — the words numbered
/// after it move one square to the right, leaving its square at its place by No. (DexView, `DexBook.Hold`) —
/// and only then the star flies there on an arc (720 ms, cubic-bezier(.5,0,.25,1), ±90 / −120 at the middle, a
/// full turn, scale 1 → 1.15 → .85, a trail of sparkles), lands with `.landpop` + SFX.pop + the pon tap, and the
/// square fills with the cut-out in place (nothing else moves); 20 ms later `renderDex`'s focus burst, glints and
/// SFX.land there. A re-encounter (`alreadyCaught`, owner 2026-10-11: 「同じ単語でも図鑑に追加するアニメーションを
/// 追加して」) lands the same way on the word's own square, which is already there: no room to make.
@MainActor @Observable
final class CatchLandingController {
    enum Phase { case opening, flying, landed }

    /// The landing word. A catch lands at once on a provisional entry; when its background save
    /// finishes this becomes the saved sticker's id (DexView moves its hold and focus along).
    var stickerId: String
    /// A re-encounter: the word is in the dex already (its square is not held, no room is made).
    let alreadyCaught: Bool
    /// The category's first five words, for the goal toast (nil = not a catalog word: no toast).
    let goal: CatchGoal?
    /// Film v6's finale: the counters roll one after another (category → 枚 → 影) after the impact. 3 = all rolled.
    var ticks: Int
    /// Film v6: anticipation pulse (`anticipAt` … `launchAt`), the flight to `impactAt`, the goal toast at `toastAt`.
    var anticipAt: Double?
    var launchAt: Double?
    var impactAt: Double?
    var toastAt: Double?
    /// The sticker's flight: duration (.40 s, film I − launch).
    let flightTime = 0.4
    let star: CatchStar
    let motion: CCMotion
    /// The screen's size, for the prototype's fallback target when the slot is not on screen.
    let screen: CGSize

    var phase: Phase = .opening
    /// [translateX, translateY, scale, rotate°] from `star.center`.
    var flight: CCAnim?
    /// After landing: [scale, opacity] (`star.animate(scale .85 → 1.6, opacity 1 → 0, 260 ms)`).
    var fade: CCAnim?
    /// `.landpop` [scale, opacity] at `landAt`.
    var pop: CCAnim?
    var landAt: CGPoint = .zero
    /// When the slot filled (`.slot.fill` → fillIn .9 s).
    var fillStart: Double?

    /// The target slot's `.sart`, in global coordinates (reported by the gallery as it lays out). After the
    /// landing it is the word's slot in the caught group (the same square).
    @ObservationIgnored var target: CGRect?
    /// Set by the gallery once the word's square is there to land in: the room made for a new word (the words
    /// numbered after it moved one square to the right), or a re-encounter's square scrolled to.
    @ObservationIgnored var roomReady = false
    /// Set by the gallery once it has been redrawn after the landing and scrolled to the word's new slot.
    @ObservationIgnored var settled = false
    let particles = CCParticles()
    @ObservationIgnored private var trailing = false

    init(stickerId: String, alreadyCaught: Bool = false, star: CatchStar, motion: CCMotion, screen: CGSize,
         goal: CatchGoal? = nil) {
        self.stickerId = stickerId
        self.alreadyCaught = alreadyCaught
        self.goal = goal
        self.ticks = star.image == nil || alreadyCaught ? 3 : 0
        self.star = star
        self.motion = motion
        self.screen = screen
        particles.calm = motion.calm
    }

    private func wait(_ seconds: Double) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func play(_ sfx: SFX) { SoundService.shared.playLayered(sfx) }

    /// The star's offset from its start at `now`.
    func offset(_ now: Double) -> CGPoint {
        guard let v = flight?.sample(now) else { return .zero }
        return CGPoint(x: v[0], y: v[1])
    }

    func run() async {
        if star.image != nil { await runSticker(); return }
        // The dex page is open and scrolled to the word's place (DexView). The page rises in .55 s; the star leaves
        // as it settles, once the gallery has made the word's square (`roomReady`) — at most 1.2 s in all, so a
        // gallery that is not on screen never keeps the star waiting.
        await wait(motion.sleep(380))
        var beforeFlight = motion.sleep(380)
        while !roomReady && beforeFlight < 1.2 {
            await wait(0.016)
            beforeFlight += 0.016
        }
        let k = Double(star.k)
        let cx = Double(star.center.x), cy = Double(star.center.y)
        // `tr = tEl ? rect(.sart) : {x: W0/2 − 40, y: 560, w: 80, h: 80}`
        let tr = target ?? CGRect(x: screen.width / 2 - 40 * star.k, y: 560 * star.k, width: 80 * star.k, height: 80 * star.k)
        let tx = Double(tr.midX), ty = Double(tr.midY)
        phase = .flying
        // No flight sound of its own (owner 2026-10-04): the landing pop and land follow.
        trailing = true
        Task {
            // setInterval(() => trail(star centre), 16)
            while trailing {
                let o = offset(CCClock.now)
                particles.trail(cx + Double(o.x), cy + Double(o.y))
                await wait(0.016)
            }
        }
        flight = CCAnim([[0, 0, 1, 0],
                         [(tx - cx) * 0.5 + (tx < cx ? -90 : 90) * k, (ty - cy) * 0.5 - 120 * k, 1.15, 180],
                         [tx - cx, ty - cy, 0.85, 360]],
                        duration: motion.d(720), easing: CCBezier(0.5, 0, 0.25, 1), fill: .forwards)
        await wait(motion.d(720))
        trailing = false

        // pon! — it lands and the cut-out appears in the silhouette
        fade = CCAnim([[0.85, 1], [1.6, 0]], duration: motion.d(260), fill: .forwards)
        landAt = CGPoint(x: tx, y: ty)
        pop = CCAnim([[0.1, 1], [1.3, 0]], duration: motion.d(550), easing: CCBezier(0.2, 0.8, 0.3, 1), fill: .forwards)
        play(.ccPop)
        Haptics.pon(open: true)
        phase = .landed
        // addEntry + renderDex: the hold is let go (DexView) and the waiting square becomes the word in place — the room
        // was made before the flight, so nothing else moves; the slot fills (`fillIn`) and keeps reporting its frame
        // into `target`.
        fillStart = CCClock.now
        var waited = 0.0
        while !settled && waited < 0.5 {
            await wait(0.016)
            waited += 0.016
        }
        // renderDex focus (focusNow): 20 ms later the burst, glints and SFX.land on the new slot
        await wait(0.02)
        let fr = target ?? tr
        particles.burst(Double(fr.midX), Double(fr.midY), n: 44, speed: 6, up: 3)
        particles.glints(fr, n: 8)
        play(.ccLand)
        await wait(2.6)   // the sparkles die down, then the overlay goes
    }
}

extension CatchLandingController {
    /// Film v6's finale (`dGet` after `open`, `drawDexPage` / `dexFx` / `goalToast`): the page rises (.4 s) and makes
    /// the word's square while the sticker waits where it was on the stage; a 7% pulse (anticipation, the riser ending
    /// 70 ms before the hit), then the sticker flies on a curve into the square (.40 s, in-cubic, shrinking to the
    /// square and tilting to −7°, three ghosts behind it). Impact: the dex shakes, light rays turn behind the square,
    /// two rings run out, sparkles; the NEW badge pops, the counters roll (category → 枚 → 影), the next shadow gets
    /// its breathing ring and the goal toast says how many of the category's five base words are left.
    func runSticker() async {
        play(.c6DexOpen)
        await wait(motion.sleep(300))
        var waited = motion.sleep(300)
        while !roomReady && waited < 1.2 {
            await wait(0.016)
            waited += 0.016
        }
        let now = CCClock.now
        let anticip = motion.d(120)
        anticipAt = now
        launchAt = now + anticip
        impactAt = now + anticip + motion.d(flightTime * 1000)
        phase = .flying
        // the riser (300 ms) ends 70 ms before the hit
        let riserAt = (impactAt ?? now) - 0.07 - 0.3
        if !motion.calm {
            Task {
                let left = riserAt - CCClock.now
                if left > 0 { try? await Task.sleep(for: .seconds(left)) }
                SoundService.shared.playLayered(.c6Riser)
            }
        }
        await wait((impactAt ?? now) - CCClock.now)

        // impact
        let hit = target ?? CGRect(x: screen.width / 2 - 40, y: screen.height * 0.3, width: 80, height: 80)
        landAt = CGPoint(x: hit.midX, y: hit.midY)
        impactAt = CCClock.now
        play(.c6LandImpact)
        HapticPatterns.shared.land()
        phase = .landed
        fillStart = CCClock.now
        particles.burst(Double(hit.midX), Double(hit.midY), n: 44, speed: 6, up: 3)
        particles.glints(hit, n: 8)
        await wait(0.1)
        play(.c6NewBadge)
        await wait(0.2)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.7)) { ticks = 1 }
        play(.c6Tick1)
        await wait(0.12)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.7)) { ticks = 2 }
        play(.c6Tick2)
        await wait(0.08)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.7)) { ticks = 3 }
        play(.c6Tick3)
        await wait(0.2)
        play(.c6Refill)
        await wait(0.15)
        if let goal {
            toastAt = CCClock.now
            if goal.left > 0 { play(.c6GoalOneMore) } else { SoundService.shared.playLayered(.c6CatchJingle, volume: 0.7) }
            await wait(2.5 + 0.35)
        } else {
            await wait(1.6)
        }
    }

    /// The sticker's place, scale and tilt at `now` during the finale (global), nil once it has landed.
    func stickerPose(_ now: Double) -> (center: CGPoint, scale: Double, rotation: Double, fly: Double)? {
        if let i = impactAt, now >= i, phase == .landed { return nil }
        let p0 = star.center
        guard let launch = launchAt else { return (p0, 1, 0, 0) }
        let anticip = anticipAt ?? launch
        let pulse = 1 + 0.07 * sin(.pi * Film6.seg(now, anticip, launch))
        let fly = Film6.seg(now, launch, launch + max(0.001, motion.d(flightTime * 1000)))
        guard fly > 0 else { return (p0, pulse, 0, 0) }
        let e = Film6.inCubic(fly)
        let p = flightPoint(e)
        return (p, Film6.lerp(1, arriveScale, e), -6.9 * e, fly)
    }

    /// The flight's curve: from the stage to the square, the control point up and to the right (film `bez2`, +80 / −320).
    func flightPoint(_ e: Double) -> CGPoint {
        let p0 = star.center
        let t = target.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: screen.width / 2, y: screen.height * 0.3)
        let c = CGPoint(x: p0.x + screen.width * 80 / 1080, y: p0.y - screen.height * 320 / 2340)
        return Film6.bez2(p0, c, t, e)
    }

    /// The square's picture size over the sticker's: it arrives 1.3× the square's cut-out (the square then settles).
    var arriveScale: Double {
        guard let t = target, star.box.width > 0, star.box.height > 0 else { return 0.35 }
        let side = t.width * 0.9 * 1.3
        return Double(min(side / star.box.width, side / star.box.height))
    }
}

/// The star, its sparkles and `.landpop`, above every screen while the dex opens (`#fly` / `#fx` / `.landpop`).
struct CatchLandingOverlay: View {
    let controller: CatchLandingController

    var body: some View {
        GeometryReader { geo in
            let o = geo.frame(in: .global).origin
            TimelineView(.animation) { _ in
                let now = CCClock.now
                let c = controller
                ZStack(alignment: .topLeading) {
                    if let p = c.pop, let v = p.sample(now), v[1] > 0.001 {
                        // radial-gradient(closest-side, rgba(255,255,255,.95), rgba(190,220,255,.5) 40%, transparent)
                        let s = 120 * c.star.k
                        Circle()
                            .fill(RadialGradient(stops: [.init(color: .rgba(255, 255, 255, 0.95), location: 0),
                                                         .init(color: .rgba(190, 220, 255, 0.5), location: 0.4),
                                                         .init(color: .rgba(255, 255, 255, 0), location: 1)],
                                                 center: .center, startRadius: 0, endRadius: s / 2))
                            .frame(width: s, height: s)
                            .scaleEffect(v[0])
                            .opacity(v[1])
                            .position(x: c.landAt.x - o.x, y: c.landAt.y - o.y)
                    }
                    if c.star.image != nil {
                        impactFX(now: now, origin: o, width: geo.size.width)
                        sticker(now: now, origin: o)
                    } else {
                        star(now: now, origin: o)
                    }
                    Canvas { ctx, _ in
                        c.particles.advance(to: now)
                        ctx.translateBy(x: -o.x, y: -o.y)
                        c.particles.draw(&ctx)
                    }
                    if let goal = c.goal, let at = c.toastAt {
                        CatchGoalToast(goal: goal, start: at, now: now, calm: c.motion.calm)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Film v6: the sticker itself, waiting on the stage, then flying into the square with three fading ghosts.
    @ViewBuilder
    private func sticker(now: Double, origin o: CGPoint) -> some View {
        let c = controller
        if let pose = c.stickerPose(now), let image = c.star.image {
            let box = c.star.box.width > 0 ? c.star.box : CGSize(width: c.star.size, height: c.star.size)
            let cut = image.size.width > 0 && Self.hasAlpha(image)
            ForEach([3, 2, 1], id: \.self) { kk in
                let fk = Film6.clamp(pose.fly - Double(kk) * 0.05)
                if pose.fly > 0, fk > 0 {
                    let e = Film6.inCubic(fk)
                    let p = c.flightPoint(e)
                    CatchStickerArt(cut: cut ? image : nil, fallback: cut ? nil : image, size: box, border: 1 - e)
                        .scaleEffect(CGFloat(Film6.lerp(1, c.arriveScale, e)))
                        .rotationEffect(.degrees(-6.9 * e))
                        .opacity(0.14 / Double(kk))
                        .position(x: p.x - o.x, y: p.y - o.y)
                }
            }
            CatchStickerArt(cut: cut ? image : nil, fallback: cut ? nil : image, size: box, border: 1 - Film6.inCubic(pose.fly))
                .scaleEffect(CGFloat(pose.scale))
                .rotationEffect(.degrees(pose.rotation))
                .shadow(color: .rgba(15, 40, 80, 0.18 * (1 - pose.fly)), radius: 10, y: 6)
                .position(x: pose.center.x - o.x, y: pose.center.y - o.y)
        }
    }

    private static func hasAlpha(_ image: UIImage) -> Bool {
        guard let info = image.cgImage?.alphaInfo else { return false }
        switch info {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    /// Film `dexFx`: light rays turning behind the square and two white rings with a blue glow running out.
    @ViewBuilder
    private func impactFX(now: Double, origin o: CGPoint, width: CGFloat) -> some View {
        let c = controller
        if let at = c.impactAt, c.phase == .landed, now - at < 1.1, !c.motion.calm {
            let u = now - at
            let k = width / 1080
            Canvas { ctx, _ in
                let center = CGPoint(x: c.landAt.x - o.x, y: c.landAt.y - o.y)
                let ra = Film6.outCubic(Film6.seg(u, 0, 0.12)) * (1 - Film6.seg(u, 0.45, 1.0))
                if ra > 0 {
                    var g = ctx
                    g.blendMode = .plusLighter
                    g.opacity = 0.38 * ra
                    g.translateBy(x: center.x, y: center.y)
                    g.rotate(by: .radians(u * 0.6))
                    let L = 330 * k
                    for _ in 0..<12 {
                        g.rotate(by: .radians(2 * .pi / 12))
                        var ray = Path()
                        ray.move(to: CGPoint(x: -10 * k, y: 0))
                        ray.addLine(to: CGPoint(x: -34 * k, y: -L))
                        ray.addLine(to: CGPoint(x: 34 * k, y: -L))
                        ray.addLine(to: CGPoint(x: 10 * k, y: 0))
                        ray.closeSubpath()
                        g.fill(ray, with: .linearGradient(Gradient(colors: [.rgba(120, 190, 255, 0.9), .rgba(120, 190, 255, 0)]),
                                                          startPoint: .zero, endPoint: CGPoint(x: 0, y: -L)))
                    }
                }
                for (d, a0, w0, R) in [(0.0, 0.75, 12.0, 300.0), (0.07, 0.45, 6.0, 380.0)] {
                    let p = Film6.seg(u, d, d + 0.5)
                    guard p > 0, p < 1 else { continue }
                    var g = ctx
                    g.opacity = a0 * (1 - p)
                    g.addFilter(.shadow(color: Theme.primaryBright, radius: 12 * k * 2))
                    let r = CGFloat(70 + (R - 70) * Film6.outCubic(p)) * k
                    g.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(.white), lineWidth: CGFloat(w0 * (1 - p) + 1) * k)
                }
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func star(now: Double, origin o: CGPoint) -> some View {
        let c = controller
        let fl = c.flight?.sample(now)
        let fd = c.fade?.sample(now)
        let opacity = fd?[1] ?? 1
        if opacity > 0.001 {
            let tx = fl?[0] ?? 0, ty = fl?[1] ?? 0
            let scale = fd?[0] ?? fl?[2] ?? 1
            let rot = fd == nil ? (fl?[3] ?? 0) : 0
            CCStarlight(size: c.star.size, now: now, calm: c.motion.calm)
                .scaleEffect(scale)
                .rotationEffect(.degrees(rot))
                .opacity(opacity)
                .position(x: c.star.center.x + tx - o.x, y: c.star.center.y + ty - o.y)
        }
    }
}

enum CatchLanding {
    /// The catch is saved: open the dex gallery and fly the waiting star into the word's slot. `alreadyCaught`: a
    /// re-encounter's photo going into a word the dex already shows (no room to make, its own square lands).
    @MainActor
    static func land(stickerId: String, router: AppRouter, calm: Bool, alreadyCaught: Bool = false, goal: CatchGoal? = nil) {
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size ?? CGSize(width: 390, height: 844)
        let star = router.catchStar ?? CatchStar(center: CGPoint(x: screen.width / 2, y: screen.height * 306 / 844),
                                                  size: 52, k: 1)
        router.catchStar = nil
        let c = CatchLandingController(stickerId: stickerId, alreadyCaught: alreadyCaught, star: star,
                                       motion: CCMotion(calm: calm), screen: screen, goal: alreadyCaught ? nil : goal)
        router.landing = c
        Task {
            // One frame first, so the camera screen knows it stays under the rising dex page.
            try? await Task.sleep(for: .milliseconds(16))
            // Film v6: the 図鑑 page rises 140 px with a fade (.4 s, in-out cubic; MainTabView's transition) (calm: no slide)
            withAnimation(calm ? nil : .timingCurve(0.65, 0, 0.35, 1, duration: 0.4)) { router.tab = .dex }
            await c.run()
            if router.landing === c { router.landing = nil }
        }
    }
}

/// The goal toast (film `goalToast`): a glass capsule above the tab bar — the category's emoji, 「〜の基本5語」, how many
/// are left in blue, and five dots (caught: blue with a white check, the new one popping in; still to find: dashed,
/// breathing). On for 2.5 s.
struct CatchGoalToast: View {
    let goal: CatchGoal
    let start: Double
    let now: Double
    let calm: Bool

    var body: some View {
        let u = now - start
        let a = (calm ? Film6.clamp(u / 0.2) : Film6.outCubic(Film6.seg(u, 0, 0.35))) * (1 - Film6.seg(u, 2.5, 2.75))
        if a > 0.001 {
            HStack(spacing: 12) {
                Text(goal.emoji).font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("\(goal.label)の基本5語"))
                        .font(.system(size: 13.5, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x0B121A))
                    Text(goal.left == 0 ? L("コンプリート！") : L("あと\(goal.left)語でコンプリート"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    ForEach(Array(goal.caught.enumerated()), id: \.offset) { i, caught in
                        dot(i, caught: caught, u: u)
                    }
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 18)
            .frame(height: 56)
            .background(.regularMaterial, in: Capsule())
            .background(Color.white.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1))
            .shadow(color: .rgba(15, 40, 80, 0.14), radius: 16, y: 6)
            .padding(.horizontal, 16)
            .opacity(a)
            .offset(y: CGFloat(1 - a) * 15)
            .padding(.bottom, 96)
            .environment(\.colorScheme, .light)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func dot(_ i: Int, caught: Bool, u: Double) -> some View {
        let isNew = goal.newIndex == i
        let filled = caught && (!isNew || u > 0.25)
        if filled {
            let pop = isNew && !calm ? Film6.outBack(Film6.seg(u, 0.25, 0.5), 3) : 1
            Circle()
                .fill(Theme.primary)
                .frame(width: 14, height: 14)
                .overlay(Image(systemName: "checkmark").font(.system(size: 7, weight: .black)).foregroundStyle(.white))
                .scaleEffect(CGFloat(pop))
        } else {
            Circle()
                .strokeBorder(Theme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [2.4, 2]))
                .frame(width: 13, height: 13)
                .opacity(calm ? 1 : 0.55 + 0.45 * sin(u * 4.2))
                .frame(width: 14, height: 14)
        }
    }
}
