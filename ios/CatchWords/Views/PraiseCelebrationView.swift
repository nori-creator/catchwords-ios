import SwiftUI
import StoreKit

/// The praise after a catch (owner 2026-10-25), in the look of the milestone album's opening (web `MemorialReveal`,
/// `MemorialAlbum.swift`): the night sky drops, the big number counts to the learner's place (a top % or a rank counts
/// down, a total counts up), and at its end confetti, the fanfare and a success tap land in the same instant (one event
/// for the eye, the ear and the hand). Then the line on what the learner did to get here, and 「続ける」.
/// Tap anywhere skips to the end; a second tap closes. Reduce Motion: the last frame, quietly.
struct PraiseCelebrationView: View {
    let moment: PraiseMoment
    let onDone: () -> Void

    @Environment(\.appReduceMotion) private var reduceMotion
    private enum Phase { case count, burst, ready, leaving }
    @State private var phase: Phase = .count
    @State private var value: Int
    @State private var task: Task<Void, Never>?
    /// The caught thing's cut-out has popped in (first catcher).
    @State private var imageIn = false

    init(moment: PraiseMoment, onDone: @escaping () -> Void) {
        self.moment = moment
        self.onDone = onDone
        _value = State(initialValue: moment.from)
    }

    private static var kickers: [String] { [L("すごい！"), L("おめでとう"), L("やったね！")] }
    private var kicker: String { Self.kickers[abs(moment.to + moment.kind.rawValue.count) % Self.kickers.count] }

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x1E2B55), Color(hex: 0x070B18)], center: .center, startRadius: 20, endRadius: 520)
                .ignoresSafeArea()
            Rays(turning: phase != .count && !reduceMotion)
                .opacity(phase == .count ? 0 : 0.55)
                .scaleEffect(phase == .count ? 0.6 : 1)
                .animation(.easeOut(duration: 0.9), value: phase)
                .ignoresSafeArea()
            Confetti(active: phase != .count && !reduceMotion)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                if let image = moment.image {
                    // The thing the learner was first to catch, lifted out of the photo (owner 2026-10-25).
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 180, maxHeight: 180)
                        .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
                        .shadow(color: Theme.gold.opacity(phase == .count ? 0 : 0.55), radius: 28)
                        .scaleEffect(imageIn ? (phase == .burst ? 1.06 : 1) : 0.3)
                        .rotationEffect(.degrees(imageIn ? 0 : -12))
                        .opacity(imageIn ? 1 : 0)
                        .padding(.bottom, 6)
                        .accessibilityHidden(true)
                }
                Text(kicker)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(4)
                    .foregroundStyle(Theme.gold)
                Text(moment.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                Text(moment.format(value))
                    .font(.system(size: 76, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(LinearGradient(colors: [.white, Color(hex: 0xFFE7A8)], startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText(value: Double(value)))
                    .shadow(color: Theme.gold.opacity(0.5), radius: phase == .count ? 0 : 24)
                    .scaleEffect(phase == .burst ? 1.08 : 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(moment.caption)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .opacity(phase == .count ? 0 : 1)
                    .offset(y: phase == .count ? 8 : 0)
                Text(moment.note)  // lang-ok: the app's own text (L), never from the server
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .opacity(phase == .ready || phase == .leaving ? 1 : 0)
                Text(L("続ける"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x33291F))
                    .padding(.horizontal, 36)
                    .frame(minHeight: 50)
                    .background(LinearGradient(colors: [Color(hex: 0xFFE7A8), Theme.gold], startPoint: .top, endPoint: .bottom), in: Capsule())
                    .shadow(color: Theme.gold.opacity(0.5), radius: 14, y: 5)
                    .opacity(phase == .ready ? 1 : 0)
                    .scaleEffect(phase == .ready ? 1 : 0.85)
                    .padding(.top, 26)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 28)
            .scaleEffect(phase == .leaving ? 1.08 : 1)
            .opacity(phase == .leaving ? 0 : 1)
        }
        .contentShape(.rect)
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([moment.title, moment.format(moment.to), moment.caption, moment.note].joined(separator: " "))  // lang-ok: the app's own text (L)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("praise.celebration")
        .statusBarTone(.light)
        .onAppear(perform: run)
        .onDisappear { task?.cancel() }
    }

    private func run() {
        if reduceMotion {
            value = moment.to; phase = .ready; imageIn = true
            return
        }
        task = Task { @MainActor in
            if moment.image != nil {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { imageIn = true }
                Haptics.impact(.light)
            }
            try? await Task.sleep(for: .milliseconds(250))
            // 1) The number counts to the learner's place (ease-out: it slows before the end — one beat of suspense).
            let distance = abs(moment.to - moment.from)
            let steps = max(1, min(distance, 36))
            if distance > 0 {
                for i in 1...steps {
                    let p = Double(i) / Double(steps)
                    let e = 1 - pow(1 - p, 3)
                    let v = moment.from + Int((e * Double(moment.to - moment.from)).rounded())
                    withAnimation(.snappy(duration: 0.08)) { value = v }
                    if i % 3 == 0 { Haptics.impact(.light, intensity: 0.4) }
                    try? await Task.sleep(for: .milliseconds(Int(1200.0 / Double(steps))))
                    if Task.isCancelled { return }
                }
            }
            value = moment.to
            // 2) Burst: confetti, fanfare and the tap in the same instant.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { phase = .burst }
            Haptics.success()
            HapticPatterns.shared.bloom()
            SoundService.shared.play(.sting)
            try? await Task.sleep(for: .milliseconds(650))
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { phase = .ready }
        }
    }

    private func finish() {
        guard phase != .leaving else { return }
        if phase != .ready {
            task?.cancel()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { value = moment.to; phase = .ready; imageIn = true }
            return
        }
        Haptics.impact(.medium)
        withAnimation(.easeIn(duration: 0.4)) { phase = .leaving }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 420))
            onDone()
        }
    }
}

/// After a new word is saved: decide (`PraiseSchedule`), read the learner's standing only when a praise is due, and show
/// it — or the system's review sheet on the word after a praise — once the catch's landing has ended.
@MainActor
enum PraiseFlow {
    static func afterCatch(_ caught: CaughtWord, router: AppRouter, dex: DexStore, start: Date?,
                           requestReview: RequestReviewAction) async {
        // The UI tests' demo accounts (`-uiDemo`) start with many words: a praise over their next catch would cover the
        // screens they walk through. Only `-uiDemoPraise YES` lets it show there.
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "uiDemo") != nil, !defaults.bool(forKey: "uiDemoPraise") { return }
        let uid = SupabaseClient.shared.userId
        guard let uid else { return }
        var schedule = PraiseSchedule.load(userId: uid)
        let total = dex.wordCount
        let decision = schedule.noteCatch(totalWords: total)
        schedule.save(userId: uid)
        // Never over the first tour (its own guide is on screen); the catch still counts.
        guard router.tour == .off else { return }
        switch decision {
        case .none:
            return
        case .askReview:
            guard await waitForCalm(router), SupabaseClient.shared.userId == uid else { return }
            UITestTrace.log("praise review ask")
            requestReview()
        case .praise:
            // Read while the landing plays; offline or a slow answer leaves the learner's own counts.
            let input: [String: Any] = caught.wordId.isEmpty ? [:] : ["word_id": caught.wordId]
            let standing = try? await NativeAPI.call("getMyStanding", input, as: MyStanding.self, timeout: 8, asUser: uid)
            let options = PraiseMoment.options(standing: standing, headword: caught.headword, totalWords: total, start: start,
                                               image: caught.image)
            guard let moment = PraiseMoment.pick(options, recent: schedule.recentKinds) else { return }
            // Still covered (a word sheet, the paywall…): this praise is skipped, and the next catch may bring one.
            guard await waitForCalm(router), SupabaseClient.shared.userId == uid, router.praise == nil else { return }
            var s = PraiseSchedule.load(userId: uid)
            s.notePraised(kind: moment.kind.rawValue)
            s.save(userId: uid)
            UITestTrace.log("praise show \(moment.kind.rawValue)")
            withAnimation(.easeOut(duration: 0.35)) { router.praise = moment }
        }
    }

    /// The landing is over, nothing else covers the screen, and a short breath has passed (so the praise is its own
    /// moment, not part of the landing). False when the screen is still covered after about 20 s.
    private static func waitForCalm(_ router: AppRouter) async -> Bool {
        func covered() -> Bool { router.landing != nil || router.detailSticker != nil || router.showPaywall || router.showCatchLimit }
        var waited = 0
        while covered(), waited < 100 {
            try? await Task.sleep(for: .milliseconds(200))
            waited += 1
        }
        try? await Task.sleep(for: .milliseconds(700))
        return !covered() && router.tour == .off
    }
}

/// A new word just saved (not a re-encounter): what the praise needs to know about it.
struct CaughtWord: Equatable {
    let id = UUID()
    let wordId: String
    let headword: String
    /// The cut-out of the thing caught (or the photo when it could not be cut out).
    var image: UIImage? = nil
}
