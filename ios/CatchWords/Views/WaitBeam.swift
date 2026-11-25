import SwiftUI

/// The light that runs round a box while the learner waits for it (owner 2026-11-24: 「待ち時間にこの GitHub の、枠が光る
/// ものを導入したい。このアプリのコンセプトと同じように青白く光らせたい…色は虹色じゃなくて、このアプリのコンセプトの青とか白
/// とかにして」). The look is BorderBeam's (vendored, `ThirdParty/BorderBeam`); every use goes through `.waitBeam` so they
/// all look the same: the scan's blue-white (`ScanGlow`) — a pale blue tail, the icon's blue head on light surfaces, a
/// white head on dark ones. Never the library's rainbow palettes.
///
/// Drawn by Core Animation, not by the library's shader (owner 2026-11-25: 「青い光も途中で止まらないようにして」「可能な限り
/// アニメーションを滑らかにして、また止まらないようにして」): the shader was drawn again by the main thread every frame
/// (`TimelineView`), so the light stood still whenever the screen was busy — 0.85 s when a search's results arrived, in
/// the owner's recording — while the system's spinner beside it kept turning. Now the light is layers the render server
/// moves (`WaitBeamView`): it keeps running while the main thread works. The look is the shader's, measured against it.
///
/// Cost: the light's layers are only in the view while `active`; it fades in and out, and with reduced motion it is a
/// still light (`\.appReduceMotion`).
extension View {
    /// `darkSurface`: the box's own surface when it does not follow the appearance (a white box: false); nil = the
    /// appearance's.
    func waitBeam(_ active: Bool, cornerRadius: CGFloat, small: Bool = false, darkSurface: Bool? = nil) -> some View {
        modifier(WaitBeamModifier(active: active, cornerRadius: cornerRadius, small: small, darkSurface: darkSurface))
    }
}

private struct WaitBeamModifier: ViewModifier {
    let active: Bool
    let cornerRadius: CGFloat
    let small: Bool
    let darkSurface: Bool?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // The fade is the overlay's own: the box's content keeps its animations as they were.
        content.overlay {
            ZStack {
                if active {
                    // In: the layers fade themselves in (`WaitBeamView`, the render server's — it does not wait for the
                    // main thread either). Out: SwiftUI's, then the view is gone.
                    WaitBeamLight(look: WaitBeamLook(cornerRadius: cornerRadius, small: small,
                                                     dark: darkSurface ?? (scheme == .dark), still: reduceMotion))
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
            }
            .animation(.easeInOut(duration: WaitBeamLook.fade), value: active)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The light's UIKit view in SwiftUI: as large as the box it is laid over.
private struct WaitBeamLight: UIViewRepresentable {
    let look: WaitBeamLook

    func makeUIView(context: Context) -> WaitBeamView { WaitBeamView(look: look) }

    func updateUIView(_ uiView: WaitBeamView, context: Context) { uiView.look = look }
}

/// One light's look. The numbers are the ones the owner settled on (2026-11-24: 「もう少し明るく」, then 「少しだけ弱く」 —
/// the stronger head stays, the glow is narrow so it does not reach a short card's text, 台湾メモ above all in the dark
/// appearance).
nonisolated struct WaitBeamLook: Equatable {
    var cornerRadius: CGFloat
    /// The tighter, longer comet for small things (a photo's tile).
    var small: Bool
    /// The surface under the light is dark: a white head instead of the icon's blue.
    var dark: Bool
    /// Reduced motion: the comet stands still.
    var still: Bool

    /// Seconds for one lap, at one speed all the way round.
    static let lap: Double = 2.2
    /// Seconds to fade in and out.
    static let fade: Double = 0.4
    /// Where the still comet's head is (a lap's fraction, clockwise from the middle of the right edge).
    static let stillHead: CGFloat = 0.15
    /// Brighter than the library's own (1).
    static let intensity: Double = 1.4

    /// The comet's length, as a part of the lap.
    var arc: CGFloat { small ? 0.5 : 0.4 }
    /// How far the soft glow reaches into the box (points).
    var glow: CGFloat { small ? 5 : 14 }
    /// The bright line on the border (points): the shader's crisp line and tight halo together.
    var lineWidth: CGFloat { small ? 1.65 : 2 }
}

/// The scan's blue-white (`ScanGlow`): first colour = the tail, last = the head.
enum WaitBeamPalette {
    struct RGBA {
        var r: Double
        var g: Double
        var b: Double
        var a: Double
    }

    static func stops(dark: Bool) -> [RGBA] {
        if dark {
            return [rgba(0x78BEFF, 0.6), rgba(0xBFE8FF), rgba(0xFFFFFF), rgba(0xFFFFFF)]
        }
        return [rgba(0x9CC8FF, 0.7), rgba(0x4AA8FF), rgba(0x0589FE), rgba(0x0070F0)]
    }

    static func colors(dark: Bool) -> [Color] {
        stops(dark: dark).map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b, opacity: $0.a) }
    }

    /// The colour `t` of the way from the tail (0) to the head (1): a straight blend between the stops, as the shader's.
    static func sample(dark: Bool, at t: Double) -> RGBA {
        let all = stops(dark: dark)
        guard all.count > 1 else { return all.first ?? RGBA(r: 1, g: 1, b: 1, a: 1) }
        let x = min(1, max(0, t)) * Double(all.count - 1)
        let i = min(Int(x), all.count - 2)
        let f = x - Double(i)
        let a = all[i], b = all[i + 1]
        return RGBA(r: a.r + (b.r - a.r) * f, g: a.g + (b.g - a.g) * f, b: a.b + (b.b - a.b) * f,
                    a: a.a + (b.a - a.a) * f)
    }

    private static func rgba(_ hex: UInt32, _ opacity: Double = 1) -> RGBA {
        RGBA(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255,
             a: opacity)
    }
}
