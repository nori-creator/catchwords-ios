import SwiftUI
import UIKit

// Concept film v6 (scratchpad catchfilm js6/concepts6.js: `dGet`, `getTimes`, `getStage`, `stageFloor`, `getText`,
// `wordPop`, `star4`; js6/core.js `sticker`): what happens after a tag is tapped. The choose screen (film "D") and
// the GET moment draw the same scene here — the app's page over the photo, the lit stage, the sticker and its floor —
// so the hand-over from one screen to the other cannot be seen. The film's canvas is one iPhone screen (1080 × 2340
// px); its positions are kept as fractions of the screen, its lengths as fractions of the width.

/// The film's easings, timeline and geometry.
nonisolated enum Film6 {
    static let canvasW: Double = 1080
    static let canvasH: Double = 2340

    static func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b, max(a, x)) }
    static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        let k = CGFloat(t)
        return CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }
    static func lerp(_ a: CGSize, _ b: CGSize, _ t: Double) -> CGSize {
        let k = CGFloat(t)
        return CGSize(width: a.width + (b.width - a.width) * k, height: a.height + (b.height - a.height) * k)
    }
    static func outCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func inCubic(_ x: Double) -> Double { x * x * x }
    static func inOutCubic(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    static func outBack(_ x: Double, _ s: Double = 1.7) -> Double { 1 + (s + 1) * pow(x - 1, 3) + s * pow(x - 1, 2) }
    /// The film's damped spring (SwiftUI-style response / dampingFraction), its step response at `t`.
    static func spring(_ t: Double, response: Double, damping: Double) -> Double {
        guard t > 0 else { return 0 }
        let w = 2 * Double.pi / response, z = damping
        if z >= 1 { return 1 - (1 + w * t) * exp(-w * t) }
        let wd = w * (1 - z * z).squareRoot()
        return 1 - exp(-z * w * t) * (cos(wd * t) + (z * w / wd) * sin(wd * t))
    }
    /// The film's hash noise (`rnd`).
    static func rnd(_ i: Double) -> Double {
        let x = sin(i * 127.1 + 311.7) * 43758.5453
        return x - floor(x)
    }
    static func bez2(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ u: Double) -> CGPoint {
        let u = CGFloat(u), v = 1 - u
        return CGPoint(x: v * v * p0.x + 2 * v * u * p1.x + u * u * p2.x,
                       y: v * v * p0.y + 2 * v * u * p1.y + u * u * p2.y)
    }

    // MARK: Times after the choice P (`getTimes`)

    static let stageIn0 = 0.14, stageIn1 = 0.8
    static let rise = 0.18
    static let cut = 0.32
    /// G: the voice says the word.
    static let voice = 0.62
    /// The characters land one per syllable from G + .04, this far apart.
    static let charStep = 0.19
    static let meaning = 1.15
    static let catchT = 1.32
    /// The texts fade (.25 s) …
    static let out = 2.9
    /// … and the word goes into the 図鑑.
    static let open = 3.0
    /// The choose screen hands over to the GET screen once its card has folded away (P + .5); a thing with one
    /// way to say it has no card (P = tap + .3, handed over at P + .4).
    static let handoff = 0.5
    static let singleChoiceDelay = 0.3
    static let handoffSingle = 0.4

    // MARK: Geometry (film px → this screen)

    /// A y on the film's canvas, on a screen `h` tall.
    static func y(_ px: Double, _ h: CGFloat) -> CGFloat { CGFloat(px / canvasH) * h }
    /// A length on the film's canvas, on a screen `w` wide.
    static func len(_ px: Double, _ w: CGFloat) -> CGFloat { CGFloat(px / canvasW) * w }

    static let dPosY = 560.0, getPosY = 1060.0, floorY = 1388.0
    /// The film's cup cut-out is 1172 px tall; the sticker is drawn at D_S .34 of it on the choose screen and at
    /// GET_S .5 on the stage. Other things keep that height (narrower than the box) or the box's width.
    static func stickerSize(aspect: CGFloat, screen: CGSize, get: Bool) -> CGSize {
        let a = aspect > 0.05 ? aspect : 1
        let h = y(1172 * (get ? 0.5 : 0.34), screen.height)
        let wMax = screen.width * (get ? 0.5 : 0.36)
        var s = CGSize(width: h * a, height: h)
        if s.width > wMax { s = CGSize(width: wMax, height: wMax / a) }
        return s
    }

    /// The largest size of `aspect` inside `box`.
    static func fit(aspect: CGFloat, in box: CGSize) -> CGSize {
        let a = aspect > 0.05 ? aspect : 1
        if box.width / max(box.height, 1) > a { return CGSize(width: box.height * a, height: box.height) }
        return CGSize(width: box.width, height: box.width / a)
    }

    /// Where the sticker is: lifted from its place in the photo to the top of the page (spring .62 / .8, from the
    /// tap), then from the choice gliding down onto the stage and growing (spring .55 / .8, from P + .18), bobbing.
    struct Pose {
        var center: CGPoint
        var size: CGSize
        /// 0 → 1 (up to 1.08 with the spring): on its way from the top of the page to the stage.
        var m: Double
        /// The pose's centre without the bob (the page's glow follows it).
        var still: CGPoint
    }

    static func pose(screen: CGSize, aspect: CGFloat, start: CGRect?, sinceTap: Double, sinceChoice: Double?,
                     live: Double, bobWeight: Double, calm: Bool) -> Pose {
        let up = start == nil || calm ? 1 : clamp(spring(sinceTap - 0.05, response: 0.62, damping: 0.8))
        let dCenter = CGPoint(x: screen.width / 2, y: y(dPosY, screen.height))
        let gCenter = CGPoint(x: screen.width / 2, y: y(getPosY, screen.height))
        let dSize = stickerSize(aspect: aspect, screen: screen, get: false)
        let gSize = stickerSize(aspect: aspect, screen: screen, get: true)
        let s0 = start.map { fit(aspect: aspect, in: $0.size) } ?? dSize
        let c0 = start.map { CGPoint(x: $0.midX, y: $0.midY) } ?? dCenter
        let pc = lerp(c0, dCenter, up), ps = lerp(s0, dSize, up)
        var m = 0.0
        if let tc = sinceChoice {
            m = calm ? seg(tc, rise, rise + 0.2) : clamp(spring(tc - rise, response: 0.55, damping: 0.8), 0, 1.08)
        }
        let still = lerp(pc, gCenter, m)
        var center = still
        if !calm { center.y += CGFloat(sin(live * 2.6) * bobWeight) * len(10, screen.width) }
        return Pose(center: center, size: lerp(ps, gSize, m), m: m, still: still)
    }
}

// MARK: - The thing's own colour

/// The thing's warm tone as light (film `getPalette`): the average colour of its opaque mid-tone pixels lifted to a
/// luminous pastel (HSL lightness .89, saturation ×1.6 up to .8), and its lightest tone (.93, ×1.4 up to .7).
nonisolated struct StagePalette: Equatable, Sendable {
    struct RGB: Equatable, Sendable {
        var r: Double, g: Double, b: Double
        func color(_ a: Double) -> Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a) }
    }

    var glow: RGB
    var glow2: RGB

    /// Without a picture: the app's own pale blue.
    static let plain = StagePalette(glow: RGB(r: 221, g: 238, b: 255), glow2: RGB(r: 234, g: 244, b: 255))

    static func make(from image: UIImage?) -> StagePalette {
        guard let cg = image?.cgImage, cg.width > 0, cg.height > 0 else { return .plain }
        let w = 48, h = max(1, min(96, Int((48 * Double(cg.height) / Double(cg.width)).rounded())))
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = data.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return .plain }
        var mid = (r: 0.0, g: 0.0, b: 0.0, n: 0.0)
        var all: [(Double, Double, Double, Double)] = []
        for i in stride(from: 0, to: data.count, by: 4) where data[i + 3] > 200 {
            let a = Double(data[i + 3]) / 255
            let r = Double(data[i]) / a, g = Double(data[i + 1]) / a, b = Double(data[i + 2]) / a
            let l = 0.299 * r + 0.587 * g + 0.114 * b
            all.append((r, g, b, l))
            if l > 70, l < 200 { mid = (mid.r + r, mid.g + g, mid.b + b, mid.n + 1) }
        }
        guard !all.isEmpty else { return .plain }
        let warm: (Double, Double, Double)
        if mid.n > 0 {
            warm = (mid.r / mid.n, mid.g / mid.n, mid.b / mid.n)
        } else {
            let n = Double(all.count)
            warm = (all.reduce(0) { $0 + $1.0 } / n, all.reduce(0) { $0 + $1.1 } / n, all.reduce(0) { $0 + $1.2 } / n)
        }
        let top = all.sorted { $0.3 > $1.3 }.prefix(max(1, all.count / 4))
        let n = Double(top.count)
        let light = (top.reduce(0) { $0 + $1.0 } / n, top.reduce(0) { $0 + $1.1 } / n, top.reduce(0) { $0 + $1.2 } / n)
        return StagePalette(glow: hsl(warm, l: 0.89, sMul: 1.6, sMax: 0.8), glow2: hsl(light, l: 0.93, sMul: 1.4, sMax: 0.7))
    }

    /// Film `hslAdj`: the same hue at lightness `l`, saturation × `sMul` (at most `sMax`).
    static func hsl(_ c: (Double, Double, Double), l: Double, sMul: Double, sMax: Double) -> RGB {
        let r = min(1, c.0 / 255), g = min(1, c.1 / 255), b = min(1, c.2 / 255)
        let mx = max(r, g, b), mn = min(r, g, b)
        var h = 0.0, s = 0.0
        let l0 = (mx + mn) / 2
        if mx != mn {
            let d = mx - mn
            s = l0 > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
            h /= 6
        }
        s = min(sMax, s * sMul)
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
        func f(_ t0: Double) -> Double {
            let t = (t0 + 1).truncatingRemainder(dividingBy: 1)
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return RGB(r: (f(h + 1.0 / 3) * 255).rounded(), g: (f(h) * 255).rounded(), b: (f(h - 1.0 / 3) * 255).rounded())
    }
}

// MARK: - The sticker

/// The photo cropped round a thing (orientation-safe), for the sticker while its cut-out is not ready.
enum StickerCrop {
    /// `box`: 0–1 of the photo (nil = the whole photo), widened by 8% each side.
    static func image(_ photo: UIImage?, box: CGRect?) -> UIImage? {
        guard let photo else { return nil }
        guard let b = box, b.width > 0.01, b.height > 0.01 else { return photo }
        let size = photo.size
        var r = CGRect(x: b.minX * size.width, y: b.minY * size.height, width: b.width * size.width, height: b.height * size.height)
        r = r.insetBy(dx: -r.width * 0.08, dy: -r.height * 0.08).intersection(CGRect(origin: .zero, size: size))
        guard r.width > 4, r.height > 4 else { return photo }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let out = CGSize(width: min(r.width, 700), height: min(r.width, 700) * r.height / r.width)
        let k = out.width / r.width
        return UIGraphicsImageRenderer(size: out, format: format).image { _ in
            photo.draw(in: CGRect(x: -r.minX * k, y: -r.minY * k, width: size.width * k, height: size.height * k))
        }
    }
}

/// The thing as a sticker (film `sticker()`): its cut-out, a white die-cut border that grows in (`border` 0 → 1),
/// a white sheen sweeping across (`sheen` 0 → 1) and the holographic sheen of the catch (`holo` 0 → 1). Without a
/// cut-out yet, the photo round the thing in a rounded white frame.
struct CatchStickerArt: View {
    let cut: UIImage?
    let fallback: UIImage?
    let size: CGSize
    var border: Double = 1
    var sheen: Double = -1
    var holo: Double = -1

    var body: some View {
        Group {
            if let cut {
                cutout(cut)
            } else if let fallback {
                let pad = max(3, min(size.width, size.height) * 0.045)
                Image(uiImage: fallback)
                    .resizable()
                    .scaledToFill()
                    .frame(width: max(1, size.width - 2 * pad), height: max(1, size.height - 2 * pad))
                    .clipShape(.rect(cornerRadius: min(size.width, size.height) * 0.12, style: .continuous))
                    .padding(pad)
                    .background(Color.white, in: .rect(cornerRadius: min(size.width, size.height) * 0.12 + pad, style: .continuous))
                    .overlay { sweep(sheen, holo).clipShape(.rect(cornerRadius: min(size.width, size.height) * 0.12 + pad, style: .continuous)) }
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    private func cutout(_ cut: UIImage) -> some View {
        let edge = max(2, min(size.width, size.height) * 0.04) * CGFloat(border)
        return ZStack {
            if border > 0.001 {
                ZStack {
                    ForEach(0..<12, id: \.self) { i in
                        let a = CGFloat(i) / 12 * 2 * .pi
                        Image(uiImage: cut)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.white)
                            .offset(x: cos(a) * edge, y: sin(a) * edge)
                    }
                }
                .opacity(min(1, border * 1.6))
            }
            Image(uiImage: cut)
                .resizable()
                .scaledToFit()
            if (sheen > 0 && sheen < 1) || (holo > 0 && holo < 1) {
                sweep(sheen, holo)
                    .mask { Image(uiImage: cut).resizable().scaledToFit() }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// The sheen (white, film .55) and the holographic band (cyan → pink → yellow → blue), each a diagonal band.
    @ViewBuilder
    private func sweep(_ sheen: Double, _ holo: Double) -> some View {
        ZStack {
            if sheen > 0 && sheen < 1 {
                let p = -0.35 + sheen * 1.7
                LinearGradient(stops: Self.band(p, width: 0.16, colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)]),
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            if holo > 0 && holo < 1 {
                let p = -0.5 + holo * 2
                LinearGradient(stops: Self.band(p, width: 0.45, colors: [.rgba(120, 255, 240, 0), .rgba(120, 255, 240, 0.55),
                                                                         .rgba(255, 120, 220, 0.55), .rgba(255, 230, 120, 0.55),
                                                                         .rgba(120, 180, 255, 0.5), .rgba(120, 180, 255, 0)]),
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .blendMode(.softLight)
                    .opacity(0.95)
            }
        }
        .allowsHitTesting(false)
    }

    /// Evenly spaced stops of a band centred at `p` (0–1 along the gradient), clamped into 0…1 in order.
    private static func band(_ p: Double, width: Double, colors: [Color]) -> [Gradient.Stop] {
        let n = colors.count
        var last = 0.0
        return colors.enumerated().map { i, c in
            let raw = p - width / 2 + width * Double(i) / Double(max(1, n - 1))
            let loc = max(last, min(1, max(0, raw)))
            last = loc
            return Gradient.Stop(color: c, location: loc)
        }
    }
}

// MARK: - The stage

/// The lit stage of the catch (film `getStage`): the wall curving into the floor, the key light behind the piece, an
/// aura in the thing's own colour, the pool of light on the floor, two rings running out across the floor at the catch
/// and motes drifting up in the light. `tc`: seconds since the choice (the catch beat); `live`: the clock (the motes).
struct CatchStageCanvas: View {
    var alpha: Double
    var cx: CGFloat
    var tc: Double
    var live: Double
    var palette: StagePalette
    var calm: Bool

    private static let wall: [Gradient.Stop] = [
        .init(color: Color(hex: 0xE6EEFB), location: 0), .init(color: Color(hex: 0xF1F6FE), location: 0.22),
        .init(color: Color(hex: 0xFBFCFF), location: 0.42), .init(color: Color(hex: 0xF6F8FC), location: 0.54),
        .init(color: Color(hex: 0xE9EEF6), location: 0.585), .init(color: Color(hex: 0xEDF1F8), location: 0.62),
        .init(color: Color(hex: 0xE8EDF5), location: 0.8), .init(color: Color(hex: 0xDFE6F0), location: 1),
    ]

    /// Fine grain over the soft gradients so they never band (film `grainTile`).
    private static let grain: Image = {
        let n = 128
        var px = [UInt8](repeating: 255, count: n * n * 4)
        var seed: UInt32 = 0x9E3779B9
        for i in 0..<(n * n) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let v = UInt8(128 + Int((seed >> 24) & 0xFF) * 90 / 255 - 45)
            px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v
        }
        let provider = CGDataProvider(data: Data(px) as CFData)
        guard let provider,
              let cg = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return Image(systemName: "circle") }
        return Image(decorative: cg, scale: 2)
    }()

    var body: some View {
        Canvas { ctx, size in
            guard alpha > 0.001 else { return }
            ctx.opacity = alpha
            let W = size.width, H = size.height, k = W / 1080
            let rect = CGRect(origin: .zero, size: size)
            let swell = calm ? 0 : sin(.pi * Film6.seg(tc, Film6.catchT - 0.05, Film6.catchT + 0.95))
            ctx.fill(Path(rect), with: .linearGradient(Gradient(stops: Self.wall), startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
            // the key light on the wall behind the piece
            ctx.fill(Path(rect), with: .radialGradient(Gradient(stops: [
                .init(color: .white.opacity(0.85 + 0.15 * swell), location: 0),
                .init(color: .white.opacity(0.35), location: 0.55),
                .init(color: .white.opacity(0), location: 1),
            ]), center: CGPoint(x: cx, y: Film6.y(930, H)), startRadius: 0, endRadius: 760 * k))
            // the aura in the thing's own colour
            ctx.fill(Path(rect), with: .radialGradient(Gradient(stops: [
                .init(color: palette.glow.color(0.5 + 0.2 * swell), location: 0),
                .init(color: palette.glow2.color(0.22), location: 0.6),
                .init(color: palette.glow2.color(0), location: 1),
            ]), center: CGPoint(x: cx, y: Film6.y(1010, H)), startRadius: 0, endRadius: CGFloat(520 + 60 * swell) * k))
            // the pool of light on the floor, the thing's colour bouncing in it
            let fy = Film6.y(Film6.floorY + 10, H)
            var pool = ctx
            pool.translateBy(x: cx, y: fy)
            pool.scaleBy(x: 1, y: 0.2)
            let r1 = 640 * k, r2 = 300 * k
            pool.fill(Path(ellipseIn: CGRect(x: -r1, y: -r1, width: 2 * r1, height: 2 * r1)), with: .radialGradient(Gradient(stops: [
                .init(color: .white.opacity(0.95), location: 0),
                .init(color: .white.opacity(0.45), location: 0.5),
                .init(color: .white.opacity(0), location: 1),
            ]), center: .zero, startRadius: 0, endRadius: CGFloat(600 + 40 * swell) * k))
            pool.fill(Path(ellipseIn: CGRect(x: -r2, y: -r2, width: 2 * r2, height: 2 * r2)), with: .radialGradient(Gradient(stops: [
                .init(color: palette.glow.color(0.45), location: 0),
                .init(color: palette.glow.color(0), location: 1),
            ]), center: .zero, startRadius: 0, endRadius: r2))
            var grain = ctx
            grain.opacity = alpha * 0.045
            grain.blendMode = .overlay
            grain.fill(Path(rect), with: .tiledImage(Self.grain))
            guard !calm else { return }
            // the catch: two rings run out across the floor
            for (d, a0) in [(0.0, 1.0), (0.14, 0.55)] {
                let u = Film6.seg(tc, Film6.catchT + d, Film6.catchT + d + 0.95)
                guard u > 0, u < 1 else { continue }
                let e = Film6.outCubic(u), rx = CGFloat(Film6.lerp(170, 720, e)) * k
                var g = ctx
                g.opacity = alpha * a0 * pow(1 - u, 1.3)
                g.addFilter(.shadow(color: .rgba(42, 155, 255, 0.75), radius: 9 * k * 2))
                let ry = rx * 0.19, cy = Film6.y(Film6.floorY + 8, H)
                g.stroke(Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)),
                         with: .color(.white.opacity(0.95)), lineWidth: CGFloat(Film6.lerp(4, 1.5, e)) * k)
            }
            // motes drifting in the light (film px: x round the piece, y on the canvas)
            let cxPx = Double(cx / k)
            for i in 0..<16 {
                let di = Double(i)
                let speed = 10 + 14 * Film6.rnd(di * 5.1)
                let y0 = 260 + 1080 * Film6.rnd(di * 2.7)
                let raw = (y0 - live * speed).truncatingRemainder(dividingBy: 1100)
                let yy = (raw + 1100).truncatingRemainder(dividingBy: 1100) + 260
                let xx = cxPx + (Film6.rnd(di * 9.3) - 0.5) * 640 + 24 * sin(live * 0.5 + di)
                let inLight = Film6.clamp(1 - abs(xx - cxPx) / 360) * Film6.clamp((yy - 240) / 200) * Film6.clamp((1380 - yy) / 160)
                let tw = 0.55 + 0.45 * sin(live * (1.3 + Film6.rnd(di)) * 2 + di)
                let r = CGFloat((2 + 2.5 * Film6.rnd(di * 1.9)) * 3) * k
                let al = 0.55 * inLight * tw * (1 + swell)
                guard al > 0.02 else { continue }
                let p = CGPoint(x: CGFloat(xx) * k, y: Film6.y(yy, H))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .radialGradient(Gradient(stops: [
                    .init(color: .white.opacity(min(1, al)), location: 0),
                    .init(color: .white.opacity(min(1, al * 0.5)), location: 0.35),
                    .init(color: .white.opacity(0), location: 1),
                ]), center: p, startRadius: 0, endRadius: r))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The scene the choose screen and the GET moment share: the app's page over the photo (`page`, the melt) with a soft
/// blue glow behind the sticker, the stage lighting up after the choice, the sticker's shadow and reflection on the
/// floor, and the sticker itself.
struct CatchStageScene: View {
    let size: CGSize
    let cut: UIImage?
    let fallback: UIImage?
    let palette: StagePalette
    /// Where the thing sits in the photo, in this view's coordinates (nil = already lifted to the top of the page).
    var start: CGRect? = nil
    /// Seconds since the tag was tapped (C).
    var sinceTap: Double = 99
    /// Seconds since the way to say it was chosen (P); nil before the choice.
    var sinceChoice: Double? = nil
    var live: Double
    /// 0 → 1: the app's page over the photo.
    var page: Double = 1
    var calm: Bool
    var hideSticker: Bool = false

    private var aspect: CGFloat {
        let s = (cut ?? fallback)?.size ?? CGSize(width: 1, height: 1)
        return s.height > 0 ? s.width / s.height : 1
    }

    var body: some View {
        let tc = sinceChoice ?? -10
        let bobWeight = sinceChoice == nil ? Film6.seg(sinceTap, 0.6, 1) : 1
        let p = Film6.pose(screen: size, aspect: aspect, start: start, sinceTap: sinceTap, sinceChoice: sinceChoice,
                           live: live, bobWeight: bobWeight, calm: calm)
        let stageA = calm ? Film6.seg(tc, Film6.stageIn0, Film6.stageIn0 + 0.25)
            : Film6.inOutCubic(Film6.seg(tc, Film6.stageIn0, Film6.stageIn1))
        let k = size.width / 1080
        ZStack(alignment: .topLeading) {
            // the page over the photo, with the soft blue glow behind the sticker
            ZStack {
                Theme.background
                let r = CGFloat(Film6.lerp(620, 760, Film6.clamp(p.m))) * k
                RadialGradient(stops: [.init(color: Color(hex: 0xDDEEFF), location: 0),
                                       .init(color: .rgba(234, 244, 255, 0.75), location: 0.55),
                                       .init(color: .rgba(234, 244, 255, 0), location: 1)],
                               center: UnitPoint(x: p.still.x / max(1, size.width), y: (p.still.y + 20 * k) / max(1, size.height)),
                               startRadius: 0, endRadius: r)
            }
            .opacity(page)
            CatchStageCanvas(alpha: stageA, cx: p.still.x, tc: tc, live: live, palette: palette, calm: calm)
            if !hideSticker {
                floorLayer(p, stageA: stageA, tc: tc)
                sticker(p, tc: tc)
                    .position(p.center)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func sticker(_ p: Film6.Pose, tc: Double) -> some View {
        let border = calm ? Film6.seg(tc, Film6.cut, Film6.cut + 0.2) : Film6.outCubic(Film6.seg(tc, Film6.cut, Film6.cut + 0.3))
        let sheen = sinceChoice == nil && !calm ? Film6.seg(sinceTap, 0.6, 1.1) : -1
        let holo = calm ? -1 : Film6.seg(tc, Film6.catchT - 0.05, Film6.catchT + 0.85)
        return CatchStickerArt(cut: cut, fallback: fallback, size: p.size, border: border, sheen: sheen, holo: holo)
    }

    /// The soft shadow under the floating sticker, and on the stage its shadow and faint reflection on the floor
    /// (film `stageFloor`).
    @ViewBuilder
    private func floorLayer(_ p: Film6.Pose, stageA: Double, tc: Double) -> some View {
        let W = size.width, H = size.height, k = W / 1080
        let floorPt = Film6.y(Film6.floorY, H)
        let bottom = p.center.y + p.size.height / 2
        // in film px
        let lift = max(0, Double((floorPt - bottom) / H) * Film6.canvasH) + 6
        // the soft shadow that follows the floating sticker
        let pose = Film6.clamp(Film6.seg(sinceTap, 0.05, 0.4))
        Ellipse()
            .fill(Color(hex: 0x0F2850))
            .frame(width: p.size.width * 1.05, height: max(2, p.size.height * 0.09))
            .blur(radius: 16 * k)
            .opacity(0.2 * (sinceChoice == nil ? pose : 1) * (1 - stageA * 0.6))
            .position(x: p.center.x, y: p.still.y + p.size.height * 0.5 + p.size.height * 0.1)
        if stageA > 0.001 {
            let sa = stageA * Film6.clamp(1 - lift / 160) * 0.42
            if sa > 0.005 {
                Ellipse()
                    .fill(Color(hex: 0x2B3A52))
                    .frame(width: max(2, p.size.width * 0.9 * CGFloat(1 - lift / 600)), height: max(2, 40 * k * p.size.height / Film6.y(586, H)))
                    .blur(radius: CGFloat(10 + lift * 0.18) * k)
                    .opacity(sa)
                    .position(x: p.center.x, y: floorPt + 4 * k)
            }
            if lift < 120 {
                let band = 190 * k
                CatchStickerArt(cut: cut, fallback: fallback, size: p.size, border: 1)
                    .scaleEffect(x: 1, y: -1)
                    .position(x: p.center.x, y: 2 * floorPt - p.center.y + 4 * k)
                    .frame(width: W, height: H, alignment: .topLeading)
                    .mask(alignment: .topLeading) {
                        LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(width: W, height: band)
                            .offset(y: floorPt + 2 * k)
                    }
                    .blur(radius: 0.6)
                    .opacity(stageA * 0.16 * Film6.clamp(1 - lift / 120))
            }
        }
    }
}

// MARK: - Bits of the stage's text

/// A four-point star (the sparkle of the app's sparkles icon, film `star4`).
struct Star4: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2, c = CGPoint(x: rect.midX, y: rect.midY), q = r * 0.14
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + q, y: c.y - q))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + q, y: c.y + q))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - q, y: c.y + q))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - q, y: c.y - q))
        p.closeSubpath()
        return p
    }
}

/// The blue NEW chip with the thing's number and category in the 図鑑 (「No.001 · 飲み物」).
struct CatchDexChip: View {
    let label: String?
    var scale: CGFloat = 1
    /// The blue capsule's word: 「初ゲット」 for a new word, 「再会 N回目」 for a re-encounter.
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 6 * scale) {
            Text(badge ?? L("初ゲット"))
                .font(.system(size: 9.5 * scale, weight: .heavy))
                .tracking(0.8 * scale)
                .foregroundStyle(.white)
                .padding(.horizontal, 10 * scale)
                .frame(height: 18 * scale)
                .background(Theme.primary, in: Capsule())
            if let label {
                Text(verbatim: label)
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x5C646F))
                    .lineLimit(1)
            }
        }
        .fixedSize()
    }
}

/// The 図鑑 number and category of a word, when the dex's catalog knows it (「No.001 · 飲み物」).
enum CatchDexInfo {
    static func label(headword: String, stickers: [Sticker]) -> String? {
        let lang = NativeAPI.targetLanguage
        guard let item = DexCatalog.item(headword: headword, lang: lang) else { return nil }
        let no = DexNumbering.preview(headword: headword, stickers: stickers, lang: lang, uid: SupabaseClient.shared.userId)
        return "\(L("No.\(String(format: "%03d", no))")) · \(DexCatalog.label(item.category))"
    }
}

/// The category's first five words, for the goal toast after a catch (film `goalToast`).
struct CatchGoal: Equatable {
    let emoji: String
    let label: String
    /// The five base words: caught (the new one included).
    let caught: [Bool]
    /// The new word among them (its dot pops in), nil when it is not one of the five.
    let newIndex: Int?

    var left: Int { caught.filter { !$0 }.count }

    /// nil when the word is not in the dex's catalog.
    static func make(headword: String, stickers: [Sticker], lang: String) -> CatchGoal? {
        guard let item = DexCatalog.item(headword: headword, lang: lang),
              let cat = DexCatalog.categories.first(where: { $0.no == item.category }) else { return nil }
        let have = Set(stickers.compactMap { DexCatalog.item(headword: $0.word?.headword, lang: lang)?.id })
        let base = Array(cat.base.prefix(5))
        guard !base.isEmpty else { return nil }
        return CatchGoal(emoji: cat.emoji, label: cat.label,
                         caught: base.map { have.contains($0.id) || $0.id == item.id },
                         newIndex: base.firstIndex { $0.id == item.id })
    }
}
