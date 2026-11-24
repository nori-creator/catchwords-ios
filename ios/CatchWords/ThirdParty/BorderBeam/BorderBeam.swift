//  Vendored from https://github.com/ismnoiet/border-beam-ios at a11d1b938b1cc8efad02e942f7590a0156bbd7da
//  (MIT, full text in BorderBeamLicense.swift). CatchWords changes: the shader is read from the app's own
//  Metal library (ShaderLibrary.default) and Reduce Motion follows the app's setting (\.appReduceMotion).
//
//
//  BorderBeam.swift
//  BorderBeam
//
//  Author: ismnoiet
//  Minimum supported: iOS 17 (macOS 14, visionOS 1)
//
import SwiftUI

/// Container that draws a surface, hairline border and animated beam around ANY content:
/// text fields, pickers, menus, buttons, plain views…
///
///     BorderBeam(shape: .rounded(26), active: isFocused) {
///         TextField("Build anything...", text: $text)
///     }
///
///     BorderBeam(.small, shape: .circle) { Image(systemName: "stop.fill") }
///     BorderBeam(.line, shape: .capsule) { SearchField() }
///     BorderBeam(colors: BeamPalette.single(.cyan)) { ... }
///     BorderBeam(direction: .rightToLeft) { ... }
public struct BorderBeam<Content: View>: View {
    private let style: BeamStyle
    private let shape: BeamShape
    private let direction: BeamDirection
    private let active: Bool
    private let colors: [Color]
    private let intensity: Double
    private let timing: BeamTiming
    private let surface: Color?
    private let borderColor: Color
    private let content: Content

    public init(
        _ style: BeamStyle = .large,
        shape: BeamShape = .rounded(26),
        direction: BeamDirection = .leftToRight,
        active: Bool = true,
        colors: [Color] = BeamPalette.colorful,
        intensity: Double = 1,
        timing: BeamTiming = .default,
        surface: Color? = Color(white: 0.11),
        borderColor: Color = .white.opacity(0.08),
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.shape = shape
        self.direction = direction
        self.active = active
        self.colors = colors
        self.intensity = intensity
        self.timing = timing
        self.surface = surface
        self.borderColor = borderColor
        self.content = content()
    }

    public var body: some View {
        content
            .background { surfaceView }
            .borderBeam(shape: shape, style: style, direction: direction,
                        active: active, colors: colors, intensity: intensity, timing: timing)
    }

    @ViewBuilder
    private var surfaceView: some View {
        switch shape {
        case .rounded(let r): surfaceLayer(RoundedRectangle(cornerRadius: r, style: .circular))
        case .capsule: surfaceLayer(Capsule())
        case .circle: surfaceLayer(Circle())
        }
    }

    private func surfaceLayer<S: InsettableShape>(_ s: S) -> some View {
        ZStack {
            if let surface { s.fill(surface) }
            s.strokeBorder(borderColor, lineWidth: 1)
        }
    }
}
