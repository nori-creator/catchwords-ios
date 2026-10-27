import SwiftUI

/// The keyword of a headline: the part its translation wraps in `**…**` (「撮るだけで、**ことば**になる」). Drawn on a blue
/// pill by `HeadlineReveal` (owner 2026-10-27: the first screens like the reference film — the headline comes in out of
/// a blur and its keyword pops in on a pill).
nonisolated struct KeywordMark: TextAttribute {}

enum MarkedText {
    /// "撮るだけで、**ことば**になる" → one Text, the marked part white and flagged with `KeywordMark`.
    static func text(_ marked: String) -> Text {
        var out = Text(verbatim: "")
        for (i, part) in marked.components(separatedBy: "**").enumerated() where !part.isEmpty {
            let piece = i % 2 == 1
                ? Text(verbatim: part).foregroundStyle(Color.white).customAttribute(KeywordMark())
                : Text(verbatim: part)
            out = Text("\(out)\(piece)")
        }
        return out
    }

    /// The same words without the marks (accessibility, measuring).
    static func plain(_ marked: String) -> String {
        marked.replacingOccurrences(of: "**", with: "")
    }
}

/// A headline coming in: each line rises out of a blur, one after the other, then the keyword's pill pops in with a
/// small overshoot. `progress` runs 0 → 1 with a linear animation; the easing is done here, per line.
nonisolated struct HeadlineReveal: TextRenderer {
    var progress: Double
    var pill: Color

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for (i, line) in layout.enumerated() {
            let t = Self.easeOut(Self.clamp((progress - Double(i) * 0.16) / 0.5))
            var ctx = context
            ctx.opacity = t
            ctx.translateBy(x: 0, y: (1 - t) * 14)
            if t < 1 { ctx.addFilter(.blur(radius: (1 - t) * 7)) }
            for run in line {
                guard run[KeywordMark.self] != nil else {
                    ctx.draw(run)
                    continue
                }
                let k = Self.clamp((progress - 0.5) / 0.5)
                guard k > 0 else { continue }
                let r = run.typographicBounds.rect.insetBy(dx: -8, dy: -1)
                let s = Self.overshoot(k)
                var pc = ctx
                pc.opacity = t * min(1, k * 3)
                pc.translateBy(x: r.midX, y: r.midY)
                pc.scaleBy(x: s, y: s)
                pc.translateBy(x: -r.midX, y: -r.midY)
                pc.fill(Path(roundedRect: r, cornerRadius: r.height * 0.3, style: .continuous), with: .color(pill))
                pc.draw(run)
            }
        }
    }

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    /// 0 → 1 passing a little beyond 1 (a pop), settled at 1.
    static func overshoot(_ x: Double) -> Double {
        x >= 1 ? 1 : 0.6 + 0.4 * (1 - exp(-6 * x) * cos(9 * x))
    }
}

/// A headline with a `**keyword**`, revealed by `HeadlineReveal` while `active` (again each time it turns on).
/// With reduced motion it is simply there.
struct RevealHeadline: View {
    let marked: String
    var size: CGFloat = 30
    var alignment: TextAlignment = .center
    var active: Bool = true
    var delay: Double = 0
    var duration: Double = 1.0

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    var body: some View {
        MarkedText.text(marked)
            .scaledFont(size: size, weight: .heavy)
            .foregroundStyle(Theme.foreground)
            .multilineTextAlignment(alignment)
            .lineSpacing(4)
            .minimumScaleFactor(0.6)
            .textRenderer(HeadlineReveal(progress: progress, pill: Theme.primary))
            .accessibilityLabel(MarkedText.plain(marked))
            .accessibilityAddTraits(.isHeader)
            .onAppear { run(active) }
            .onChange(of: active) { _, on in run(on) }
    }

    private func run(_ on: Bool) {
        guard !reduceMotion else {
            progress = 1
            return
        }
        guard on else {
            progress = 0
            return
        }
        progress = 0
        withAnimation(.linear(duration: duration).delay(delay)) { progress = 1 }
    }
}

extension View {
    /// Rises and fades in after `delay` once `shown` (a list's rows one after another: `delay: Double(i) * 0.05`).
    func staggerIn(_ shown: Bool, delay: Double = 0, distance: CGFloat = 16) -> some View {
        modifier(StaggerIn(shown: shown, delay: delay, distance: distance))
    }
}

private struct StaggerIn: ViewModifier {
    let shown: Bool
    let delay: Double
    let distance: CGFloat
    @Environment(\.appReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.82).delay(delay),
                       value: shown)
    }
}
