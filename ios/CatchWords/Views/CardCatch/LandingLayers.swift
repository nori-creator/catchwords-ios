import SwiftUI
import QuartzCore

/// Film v6's landing in the 図鑑, drawn by Core Animation (owner 2026-11-27: 「図鑑にポンと追加されるところがカクカク
/// して止まってる…根本的に原因を特定し、限界まで滑らかになるように」).
///
/// The sticker's flight, its hit and settle in the square, the blue ring round the square, the light rays, the two rings
/// running out and the sparkles were SwiftUI views redrawn by the main thread on every frame (`TimelineView`), and the
/// hit is the very moment the 図鑑 takes the word in (its square, its count, its NEW badge): the main thread was busy
/// with that, so every one of them stood still until it was done — the recording showed the sticker frozen in its square
/// for most of a second. Here all of it is handed to Core Animation once, as the sticker sets off, with the times it
/// is to play at (`CACurrentMediaTime`, the clock `CCClock` reads): the system's render server plays it, frame by frame,
/// whatever the main thread is doing. Nothing in it is redrawn by the app.
///
/// The look and the timing are the film's, as `CatchLanding.swift` drew them: the 7% gathering pulse (.12 s), the
/// in-cubic curve to the square (.40 s, up and to the right, shrinking to 1.3× the square's picture and tilting −6.9°,
/// the white border going, three ghosts behind it), the dashed ring tightening round the square, then the hit: the
/// solid ring with its glow (1.5 s), twelve rays turning (1.1 s), two rings running out, 44 sparks and 8 glints. What
/// the square itself did after the hit (`DexFillIn` settle: 1.3× → 1 with the squash of the contact) the sticker now
/// does here, in the square's place; the square's own picture is shown once it has settled (`handoffAt`) and the
/// sticker then fades over it.
struct LandingLayers: UIViewRepresentable {
    let controller: CatchLandingController

    func makeUIView(context: Context) -> LandingLayerView {
        LandingLayerView()
    }

    func updateUIView(_ view: LandingLayerView, context: Context) {
        let c = controller
        // Read here so SwiftUI calls this again when they change (the launch, the hand-off): two calls in all.
        _ = c.launchAt
        _ = c.handoffAt
        view.show(c)
    }
}

final class LandingLayerView: UIView {
    private weak var controller: CatchLandingController?
    /// The sticker (and its ghosts) as they wait on the stage, then fly.
    private var sticker: StickerLayers?
    private var ghosts: [StickerLayers] = []
    /// The launch whose animations have been handed to Core Animation.
    private var scheduled: Double?
    private var handedOff: Double?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let c = controller { show(c) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let c = controller, sticker == nil || (scheduled == nil && c.launchAt != nil) { show(c) }
    }

    /// The landing as it stands: the sticker waiting where the GET moment left it, everything handed to Core
    /// Animation once it sets off, the sticker fading once the square shows its own picture.
    func show(_ c: CatchLandingController) {
        controller = c
        // Global (window) coordinates need the window; the size is known after the first layout.
        guard window != nil, bounds.width > 0, let image = c.star.image else { return }
        if sticker == nil {
            let s = StickerLayers(image: image, box: c.star.box.width > 0 ? c.star.box : CGSize(width: c.star.size, height: c.star.size),
                                  scale: traitCollection.displayScale)
            s.root.position = local(c.star.center)
            s.root.shadowOpacity = 0.18
            layer.addSublayer(s.root)
            sticker = s
        }
        if let launch = c.launchAt, scheduled != launch, let plan = c.plan {
            scheduled = launch
            schedule(plan, calm: c.motion.calm)
        }
        if let at = c.handoffAt, handedOff != at {
            handedOff = at
            fadeSticker()
        }
    }

    private func local(_ global: CGPoint) -> CGPoint { convert(global, from: nil) }
    private func local(_ global: CGRect) -> CGRect { convert(global, from: nil) }

    // MARK: Scheduling

    private func schedule(_ plan: LandingPlan, calm: Bool) {
        guard let sticker, let image = controller?.star.image else { return }
        let p0 = local(plan.start)
        let control = local(plan.control)
        let hit = local(plan.target)
        let t = CGPoint(x: hit.midX, y: hit.midY)
        let k = bounds.width / 1080
        // The ghosts: behind the sticker, a little later on the same curve.
        if !calm {
            for kk in 1...3 {
                let g = StickerLayers(image: image, box: sticker.box, scale: traitCollection.displayScale)
                g.root.position = p0
                g.root.opacity = 0
                layer.insertSublayer(g.root, below: sticker.root)
                ghosts.append(g)
                fly(g, plan: plan, p0: p0, control: control, t: t, lag: Double(kk) * 0.05, ghost: 0.14 / Double(kk))
            }
            ring(plan, hit: hit, k: k)
            rays(plan, at: t, k: k)
            rings(plan, at: t, k: k)
            sparks(plan, hit: hit)
        }
        fly(sticker, plan: plan, p0: p0, control: control, t: t, lag: 0, ghost: nil)
    }

    /// The sticker's whole way from the stage into the square: the gathering pulse, the curve, the hit and the settle
    /// (or a ghost's way: the curve only, `lag` of the flight behind, at `ghost` opacity, gone at the hit).
    private func fly(_ s: StickerLayers, plan: LandingPlan, p0: CGPoint, control: CGPoint, t: CGPoint, lag: Double, ghost: Double?) {
        let a0 = plan.anticipAt, l0 = plan.launchAt, i0 = plan.impactAt
        let flight = max(0.001, i0 - l0)
        let end = ghost == nil ? i0 + plan.settle : i0
        let total = max(0.001, end - a0)
        let steps = max(8, Int((total * 120).rounded()))
        var positions: [NSValue] = [], transforms: [NSValue] = [], rings: [NSValue] = [], ringAlpha: [NSNumber] = []
        var shadow: [NSNumber] = [], alpha: [NSNumber] = [], times: [NSNumber] = []
        for i in 0...steps {
            let now = a0 + total * Double(i) / Double(steps)
            times.append(NSNumber(value: Double(i) / Double(steps)))
            var pos = p0, sx = 1.0, sy = 1.0, rot = 0.0, border = 1.0, fly = 0.0
            if now < l0 {
                // The gathering pulse (anticipation).
                let pulse = 1 + 0.07 * sin(.pi * Film6.seg(now, a0, l0))
                sx = pulse; sy = pulse
            } else if now < i0 || ghost != nil {
                fly = Film6.clamp((now - l0) / flight - lag)
                let e = Film6.inCubic(fly)
                pos = Film6.bez2(p0, control, t, e)
                let sc = Film6.lerp(1, plan.arriveScale, e)
                sx = sc; sy = sc
                rot = -6.9 * e
                border = 1 - e
            } else {
                // The hit: from 1.3× the square's picture, tilted, to the square's size with the squash of the contact.
                let u = now - i0
                let st = Film6.spring(u, response: 0.42, damping: 0.52)
                let sq = sin(Film6.clamp(u / 0.22) * .pi) * exp(-u * 6)
                let kk = Film6.lerp(plan.arriveScale, plan.arriveScale / 1.3, st)
                pos = t
                sx = kk * (1 + 0.14 * sq)
                sy = kk * (1 - 0.12 * sq)
                rot = -6.9 * (1 - st)
                border = 0
                fly = 1
            }
            positions.append(NSValue(cgPoint: pos))
            var m = CATransform3DMakeRotation(CGFloat(rot * .pi / 180), 0, 0, 1)
            m = CATransform3DScale(m, CGFloat(sx), CGFloat(sy), 1)
            transforms.append(NSValue(caTransform3D: m))
            rings.append(NSValue(cgRect: s.ringBounds(border: border)))
            ringAlpha.append(NSNumber(value: min(1, border * 1.6)))
            shadow.append(NSNumber(value: 0.18 * (1 - fly)))
            if let ghost {
                // Seen only while it is on its way (the film: `pose.fly > 0 && fk > 0`), gone at the hit.
                let fk = (now - l0) / flight - lag
                alpha.append(NSNumber(value: now >= l0 && fk > 0 && now < i0 ? ghost : 0))
            }
        }
        func keyframes(_ path: String, _ values: [Any]) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: path)
            a.values = values
            a.keyTimes = times
            a.calculationMode = .linear
            a.beginTime = a0
            a.duration = total
            a.fillMode = .both
            a.isRemovedOnCompletion = false
            return a
        }
        s.root.add(keyframes("position", positions), forKey: "landing.position")
        s.root.add(keyframes("transform", transforms), forKey: "landing.transform")
        if ghost == nil { s.root.add(keyframes("shadowOpacity", shadow), forKey: "landing.shadow") }
        if let ring = s.ring {
            ring.add(keyframes("bounds", rings), forKey: "landing.ring")
            ring.add(keyframes("opacity", ringAlpha), forKey: "landing.ringAlpha")
        }
        if ghost != nil { s.root.add(keyframes("opacity", alpha), forKey: "landing.ghost") }
    }

    /// The square shows its own picture now: the sticker over it fades and goes.
    private func fadeSticker() {
        guard let sticker else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + 0.03
        fade.duration = 0.16
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false
        sticker.root.add(fade, forKey: "landing.handoff")
    }

    /// Film `drawTargetSlot`: a dashed blue ring tightening round the square as the sticker gathers itself and flies
    /// (marching), then a solid ring with its glow, held 1.5 s and gone by 1.9 s.
    private func ring(_ plan: LandingPlan, hit: CGRect, k: CGFloat) {
        let a0 = plan.anticipAt, i0 = plan.impactAt
        let lead = max(0.05, i0 - a0)
        let dashed = CAShapeLayer()
        dashed.frame = bounds
        dashed.fillColor = nil
        dashed.strokeColor = UIColor(Theme.primaryBright).cgColor
        dashed.lineDashPattern = [NSNumber(value: Double(16 * k)), NSNumber(value: Double(12 * k))]
        dashed.opacity = 0
        layer.insertSublayer(dashed, at: 0)
        let steps = 24
        var paths: [Any] = [], widths: [Any] = [], alphas: [Any] = [], times: [NSNumber] = []
        for i in 0...steps {
            let an = Double(i) / Double(steps)
            let gr = CGFloat(12 * (1 - an)) * k
            let r = hit.insetBy(dx: -gr, dy: -gr)
            paths.append(UIBezierPath(roundedRect: r, cornerRadius: 14 + gr).cgPath)
            widths.append(NSNumber(value: Double((5 + 3 * an) * k)))
            alphas.append(NSNumber(value: an))
            times.append(NSNumber(value: an))
        }
        // Gone at the hit (the solid ring takes over).
        alphas[alphas.count - 1] = NSNumber(value: 1)
        for (path, values) in [("path", paths), ("lineWidth", widths), ("opacity", alphas)] {
            let a = CAKeyframeAnimation(keyPath: path)
            a.values = values
            a.keyTimes = times
            a.beginTime = a0
            a.duration = lead
            a.fillMode = .backwards
            a.isRemovedOnCompletion = false
            dashed.add(a, forKey: "landing.\(path)")
        }
        let march = CABasicAnimation(keyPath: "lineDashPhase")
        march.fromValue = 0
        march.toValue = -160 * k * CGFloat(lead)
        march.beginTime = a0
        march.duration = lead
        march.fillMode = .both
        dashed.add(march, forKey: "landing.march")

        let solid = CAShapeLayer()
        solid.frame = bounds
        solid.fillColor = nil
        solid.strokeColor = UIColor(Theme.primaryBright).cgColor
        solid.lineWidth = 7 * k
        let r = hit.insetBy(dx: -3.5 * k, dy: -3.5 * k)
        solid.path = UIBezierPath(roundedRect: r, cornerRadius: 14 + 3.5 * k).cgPath
        solid.shadowColor = UIColor(red: 42 / 255, green: 155 / 255, blue: 1, alpha: 1).cgColor
        solid.shadowOpacity = 0.6
        solid.shadowRadius = 20 * k
        solid.shadowOffset = .zero
        solid.opacity = 0
        layer.insertSublayer(solid, at: 0)
        let hold = CAKeyframeAnimation(keyPath: "opacity")
        hold.values = [0, 1, 1, 0]
        hold.keyTimes = [0, NSNumber(value: 0.08 / 1.9), NSNumber(value: 1.5 / 1.9), 1]
        hold.beginTime = i0
        hold.duration = 1.9
        hold.fillMode = .both
        hold.isRemovedOnCompletion = false
        solid.add(hold, forKey: "landing.solid")
    }

    /// Film `dexFx`: twelve light rays turning behind the square (they fade in for .12 s, out from .45 s to 1 s).
    private func rays(_ plan: LandingPlan, at c: CGPoint, k: CGFloat) {
        let L = 330 * k
        let holder = CALayer()
        holder.bounds = CGRect(x: 0, y: 0, width: 2 * L, height: 2 * L)
        holder.position = c
        holder.opacity = 0
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.frame = holder.bounds
        glow.colors = [UIColor(red: 120 / 255, green: 190 / 255, blue: 1, alpha: 0.9).cgColor,
                       UIColor(red: 120 / 255, green: 190 / 255, blue: 1, alpha: 0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        let mask = CAShapeLayer()
        mask.frame = holder.bounds
        let rays = UIBezierPath()
        for i in 0..<12 {
            let a = CGFloat(i + 1) * 2 * .pi / 12
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: L + x * cos(a) - y * sin(a), y: L + x * sin(a) + y * cos(a))
            }
            rays.move(to: pt(-10 * k, 0))
            rays.addLine(to: pt(-34 * k, -L))
            rays.addLine(to: pt(34 * k, -L))
            rays.addLine(to: pt(10 * k, 0))
            rays.close()
        }
        mask.path = rays.cgPath
        glow.mask = mask
        holder.addSublayer(glow)
        layer.insertSublayer(holder, at: 0)
        let steps = 22
        var alpha: [Any] = [], times: [NSNumber] = []
        for i in 0...steps {
            let u = 1.1 * Double(i) / Double(steps)
            let ra = Film6.outCubic(Film6.seg(u, 0, 0.12)) * (1 - Film6.seg(u, 0.45, 1.0))
            alpha.append(NSNumber(value: 0.38 * ra))
            times.append(NSNumber(value: Double(i) / Double(steps)))
        }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = alpha
        fade.keyTimes = times
        fade.beginTime = plan.impactAt
        fade.duration = 1.1
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false
        holder.add(fade, forKey: "landing.rays")
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = 0.6 * 1.1
        turn.beginTime = plan.impactAt
        turn.duration = 1.1
        turn.fillMode = .both
        turn.isRemovedOnCompletion = false
        holder.add(turn, forKey: "landing.turn")
    }

    /// Film `dexFx`: two white rings with a blue glow running out from the square (.5 s each, the second .07 s later).
    private func rings(_ plan: LandingPlan, at c: CGPoint, k: CGFloat) {
        for (d, a0, w0, R) in [(0.0, 0.75, 12.0, 300.0), (0.07, 0.45, 6.0, 380.0)] {
            let ring = CAShapeLayer()
            ring.frame = bounds
            ring.fillColor = nil
            ring.strokeColor = UIColor.white.cgColor
            ring.shadowColor = UIColor(Theme.primaryBright).cgColor
            ring.shadowOpacity = 1
            ring.shadowRadius = 24 * k
            ring.shadowOffset = .zero
            ring.opacity = 0
            layer.insertSublayer(ring, at: 0)
            let steps = 16
            var paths: [Any] = [], widths: [Any] = [], alphas: [Any] = [], times: [NSNumber] = []
            for i in 0...steps {
                let p = Double(i) / Double(steps)
                let r = CGFloat(70 + (R - 70) * Film6.outCubic(p)) * k
                paths.append(UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).cgPath)
                widths.append(NSNumber(value: (w0 * (1 - p) + 1) * Double(k)))
                alphas.append(NSNumber(value: i == steps ? 0 : a0 * (1 - p)))
                times.append(NSNumber(value: p))
            }
            for (path, values) in [("path", paths), ("lineWidth", widths), ("opacity", alphas)] {
                let a = CAKeyframeAnimation(keyPath: path)
                a.values = values
                a.keyTimes = times
                a.beginTime = plan.impactAt + d
                a.duration = 0.5
                a.fillMode = .forwards
                a.isRemovedOnCompletion = false
                ring.add(a, forKey: "landing.\(path)")
            }
        }
    }

    /// `#fx` at the hit: 44 sparks thrown up and out (stars and confetti, falling) and 8 white glints twinkling in the
    /// square — the same steps as `CCParticles` (1/60 s each: drag .982, gravity, the life running out), worked out
    /// ahead and handed over as keyframes.
    private func sparks(_ plan: LandingPlan, hit: CGRect) {
        let at = CGPoint(x: hit.midX, y: hit.midY)
        for spark in LandingSpark.burst(at: at, n: 44, speed: 6, up: 3) + LandingSpark.glints(in: hit, n: 8) {
            let shape = CAShapeLayer()
            shape.fillColor = spark.color.cgColor
            if spark.star {
                // The star's outline itself grows and shrinks (a scaled layer would scale its glow with it).
                shape.path = LandingSpark.starPath(size: spark.frames.first?.size ?? 1)
                shape.shadowColor = UIColor(red: 1, green: 245 / 255, blue: 200 / 255, alpha: 1).cgColor
                shape.shadowOpacity = 0.95
                shape.shadowRadius = 5
                shape.shadowOffset = .zero
                shape.shadowPath = shape.path
            } else {
                shape.path = CGPath(rect: CGRect(x: -0.5, y: -0.5, width: 1, height: 1), transform: nil)
            }
            shape.opacity = 0
            layer.addSublayer(shape)
            let n = spark.frames.count
            guard n > 1 else { continue }
            var positions: [Any] = [], shapes: [Any] = [], alphas: [Any] = [], times: [NSNumber] = []
            for (i, f) in spark.frames.enumerated() {
                positions.append(NSValue(cgPoint: f.at))
                if spark.star {
                    shapes.append(LandingSpark.starPath(size: f.size))
                } else {
                    shapes.append(NSValue(caTransform3D: f.transform))
                }
                alphas.append(NSNumber(value: f.alpha))
                times.append(NSNumber(value: Double(i) / Double(n - 1)))
            }
            let duration = Double(n - 1) * LandingSpark.frameStep
            let shapeKeys = spark.star ? ["path", "shadowPath"] : ["transform"]
            for (path, values) in [("position", positions), ("opacity", alphas)] + shapeKeys.map({ ($0, shapes) }) {
                let a = CAKeyframeAnimation(keyPath: path)
                a.values = values
                a.keyTimes = times
                a.beginTime = plan.impactAt
                a.duration = duration
                a.fillMode = .forwards
                a.isRemovedOnCompletion = false
                shape.add(a, forKey: "landing.\(path)")
            }
        }
    }
}

/// When and where the sticker flies (global coordinates, `CACurrentMediaTime` times), fixed as it sets off.
struct LandingPlan: Equatable {
    var start: CGPoint
    /// The curve's control point (film `bez2`: up and to the right of the stage).
    var control: CGPoint
    var target: CGRect
    var anticipAt: Double
    var launchAt: Double
    var impactAt: Double
    /// The sticker's size at the hit over its size on the stage (1.3× the square's picture).
    var arriveScale: Double
    /// How long the sticker settles in the square after the hit before the square's own picture takes over (none with
    /// アニメーション off).
    var settle: Double

    static let settleTime: Double = 0.62
}

/// The sticker as layers: its cut-out with the white border picture behind it (or the photo in its white frame).
private final class StickerLayers {
    let root = CALayer()
    /// The border (a cut-out's white copies), shrinking to nothing as it flies.
    private(set) var ring: CALayer?
    let box: CGSize
    private var fitted: CGSize = .zero
    private var pad: (x: CGFloat, y: CGFloat) = (0, 0)

    init(image: UIImage, box: CGSize, scale: CGFloat) {
        self.box = box
        root.bounds = CGRect(origin: .zero, size: box)
        root.shadowColor = UIColor(red: 15 / 255, green: 40 / 255, blue: 80 / 255, alpha: 1).cgColor
        root.shadowRadius = 10
        root.shadowOffset = CGSize(width: 0, height: 6)
        root.shadowOpacity = 0
        if Self.hasAlpha(image) {
            let shown = StickerDisplay.image(image)
            fitted = Film6.fit(aspect: image.size.width / max(1, image.size.height), in: box)
            let center = CGPoint(x: box.width / 2, y: box.height / 2)
            if let b = StickerDisplay.borderedIfReady(image) {
                let r = CALayer()
                r.contents = b.ring.cgImage
                r.contentsGravity = .resize
                r.contentsScale = scale
                pad = (b.padX, b.padY)
                r.bounds = ringBounds(border: 1)
                r.position = center
                root.addSublayer(r)
                ring = r
            }
            let pic = CALayer()
            pic.contents = shown.cgImage
            pic.contentsGravity = .resize
            pic.contentsScale = scale
            pic.bounds = CGRect(origin: .zero, size: fitted)
            pic.position = center
            root.addSublayer(pic)
        } else {
            // A photo without a cut-out: rounded, in a white frame (`CatchStickerArt`'s fallback).
            let side = min(box.width, box.height)
            let p = max(3, side * 0.045)
            let frame = CALayer()
            frame.frame = root.bounds
            frame.backgroundColor = UIColor.white.cgColor
            frame.cornerRadius = side * 0.12 + p
            frame.cornerCurve = .continuous
            root.addSublayer(frame)
            let pic = CALayer()
            pic.frame = root.bounds.insetBy(dx: p, dy: p)
            pic.contents = image.cgImage
            pic.contentsGravity = .resizeAspectFill
            pic.contentsScale = scale
            pic.cornerRadius = side * 0.12
            pic.cornerCurve = .continuous
            pic.masksToBounds = true
            root.addSublayer(pic)
        }
    }

    /// The border picture's bounds at `border` (1: full, 0: under the cut-out).
    func ringBounds(border: Double) -> CGRect {
        let g = CGFloat(max(0, min(1, border)))
        return CGRect(x: 0, y: 0, width: fitted.width * (1 + 2 * pad.x * g), height: fitted.height * (1 + 2 * pad.y * g))
    }

    private static func hasAlpha(_ image: UIImage) -> Bool {
        guard let info = image.cgImage?.alphaInfo else { return false }
        switch info {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }
}

/// One spark of the hit, its way worked out ahead with `CCParticles`' steps.
private struct LandingSpark {
    struct Frame {
        let at: CGPoint
        /// A confetti's turn and squash.
        let transform: CATransform3D
        /// A star's radius.
        let size: Double
        let alpha: Double
    }

    let star: Bool
    let color: UIColor
    let frames: [Frame]

    /// A keyframe every 3 steps (20 a second; Core Animation draws the frames in between).
    static let frameStep = 3.0 / 60

    private static let colors: [UIColor] = [0x8FD8FF, 0xB9A4FF, 0xFFD27A, 0xFF9ED2, 0x9FF0C0, 0xFFFFFF].map {
        UIColor(red: CGFloat(($0 >> 16) & 0xFF) / 255, green: CGFloat(($0 >> 8) & 0xFF) / 255, blue: CGFloat($0 & 0xFF) / 255, alpha: 1)
    }

    /// `burst(x, y, {n, speed, up, g, stars})`.
    static func burst(at c: CGPoint, n: Int, speed: Double, up: Double, g: Double = 0.16, stars: Double = 0.45) -> [LandingSpark] {
        (0..<n).map { i in
            let a = Double.random(in: 0..<1) * .pi * 2
            let v = speed * (0.3 + Double.random(in: 0..<1) * 0.9)
            let isStar = Double.random(in: 0..<1) < stars
            let w = isStar ? 5 + Double.random(in: 0..<1) * 9 : 4 + Double.random(in: 0..<1) * 5
            let h = 2.5 + Double.random(in: 0..<1) * 3
            return walk(star: isStar, color: colors[i % colors.count], x: Double(c.x), y: Double(c.y),
                        vx: cos(a) * v, vy: sin(a) * v - up, r: Double.random(in: 0..<1) * 6,
                        vr: (Double.random(in: 0..<1) - 0.5) * 0.35, w: w, h: h,
                        decay: 0.006 + Double.random(in: 0..<1) * 0.008, g: g, delay: 0)
        }
    }

    /// `glints(rect, n)`: white stars twinkling in the square, each after its own short wait.
    static func glints(in rect: CGRect, n: Int) -> [LandingSpark] {
        (0..<n).map { _ in
            walk(star: true, color: .white, x: Double(rect.minX) + Double.random(in: 0..<1) * Double(rect.width),
                 y: Double(rect.minY) + Double.random(in: 0..<1) * Double(rect.height), vx: 0, vy: -0.12, r: 0, vr: 0,
                 w: 6 + Double.random(in: 0..<1) * 9, h: 0, decay: 0.013 + Double.random(in: 0..<1) * 0.018, g: 0,
                 delay: Int(Double.random(in: 0..<1) * 40))
        }
    }

    /// The steps of `CCParticles.step()`, a keyframe every 3: its place, turn and squash (confetti) or size (stars), and
    /// its opacity (`life × 1.4`). Before its wait is over it is not drawn.
    private static func walk(star: Bool, color: UIColor, x: Double, y: Double, vx: Double, vy: Double, r: Double, vr: Double,
                             w: Double, h: Double, decay: Double, g: Double, delay: Int) -> LandingSpark {
        var x = x, y = y, vx = vx, vy = vy, r = r, life = 1.0, wait = delay
        var frames: [Frame] = []
        var step = 0
        func keep() {
            let alpha = wait > 0 ? 0 : max(0, min(1, life * 1.4))
            let size = star ? max(0.01, w * (0.35 + 0.65 * sin(max(0, life) * .pi))) : 1
            var m = CATransform3DMakeRotation(CGFloat(r), 0, 0, 1)
            m = CATransform3DScale(m, CGFloat(w), CGFloat(h * cos(r * 2.3)), 1)
            frames.append(Frame(at: CGPoint(x: x, y: y), transform: m, size: size, alpha: alpha))
        }
        keep()
        while life > 0, step < 600 {
            step += 1
            if wait > 0 {
                wait -= 1
            } else {
                life -= decay
                vy += g
                vx *= 0.982; vy *= 0.982
                x += vx; y += vy
                r += vr
            }
            if step % 3 == 0 || life <= 0 { keep() }
        }
        return LandingSpark(star: star, color: color, frames: frames)
    }

    /// `star(g, x, y, s)`: an 8-point polygon, inner radius .22, around the origin at radius `size`.
    static func starPath(size s: Double) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<8 {
            let a = Double(i) * .pi / 4, r = i % 2 == 1 ? s * 0.22 : s
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
