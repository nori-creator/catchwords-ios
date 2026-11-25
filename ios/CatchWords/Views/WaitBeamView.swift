import UIKit

/// The wait light (`.waitBeam`) as layers Core Animation moves by itself (owner 2026-11-25: 「青い光も途中で止まらないように
/// して」): once the animations are added, the render server runs them — nothing is drawn by the app per frame, so the
/// light keeps running while the main thread is busy (results arriving, a card being laid out).
///
/// How the shader's comet (`ThirdParty/BorderBeam/BorderBeam.metal`) is rebuilt from layers:
/// - The shader's soft glow is a chain of 24 round lights laid along the comet's stretch of the border. Here each light
///   is a small layer with a ready-made picture (`WaitBeamLights`), and each one travels the border's path for ever
///   (`CAKeyframeAnimation` along the path, paced = one speed all the way round, clockwise), a little behind the next.
///   The pale tail … the strong head are the lights' own colours and strengths.
/// - The glow (`glowHost`) is cut to the box's shape: the light falls inside the box only, as the shader's.
/// - The bright line on the border (`lineHost`) is a second chain of the same lights seen through a thin ring (a mask
///   that never moves): where the comet is, the ring shows its colour.
///
/// Sizes, strengths and colours follow the shader's numbers; a still frame of the two was compared pixel by pixel
/// (within about 2 % of the light, the difference is in the line's last points at both ends).
final class WaitBeamView: UIView {
    var look: WaitBeamLook {
        didSet { if look != oldValue { setNeedsLayout() } }
    }

    private static let orbitKey = "waitBeam.orbit"
    private static let fadeKey = "waitBeam.fadeIn"

    /// Everything the light draws; fades in once.
    private let root = CALayer()
    private let glowHost = CALayer()
    private let lineHost = CALayer()
    private let ring = CAShapeLayer()
    private var glowLights: [CALayer] = []
    private var lineLights: [CALayer] = []

    /// What the layers were last laid out for.
    private var builtSize: CGSize = .zero
    private var builtLook: WaitBeamLook?
    /// The border, once round: what every light travels.
    private var orbit: CGPath?
    /// The clock the comet's place is counted from, so it carries on from where it was when the box changes size or
    /// the app comes back (never from the start again).
    private var anchor = CACurrentMediaTime()
    private let startHead = Double.random(in: 0..<1)
    private var fadedIn = false

    init(look: WaitBeamLook) {
        self.look = look
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true

        glowHost.masksToBounds = true
        ring.fillColor = nil
        ring.strokeColor = UIColor.black.cgColor
        lineHost.mask = ring
        root.addSublayer(glowHost)
        root.addSublayer(lineHost)
        layer.addSublayer(root)
        // The tail's lights first: the head's are on top.
        for _ in 0..<WaitBeamLights.count {
            let glow = CALayer(), line = CALayer()
            glowHost.addSublayer(glow)
            lineHost.addSublayer(line)
            glowLights.append(glow)
            lineLights.append(line)
        }
        // iOS removes a layer's animations when the app goes to the background: put them back when it returns.
        NotificationCenter.default.addObserver(self, selector: #selector(appReturned),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != builtSize || look != builtLook { rebuild() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        if !fadedIn {
            fadedIn = true
            if !look.still {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = WaitBeamLook.fade
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                root.add(fade, forKey: Self.fadeKey)
            }
        }
        // A layer that left the window lost its animations too.
        syncMotion()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        // SwiftUI may move the view to another container without it leaving the window.
        if superview != nil { syncMotion() }
    }

    @objc private func appReturned() {
        syncMotion()
    }

    /// Where the comet's head is now: a lap's fraction, clockwise from the middle of the right edge.
    private var headNow: CGFloat {
        if look.still { return WaitBeamLook.stillHead }
        let laps = startHead + (CACurrentMediaTime() - anchor) / WaitBeamLook.lap
        return CGFloat(laps - laps.rounded(.down))
    }

    /// Lays the layers out for the box as it is now (its size, its corners, the surface) and starts them.
    private func rebuild() {
        builtSize = bounds.size
        builtLook = look
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let size = bounds.size
        guard let track = WaitBeamTrack(size: size, cornerRadius: look.cornerRadius) else {
            root.isHidden = true
            orbit = nil
            syncMotion()
            return
        }
        let box = CGRect(origin: .zero, size: size)
        root.isHidden = false
        root.frame = box
        glowHost.frame = box
        lineHost.frame = box
        glowHost.cornerRadius = track.radius
        orbit = track.path(closed: false)

        // The line: a ring just inside the border.
        let width = look.lineWidth
        let inner = CGSize(width: size.width - width, height: size.height - width)
        if let ringTrack = WaitBeamTrack(size: inner, cornerRadius: track.radius - width / 2) {
            ring.frame = CGRect(origin: CGPoint(x: width / 2, y: width / 2), size: inner)
            ring.lineWidth = width
            ring.contentsScale = max(1, traitCollection.displayScale)
            ring.path = ringTrack.path(closed: true)
        } else {
            ring.path = nil
        }

        // The lights: as far apart as the shader's, and as wide (its `orbitGlowBlobs`).
        let count = WaitBeamLights.count
        let apart = look.arc * track.length / CGFloat(count)
        let glowSigma = max(look.glow * 0.7, 0.8 * apart)
        let lineSigma = max(0.8 * apart, 1)
        let glow = WaitBeamLights.pictures(dark: look.dark, line: false, share: Double(apart / (glowSigma * 2.50663)))
        let line = WaitBeamLights.pictures(dark: look.dark, line: true, share: Double(apart / (lineSigma * 2.50663)))
        let head = headNow
        for k in 0..<count {
            // Where the light rests (reduced motion, or before its animation is on).
            let at = track.point(at: head - look.arc * (1 - WaitBeamLights.place(k)))
            let glowSide = 2 * CGFloat(WaitBeamLights.reach) * glowSigma
            let lineSide = 2 * CGFloat(WaitBeamLights.reach) * lineSigma
            glowLights[k].bounds = CGRect(x: 0, y: 0, width: glowSide, height: glowSide)
            glowLights[k].position = at
            glowLights[k].contents = glow.images[k]
            glowLights[k].opacity = glow.opacity
            lineLights[k].bounds = CGRect(x: 0, y: 0, width: lineSide, height: lineSide)
            lineLights[k].position = at
            lineLights[k].contents = line.images[k]
            lineLights[k].opacity = line.opacity
        }
        syncMotion()
    }

    /// Puts every light's lap on (or takes it off: reduced motion, no window, no box). Safe to call again at any time:
    /// the laps are counted from `anchor`, so the comet carries on from where it is.
    private func syncMotion() {
        let count = WaitBeamLights.count
        guard window != nil, !look.still, let orbit else {
            for light in glowLights + lineLights { light.removeAnimation(forKey: Self.orbitKey) }
            return
        }
        let lap = WaitBeamLook.lap
        // Keep the anchor within one lap of now (the comet's place is the same).
        anchor += ((CACurrentMediaTime() - anchor) / lap).rounded(.down) * lap
        let base = root.convertTime(anchor, from: nil)
        for k in 0..<count {
            // Light k is `arc × (1 − place)` of a lap behind the head. An animation that began `ahead` laps ago is
            // `ahead` of the way round now.
            let laps = startHead - Double(look.arc) * (1 - Double(WaitBeamLights.place(k)))
            let ahead = laps - laps.rounded(.down)
            for light in [glowLights[k], lineLights[k]] {
                let run = CAKeyframeAnimation(keyPath: "position")
                run.path = orbit
                run.calculationMode = .paced   // one speed along the whole path
                run.duration = lap
                run.repeatCount = .infinity
                run.isRemovedOnCompletion = false
                run.beginTime = base - ahead * lap
                light.add(run, forKey: Self.orbitKey)
            }
        }
    }
}

/// The border of a rounded box as a track: clockwise from the middle of the right edge, as the shader measures it
/// (`boundaryPoint` in `BorderBeam.metal`). Circular corners, the radius held to half the shorter side.
nonisolated struct WaitBeamTrack {
    let size: CGSize
    let radius: CGFloat
    /// Once round (points).
    let length: CGFloat

    init?(size: CGSize, cornerRadius: CGFloat) {
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1 else { return nil }
        let r = max(0, min(cornerRadius, min(size.width, size.height) / 2))
        self.size = size
        radius = r
        length = 2 * (size.width - 2 * r) + 2 * (size.height - 2 * r) + 2 * CGFloat.pi * r
    }

    /// The point `lap` of the way round (any number: 1.25 and −0.75 are 0.25), in the box's own coordinates.
    func point(at lap: CGFloat) -> CGPoint {
        let hx = size.width / 2, hy = size.height / 2, r = radius
        let ix = hx - r, iy = hy - r
        let corner = CGFloat.pi * r / 2
        var s = (lap - lap.rounded(.down)) * length
        // right edge, down from its middle
        if s < iy { return CGPoint(x: hx + hx, y: hy + s) }
        s -= iy
        if s < corner { return arc(centerX: ix, centerY: iy, from: 0, along: s) }
        s -= corner
        // bottom edge, leftwards
        if s < 2 * ix { return CGPoint(x: hx + ix - s, y: hy + hy) }
        s -= 2 * ix
        if s < corner { return arc(centerX: -ix, centerY: iy, from: CGFloat.pi / 2, along: s) }
        s -= corner
        // left edge, upwards
        if s < 2 * iy { return CGPoint(x: 0, y: hy + iy - s) }
        s -= 2 * iy
        if s < corner { return arc(centerX: -ix, centerY: -iy, from: CGFloat.pi, along: s) }
        s -= corner
        // top edge, rightwards
        if s < 2 * ix { return CGPoint(x: hx - ix + s, y: 0) }
        s -= 2 * ix
        if s < corner { return arc(centerX: ix, centerY: -iy, from: CGFloat.pi * 1.5, along: s) }
        s -= corner
        // right edge, down to its middle
        return CGPoint(x: hx + hx, y: hy - iy + s)
    }

    /// A point on a corner: `along` points past the angle `from` (only called when the radius is not 0).
    private func arc(centerX: CGFloat, centerY: CGFloat, from: CGFloat, along: CGFloat) -> CGPoint {
        let angle = from + along / radius
        return CGPoint(x: size.width / 2 + centerX + radius * cos(angle),
                       y: size.height / 2 + centerY + radius * sin(angle))
    }

    /// The same track as a path. `closed` for a stroke (the ring); open for an animation (no segment without length).
    func path(closed: Bool) -> CGPath {
        let w = size.width, h = size.height, r = radius
        let path = CGMutablePath()
        path.move(to: CGPoint(x: w, y: h / 2))
        path.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w / 2, y: h), radius: r)
        path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h / 2), radius: r)
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: w / 2, y: 0), radius: r)
        path.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: h / 2), radius: r)
        if h / 2 - r > 0.01 { path.addLine(to: CGPoint(x: w, y: h / 2)) }
        if closed { path.closeSubpath() }
        return path
    }
}

/// The comet's lights as pictures: 24 round, soft dots from the pale tail to the strong head, drawn once and kept.
/// Laid along the border and blended one over the next, they add up to the shader's comet: its bell-shaped strength
/// (lighter toward both ends), its colours, its glow falling off across the border as a Gaussian.
enum WaitBeamLights {
    /// As many as the shader's glow (K = 24).
    static let count = 24
    /// A picture reaches this many σ from the light's centre (the shader stops drawing at 3 σ too).
    static let reach: Double = 3
    /// The shader's line (crisp 1 + halo 0.6 on the border) spread over the ring's width.
    private static let lineGain: Double = 1.7
    /// A light's share of the chain's strength when σ is 0.8 × the distance between two lights — the shader's rule for
    /// all but short borders. On a short border the lights sit closer (for their width) and each gives less.
    private static let fullShare: Double = 1 / (0.8 * 2.50663)
    private static let shareSteps = 20
    private static let tableSteps = 64

    /// Where light `k` is in the comet: 0 = the tail's end … 1 = the head's.
    static func place(_ k: Int) -> CGFloat {
        (CGFloat(k) + 0.5) / CGFloat(count)
    }

    private struct Key: Hashable {
        let dark: Bool
        let line: Bool
        let step: Int
    }

    private static var kept: [Key: [CGImage?]] = [:]

    /// The 24 pictures for a surface (`dark`), for the glow or the line, when each light carries `share` of the
    /// chain's strength (the lights' distance ÷ (σ √2π)). Pictures are drawn for the share rounded up to a 20th; the
    /// rest is the layers' opacity.
    static func pictures(dark: Bool, line: Bool, share: Double) -> (images: [CGImage?], opacity: Float) {
        let wanted = min(fullShare, max(0.001, share))
        let step = min(shareSteps, max(1, Int((wanted / fullShare * Double(shareSteps) - 1e-9).rounded(.up))))
        let drawn = fullShare * Double(step) / Double(shareSteps)
        let key = Key(dark: dark, line: line, step: step)
        let images: [CGImage?]
        if let have = kept[key] {
            images = have
        } else {
            if kept.count >= 12 { kept.removeAll() }
            images = (0..<count).map { picture(of: $0, dark: dark, line: line, share: drawn) }
            kept[key] = images
        }
        return (images, Float(min(1, wanted / drawn)))
    }

    /// How strong the comet is at light `k` — its opacity on the border, 0…1 — and its colour there.
    /// The shader's: brightness × (line or glow) × the bell along the comet × the palette's own opacity.
    static func light(_ k: Int, dark: Bool, line: Bool) -> (strength: Double, color: WaitBeamPalette.RGBA) {
        let t = Double(place(k))
        let color = WaitBeamPalette.sample(dark: dark, at: t)
        let bell = sin(Double.pi * t)
        let strength = line
            ? min(0.995, WaitBeamLook.intensity * lineGain * pow(bell, 1.2) * color.a)
            : min(0.98, WaitBeamLook.intensity * 0.55 * pow(bell, 1.6) * color.a)
        return (strength, color)
    }

    /// One light's opacity from its centre (index 0) out to `reach` σ (the last index), for a comet of `strength`.
    ///
    /// Layers are blended one over the next, the shader adds its lights up; so a light is not a plain Gaussian here.
    /// The glow: the opacity whose chain, blended, gives exactly strength × exp(−d²/2σ²) at d from the border —
    /// −ln(1 − T·g) written as the sum of Gaussians Tⁿ/n · exp(−n d²/2σ²), each one the chain of a round light.
    /// The line only has to be right on the border itself (the ring hides the rest): (1 − T) to the light's share.
    static func falloff(strength: Double, share: Double, line: Bool) -> [Double] {
        var table: [Double] = []
        table.reserveCapacity(tableSteps + 1)
        for i in 0...tableSteps {
            let u = reach * Double(i) / Double(tableSteps)
            var alpha = 0.0
            if line {
                alpha = 1 - pow(1 - strength, share * exp(-u * u / 2))
            } else {
                var sum = 0.0
                var power = strength
                var n = 1.0
                while power > 1e-4 && n <= 80 {
                    sum += power / n.squareRoot() * exp(-n * u * u / 2)
                    power *= strength
                    n += 1
                }
                alpha = 1 - exp(-share * sum)
            }
            // nothing left at the picture's edge
            let edge = min(1, max(0, (reach - u) / (0.2 * reach)))
            table.append(alpha * edge * edge * (3 - 2 * edge))
        }
        return table
    }

    /// Light `k` as a small picture (premultiplied sRGB); the layer stretches it to the light's size.
    private static func picture(of k: Int, dark: Bool, line: Bool, share: Double) -> CGImage? {
        let (strength, color) = light(k, dark: dark, line: line)
        let table = falloff(strength: strength, share: share, line: line)
        let side = line ? 32 : 40
        let half = Double(side) / 2
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let dx = Double(x) + 0.5 - half, dy = Double(y) + 0.5 - half
                let at = (dx * dx + dy * dy).squareRoot() / half * Double(tableSteps)
                guard at < Double(tableSteps) else { continue }
                let i = Int(at)
                let f = at - Double(i)
                let alpha = table[i] * (1 - f) + table[i + 1] * f
                let o = (y * side + x) * 4
                bytes[o] = byte(color.r * alpha)
                bytes[o + 1] = byte(color.g * alpha)
                bytes[o + 2] = byte(color.b * alpha)
                bytes[o + 3] = byte(alpha)
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(min(255, max(0, (value * 255).rounded())))
    }
}
