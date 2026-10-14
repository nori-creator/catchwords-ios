import SwiftUI

/// After the shot: the photo with each word the AI found as a tag ON its object — deep inside the Vision instance
/// its outline goes round (`CatchObject.anchor`; owner 2026-10-11 「しっかりもののうえに名前タグをおいて」), the AI's
/// point only when Vision found no instance for it — and "違う単語を入力" underneath for a word that is not among them.
/// A tap on a tag goes straight to the celebration (owner 2026-10-09: shoot → words → tap → done).
/// - One tag per THING, named in the reader's own language (owner 2026-10-14: 「表示するのは母語にして」「表示する
///   タグは言い方ではなく、異なるものにして」): 鮮乳 / 牛奶 / 全脂鮮乳 were three tags for one bottle, in Mandarin.
///   A thing with several ways to say it (ふだん / 砕けた / くわしい・専門的 / 固有名詞 — the server's `group` and
///   `register`) opens the list of them on a tap, to pick the one to learn (web CandidatePicker's ほかの言い方);
///   a thing with one name goes straight on. Tags never cover each other (`CCPickLayout`), and stay inside the photo.
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
    /// The thing whose ways to say it are listed (nil = none open).
    @State private var openTag: Tag?

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
        /// Its ways to say it: the everyday one first (ふだん → 砕けた → くわしい → 固有名詞).
        let choices: [Choice]
        /// The tag's text: the thing's name in the reader's language (the headword when there is none).
        let label: String
        /// Order among the tags (`candidate.<n>`).
        let mainIndex: Int?
        var word: Candidate { choices[0].word }
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
            if let open = openTag {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { closeChoices() }
                    .transition(.opacity)
                choicesPanel(open)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if vm.isCheckingOwned {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .allowsHitTesting(!vm.isCheckingOwned)
        // A new photo (撮り直す) or the move on to the celebration closes the list.
        .onChange(of: scanning) { _, _ in openTag = nil }
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
                }
                ForEach(placedTags) { p in
                    tagButton(p)
                        .position(x: p.spot.x, y: p.spot.y - p.size.height / 2)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(.rect)
            .onTapGesture {
                UITestTrace.log("stage.tap")
                inputFocused = false
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
            // ふだん → 砕けた → くわしい → 固有名詞. Same rank keeps the AI's order (likelihood).
            let order = o.words.indices.sorted { a, b in
                let ra = Self.rank(o.words[a].register), rb = Self.rank(o.words[b].register)
                return ra != rb ? ra < rb : a < b
            }
            let choices = order.map { Choice(word: o.words[$0], object: o) }
            guard let main = choices.first else { continue }
            let label = Self.readerName(main.word)
            let key = Self.mergeKey(label)
            if let key, let at = out.firstIndex(where: { Self.mergeKey($0.label) == key }) {
                let had = out[at]
                let added = choices.filter { c in !had.choices.contains { $0.word.headword == c.word.headword } }
                out[at] = Tag(id: had.id, object: had.object, choices: Self.ordered(had.choices + added),
                              label: had.label, mainIndex: had.mainIndex)
                continue
            }
            out.append(Tag(id: "\(o.id)", object: o, choices: choices,
                           label: label.isEmpty ? main.word.headword : label, mainIndex: out.count))
        }
        return out
    }

    /// Everyday names before the others; within a register the order they came in.
    private static func ordered(_ list: [Choice]) -> [Choice] {
        list.indices.sorted { a, b in
            let ra = rank(list[a].word.register), rb = rank(list[b].word.register)
            return ra != rb ? ra < rb : a < b
        }.map { list[$0] }
    }

    /// The thing's name in the reader's language: the short meaning the server wrote in it (empty when it came back
    /// in another language — `ReaderLanguage.shown` drops it, and the tag shows the headword).
    private static func readerName(_ c: Candidate) -> String {
        let meaning = ReaderLanguage.shown(c.meaningJa)
        guard !meaning.isEmpty else { return "" }
        return ReaderLanguage.gloss(meaning, limit: L10n.lang == "en" ? 24 : 12)
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
            // The first tour's 選ぶ step dims everything but this tag: there the everyday name is taken at once.
            if t.choices.count > 1, !router.tour.isCapture {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)) { openTag = t }
            } else {
                vm.choose(t.word, object: t.choices[0].object)
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
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
        .animation(motion, value: shown)
    }

    // MARK: The ways to say one thing

    private func closeChoices() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.9)) { openTag = nil }
    }

    /// The thing's name in the reader's language on top, then each way to say it in the learning language: what
    /// kind of word it is (いちばんよく使う / 砕けた / くわしい・専門的 / 固有名詞), its reading, meaning and how it
    /// differs. A tap on one is the word to learn (owner 2026-10-14: 文旦 → 台湾ではふつう柚子と言う).
    private func choicesPanel(_ t: Tag) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.label)
                        .scaledFont(size: 24, weight: .heavy)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(2)
                    Text(L("覚えたい言い方を選んでください"))
                        .scaledFont(size: 13)
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Button { closeChoices() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(L("閉じる"))
                .accessibilityIdentifier("variant.close")
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(t.choices.enumerated()), id: \.element.id) { idx, c in
                        HStack(spacing: 8) {
                            Button {
                                openTag = nil
                                vm.choose(c.word, object: c.object)
                            } label: {
                                choiceRow(c.word, first: idx == 0)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle(scale: 0.98))
                            .accessibilityIdentifier("variant.\(idx)")
                            PronounceCircle(text: c.word.headword, size: 36)
                        }
                        .padding(.vertical, 10)
                        if idx < t.choices.count - 1 { Divider().overlay(Theme.border) }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 420)
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }

    private func choiceRow(_ c: Candidate, first: Bool) -> some View {
        let meaning = ReaderLanguage.gloss(ReaderLanguage.shown(c.meaningJa))
        let note = ReaderLanguage.shown(c.distinction, hanOnlyOk: false)
        return VStack(alignment: .leading, spacing: 5) {
            Text(Self.registerLabel(c.register, first: first))
                .scaledFont(size: 11, weight: .semibold)
                .foregroundStyle(first ? Theme.primaryInk : Theme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(first ? Theme.primary.opacity(0.12) : Theme.secondary, in: Capsule())
            ZhuyinWordView(headword: c.headword, zhuyin: c.zhuyin, size: first ? 30 : 24, pinyin: c.pinyin)
            if !meaning.isEmpty {
                Text(meaning)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !note.isEmpty {
                Text(note)
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Theme.primaryInk)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What kind of word it is (candidate-order.ts registers). The first everyday name is the one people say most.
    private static func registerLabel(_ register: String?, first: Bool) -> String {
        switch register {
        // Short and telling apart at a glance (owner 2026-10-14: 「日本語を洗練させた言い方を考えて。分かりやすく
        // ユーザーが区別できるようにして」): what kind of word it is, then in brackets when you would use it.
        case "casual": L("口語（くだけた言い方）")
        case "specific": L("正式名（くわしい・専門的）")
        case "proper": L("固有名（商品名・店名）")
        default: first ? L("定番（いちばんよく使う）") : L("よく使う別の言い方")
        }
    }

    /// ふだん → 砕けた → くわしい → 固有名詞 (candidate-order.ts).
    private static func rank(_ register: String?) -> Int {
        switch register {
        case "casual": 1
        case "specific": 2
        case "proper": 3
        default: 0
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
                Button { vm.choose(c, object: nil) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
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

    var body: some View {
        Button { SoundService.shared.speak(text) } label: {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Theme.primary, in: Circle())
                .shadow(color: Theme.primary.opacity(0.35), radius: 6, y: 3)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(L("発音を聞く"))
        // Web `pronounce.prefetch`: fetch the server voice when the button appears, so the tap is instant.
        .task(id: text) { if prefetch { SoundService.shared.prefetch(text) } }
    }
}
