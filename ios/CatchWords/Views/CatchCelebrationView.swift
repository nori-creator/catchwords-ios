import SwiftUI

/// The GET moment (concept film v6, `dGet` / `getText` after the choice P): the word gets its own moment before it
/// goes into the 図鑑. The sticker glides from the choose screen onto a lit stage (`CatchStageScene`) and grows, the
/// voice says the word while its characters land one per syllable, the meaning and the note follow, then
/// 「新しいことばをキャッチ！」 pops with the catch jingle, sparkles and two rings running out across the floor. It holds
/// so the word can be read and heard; at P + 2.9 the texts fade and at P + 3.0 the word goes into the 図鑑 by itself
/// (`onAdd`, the landing flies the sticker into its slot). A tap anywhere skips ahead; 「戻る」 undoes until then.
/// The first tour keeps the old ending: it holds, and 「図鑑に追加」 is pressed by the learner (its coach mark).
/// Never waits for the cut-out: the photo round the thing stands in until it is ready.
///
/// A word already in the dex (`vm.owned`, a re-encounter) gets the very same moment (owner 2026-10-15: 「再会も新しい
/// 単語と同じアニメーションで」): only the words say it is a re-encounter — 「また会えた！」 with 「再会 N回目」 where NEW
/// was, and when and where it was first caught under the meaning — and `onAdd` records the new photo on that word.
struct CatchCelebrationView: View {
    let vm: CaptureViewModel
    /// The save started from here is still running: no second start, no going back.
    var saving: Bool = false
    /// Saves the catch and opens the dex. False = it did not start (a notice says why; the button takes over).
    let onAdd: () async -> Bool
    /// The sticker's frame on screen (global) at the hand-over, where the landing's sticker starts.
    var onStickerFrame: (CGRect) -> Void = { _ in }

    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(AppRouter.self) private var router
    @Environment(DexStore.self) private var dex

    /// P (the choice) on `CCClock`: the origin of every time below.
    @State private var origin: Double
    /// Added to the clock by a tap that skips ahead to the end.
    @State private var shift: Double = 0
    /// Where a skip started (the sounds it jumped over stay silent).
    @State private var skippedFrom: Double?
    @State private var palette: StagePalette
    @State private var fallback: UIImage?
    @State private var dexLabel: String?
    /// The texts have faded (`Film6.out`): no more skipping or going back.
    @State private var pastOut = false
    /// The word is on its way into the 図鑑.
    @State private var handing = false
    /// The automatic add did not start (a notice says why): 「図鑑に追加」 takes over.
    @State private var failed = false
    /// The first tour holds the end: the learner presses 「図鑑に追加」 (its coach mark points at it).
    @State private var tourHold = false
    @State private var screen: CGSize = .zero
    @State private var screenOrigin: CGPoint = .zero

    init(vm: CaptureViewModel, saving: Bool = false, onAdd: @escaping () async -> Bool,
         onStickerFrame: @escaping (CGRect) -> Void = { _ in }) {
        self.vm = vm
        self.saving = saving
        self.onAdd = onAdd
        self.onStickerFrame = onStickerFrame
        // Handed over from the choose screen: the timeline goes on from where that screen held it (normally P + .5),
        // so the two screens draw the very same frame at the hand-over.
        let now = CCClock.now
        var o = now
        if let p = vm.stageOrigin, let h = vm.stageHandoff { o = now - min(max(0, now - p), h) }
        _origin = State(initialValue: o)
        _palette = State(initialValue: vm.stagePalette ?? .plain)
        _fallback = State(initialValue: vm.stageFallback)
    }

    private var busy: Bool { handing || saving }

    /// A re-encounter: the word is in the dex already.
    private var again: OwnedWord? { vm.owned }

    /// The full-screen skip and the tour's button: the UI tests tell a re-encounter's moment by its identifier.
    private var catchIdentifier: String { again == nil ? "card.catch" : "reencounter.get" }

    private func time(_ now: Double) -> Double { now - origin + shift }

    /// The texts fade at `out` (never while the tour holds the end).
    private func textAlpha(_ tc: Double) -> Double {
        tourHold ? 1 : 1 - Film6.inOutCubic(Film6.seg(tc, Film6.out, Film6.out + 0.25))
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let size = geo.size
                // Once the word flies into the 図鑑, the 図鑑's page rises over this screen: it stops being redrawn
                // under it (it went on for the 0.6 s the camera screen stays, under the landing).
                TimelineView(.animation(minimumInterval: nil, paused: router.landing != nil)) { _ in
                    let now = CCClock.now
                    let tc = time(now)
                    ZStack(alignment: .topLeading) {
                        CatchStageScene(size: size, cut: vm.cutout, fallback: fallback, palette: palette,
                                        sinceChoice: tc, live: now, calm: reduceMotion, hideSticker: router.landing != nil)
                        headline(tc, size)
                        meaningBlock(tc, size)
                    }
                    .frame(width: size.width, height: size.height)
                }
                .onAppear {
                    screen = size
                    screenOrigin = geo.frame(in: .global).origin
                }
                .onChange(of: size) { _, s in screen = s }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if !tourHold && !pastOut && !failed {
                // A tap anywhere skips ahead to the end (the UI tests tap it as 図鑑に追加).
                Button(action: skip) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .ignoresSafeArea()
                .accessibilityLabel(L("図鑑に追加"))
                .accessibilityIdentifier(catchIdentifier)
            }

            GeometryReader { geo in
                let size = geo.size
                TimelineView(.animation(minimumInterval: nil, paused: router.landing != nil)) { _ in
                    wordLine(time(CCClock.now), size)
                }
            }
            .ignoresSafeArea()

            controls
        }
        .environment(\.colorScheme, .light)
        .task { await run() }
        .onChange(of: vm.cutout) { _, cut in
            if let cut { palette = StagePalette.make(from: cut) }
        }
    }

    // MARK: Texts

    /// 「新しいことばをキャッチ！」 pops with the jingle (scale .6 → 1, strong overshoot), the NEW chip with the 図鑑
    /// number under it, six sparkles round it. A re-encounter: 「また会えた！」 and 「再会 N回目」 in the chip.
    @ViewBuilder
    private func headline(_ tc: Double, _ size: CGSize) -> some View {
        let W = size.width, H = size.height, k = W / 1080
        let hp = Film6.seg(tc, Film6.catchT, Film6.catchT + 0.4)
        let a = textAlpha(tc)
        if hp > 0 {
            let s = reduceMotion ? 1 : CGFloat(Film6.lerp(0.6, 1, Film6.outBack(hp, 2.6)))
            Text(again == nil ? L("新しいことばをキャッチ！") : L("また会えた！"))
                .font(.system(size: 66 * k, weight: .black))
                .foregroundStyle(Theme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: W * 0.88)
                .scaleEffect(s)
                .opacity(min(1, hp * 4) * a)
                .position(x: W / 2, y: Film6.y(552, H))
            if dexLabel != nil || again != nil {
                let cp = Film6.outCubic(Film6.seg(tc, Film6.catchT + 0.12, Film6.catchT + 0.42))
                CatchDexChip(label: dexLabel, scale: W / 393,
                             badge: again.map { L("再会\($0.encounterCount + 1)回目") })
                    .opacity(cp * a)
                    .position(x: W / 2, y: Film6.y(636, H) + CGFloat(1 - cp) * 14 * k)
            }
            if !reduceMotion {
                ForEach(Array(Self.sparkles.enumerated()), id: \.offset) { i, sp in
                    let u = Film6.seg(tc, Film6.catchT + sp.d, Film6.catchT + sp.d + 0.9)
                    if u > 0, u < 1 {
                        let grow = Film6.outBack(Film6.seg(u, 0, 0.3), 3) * (1 - Film6.inCubic(Film6.seg(u, 0.55, 1)))
                        let r = CGFloat(max(0.1, sp.r * grow * (0.75 + 0.25 * sin(u * 20)))) * k
                        let x = W / 2 + CGFloat(sp.dx * Film6.lerp(0.86, 1.04, Film6.outCubic(u))) * k
                        Star4()
                            .fill(sp.cyan ? Theme.cyan : Theme.primaryBright)
                            .frame(width: 2 * r, height: 2 * r)
                            .rotationEffect(.radians(u * 1.2))
                            .opacity(a)
                            .position(x: x, y: Film6.y(550 + sp.dy, H))
                    }
                }
            }
        }
    }

    /// Film `getText`'s sparkles: offset from the headline (px), radius (px), delay (s), colour.
    private static let sparkles: [(dx: Double, dy: Double, r: Double, d: Double, cyan: Bool)] = [
        (-430, -40, 34, 0, false), (424, -70, 28, 0.05, true), (-392, 52, 20, 0.1, false),
        (452, 34, 30, 0.07, true), (-470, 6, 16, 0.14, true), (330, -112, 18, 0.12, true),
    ]

    /// The word, one character per syllable as the voice says it, and the speaker beside it.
    @ViewBuilder
    private func wordLine(_ tc: Double, _ size: CGSize) -> some View {
        if let c = vm.picked {
            let W = size.width
            let n = max(1, CatchWordPop.units(c).count)
            let ws = min(W * 150 / 1080, W * 0.66 / (CGFloat(n) * 1.45))
            let sa = Film6.outCubic(Film6.seg(tc, Film6.voice - 0.1, Film6.voice + 0.15)) * textAlpha(tc)
            HStack(spacing: W * 0.035) {
                CatchWordPop(candidate: c, size: ws, tc: tc, calm: reduceMotion, alpha: textAlpha(tc))
                    .allowsHitTesting(false)
                ZStack {
                    voiceRings(tc)
                    PronounceCircle(text: c.headword, size: 34, light: true)
                        .tourAnchor(.headword)
                }
                .opacity(sa)
                .allowsHitTesting(sa > 0.5)
            }
            .frame(maxWidth: W * 0.94)
            .position(x: W / 2, y: Film6.y(1546, size.height))
        }
    }

    /// The speaker shows the voice: two blue rings going out from it as the word is said.
    @ViewBuilder
    private func voiceRings(_ tc: Double) -> some View {
        let v = Film6.seg(tc, Film6.voice, Film6.voice + 0.9)
        if v > 0, v < 1, !reduceMotion {
            ForEach(0..<2, id: \.self) { i in
                let u = Film6.clamp(v * 1.4 - Double(i) * 0.3)
                if u > 0, u < 1 {
                    Circle()
                        .stroke(Theme.primary, lineWidth: 1.5)
                        .frame(width: CGFloat(34 + 29 * Film6.outCubic(u)), height: CGFloat(34 + 29 * Film6.outCubic(u)))
                        .opacity((1 - u) * 0.5)
                }
            }
        }
    }

    /// The register chip and the meaning, then the note on when the word is used.
    @ViewBuilder
    private func meaningBlock(_ tc: Double, _ size: CGSize) -> some View {
        if let c = vm.picked {
            let W = size.width, H = size.height, k = W / 1080
            let ma = Film6.outCubic(Film6.seg(tc, Film6.meaning, Film6.meaning + 0.3))
            let a = textAlpha(tc)
            if ma > 0 {
                HStack(spacing: 20 * k) {
                    if let reg = Self.registerChip(c.register) {
                        Text(reg)
                            .font(.system(size: 28 * k, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x5C646F))
                            .lineLimit(1)
                            .padding(.horizontal, 18 * k)
                            .frame(height: 50 * k)
                            .background(Color(hex: 0xEDF2F8), in: Capsule())
                            .fixedSize()
                    }
                    Text(meaning(c))
                        .font(.system(size: 38 * k, weight: .medium))
                        .foregroundStyle(Color(hex: 0x5C646F))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: W * 0.9)
                .opacity(ma * a)
                .position(x: W / 2, y: Film6.y(1690, H) + CGFloat(1 - ma) * 16 * k)
                // A re-encounter: when (and where) it was first caught, as the re-encounter card said.
                let note = again.map { Self.metLine($0) } ?? ReaderLanguage.shown(c.distinction, hanOnlyOk: false)
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 30 * k, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0066CC))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: W * 0.86)
                        .opacity(Film6.outCubic(Film6.seg(tc, Film6.meaning + 0.15, Film6.meaning + 0.45)) * a)
                        .position(x: W / 2, y: Film6.y(1776, H) + CGFloat(1 - ma) * 16 * k)
                }
            }
        }
    }

    /// A register chip only for the other ways of saying it (the everyday word has none, as in the film).
    private static func registerChip(_ register: String?) -> String? {
        guard let r = NameRegister.normalize(register), r != .common else { return nil }
        return r.label
    }

    /// The card's meaning once it arrives (reader language, scrubbed), else the candidate's. A re-encounter: the
    /// meaning the word has in the dex.
    private func meaning(_ c: Candidate) -> String {
        if let again {
            let own = ReaderLanguage.gloss(ReaderLanguage.shown(again.meaningJa))
            if !own.isEmpty { return own }
        }
        let m = vm.details?.raw?["meaning_ja"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ReaderLanguage.gloss(ReaderLanguage.shown(m, c.meaningJa))
    }

    /// 「この言葉、{date}に{place}でゲットしています。」 (web cap.reencBefore + reencAt/reencOn + reencAfter).
    static func metLine(_ owned: OwnedWord) -> String {
        let date = owned.takenDate.map { $0.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(L10n.locale)) } ?? ""
        if let place = owned.locationName, !place.isEmpty {
            return L("この言葉、\(date)に\(place)でゲットしています。")
        }
        return L("この言葉、\(date)にゲットしています。")
    }

    // MARK: Controls

    private var controls: some View {
        VStack {
            HStack {
                if !pastOut && !handing {
                    Button { vm.backToCandidates() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").scaledFont(size: 13, weight: .semibold)
                            Text(L("戻る"))
                        }
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Color(hex: 0x5C646F))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(.white.opacity(0.8), in: Capsule())
                        .overlay(Capsule().stroke(Color(hex: 0xE0E5EB), lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(busy)
                    .accessibilityIdentifier("celebrate.back")
                    .transition(.opacity)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            Spacer()
            if tourHold || failed {
                Button { Task { await hand() } } label: {
                    HStack(spacing: 8) {
                        if busy {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "checkmark").scaledFont(size: 15, weight: .semibold)
                        }
                        Text(L("図鑑に追加")).scaledFont(size: 17, weight: .bold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Theme.primary, in: Capsule())
                    .shadow(color: Theme.primary.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(PressableStyle())
                .disabled(busy)
                .accessibilityIdentifier(catchIdentifier)
                .tourAnchor(.peel)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: pastOut)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: failed)
    }

    // MARK: The timeline

    /// The moment's sounds, haptic and the hand-over, each at its time (a skip jumps over the ones before the end).
    private func run() async {
        tourHold = router.tour.isCapture
        if vm.cutout == nil, fallback == nil { fallback = vm.stickerFallback() }
        if vm.stagePalette == nil { palette = StagePalette.make(from: vm.cutout ?? fallback) }
        if let c = vm.picked { dexLabel = CatchDexInfo.label(headword: c.headword, stickers: dex.stickers) }
        if let c = vm.picked { SoundService.shared.prefetch(c.headword) }
        let events: [(at: Double, id: Int)] = [(Film6.stageIn0, 0), (Film6.voice, 1), (Film6.catchT, 2),
                                               (Film6.out, 3), (Film6.open, 4)]
        var fired = Set<Int>()
        while !Task.isCancelled {
            let t = time(CCClock.now)
            for e in events where !fired.contains(e.id) && t >= e.at {
                fired.insert(e.id)
                if let from = skippedFrom, from < e.at, e.at < Film6.out { continue }
                fire(e.id)
            }
            if fired.count == events.count || (tourHold && fired.contains(2)) { return }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func fire(_ id: Int) {
        switch id {
        case 0:
            SoundService.shared.playLayered(.c6StagePad)
        case 1:
            if let w = vm.picked { SoundService.shared.speak(w.headword) }
        case 2:
            Haptics.success()
            SoundService.shared.playLayered(.c6CatchJingle)
        case 3:
            if !tourHold { pastOut = true }
        default:
            if !tourHold { Task { await hand() } }
        }
    }

    /// A tap anywhere: on to the end (the texts fade, then the word goes into the 図鑑).
    private func skip() {
        let t = time(CCClock.now)
        guard t < Film6.out, !busy else { return }
        skippedFrom = t
        shift += Film6.out - t
    }

    /// The word goes into the 図鑑: the landing takes the sticker from where it is now.
    private func hand() async {
        guard !handing, !saving else { return }
        handing = true
        failed = false
        pastOut = true
        let tc = time(CCClock.now)
        let cut = vm.cutout ?? fallback
        let aspect = cut.map { $0.size.height > 0 ? $0.size.width / $0.size.height : 1 } ?? 1
        let p = Film6.pose(screen: screen, aspect: aspect, start: nil, sinceTap: 99, sinceChoice: max(tc, 2),
                           live: CCClock.now, bobWeight: 1, calm: reduceMotion)
        onStickerFrame(CGRect(x: screenOrigin.x + p.center.x - p.size.width / 2, y: screenOrigin.y + p.center.y - p.size.height / 2,
                              width: p.size.width, height: p.size.height))
        let started = await onAdd()
        if !started {
            handing = false
            failed = true
        }
    }
}

/// The word as the voice says it (film `wordPop`): each character lands with its syllable — scale 1.38 → 1 with an
/// overshoot, blurred to sharp in the first third, a soft blue glow pulsing behind it — its reading beside it. A word
/// that cannot be split one syllable per character (English, kana) lands as one.
struct CatchWordPop: View {
    let candidate: Candidate
    let size: CGFloat
    let tc: Double
    let calm: Bool
    var alpha: Double = 1

    struct Unit {
        let text: String
        let zhuyin: String?
        let pinyin: String?
    }

    /// One unit per character with its zhuyin syllable (Taiwan Mandarin), else the whole word.
    static func units(_ c: Candidate) -> [Unit] {
        let lang = NativeAPI.targetLanguage
        guard lang != "en", lang != "ja", let pairs = ZhuyinLayout.pair(c.headword, c.zhuyin) else {
            return [Unit(text: c.headword, zhuyin: c.zhuyin, pinyin: c.pinyin)]
        }
        let py = PinyinLayout.pair(c.headword, pinyin: c.pinyin, zhuyin: c.zhuyin)
        return pairs.enumerated().map { i, u in
            let reading = u.hasReading ? (u.neutral ? "˙" : "") + u.body.joined() + u.tone : nil
            let p = py.flatMap { i < $0.count ? $0[i].reading : nil }
            return Unit(text: u.char, zhuyin: reading, pinyin: p)
        }
    }

    var body: some View {
        let units = Self.units(candidate)
        HStack(alignment: .center, spacing: size * 0.06) {
            ForEach(Array(units.enumerated()), id: \.offset) { i, u in
                let t0 = Film6.voice + 0.04 + Double(i) * Film6.charStep
                let p = Film6.seg(tc, t0 - 0.02, t0 + 0.32)
                let g = Film6.seg(tc, t0, t0 + 0.6)
                ZhuyinWordView(headword: u.text, zhuyin: u.zhuyin, size: size, weight: .semibold,
                               color: Color(hex: 0x0B121A), readingColor: Color(hex: 0x5C646F), pinyin: u.pinyin)
                    .fixedSize(horizontal: units.count > 1, vertical: true)
                    .background {
                        if g > 0, g < 1, !calm {
                            Circle()
                                .fill(RadialGradient(colors: [.rgba(42, 155, 255, 0.28 * sin(.pi * g)), .rgba(42, 155, 255, 0)],
                                                     center: .center, startRadius: 0, endRadius: size * 1.1))
                                .frame(width: size * 2.2, height: size * 2.2)
                                .allowsHitTesting(false)
                        }
                    }
                    .scaleEffect(calm ? 1 : CGFloat(Film6.lerp(1.38, 1, Film6.outBack(p, 1.9))))
                    .blur(radius: calm || p >= 0.35 ? 0 : CGFloat(1 - p / 0.35) * size * 0.047)
                    .opacity(Film6.clamp(p * 3) * alpha)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(candidate.headword)
    }
}

/// Paper confetti that bursts once and flutters down.
struct Confetti: View {
    let active: Bool
    @State private var start: Date?

    private static let colors: [Color] = [Color(hex: 0xF4B93C), Color(hex: 0x64E0FF), Color(hex: 0xFF7EB6), Color(hex: 0xA78BFA), Color(hex: 0x4ADE80), .white]

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { tl in
            Canvas { ctx, size in
                guard let start else { return }
                let t = tl.date.timeIntervalSince(start)
                guard t < 3.2 else { return }
                for i in 0..<70 {
                    let seed = Double(i)
                    let ang = seed * 2.399
                    let speed = 180 + (seed * 37).truncatingRemainder(dividingBy: 220)
                    let x0 = size.width / 2, y0 = size.height * 0.42
                    let vx = cos(ang) * speed, vy = sin(ang) * speed - 160
                    let x = x0 + vx * t * 1.1 + sin(t * 3 + seed) * 12
                    let y = y0 + vy * t + 260 * t * t
                    let alpha = max(0, 1 - t / 3.2)
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(t * (4 + seed.truncatingRemainder(dividingBy: 5)) + seed))
                    let w = 5 + seed.truncatingRemainder(dividingBy: 4), h = 3 + seed.truncatingRemainder(dividingBy: 3)
                    c.fill(Path(CGRect(x: -w / 2, y: -h / 2, width: w, height: h * abs(cos(t * 6 + seed)) + 1)),
                           with: .color(Self.colors[i % Self.colors.count].opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: active) { _, on in if on { start = Date() } }
    }
}
