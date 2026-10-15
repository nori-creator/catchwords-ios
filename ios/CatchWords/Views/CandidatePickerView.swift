import SwiftUI

/// After the shot: the photo with each word the AI found as a tag ON its object — deep inside the Vision instance
/// its outline goes round (`CatchObject.anchor`; owner 2026-10-11 「しっかりもののうえに名前タグをおいて」), the AI's
/// point only when Vision found no instance for it — and "違う単語を入力" underneath for a word that is not among them.
/// A tap on a tag goes straight to the celebration (owner 2026-10-09: shoot → words → tap → done).
/// - One tag per THING, named in the reader's own language (owner 2026-10-14: 「表示するのは母語にして」「表示する
///   タグは言い方ではなく、異なるものにして」): 鮮乳 / 牛奶 / 全脂鮮乳 were three tags for one bottle, in Mandarin.
///   A thing with several ways to say it (一般的な言い方 / 口語 / より詳しい言い方 / 学術的な言い方 / 固有名詞 — the
///   server's `group` and `register`, `NameRegister`) opens the list of them on a tap, to pick the one to learn (web
///   CandidatePicker's ほかの言い方); a thing with one name goes straight on. The tag is the thing's everyday name
///   (owner 2026-10-15: never a detailed name or a proper noun). Tags never cover each other (`CCPickLayout`), and stay
///   inside the photo.
/// - Without a position (the AI gave none) and no Vision instance there, the words gather at the photo's centre,
///   still one per line.
/// - From the shutter on (`.processing`) the same screen runs the catch scan over the photo (v10, owner 2026-10-11:
///   bracket, light pen, `CatchScan.swift`), and each tag comes up where it is tapped, when the scan brings it up.
///   Typing a word waits until the names are in.
struct CandidatePickerView: View {
    let vm: CaptureViewModel
    /// The names are not in yet (`.processing`): the scan is running and nothing can be typed. Handed in by the camera
    /// screen, which switches on `vm.step`: this view must never read `vm.step` itself. When it did, the camera screen
    /// missed the change to `.celebrate` made right after the tap (it was redrawn during that change and kept the old
    /// step), so the words stayed on screen and the celebration never opened (the UI tour's 5 of 6, trace 2026-10-11).
    let scanning: Bool
    @State private var appeared: Bool = false
    @State private var typed: String = ""
    @FocusState private var inputFocused: Bool
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(AppRouter.self) private var router
    @Environment(DexStore.self) private var dex
    /// The choose screen over the photo (film v6 "D"), nil = the tags.
    @State private var flow: ChooseFlow?
    /// The photo melting into the app's page under the choose screen.
    @State private var melt = false
    /// The photo stage on screen (global): where each thing's sticker lifts from.
    @State private var stageFrame: CGRect = .zero
    /// DEBUG previews: open the first thing with several ways to say it once the tags are up.
    var autoOpen: Bool = false
    /// DEBUG previews (`-uiPreview choose`): open it once and keep it open (nothing is chosen).
    var holdOpen: Bool = false

    private let ink = Color(hex: 0x0B121A)

    /// One way to say a thing, with the object its cut-out comes from.
    private struct Choice: Identifiable {
        let word: Candidate
        let object: CatchObject
        var id: String { "\(object.id)-\(word.headword)" }
    }

    /// One thing's tag over the photo.
    private struct Tag: Identifiable {
        let id: String
        /// Where the tag sits and what the scan waits for.
        let object: CatchObject
        /// Its ways to say it: the everyday one first (一般的 → 口語 → より詳しい → 学術的 → 固有名詞).
        let choices: [Choice]
        /// The tag's text: the everyday name's meaning in the reader's language (`tagLabel`; never a learning-language
        /// word).
        let label: String
        /// The key two tags with the same name are merged by (nil: the label is not a name, never merged).
        var nameKey: String? = nil
        /// Order among the tags (`candidate.<n>`).
        let mainIndex: Int?
        var word: Candidate { choices[0].word }
    }

    /// The choose screen's state: what is chosen from, when, and the choice (`CCClock` times).
    private struct ChooseFlow {
        /// The ways to say it, the everyday one first.
        let words: [Candidate]
        /// The thing each word's cut-out comes from (nil: a word typed under the photo — the photo's main subject).
        let objects: [CatchObject?]
        /// The line under 「覚える単語を選ぶ」: what is in the photo, or what was typed.
        let subtitle: String
        /// The thing the photo melts towards and a typed word is looked up for (nil: the photo itself).
        let anchor: CatchObject?
        /// The words were found by typing (`CaptureViewModel.search`): always a card, even for one, and chosen as typed.
        let typed: Bool
        let tappedAt: Double
        /// When the rows came in (a search on the open card replaces its rows; nil = with the card).
        var rowsAt: Double? = nil
        var chosenAt: Double?
        var chosen: Int?
        var closingAt: Double?
        let start: CGRect?
        let cut: UIImage?
        let fallback: UIImage?
        let palette: StagePalette
        let dexLabel: String?
    }

    /// A tag with its size and its bottom centre in the photo stage.
    private struct Placed: Identifiable {
        let tag: Tag
        let size: CGSize
        let spot: CGPoint
        var id: String { tag.id }
    }

    /// The photo's objects. Built here from the words alone when the analysis did not build them
    /// (no masks: each object gets the box around its own point).
    private var objects: [CatchObject] {
        if !vm.objects.isEmpty { return vm.objects }
        guard let photo = vm.photo, !vm.candidates.isEmpty else { return [] }
        return CatchObject.build(candidates: vm.candidates, masks: nil, photoSize: photo.size)
    }

    var body: some View {
        ZStack {
            MachineBackground()
            VStack(spacing: 12) {
                topBar
                photoStage
                    .clipShape(.rect(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 10)
                bottomPanel
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .disabled(scanning)
                    .opacity(scanning ? 0.5 : 1)
                    .animation(.easeOut(duration: 0.25), value: scanning)
            }
            if let f = flow {
                CatchChooseOverlay(words: f.words, subtitle: f.subtitle,
                                   dexLabel: f.dexLabel, cut: f.cut ?? (f.chosenAt != nil ? vm.cutout : nil),
                                   fallback: f.fallback, palette: f.palette, start: f.start,
                                   tappedAt: f.tappedAt, chosenAt: f.chosenAt, chosen: f.chosen, closingAt: f.closingAt,
                                   calm: reduceMotion, alwaysCard: true, rowsAt: f.rowsAt, searching: vm.isLookingUp,
                                   searchError: vm.searchError, onChoose: pick, onClose: closeChoices,
                                   onSearch: searchFromChoices)
                    .zIndex(5)
            }
            // The choose screen keeps its sticker floating while the word is checked (no dark wait over it).
            if vm.isCheckingOwned && flow == nil {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .allowsHitTesting(!vm.isCheckingOwned)
        // A new photo (撮り直す) or the move on to the celebration closes the choose screen.
        .onChange(of: scanning) { _, _ in
            flow = nil
            melt = false
        }
        .task(id: autoOpen) { await openForPreview() }
        // A typed word's lookup brought words: the choose screen lists them (never straight on to the catch).
        .onChange(of: vm.typedRound) { _, _ in openTyped() }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
            }
        }
        .task(id: vm.scan.map { ObjectIdentifier($0) }) { await runScan() }
    }

    /// Steps this photo's scan about 60 times a second (its sounds, its tags) until everything is up.
    private func runScan() async {
        guard let scan = vm.scan else { return }
        scan.begin(now: Date())
        while !Task.isCancelled, !scan.settled {
            scan.step(now: Date(), reduceMotion: reduceMotion)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// The line at the top right: what the scan is doing, then what to do.
    private var topHint: String {
        switch vm.scan?.phase {
        case .scanning?: return L("写真をスキャンしています")
        case .naming?: return L("名前を調べています")
        default: return L("覚えたいことばをタップ")
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { vm.reset() } label: {
                Label(L("撮り直す"), systemImage: "arrow.counterclockwise")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(.white.opacity(0.12), in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("picker.retake")
            Spacer(minLength: 8)
            Text(topHint)
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: topHint)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: The photo and its tags

    private var photoStage: some View {
        GeometryReader { geo in
            let size = geo.size
            let placedTags = placed(in: size)
            let _ = UITestTrace.log(traceStage(size, placedTags))
            ZStack(alignment: .topLeading) {
                if let photo = vm.photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .allowsHitTesting(false)
                }
                if let scan = vm.scan, let photo = vm.photo {
                    CatchScanOverlay(scan: scan, photo: photo.size, reduceMotion: reduceMotion)
                        .frame(width: size.width, height: size.height)
                        // On the tap the outlines fade out in .5 s (the film's v8 note).
                        .opacity(flow == nil ? 1 : 0)
                        .animation(.easeOut(duration: 0.5), value: flow == nil)
                }
                ForEach(placedTags) { p in
                    tagButton(p)
                        .position(x: p.spot.x, y: p.spot.y - p.size.height / 2)
                }
            }
            .frame(width: size.width, height: size.height)
            // The choose screen melts the photo (film: blur 40 px, brightness +6%, scale 1.08 round the thing).
            .blur(radius: melt ? 15 : 0)
            .brightness(melt ? 0.06 : 0)
            .scaleEffect(melt ? 1.08 : 1, anchor: meltAnchor)
            .contentShape(.rect)
            .onTapGesture {
                UITestTrace.log("stage.tap")
                inputFocused = false
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                stageFrame = frame
            }
            .onChange(of: size, initial: true) { _, s in layoutScan(s) }
            .onChange(of: vm.scan.map { ObjectIdentifier($0) }) { _, _ in layoutScan(size) }
        }
    }

    /// The UI tests' trace of a render of the stage (`UITestTrace`, DEBUG + `-uiDemo` only): what it shows and can take.
    private func traceStage(_ size: CGSize, _ placedTags: [Placed]) -> String {
        let shown = placedTags.filter { vm.scan?.revealed.contains($0.tag.object.id) ?? true }.map(\.id)
        let state = "scanning=\(scanning) checking=\(vm.isCheckingOwned) enabled=\(isEnabled)"
        return "picker.stage \(Int(size.width))x\(Int(size.height)) \(state) shown=\(shown)"
    }

    /// Tells the scan where the photo sits on the stage (it draws in the stage's points).
    private func layoutScan(_ size: CGSize) {
        guard let scan = vm.scan, let photo = vm.photo else { return }
        scan.layout(stage: size, fill: Self.fillRect(image: photo.size, in: size))
    }

    /// One tag per thing. Two objects the AI kept apart but that read the same in the reader's language (鮮乳 and
    /// 牛奶 both 「牛乳」) are one thing to the learner: one tag, both names in its list.
    private func tags(_ objects: [CatchObject]) -> [Tag] {
        var out: [Tag] = []
        for o in objects {
            // 一般的 → 口語 → より詳しい → 学術的 → 固有名詞, a register on every name (the server orders them too; this
            // keeps the list right with an older answer). Same register keeps the AI's order (likelihood).
            let words = NameRegister.finalized(o.words)
            let choices = words.map { Choice(word: $0, object: o) }
            guard !choices.isEmpty else { continue }
            let tag = Self.tagLabel(words)
            let key = tag.isName ? Self.mergeKey(tag.text) : nil
            if let key, let at = out.firstIndex(where: { $0.nameKey == key }) {
                let had = out[at]
                let added = choices.filter { c in !had.choices.contains { $0.word.headword == c.word.headword } }
                out[at] = Tag(id: had.id, object: had.object, choices: Self.ordered(had.choices + added),
                              label: had.label, nameKey: had.nameKey, mainIndex: had.mainIndex)
                continue
            }
            out.append(Tag(id: "\(o.id)", object: o, choices: choices, label: tag.text, nameKey: key, mainIndex: out.count))
        }
        return out
    }

    /// Everyday names before the others; within a register the order they came in.
    private static func ordered(_ list: [Choice]) -> [Choice] {
        list.indices.sorted { a, b in
            let ra = NameRegister.of(list[a].word).rank, rb = NameRegister.of(list[b].word).rank
            return ra != rb ? ra < rb : a < b
        }.map { list[$0] }
    }

    /// The tag on a thing (owner 2026-10-15): the most general everyday name, in the reader's language — the server's
    /// `object_label` (server #184, 下着 for boxer briefs), else the first gloss of the meaning of the thing's common
    /// name (`NameRegister.finalized` puts it first: 內褲 → 「下着」); never 「ボクサーパンツ」 (a more specific name's
    /// meaning) and never the learning-language word itself. With neither in the reader's language, the thing's
    /// category in it (服), which is never merged with another tag.
    static func tagLabel(_ words: [Candidate]) -> (text: String, isName: Bool) {
        guard let main = words.first else { return ("", false) }
        let label = ReaderLanguage.shown(main.objectLabel, words.lazy.map(\.objectLabel).first { !$0.isEmpty })
        if !label.isEmpty { return (ReaderLanguage.gloss(label, limit: L10n.lang == "en" ? 24 : 12), true) }
        let name = readerName(main)
        if !name.isEmpty { return (name, true) }
        let category = main.categoryKey ?? words.lazy.compactMap(\.categoryKey).first
        return (Category.label(for: category), false)
    }

    /// The thing's name in the reader's language: the first gloss of the meaning the server wrote in it (下着（パンツ類）
    /// → 下着; empty when it came back in another language — `ReaderLanguage.shown` drops it).
    private static func readerName(_ c: Candidate) -> String {
        let meaning = ReaderLanguage.shown(c.meaningJa)
        guard !meaning.isEmpty else { return "" }
        return ReaderLanguage.gloss(firstGloss(meaning), limit: L10n.lang == "en" ? 24 : 12)
    }

    /// The first of the meanings listed in `meaning` (「下着、パンツ」 → 下着, "underwear; briefs" → underwear), never
    /// cut inside a word (ボクサー・パンツ stays whole).
    static func firstGloss(_ meaning: String) -> String {
        let separators: Set<Character> = ["、", "，", ",", "；", ";", "／", "/", "（", "(", "。", "：", ":", "\n"]
        let first = meaning.split(whereSeparator: { separators.contains($0) }).first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return first.isEmpty ? meaning.trimmingCharacters(in: .whitespacesAndNewlines) : first
    }

    /// Names that are the same thing to the reader (case and spaces aside); nil = never merged.
    private static func mergeKey(_ label: String) -> String? {
        let k = label.lowercased().filter { !$0.isWhitespace }
        return k.isEmpty ? nil : k
    }

    private func placed(in size: CGSize) -> [Placed] {
        guard let photo = vm.photo, size.width > 0, size.height > 0 else { return [] }
        let list = tags(objects)
        guard !list.isEmpty else { return [] }
        let fill = Self.fillRect(image: photo.size, in: size)
        let sizes = list.map { CCPickLayout.tagSize(name: $0.label, badge: $0.choices.count > 1) }
        let tallest = sizes.map(\.height).max() ?? 30
        let area = CCPickLayout.Area(width: size.width, minBottom: tallest + 6,
                                     maxBottom: max(tallest + 6, size.height - 6), sideClamp: 0)
        var anchors: [CGPoint] = []
        for (i, t) in list.enumerated() {
            // Centred on the object's own place inside its Vision instance, put on the stage exactly as the scan puts
            // that instance's outline (`CatchScanShape`: the same `fill`), so the tag lands inside its own outline.
            let a = t.object.anchor
            let p = CGPoint(x: fill.minX + a.x * fill.width, y: fill.minY + a.y * fill.height)
            anchors.append(CCPickLayout.anchor(at: p, size: sizes[i], in: area))
        }
        let spots = CCPickLayout.layout(anchors: anchors, sizes: sizes, in: area)
        return list.indices.map { Placed(tag: list[$0], size: sizes[$0], spot: spots[$0]) }
    }

    /// White capsule with a blue dot and the thing's name in the reader's language; a thing with several ways to
    /// say it carries their number. With a scan, a tag comes up when the scan brings its object up (the film's rise:
    /// a little low, small and soft, then up into place).
    private func tagButton(_ p: Placed) -> some View {
        let t = p.tag
        let delay = 0.08 + Double(t.mainIndex ?? 4) * 0.06
        let scanned = vm.scan != nil
        let shown = vm.scan.map { $0.revealed.contains(t.object.id) } ?? appeared
        let rise = scanned && !reduceMotion && !shown
        let motion: Animation? = scanned
            ? (reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.68))
            : (reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7).delay(delay))
        return Button {
            UITestTrace.log("tag.action \(t.id) shown=\(shown) checking=\(vm.isCheckingOwned)")
            // The first tour's 選ぶ step dims everything but this tag: there the everyday name is taken at once, as before.
            if router.tour.isCapture || vm.photo == nil {
                vm.choose(t.word, object: t.choices[0].object)
            } else {
                open(t)
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(hex: 0x2A9BFF))
                    .frame(width: 10, height: 10)
                Text(t.label)
                    .font(.system(size: CCPickLayout.tagFontSize, weight: .heavy))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .fixedSize()
                if t.choices.count > 1 {
                    HStack(spacing: 2) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(t.choices.count)")
                            .font(.system(size: 11, weight: .heavy))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color(hex: 0x1F6FD1))
                    .frame(width: CCPickLayout.badgeWidth, height: 18)
                    .background(Color(hex: 0x2A9BFF).opacity(0.14), in: Capsule())
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.96), in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
            .contentShape(Capsule().inset(by: -6))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(t.label)
        .accessibilityHint(t.choices.count > 1 ? L("言い方が\(t.choices.count)つあります") : t.word.headword)
        .accessibilityIdentifier(t.mainIndex.map { "candidate.\($0)" } ?? "candidate.other")
        .tourAnchor(.pick, if: t.mainIndex == 0)
        .scaleEffect(shown ? 1 : (scanned ? 0.86 : 0.6))
        .offset(y: rise ? 6 : 0)
        .blur(radius: rise ? 3 : 0)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown && flow == nil)
        .accessibilityHidden(!shown)
        .animation(motion, value: shown)
        // A tap puts every tag away (.15 s) as the photo melts.
        .opacity(flow == nil ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: flow == nil)
    }

    // MARK: The choose screen (film v6 "D")

    /// Where the photo melts towards: the thing that was tapped.
    private var meltAnchor: UnitPoint {
        guard let o = flow?.anchor, let photo = vm.photo, stageFrame.width > 0 else { return .center }
        let fill = Self.fillRect(image: photo.size, in: stageFrame.size)
        return UnitPoint(x: (fill.minX + o.anchor.x * fill.width) / stageFrame.width,
                         y: (fill.minY + o.anchor.y * fill.height) / stageFrame.height)
    }

    /// The thing's place on screen (global), where its sticker lifts from.
    private func startRect(_ o: CatchObject) -> CGRect? {
        guard let photo = vm.photo, stageFrame.width > 0 else { return nil }
        let fill = Self.fillRect(image: photo.size, in: stageFrame.size)
        let b = o.box
        return CGRect(x: stageFrame.minX + fill.minX + b.minX * fill.width, y: stageFrame.minY + fill.minY + b.minY * fill.height,
                      width: b.width * fill.width, height: b.height * fill.height)
    }

    /// A tag was tapped: the photo melts and the thing lifts out as a sticker, and its ways to say it are listed to choose
    /// from — one too (2026-10-15: a thing with a single name went straight on, so the strawberry cake was taken as
    /// 草莓蛋糕 without the learner seeing the word and its meaning first). The choice goes on to the GET moment.
    private func open(_ t: Tag) {
        guard flow == nil else { return }
        let now = CCClock.now
        let o = t.choices[0].object
        let fallback = o.cut == nil ? StickerCrop.image(vm.photo, box: o.box) : nil
        let palette = StagePalette.make(from: o.cut ?? fallback)
        let label = t.choices.lazy.compactMap { CatchDexInfo.label(headword: $0.word.headword, stickers: dex.stickers) }.first
        vm.stagePalette = palette
        vm.stageFallback = fallback
        vm.lightStage = true
        withAnimation(reduceMotion ? nil : .timingCurve(0.65, 0, 0.35, 1, duration: 0.55)) { melt = true }
        Haptics.selection()
        flow = ChooseFlow(words: t.choices.map(\.word), objects: t.choices.map { $0.object as CatchObject? },
                          subtitle: L("写っている物：\(t.label)"), anchor: o, typed: false, tappedAt: now,
                          start: startRect(o), cut: o.cut, fallback: fallback, palette: palette, dexLabel: label)
    }

    /// The words found for a typed word (owner 2026-10-15: 「違う単語を入力」 must show the candidates and let the learner
    /// choose, never go straight on — 犬 typed in Japanese listed 狗 first, 犬 only if it is really said): the choose
    /// screen lists them, even one, each with what kind of name it is, the everyday one first. Typed on the open choose
    /// screen, its rows become the words found and the thing's sticker stays; typed under the photo, the choose screen
    /// opens with the thing typed for (or the photo) lifting out.
    private func openTyped() {
        let words = vm.typedCandidates
        guard !words.isEmpty, vm.photo != nil else { return }
        let object = vm.searchObject
        let now = CCClock.now
        let subtitle = L("「\(vm.typedQuery)」で見つかった言葉")
        let label = words.lazy.compactMap { CatchDexInfo.label(headword: $0.headword, stickers: dex.stickers) }.first
        if let f = flow, f.chosenAt == nil, f.closingAt == nil {
            var next = ChooseFlow(words: words, objects: words.map { _ in object ?? f.anchor }, subtitle: subtitle,
                                  anchor: object ?? f.anchor, typed: true, tappedAt: f.tappedAt, start: f.start, cut: f.cut,
                                  fallback: f.fallback, palette: f.palette, dexLabel: label)
            next.rowsAt = now
            Haptics.selection()
            flow = next
            return
        }
        guard flow == nil else {
            // The choose screen is still folding away: open once it has gone.
            Task {
                try? await Task.sleep(for: .milliseconds(360))
                if flow == nil, vm.typedCandidates == words { openTyped() }
            }
            return
        }
        let fallback = object?.cut == nil
            ? (object.map { StickerCrop.image(vm.photo, box: $0.box) } ?? vm.photo.map { ImageTools.resized($0, maxSide: 700) })
            : nil
        let palette = StagePalette.make(from: object?.cut ?? fallback)
        vm.stagePalette = palette
        vm.stageFallback = fallback
        vm.lightStage = true
        inputFocused = false
        let start = object.flatMap { startRect($0) } ?? (stageFrame.width > 0 ? stageFrame : nil)
        flow = ChooseFlow(words: words, objects: words.map { _ in object }, subtitle: subtitle, anchor: object, typed: true,
                          tappedAt: now, start: start, cut: object?.cut, fallback: fallback, palette: palette,
                          dexLabel: label)
        withAnimation(reduceMotion ? nil : .timingCurve(0.65, 0, 0.35, 1, duration: 0.55)) { melt = true }
        Haptics.selection()
    }

    /// A way to say it was chosen: blue outline and check, the card folds away, then the GET moment (`vm.choose`
    /// checks the dex meanwhile; the re-encounter and the rest go on as before).
    private func pick(_ i: Int) {
        guard var f = flow, f.chosenAt == nil, f.closingAt == nil, f.words.indices.contains(i) else { return }
        let now = CCClock.now
        f.chosenAt = now
        f.chosen = i
        flow = f
        SoundService.shared.playLayered(.c6Choose)
        vm.choose(f.words[i], object: f.objects[i], typed: f.typed, stage: (origin: now, handoffAt: now + Film6.handoff))
    }

    /// A word typed at the bottom of the choose screen (owner 2026-10-15: in the display language or the learning
    /// language): the same lookup as 「違う単語を入力」 (`suggestWordCandidates`). The choose screen stays (its field shows
    /// the lookup running) and its rows become the words found (`openTyped`), the tapped thing's cut-out the sticker.
    private func searchFromChoices(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !vm.isLookingUp, let f = flow, f.chosenAt == nil, f.closingAt == nil else { return }
        vm.search(text: q, object: f.anchor)
    }

    /// × : back to the tags (the photo comes back, the sticker goes).
    private func closeChoices() {
        guard var f = flow, f.chosenAt == nil, f.closingAt == nil else { return }
        let at = CCClock.now
        f.closingAt = at
        flow = f
        vm.lightStage = false
        vm.stagePalette = nil
        vm.stageFallback = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { melt = false }
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            if flow?.closingAt == at { flow = nil }
        }
    }

    /// DEBUG previews (`-uiPreview variants`): the first thing with several ways to say it opens by itself, the second
    /// way is chosen (blue outline, the card folds away, the sticker glides on), then it starts again.
    private func openForPreview() async {
        guard autoOpen else { return }
        if holdOpen {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard flow == nil, stageFrame.width > 0, let t = tags(objects).first(where: { $0.choices.count > 1 }) else { continue }
                open(t)
                // The card's rows and the field have come in (film: 0.6–1.1 s after the tap).
                try? await Task.sleep(for: .seconds(1.6))
                UIReady.mark("preview")
                return
            }
            return
        }
        var marked = false
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            guard flow == nil, stageFrame.width > 0,
                  let t = tags(objects).first(where: { $0.choices.count > 1 }) else { continue }
            if !marked {
                UIReady.mark("preview")
                marked = true
            }
            try? await Task.sleep(for: .milliseconds(600))
            open(t)
            try? await Task.sleep(for: .seconds(2.6))
            pick(1)
            try? await Task.sleep(for: .seconds(2.2))
            flow = nil
            melt = false
            vm.backToCandidates()
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    /// Where a scaledToFill image sits inside `size`.
    static func fillRect(image: CGSize, in size: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = max(size.width / image.width, size.height / image.height)
        let w = image.width * scale, h = image.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    // MARK: "違う単語を入力"

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !vm.typedCandidates.isEmpty { typedList }
            manualInput
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 22, style: .continuous))
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: vm.typedCandidates.count)
    }

    /// Several words for what was typed: one row each (never scrolls sideways).
    private var typedList: some View {
        VStack(spacing: 0) {
            ForEach(Array(vm.typedCandidates.enumerated()), id: \.offset) { idx, c in
                Button { vm.choose(c, object: vm.searchObject, typed: true) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            // What kind of name it is, on every row (owner 2026-10-15).
                            RegisterTag(register: NameRegister.of(c))
                            ZhuyinWordView(headword: c.headword, zhuyin: c.zhuyin, size: 20, pinyin: c.pinyin)
                            Text(ReaderLanguage.gloss(ReaderLanguage.shown(c.meaningJa)))
                                .scaledFont(size: 12)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 8)
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .accessibilityIdentifier("typed.\(idx)")
                if idx < vm.typedCandidates.count - 1 { Divider().overlay(Theme.border) }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var manualInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("違う単語を入力"))
                .scaledFont(size: 13, weight: .medium)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                TextField("", text: $typed, prompt: Text(L("例: \(NativeAPI.sample(.word))")).foregroundStyle(Theme.muted.opacity(0.7)))
                    .scaledFont(size: 16)
                    .foregroundStyle(Theme.foreground)
                    .focused($inputFocused)
                    .submitLabel(.search)
                    .onSubmit(submit)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .background(Theme.background, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary.opacity(inputFocused ? 0.6 : 0.25), lineWidth: 1))
                    .accessibilityIdentifier("picker.field")
                Button(action: submit) {
                    HStack(spacing: 6) {
                        if vm.isLookingUp {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text(L("検索"))
                    }
                    .scaledFont(size: 15, weight: .medium)
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                    .background(Theme.secondary, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(PressableStyle())
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || vm.isLookingUp)
                .accessibilityIdentifier("picker.submit")
            }
            if let err = vm.searchError {
                Text(err)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    private func submit() {
        let q = typed.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !vm.isLookingUp else { return }
        inputFocused = false
        typed = ""
        vm.search(text: q)
    }
}

/// What kind of name a candidate is (`NameRegister`), the small grey label over each way to say it in the lists.
struct RegisterTag: View {
    let register: NameRegister
    var size: CGFloat = 10.5

    var body: some View {
        Text(register.label)
            .scaledFont(size: size, weight: .semibold)
            .foregroundStyle(register == .common ? Color(hex: 0x1F6FD1) : Color(hex: 0x5C646F))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(register == .common ? Color(hex: 0x2A9BFF).opacity(0.12) : Color(hex: 0xEEF1F5), in: Capsule())
            .accessibilityIdentifier("register.\(register.rawValue)")
    }
}

/// Page header used through the catch flow ("集める").
struct CollectHeader: View {
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            LogoMark(size: 30)
            Text(L("集める"))
                .scaledFont(size: 15, weight: .medium)
                .foregroundStyle(Theme.muted)
            Spacer()
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(L("カメラに戻る"))
            }
        }
        .padding(.top, 4)
    }
}

/// The vivid blue pronounce button (PronounceButton tone="hero").
struct PronounceCircle: View {
    let text: String
    var size: CGFloat = 42
    /// Off in long lists (the dex list), where warming every row would synthesize words nobody plays.
    var prefetch: Bool = true
    /// White with a blue speaker (the film's light stage and choose card), instead of the vivid blue disc.
    var light: Bool = false

    var body: some View {
        Button { SoundService.shared.speak(text) } label: {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(light ? Theme.primary : .white)
                .frame(width: size, height: size)
                .background(light ? Color.white.opacity(0.92) : Theme.primary, in: Circle())
                .shadow(color: Theme.primary.opacity(light ? 0.3 : 0.35), radius: light ? 8 : 6, y: 3)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(L("発音を聞く"))
        // Web `pronounce.prefetch`: fetch the server voice when the button appears, so the tap is instant.
        .task(id: text) { if prefetch { SoundService.shared.prefetch(text) } }
    }
}
