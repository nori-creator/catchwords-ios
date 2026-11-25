//  Vendored from https://github.com/ismnoiet/border-beam-ios at a11d1b938b1cc8efad02e942f7590a0156bbd7da
//  (MIT, full text in BorderBeamLicense.swift). CatchWords changes: the shader is read from the app's own
//  Metal library (ShaderLibrary.default) and Reduce Motion follows the app's setting (\.appReduceMotion); the
//  environment key is nonisolated (the app target's default isolation is MainActor); BeamLayer takes an optional
//  glow reach and comet length (`glowOverride` / `arcOverride`); BeamLayer reads the colour scheme only, not the
//  whole environment (`@Environment(\.self)` redrew it on every change of anything in the environment).
//
//
//  BorderBeamModifier.swift
//  BorderBeam
//
//  Author: ismnoiet
//  Minimum supported: iOS 17 (macOS 14, visionOS 1)
//
import SwiftUI

// MARK: - Speed (environment)

nonisolated private struct BeamSpeedKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

public extension EnvironmentValues {
    /// Speed multiplier for every beam below this view (1 = normal, 2 = twice as fast).
    nonisolated var beamSpeed: Double {
        get { self[BeamSpeedKey.self] }
        set { self[BeamSpeedKey.self] = newValue }
    }
}

public extension View {
    /// Sets the speed of every `BorderBeam` / `.borderBeam` inside this view.
    ///
    ///     VStack { ... }.beamSpeed(1.5)
    ///
    /// Changing it while a beam runs speeds it up or slows it down smoothly, without jumping.
    func beamSpeed(_ speed: Double) -> some View {
        environment(\.beamSpeed, speed)
    }
}

/// Accumulates the beam phase frame by frame, so the speed can change at any moment without the
/// beam jumping (a plain `time / duration` would teleport it whenever the rate changes).
private final class BeamClock {
    private var last: Date?
    private(set) var phase: Double = Double.random(in: 0..<1)

    func advance(to date: Date, rate: Double) -> Double {
        if let last {
            let dt = min(max(date.timeIntervalSince(last), 0), 0.1)   // ignore long pauses
            phase += dt * rate
            phase -= floor(phase)
        }
        last = date
        return phase
    }

    /// Call when the timeline was paused so the first frame after resuming doesn't leap.
    func resync() { last = nil }
}

/// Draws the beam with a Metal shader (`colorEffect`) on top of any view.
///
/// Performance notes:
/// - one cheap GPU pass per beam, no blur layers
/// - the palette is flattened once per body update, not per frame
/// - the timeline is paused while the beam is inactive (after the fade) and under Reduce Motion
struct BeamLayer: View {
    let shape: BeamShape
    let style: BeamStyle
    let direction: BeamDirection
    let active: Bool
    let colors: [Color]
    let intensity: Double
    let timing: BeamTiming
    /// CatchWords: the glow's reach (points) and the comet's length (fraction of a lap) instead of the style's.
    var glowOverride: CGFloat? = nil
    var arcOverride: CGFloat? = nil

    /// The palette is resolved with the colour scheme alone (`flatten`; the app's beams use fixed colours), so the beam
    /// is not built again on every change elsewhere in the environment (a keystroke's focus, the keyboard's safe area).
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.beamSpeed) private var speed
    @State private var running = true
    @State private var clock = BeamClock()

    var body: some View {
        let flat = flatten(colors)
        let isLine = style == .line
        let duration = isLine ? timing.lineDuration : timing.rotateDuration

        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: !running || reduceMotion)) { tl in
                Rectangle()
                    .fill(Color.white)
                    .colorEffect(
                        ShaderLibrary.borderBeam(
                            .float2(geo.size),
                            .float(shape.cornerRadius),
                            .float(phase(tl.date, duration: duration)),
                            .float(CGFloat(direction.shaderValue)),
                            .float(isLine ? 1 : 0),   // mode: 0 orbit, 1 sweep along an edge
                            .float(2),                // edge for .line: bottom
                            .float(arcOverride ?? (style == .small ? 0.5 : 0.36)),
                            .float(glowOverride ?? glowReach),
                            .float(intensity),
                            .floatArray(flat)
                        )
                    )
            }
        }
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: timing.fade), value: active)
        .task(id: active) {
            if active {
                clock.resync()
                running = true
            } else {
                // let the fade-out finish, then stop the timeline so idle beams cost nothing
                try? await Task.sleep(nanoseconds: UInt64((timing.fade + 0.05) * 1_000_000_000))
                if !Task.isCancelled { running = false }
            }
        }
        .allowsHitTesting(false)
    }

    private var glowReach: CGFloat {
        switch style {
        case .large: return 20
        case .small: return 4
        case .line: return 10
        }
    }

    private func phase(_ date: Date, duration: Double) -> Double {
        if reduceMotion { return 0.15 }   // static, still-visible beam
        return clock.advance(to: date, rate: max(speed, 0) / max(duration, 0.01))
    }

    private func flatten(_ colors: [Color]) -> [Float] {
        let src = colors.isEmpty ? [Color.white] : Array(colors.prefix(16))
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        return src.flatMap { color -> [Float] in
            let c = color.resolve(in: environment)
            return [c.red, c.green, c.blue, c.opacity]
        }
    }
}

public extension View {
    /// Adds an animated border beam to any view.
    ///
    ///     MyView().borderBeam(shape: .capsule, style: .line)
    ///     MyView().borderBeam(shape: .rounded(12), colors: BeamPalette.single(.cyan))
    func borderBeam(
        shape: BeamShape = .rounded(26),
        style: BeamStyle = .large,
        direction: BeamDirection = .leftToRight,
        active: Bool = true,
        colors: [Color] = BeamPalette.colorful,
        intensity: Double = 1,
        timing: BeamTiming = .default
    ) -> some View {
        overlay {
            BeamLayer(shape: shape, style: style, direction: direction,
                      active: active, colors: colors, intensity: intensity, timing: timing)
        }
    }
}
