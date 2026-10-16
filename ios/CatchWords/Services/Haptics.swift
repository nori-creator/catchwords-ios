import CoreHaptics
import UIKit

/// Single haptics gateway (the web app called vibrate from 7 places; here everything goes through one switch).
enum Haptics {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "haptics.enabled") as? Bool ?? true
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// The tap under a bubble "pon" (page open / back): one soft, round transient — a little
    /// rounder and lighter going back. Core Haptics when there is an engine, a soft impact otherwise.
    static func pon(open: Bool) {
        guard isEnabled else { return }
        let patterns = HapticPatterns.shared
        if patterns.isAvailable {
            patterns.transient(intensity: open ? 0.6 : 0.45, sharpness: open ? 0.45 : 0.3)
        } else {
            impact(.soft, intensity: open ? 0.75 : 0.55)
        }
    }
}


/// Core Haptics patterns for the moments that deserve more than a single tap (native iOS strength).
/// Falls back to nothing on hardware without a haptic engine (simulator, some iPads).
@MainActor
final class HapticPatterns {
    static let shared = HapticPatterns()
    private var engine: CHHapticEngine?
    var isAvailable: Bool { engine != nil }

    /// The engine is made off the main thread (asking the hardware and starting the engine held the main thread for
    /// seconds on the first tab tap of a cold start, 2026-10-16); until it is ready, `Haptics.pon` taps without it.
    /// `warmUp()` at launch makes it before anyone needs it.
    private init() {
        Task.detached(priority: .utility) {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let made = try? CHHapticEngine() else { return }
            made.isAutoShutdownEnabled = true
            try? await made.start()
            let box = EngineBox(engine: made)
            await MainActor.run { HapticPatterns.shared.adopt(box.engine) }
        }
    }

    /// Makes the engine now, behind the first screen.
    static func warmUp() { _ = shared }

    private func adopt(_ made: CHHapticEngine) {
        guard engine == nil else { return }
        engine = made
        made.resetHandler = {
            Task { @MainActor in HapticPatterns.shared.restart() }
        }
    }

    /// After the system reset the engine (another app took the hardware, the app came back).
    private func restart() {
        try? engine?.start()
    }

    /// The engine handed from the thread that made it (nothing uses it there afterwards).
    nonisolated private struct EngineBox: @unchecked Sendable {
        let engine: CHHapticEngine
    }

    private func play(_ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = []) {
        guard Haptics.isEnabled, let engine else { return }
        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    private static func p(_ id: CHHapticEvent.ParameterID, _ v: Float) -> CHHapticEventParameter { .init(parameterID: id, value: v) }

    /// One short tap with a chosen feel (used by `Haptics.pon`).
    func transient(intensity: Float, sharpness: Float) {
        play([CHHapticEvent(eventType: .hapticTransient,
                            parameters: [Self.p(.hapticIntensity, intensity), Self.p(.hapticSharpness, sharpness)],
                            relativeTime: 0)])
    }

    /// A word lands in the dex: a firm round thud, then two smaller bounces (matches el-land-bounce).
    /// Without an engine it is the old single heavy impact.
    func land() {
        guard isAvailable else {
            Haptics.impact(.heavy)
            return
        }
        play([
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [Self.p(.hapticIntensity, 1), Self.p(.hapticSharpness, 0.4)],
                          relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [Self.p(.hapticIntensity, 0.55), Self.p(.hapticSharpness, 0.35)],
                          relativeTime: 0.16),
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [Self.p(.hapticIntensity, 0.3), Self.p(.hapticSharpness, 0.3)],
                          relativeTime: 0.27),
        ])
    }

    /// Scissors along the outline: a fine, crisp buzz for `duration` seconds that fades out.
    func trace(duration: TimeInterval) {
        let buzz = CHHapticEvent(eventType: .hapticContinuous,
                                 parameters: [Self.p(.hapticIntensity, 0.35), Self.p(.hapticSharpness, 0.9)],
                                 relativeTime: 0, duration: duration)
        var ticks: [CHHapticEvent] = []
        var t: TimeInterval = 0
        while t < duration {
            ticks.append(CHHapticEvent(eventType: .hapticTransient,
                                       parameters: [Self.p(.hapticIntensity, 0.25), Self.p(.hapticSharpness, 1)],
                                       relativeTime: t))
            t += 0.07
        }
        let fade = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0, value: 0.8), .init(relativeTime: duration, value: 0.2),
        ], relativeTime: 0)
        play([buzz] + ticks, curves: [fade])
    }

    /// The sticker lifting off: a soft swell and a round pop.
    func lift() {
        play([
            CHHapticEvent(eventType: .hapticContinuous,
                          parameters: [Self.p(.hapticIntensity, 0.5), Self.p(.hapticSharpness, 0.2)],
                          relativeTime: 0, duration: 0.18),
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [Self.p(.hapticIntensity, 0.9), Self.p(.hapticSharpness, 0.45)],
                          relativeTime: 0.18),
        ], curves: [CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0, value: 0.2), .init(relativeTime: 0.18, value: 1),
        ], relativeTime: 0)])
    }

    /// 幕2 bloom: charge (rising rumble) then the glass jar closing — heavy thud + bright clink.
    func bloom() {
        play([
            CHHapticEvent(eventType: .hapticContinuous,
                          parameters: [Self.p(.hapticIntensity, 0.6), Self.p(.hapticSharpness, 0.1)],
                          relativeTime: 0, duration: 0.22),
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [Self.p(.hapticIntensity, 1), Self.p(.hapticSharpness, 0.35)],
                          relativeTime: 0.22),
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [Self.p(.hapticIntensity, 0.55), Self.p(.hapticSharpness, 1)],
                          relativeTime: 0.5),
        ], curves: [CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0, value: 0.1), .init(relativeTime: 0.22, value: 1),
        ], relativeTime: 0)])
    }
}
