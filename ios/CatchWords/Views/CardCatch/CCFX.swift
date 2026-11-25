import SwiftUI

// Particles and lights of the catch: the star that flies into the dex (CatchLanding: burst / glints / trail /
// fxLoop, .starlight) and the shutter's white flash.

/// `#fx`: confetti and star sparks in design points, stepped once per 1/60 s like the prototype's rAF loop.
final class CCParticles {
    private struct P {
        var star: Bool
        var x: Double, y: Double, vx: Double, vy: Double
        var r: Double, vr: Double, w: Double, h: Double
        var color: Color
        var life: Double, decay: Double, g: Double
        var delay: Int
    }

    private static let colors: [Color] = [Color(hex: 0x8FD8FF), Color(hex: 0xB9A4FF), Color(hex: 0xFFD27A),
                                          Color(hex: 0xFF9ED2), Color(hex: 0x9FF0C0), Color(hex: 0xFFFFFF)]
    private var parts: [P] = []
    private var last: Double?
    private var acc = 0.0
    var calm = false

    var isEmpty: Bool { parts.isEmpty }

    /// `burst(x, y, {n, speed, up, g, stars})`.
    func burst(_ x: Double, _ y: Double, n: Int = 70, speed: Double = 7, up: Double = 3, g: Double = 0.16, stars: Double = 0.45) {
        guard !calm else { return }
        for i in 0..<n {
            let a = Double.random(in: 0..<1) * .pi * 2
            let v = speed * (0.3 + Double.random(in: 0..<1) * 0.9)
            let isStar = Double.random(in: 0..<1) < stars
            parts.append(P(star: isStar, x: x, y: y, vx: cos(a) * v, vy: sin(a) * v - up,
                           r: Double.random(in: 0..<1) * 6, vr: (Double.random(in: 0..<1) - 0.5) * 0.35,
                           w: isStar ? 5 + Double.random(in: 0..<1) * 9 : 4 + Double.random(in: 0..<1) * 5,
                           h: 2.5 + Double.random(in: 0..<1) * 3, color: Self.colors[i % Self.colors.count],
                           life: 1, decay: 0.006 + Double.random(in: 0..<1) * 0.008, g: g, delay: 0))
        }
    }

    /// `glints(rect, n)`.
    func glints(_ rect: CGRect, n: Int = 12) {
        guard !calm else { return }
        for _ in 0..<n {
            parts.append(P(star: true, x: rect.minX + Double.random(in: 0..<1) * rect.width,
                           y: rect.minY + Double.random(in: 0..<1) * rect.height, vx: 0, vy: -0.12, r: 0, vr: 0,
                           w: 6 + Double.random(in: 0..<1) * 9, h: 0, color: .white, life: 1,
                           decay: 0.013 + Double.random(in: 0..<1) * 0.018, g: 0, delay: Int(Double.random(in: 0..<1) * 40)))
        }
    }

    /// `trail(x, y)`: two small sparks.
    func trail(_ x: Double, _ y: Double) {
        guard !calm else { return }
        for _ in 0..<2 {
            parts.append(P(star: true, x: x + (Double.random(in: 0..<1) - 0.5) * 20, y: y + (Double.random(in: 0..<1) - 0.5) * 20,
                           vx: (Double.random(in: 0..<1) - 0.5) * 0.8, vy: (Double.random(in: 0..<1) - 0.5) * 0.8, r: 0, vr: 0,
                           w: 4 + Double.random(in: 0..<1) * 7, h: 0,
                           color: Double.random(in: 0..<1) < 0.5 ? .white : Color(hex: 0xFFE7A3),
                           life: 1, decay: 0.035, g: 0, delay: 0))
        }
    }

    func advance(to now: Double) {
        guard let l = last else { last = now; return }
        acc += min(0.25, now - l)
        last = now
        while acc >= 1.0 / 60 {
            acc -= 1.0 / 60
            step()
        }
    }

    private func step() {
        parts.removeAll { $0.life <= 0 }
        for i in parts.indices {
            if parts[i].delay > 0 { parts[i].delay -= 1; continue }
            parts[i].life -= parts[i].decay
            parts[i].vy += parts[i].g
            parts[i].vx *= 0.982; parts[i].vy *= 0.982
            parts[i].x += parts[i].vx; parts[i].y += parts[i].vy
            parts[i].r += parts[i].vr
        }
    }

    /// `star(g, x, y, s)`: an 8-point polygon, inner radius .22.
    private static func starPath(_ x: Double, _ y: Double, _ s: Double) -> Path {
        var p = Path()
        for i in 0..<8 {
            let a = Double(i) * .pi / 4, r = i % 2 == 1 ? s * 0.22 : s
            let pt = CGPoint(x: x + cos(a) * r, y: y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    func draw(_ ctx: inout GraphicsContext) {
        for p in parts where p.delay <= 0 && !p.star && p.life > 0 {
            var c = ctx
            c.opacity = max(0, min(1, p.life * 1.4))
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(p.r))
            c.scaleBy(x: 1, y: cos(p.r * 2.3))
            c.fill(Path(CGRect(x: -p.w / 2, y: -p.h / 2, width: p.w, height: p.h)), with: .color(p.color))
        }
        // No star to draw: no layer either (a blurred layer the size of the canvas, made on every frame for nothing).
        guard parts.contains(where: { $0.delay <= 0 && $0.star && $0.life > 0 }) else { return }
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .rgba(255, 245, 200, 0.95), radius: 5))
            for p in parts where p.delay <= 0 && p.star && p.life > 0 {
                var c = layer
                c.opacity = max(0, min(1, p.life * 1.4))
                c.fill(Self.starPath(p.x, p.y, p.w * (0.35 + 0.65 * sin(p.life * .pi))), with: .color(p.color))
            }
        }
    }
}

/// `.starlight` (mkStar): a white four-point star with a warm glow, twinkling (`twk` .45 s alternate), and
/// a second smaller star turned 45° behind it.
struct CCStarlight: View {
    var size: CGFloat = 50
    let now: Double
    let calm: Bool

    var body: some View {
        // twk: scale .85 ↔ 1.12, ease-in-out, alternate
        let tw: Double = {
            guard !calm else { return 1 }
            let cyc = now.truncatingRemainder(dividingBy: 0.9) / 0.45
            let f = cyc < 1 ? cyc : 2 - cyc
            return 0.85 + (1.12 - 0.85) * CCBezier.easeInOut(f)
        }()
        ZStack {
            glow(CCSVGPath(d: CCIcons.star).fill(.white))
                .frame(width: size, height: size)
                .scaleEffect(tw)
            glow(CCSVGPath(d: CCIcons.star).fill(.white))
                .frame(width: size * 0.56, height: size * 0.56)
                .rotationEffect(.degrees(45))
                .opacity(0.85)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    /// drop-shadow(0 0 3px #fff) drop-shadow(0 0 9px #FFE7A3) drop-shadow(0 0 16px rgba(160,200,255,.9))
    private func glow<V: View>(_ v: V) -> some View {
        v.shadow(color: .white, radius: 1.5)
            .shadow(color: Color(hex: 0xFFE7A3), radius: 4.5)
            .shadow(color: .rgba(160, 200, 255, 0.9), radius: 8)
    }
}

/// Shutter flash for the capture screen: `#flash.animate([0, 1 @12%, 0], {480 ms, ease-out})` (1 ms when calm).
struct CCShutterFlash: View {
    let start: Double?
    let calm: Bool

    var body: some View {
        if let start {
            TimelineView(.animation) { _ in
                let now = CCClock.now
                let anim = CCAnim([[0], [1], [0]], offsets: [0, 0.12, 1], duration: calm ? 0.001 : 0.48,
                                  easing: .easeOut, start: start)
                let o = anim.sample(now)?.first ?? 0
                Color.white.opacity(max(0, min(1, o)))
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
