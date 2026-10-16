import SwiftUI

/// 「作り直す」 on a word-page section (owner 2026-10-16, after a reference video): while `running` turns true, the old
/// content breaks into fine grains from left to right (`dissolve`, about half a second) that drift right and up into a
/// cloud; the cloud swirls gently for as long as the new content is being written; once `running` is false again, the
/// new content gathers back out of the cloud from left to right (`assemble`). The grains are the content's own pixels
/// (the `regenDust` shader in Effects.metal samples the live layer), so its colours stay. With reduced motion the
/// content only dims while it is being written.
struct RegenDust: ViewModifier {
    let running: Bool

    /// How long the old content takes to break up, and the new one to gather back.
    static let dissolve: TimeInterval = 0.55
    static let assemble: TimeInterval = 0.7
    /// How far a grain may sample from where it is drawn (its drift and swirl, Effects.metal).
    static let reach = CGSize(width: 110, height: 60)

    @State private var startedAt: Date?
    @State private var readyAt: Date?
    @Environment(\.appReduceMotion) private var reduceMotion

    struct Phase: Equatable {
        var out: Double
        var back: Double
        var active: Bool
    }

    /// Where the effect is at `now`: the old content goes from `startedAt`; the new one comes back from `readyAt`, but
    /// never before the old one has gone. Pure, so RegenDustTests checks the timing.
    static func phase(at now: Date, startedAt: Date?, readyAt: Date?) -> Phase {
        guard let startedAt else { return Phase(out: 0, back: 0, active: false) }
        let out = min(1, max(0, now.timeIntervalSince(startedAt) / dissolve))
        guard let readyAt else { return Phase(out: out, back: 0, active: true) }
        let from = max(readyAt, startedAt.addingTimeInterval(dissolve))
        let back = min(1, max(0, now.timeIntervalSince(from) / assemble))
        return Phase(out: out, back: back, active: back < 1)
    }

    func body(content: Content) -> some View {
        Group {
            if reduceMotion {
                content.opacity(running ? 0.45 : 1).animation(.easeOut(duration: 0.25), value: running)
            } else {
                TimelineView(.animation(paused: startedAt == nil)) { timeline in
                    let p = Self.phase(at: timeline.date, startedAt: startedAt, readyAt: readyAt)
                    let out = Float(p.out), back = Float(p.back), active = p.active, reach = Self.reach
                    let t = Float(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000))
                    content.visualEffect { view, proxy in
                        view.layerEffect(ShaderLibrary.regenDust(.float2(proxy.size), .float(out), .float(back), .float(t)),
                                         maxSampleOffset: reach, isEnabled: active)
                    }
                }
            }
        }
        .onChange(of: running) { _, now in
            if now {
                startedAt = Date()
                readyAt = nil
            } else if let started = startedAt {
                let ready = Date()
                readyAt = ready
                // Done once the new content is back (the timeline then pauses).
                let end = max(ready, started.addingTimeInterval(Self.dissolve)).addingTimeInterval(Self.assemble)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow) + 0.05))
                    if readyAt == ready { startedAt = nil; readyAt = nil }
                }
            }
        }
    }
}

extension View {
    /// The 「作り直す」 dust (`RegenDust`) while `running`.
    func regenDust(_ running: Bool) -> some View { modifier(RegenDust(running: running)) }
}
