import SwiftUI

/// The light that runs round a box while the learner waits for it (owner 2026-11-24: 「待ち時間にこの GitHub の、枠が光る
/// ものを導入したい。このアプリのコンセプトと同じように青白く光らせたい…色は虹色じゃなくて、このアプリのコンセプトの青とか白
/// とかにして」). BorderBeam (vendored, `ThirdParty/BorderBeam`) draws it; every use goes through `.waitBeam` so they all
/// look the same: the scan's blue-white (`ScanGlow`) — a pale blue tail, the icon's blue head on light surfaces, a white
/// head on dark ones. Never the library's rainbow palettes.
///
/// Cost: the beam's layer (one Metal pass a frame) is only in the view while `active`; it fades in and out, and with
/// reduced motion it is a still light (`\.appReduceMotion`).
extension View {
    /// `darkSurface`: the box's own surface when it does not follow the appearance (a white box: false); nil = the
    /// appearance's.
    func waitBeam(_ active: Bool, cornerRadius: CGFloat, small: Bool = false, darkSurface: Bool? = nil) -> some View {
        modifier(WaitBeamModifier(active: active, shape: .rounded(cornerRadius), style: small ? .small : .large,
                                  darkSurface: darkSurface))
    }
}

private struct WaitBeamModifier: ViewModifier {
    let active: Bool
    let shape: BeamShape
    let style: BeamStyle
    let darkSurface: Bool?
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        // The fade is the overlay's own: the box's content keeps its animations as they were.
        content.overlay {
            ZStack {
                if active {
                    // Brighter than the library's own (owner 2026-11-24, on the first shots: 「もう少し明るく」): a stronger
                    // head, more intensity, a wider glow and a longer comet.
                    BeamLayer(shape: shape, style: style, direction: .leftToRight, active: true,
                              colors: WaitBeamPalette.colors(dark: darkSurface ?? (scheme == .dark)), intensity: 1.8,
                              timing: BeamTiming(rotateDuration: 2.2, lineDuration: 2.0, fade: 0.4),
                              glowOverride: style == .small ? 7 : 30, arcOverride: style == .small ? 0.55 : 0.42)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: active)
            .allowsHitTesting(false)
        }
    }
}

/// The scan's blue-white (`ScanGlow`): first colour = the tail, last = the head.
enum WaitBeamPalette {
    static func colors(dark: Bool) -> [Color] {
        dark
            ? [Color(hex: 0x78BEFF).opacity(0.6), Color(hex: 0xBFE8FF), .white, .white]
            : [Color(hex: 0x9CC8FF).opacity(0.7), Color(hex: 0x4AA8FF), Color(hex: 0x0589FE), Color(hex: 0x0070F0)]
    }
}
