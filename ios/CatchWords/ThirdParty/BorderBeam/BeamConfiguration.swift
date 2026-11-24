//  Vendored from https://github.com/ismnoiet/border-beam-ios at a11d1b938b1cc8efad02e942f7590a0156bbd7da
//  (MIT, full text in BorderBeamLicense.swift). CatchWords changes: the shader is read from the app's own
//  Metal library (ShaderLibrary.default) and Reduce Motion follows the app's setting (\.appReduceMotion).
//
//
//  BeamConfiguration.swift
//  BorderBeam
//
//  Author: ismnoiet
//  Minimum supported: iOS 17 (macOS 14, visionOS 1)
//
import SwiftUI

/// Beam variants.
public enum BeamStyle: Sendable {
    /// Comet circling the whole border with a soft inner glow (cards, inputs).
    case large
    /// Tighter, longer comet for small controls (icon buttons, avatars).
    case small
    /// Glow sweeping back and forth along the bottom edge (search bars).
    case line
}

/// Outline the beam follows. Corner radii are circular so the beam hugs the edge exactly.
public enum BeamShape: Sendable {
    case rounded(CGFloat)
    case capsule
    case circle

    var cornerRadius: CGFloat {
        switch self {
        case .rounded(let r): return r
        case .capsule, .circle: return 10_000   // clamped to half the shortest side in the shader
        }
    }
}

/// Which way the beam travels when it circles the border (judged along the top edge).
public enum BeamDirection: Sendable {
    /// Default. Clockwise: moves left to right along the top edge.
    case leftToRight
    /// Counter-clockwise: moves right to left along the top edge.
    case rightToLeft

    var shaderValue: Float { self == .leftToRight ? 1 : -1 }
}

/// Animation timings. Override per instance with `timing:`.
public struct BeamTiming: Sendable {
    /// Seconds for one full lap (orbit beams).
    public var rotateDuration: Double
    /// Seconds for one there-and-back sweep (edge beams).
    public var lineDuration: Double
    /// Fade in/out when `active` toggles.
    public var fade: Double

    public init(rotateDuration: Double = 2.4, lineDuration: Double = 2.0, fade: Double = 0.6) {
        self.rotateDuration = rotateDuration
        self.lineDuration = lineDuration
        self.fade = fade
    }

    public static let `default` = BeamTiming()
}

/// Ready-made color sets. Any `[Color]` works too (first color = tail, last = head).
public enum BeamPalette {
    public static let colorful: [Color] = [
        Color(red: 0.25, green: 0.85, blue: 0.45),
        Color(red: 0.20, green: 0.60, blue: 0.95),
        Color(red: 0.70, green: 0.35, blue: 0.95),
        Color(red: 1.00, green: 0.35, blue: 0.65),
        Color(red: 1.00, green: 0.65, blue: 0.25)
    ]

    public static let gemini: [Color] = [
        Color(red: 0.26, green: 0.52, blue: 0.96),  // blue
        Color(red: 0.61, green: 0.45, blue: 0.80),  // purple
        Color(red: 0.92, green: 0.26, blue: 0.21),  // red
        Color(red: 0.98, green: 0.55, blue: 0.20),  // orange
        Color(red: 0.98, green: 0.74, blue: 0.02),  // yellow
        Color(red: 0.20, green: 0.66, blue: 0.33)   // green
    ]

    /// Blue -> teal -> cyan -> green -> yellow -> orange -> red (clockwise), sampled from a reference card.
    public static let spectrum: [Color] = [
        Color(red: 0.26, green: 0.50, blue: 0.96),  // blue
        Color(red: 0.25, green: 0.70, blue: 0.90),  // teal-blue
        Color(red: 0.25, green: 0.82, blue: 0.85),  // cyan
        Color(red: 0.25, green: 0.78, blue: 0.40),  // green
        Color(red: 0.98, green: 0.74, blue: 0.20),  // yellow
        Color(red: 0.98, green: 0.52, blue: 0.22),  // orange
        Color(red: 0.92, green: 0.28, blue: 0.25)   // red
    ]

    /// Cyan -> blue -> violet -> magenta.
    public static let neon: [Color] = [
        Color(red: 0.00, green: 0.90, blue: 1.00),
        Color(red: 0.30, green: 0.40, blue: 1.00),
        Color(red: 0.85, green: 0.20, blue: 1.00),
        Color(red: 1.00, green: 0.20, blue: 0.60)
    ]

    /// Gold -> orange -> coral -> purple.
    public static let sunset: [Color] = [
        Color(red: 1.00, green: 0.78, blue: 0.30),
        Color(red: 1.00, green: 0.50, blue: 0.30),
        Color(red: 1.00, green: 0.30, blue: 0.45),
        Color(red: 0.70, green: 0.30, blue: 0.90)
    ]

    /// Mint -> sky -> indigo -> lilac.
    public static let aurora: [Color] = [
        Color(red: 0.30, green: 1.00, blue: 0.70),
        Color(red: 0.20, green: 0.80, blue: 1.00),
        Color(red: 0.50, green: 0.40, blue: 1.00),
        Color(red: 0.90, green: 0.50, blue: 1.00)
    ]

    /// Cool, subtle white-blue.
    public static let silver: [Color] = [
        Color(red: 0.75, green: 0.80, blue: 1.00).opacity(0.2),
        Color(red: 0.90, green: 0.93, blue: 1.00),
        Color(red: 0.75, green: 0.80, blue: 1.00).opacity(0.2)
    ]

    /// One-color beam, softly fading in and out along its length.
    public static func single(_ color: Color) -> [Color] {
        [color.opacity(0.3), color, color.opacity(0.3)]
    }

    public static let mono: [Color] = [
        .white.opacity(0.25), .white.opacity(0.9), .white.opacity(0.25)
    ]
}
