import SwiftUI

/// Choosing the way to say it (concept film v6 "D", `dGet` before the choice): the photo melts into the app's page,
/// the thing lifts out of the photo as a sticker to the top of the page and floats there, and under it the header
/// (NEW · its 図鑑 number and category, 「覚える単語を選ぶ」, what is in the photo) and a white card with each way to
/// say it, each with what kind of name it is (`NameRegister`, owner 2026-10-15). A choice is marked in blue (the others
/// fade), the card folds away and the sticker glides on to the GET moment — drawn by the same `CatchStageScene`, so the
/// next screen takes over without a seam. Under the card a word can be typed instead (the display language or the
/// learning language, `onSearch`); the words found are listed on this card the same way (owner 2026-10-15: a typed word
/// is chosen here, never taken straight on). The camera shows the card for a thing with one way to say it too
/// (`alwaysCard`); without it, one way gets no card and its sticker lifts out and goes straight on. × goes back to the tags.
struct CatchChooseOverlay: View {
    /// The ways to say it (the everyday one first); one = no card, unless `alwaysCard`.
    let words: [Candidate]
    /// The line under the title: 「写っている物：…」 (the thing's name in the reader's language), or what was typed.
    let subtitle: String
    /// 「No.001 · 飲み物」, nil when the 図鑑's catalog does not know the thing.
    let dexLabel: String?
    let cut: UIImage?
    let fallback: UIImage?
    /// The sticker `cut` replaced and when (`CatchStageScene.swapFrom`): the two cross-fade.
    var swapFrom: UIImage? = nil
    var swapAt: Double? = nil
    let palette: StagePalette
    /// The thing's place in the photo (global).
    let start: CGRect?
    /// The tap on the tag (C) and the choice (P), on `CCClock`.
    let tappedAt: Double
    let chosenAt: Double?
    let chosen: Int?
    let closingAt: Double?
    let calm: Bool
    /// Words found by typing: the card even for one word (the learner always chooses).
    var alwaysCard: Bool = false
    /// When the rows came in, when a lookup replaced them on the open card (nil: with the card).
    var rowsAt: Double? = nil
    /// A typed word is being looked up (`CaptureViewModel.isLookingUp`).
    var searching: Bool = false
    /// Nothing found for what was typed (shown under the field).
    var searchError: String? = nil
    let onChoose: (Int) -> Void
    let onClose: () -> Void
    /// A word typed in the field under the card.
    var onSearch: ((String) -> Void)? = nil
    /// 囲んで切り抜き直す: the learner redraws the sticker's outline on the photo (owner 2026-11-05: 「単語の候補をタップする
    /// とき、つまり切り抜きが表示されるときに、丸で囲って切り抜きを直すボタンをつけて」). nil = no button (previews).
    var onRecut: (() -> Void)? = nil
    /// 元の写真のまま: the whole photo becomes the sticker, when no cut-out is right (owner 2026-11-09: 「切り抜き直すボタンの
    /// 横に元の画像のまま表示するってボタン」). nil = no button (no photo: a typed word).
    var onWholePhoto: (() -> Void)? = nil
    /// The first tour's choose step (`TourStep.choose`, owner 2026-11-23): the card of the ways to say it is the lit
    /// place, so the learner sees that choosing one of them moves on.
    var tourLit: Bool = false

    /// The card is on screen (`chooser`): set as it appears, so its parts come in after the film's delays.
    @State private var cardShown = false

    private func closing(_ now: Double) -> Double { closingAt.map { Film6.seg(now - $0, 0, 0.3) } ?? 0 }

    /// The field comes in with the card's rows.
    @State private var fieldShown = false
    /// The rows' own height (`chooser`): the card is as tall, up to its room, and scrolls beyond it.
    @State private var rowsHeight: CGFloat = 0
    /// The field's height as drawn (it grows with a large text size), for the first tour's room under the rows.
    @State private var fieldMeasured: CGFloat = 0
    /// The first tour's pill between the rows and the field (`TourStep.pillUnderLit`): its room grows with the text size.
    @ScaledMetric(relativeTo: .subheadline) private var tourPillRoom: CGFloat = 52

    private let ink = Color(hex: 0x0B121A)
    private let muted = Color(hex: 0x5C646F)
    private let line = Color(hex: 0xE0E5EB)

    private var hasCard: Bool { words.count > 1 || (alwaysCard && !words.isEmpty) }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let size = geo.size
                let o = geo.frame(in: .global).origin
                ZStack(alignment: .topLeading) {
                    TimelineView(.animation) { _ in
                        let now = CCClock.now
                        let tD = now - tappedAt
                        let hold = hasCard ? Film6.handoff : Film6.handoffSingle
                        let tc = chosenAt.map { min(now - $0, hold) }
                        let page = calm ? Film6.clamp(tD / 0.2) : Film6.inOutCubic(Film6.seg(tD, 0.05, 0.6))
                        CatchStageScene(size: size, cut: cut, fallback: fallback, palette: palette,
                                        start: start.map { $0.offsetBy(dx: -o.x, dy: -o.y) },
                                        sinceTap: calm ? 99 : tD, sinceChoice: tc, live: now, page: page, calm: calm,
                                        swapFrom: swapFrom, swapAt: swapAt)
                            .opacity(1 - closing(now))
                    }
                    // Taps beside the card go nowhere (the photo's words under it are put away).
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: size.width, height: size.height)
                    if hasCard {
                        // The card moves with SwiftUI's own animations (`chooser`), never rebuilt on every frame:
                        // each frame laid out every row's word and reading again while it came in and folded away
                        // (owner 2026-11-27: 「カメラ撮ってから、図鑑に追加されるまでの全てのアニメーション　限界まで
                        // 滑らかにして。カクカクなしで」).
                        chooser(size: size)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
            .ignoresSafeArea()

            if hasCard, chosenAt == nil, closingAt == nil {
                VStack {
                    HStack {
                        // Side by side, smaller where the row is narrow. The row gets its width before the Spacer:
                        // with the Spacer sharing it, the buttons were offered half the row and fell one under the other.
                        ChooseCutButtons(showsRecut: onRecut != nil, showsWholePhoto: onWholePhoto != nil,
                                         onRecut: { onRecut?() }, onWholePhoto: { onWholePhoto?() })
                            .equatable()
                            .layoutPriority(1)
                        Spacer(minLength: 8)
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(muted)
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.85), in: Circle())
                                .overlay(Circle().stroke(line, lineWidth: 1))
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.9))
                        .accessibilityLabel(L("閉じる"))
                        .accessibilityIdentifier("variant.close")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    Spacer()
                }
                .transition(.opacity)
            }

            // The field sits outside the film's stage, so it rises above the keyboard.
            if hasCard, onSearch != nil, chosenAt == nil, closingAt == nil {
                VStack {
                    Spacer()
                    ChooseTypeField(searching: searching, searchError: searchError, onSearch: { onSearch?($0) })
                        // The first tour's pill goes between the lit rows and this field (`TourStep.pillUnderLit`).
                        .tourAnchor(.chooseField, if: tourLit)
                        // Read only in the first tour, so outside it nothing is written and the screen is drawn exactly
                        // as before (CI 2026-11-23: with the height always written, the tap on a typed word's row was
                        // cancelled once — not proven to be the cause, kept out of the way all the same).
                        .onGeometryChange(for: CGFloat.self) { tourLit ? $0.size.height : 0 } action: { h in
                            if h != fieldMeasured { fieldMeasured = h }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .opacity(fieldShown ? 1 : 0)
                        .offset(y: fieldShown ? 0 : 16)
                        .onAppear {
                            withAnimation(calm ? .easeOut(duration: 0.2) : .easeOut(duration: 0.35).delay(0.9)) { fieldShown = true }
                        }
                }
                .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .light)
        .animation(.easeOut(duration: 0.2), value: chosenAt == nil && closingAt == nil)
    }

    // MARK: The header and the card

    /// The film's curves for the card: out-cubic as a part comes in (`start`…`end` seconds after the tap), in-out-cubic as
    /// it goes after the choice; a short fade when motion is reduced.
    private func comeIn(_ start: Double, _ end: Double) -> Animation {
        calm ? .linear(duration: 0.2) : .timingCurve(0.33, 1, 0.68, 1, duration: end - start).delay(start)
    }

    private func goOut(_ start: Double, _ end: Double) -> Animation {
        .timingCurve(0.65, 0, 0.35, 1, duration: end - start).delay(start)
    }

    /// The header (NEW · No. · category, 「覚える単語を選ぶ」, what is in the photo), the card of the ways to say it and the
    /// line under it. Film v6's times: the header 0.45–0.7 s after the tap, the card 0.5–0.82 s, the rows 0.58 + 0.07 s
    /// each, the line 0.9–1.1 s; after the choice the header and line go (0.02–0.16 s) and the whole folds away
    /// (0.22–0.5 s); closing fades it in 0.3 s.
    private func chooser(size: CGSize) -> some View {
        let W = Film6.columnWidth(size), H = size.height, k = W / 1080
        let chose = chosenAt != nil
        // Room under the card for the line under it and the field to type a word (`ChooseTypeField`).
        // The first tour: the field as tall as it is drawn and the pill's room taken too, so the pill never sits on the
        // rows or the field at a large text size or on a small iPhone (owner 2026-11-23). Other times as before.
        let field = onSearch == nil ? 0 : (tourLit ? max(Self.fieldHeight, fieldMeasured + 16) : Self.fieldHeight)
        let pillRoom = tourLit ? max(0, tourPillRoom - 52) : 0
        // The first tour may make the card shorter still on a small iPhone at a large text size (its rows scroll).
        let maxCard = max(tourLit ? 100 : 160, H - Film6.y(1150, H) - 96 - field - pillRoom)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let dexLabel {
                    CatchDexChip(label: dexLabel, scale: W / 393)
                        .padding(.bottom, 46 * k)
                } else {
                    Color.clear.frame(height: 98 * k)
                }
                Text(L("覚える単語を選ぶ"))
                    .font(.system(size: 50 * k, weight: .heavy))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: 30 * k, weight: .medium))
                    .foregroundStyle(muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 12 * k)
            }
            .padding(.leading, 24 * k)
            .opacity(cardShown ? 1 : 0)
            .offset(y: cardShown ? 0 : 30 * k)
            .animation(comeIn(0.45, 0.7), value: cardShown)
            .opacity(chose ? 0 : 1)
            .animation(goOut(0.02, 0.16), value: chose)
            .padding(.bottom, 40 * k)

            // The rows scroll only when they are taller than the card may be. Measured once per set of rows (their
            // height), not tried both ways on every frame: `ViewThatFits` typeset every row twice a frame while the
            // card came in and folded away — most of the main thread from the tap to the GET moment (owner
            // 2026-11-27: 「名前のタグをタップして切り抜くところもカクカクしていて、写真が止まってる」).
            ScrollView {
                rows(k: k)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        if abs(h - rowsHeight) > 0.5 { rowsHeight = h }
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: rowsHeight > 0 ? min(rowsHeight, maxCard) : nil)
            .frame(maxHeight: maxCard)
            .background(Color.white, in: .rect(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(line, lineWidth: 1))
            .shadow(color: .rgba(15, 40, 80, 0.08), radius: 18, y: 5)
            .opacity(cardShown ? 1 : 0)
            .offset(y: cardShown ? 0 : 40 * k)
            .animation(comeIn(0.5, 0.82), value: cardShown)
            .tourAnchor(.choose, if: tourLit && chosenAt == nil && closingAt == nil)

            Text(L("選ぶと、その言い方で図鑑に入ります"))
                .font(.system(size: 30 * k, weight: .medium))
                .foregroundStyle(muted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 40 * k)
                // The first tour: the guide's pill takes this line's place (its card says the same, owner 2026-11-23:
                // 「案内を見るを被らない位置に配置して」 — over the title it covered 覚える単語を選ぶ).
                .opacity(tourLit ? 0 : (cardShown ? 1 : 0))
                .animation(comeIn(0.9, 1.1), value: cardShown)
                .opacity(chose ? 0 : 1)
                .animation(goOut(0.02, 0.16), value: chose)
        }
        .padding(.horizontal, 40 * k)
        .padding(.top, Film6.y(900, H))
        .frame(width: W, alignment: .topLeading)
        .frame(width: size.width)
        .opacity(chose ? 0 : 1)
        .offset(y: chose ? 60 * k : 0)
        .animation(goOut(0.22, 0.5), value: chose)
        .opacity(closingAt == nil ? 1 : 0)
        .animation(.linear(duration: 0.3), value: closingAt == nil)
        .allowsHitTesting(chosenAt == nil && closingAt == nil)
        .onAppear { cardShown = true }
    }

    /// The ways to say it. Rows that replaced others on the open card (a lookup) are new rows (`id`), which come in as
    /// the card's first rows did, from the moment they came.
    private func rows(k: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, c in
                ChooseCardRow(index: i, candidate: c, last: i == words.count - 1, chosen: chosen, k: k, calm: calm,
                              delay: calm && rowsAt != nil ? nil : (rowsAt == nil ? 0.58 : 0) + 0.07 * Double(i),
                              line: line, onChoose: onChoose)
            }
        }
        .id(rowsAt ?? -1)
    }

    // MARK: Typing a word

    static let fieldHeight: CGFloat = 92
}

/// One way to say it on the choose card (`CatchChooseOverlay.rows`): what kind of name, its reading, meaning and how it
/// differs (`ChooseRowContent`), with its voice; once chosen, a blue outline and a blue check, the others dimmed. It comes
/// in and answers the choice with SwiftUI's own animations on the film's curves and times (`delay`: seconds after it
/// appeared, nil = at once), so the row is laid out once, not on every frame of the card's movements.
private struct ChooseCardRow: View {
    let index: Int
    let candidate: Candidate
    let last: Bool
    let chosen: Int?
    let k: CGFloat
    let calm: Bool
    let delay: Double?
    let line: Color
    let onChoose: (Int) -> Void

    @State private var shown = false
    @State private var pressed = false

    private var isPick: Bool { chosen == index }
    private var dimmed: Bool { chosen != nil && !isPick }

    private var comeIn: Animation? {
        guard let delay else { return nil }
        return calm ? .linear(duration: 0.2) : .timingCurve(0.33, 1, 0.68, 1, duration: 0.32).delay(delay)
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .offset(y: shown ? 0 : 18 * k)
            if !last {
                Rectangle()
                    .fill(line)
                    .frame(height: 1)
                    .padding(.horizontal, 30 * k)
            }
        }
        .opacity(shown ? 1 : 0)
        .animation(comeIn, value: shown)
        .onAppear { shown = true }
        // The chosen row is pressed in and back (0–0.06 s, then 0.12–0.24 s after the choice).
        .onChange(of: isPick) { _, picked in
            guard picked else { return }
            withAnimation(.linear(duration: 0.06)) { pressed = true }
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.linear(duration: 0.12)) { pressed = false }
            }
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            Button { onChoose(index) } label: {
                ChooseRowContent(candidate: candidate, first: index == 0)
                    .equatable()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.985))
            .accessibilityIdentifier("variant.\(index)")
            ZStack {
                PronounceCircle(text: candidate.headword, size: 30, light: true)
                    .opacity(isPick ? 0 : 1)
                    .animation(.linear(duration: 0.1).delay(0.06), value: isPick)
                    .allowsHitTesting(!isPick)
                Circle()
                    .fill(Theme.primary)
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white))
                    // The film's out-back (overshoot 2.2) over 0.17 s.
                    .scaleEffect(isPick ? 1 : 0.01)
                    .opacity(isPick ? 1 : 0)
                    .animation(.timingCurve(0.34, 1.8, 0.64, 1, duration: 0.17).delay(0.06), value: isPick)
                    .accessibilityHidden(true)
            }
            .frame(width: 44, height: 44)
        }
        .padding(.leading, 30 * k)
        .padding(.trailing, 18 * k)
        .padding(.vertical, 26 * k)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.rgba(0, 131, 255, 0.08))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.primary, lineWidth: 1.5))
                .padding(.horizontal, 8 * k)
                .padding(.vertical, 6 * k)
                .opacity(isPick ? 1 : 0)
                .animation(.linear(duration: 0.2).delay(0.06), value: isPick)
        }
        .scaleEffect(pressed ? 0.975 : 1)
        .opacity(dimmed ? 0.45 : 1)
        .animation(.linear(duration: 0.2).delay(0.06), value: dimmed)
    }
}

/// 囲んで切り抜き直す and 元の写真のまま at the top left of the choose screen (`CatchChooseOverlay`). Its own view, equal while
/// the same buttons are on it: the row tries two sizes (`ViewThatFits`) and was measured again every time the choose
/// screen changed (its cut-out coming, a search) — owner 2026-11-27: 「限界まで滑らかにして。カクカクなしで」.
private struct ChooseCutButtons: View, Equatable {
    let showsRecut: Bool
    let showsWholePhoto: Bool
    let onRecut: () -> Void
    let onWholePhoto: () -> Void

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.showsRecut == b.showsRecut && a.showsWholePhoto == b.showsWholePhoto
    }

    private let ink = Color(hex: 0x0B121A)
    private let line = Color(hex: 0xE0E5EB)

    /// 囲んで切り抜き直す and 元の写真のまま at the top left, always side by side (owner 2026-11-10: 「元の画像は切り抜き
    /// 治すの右に配置して」 — stacked, the second one covered the cut-out). Where the row is narrow the two get smaller.
    var body: some View {
        // Side by side, smaller where the row is narrow.
        ViewThatFits(in: .horizontal) {
            buttons(compact: false)
            buttons(compact: true)
        }
    }

    @ViewBuilder
    private func buttons(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            if showsRecut {
                cutButton(L("囲んで切り抜き直す"), icon: "lasso", id: "variant.recut", compact: compact, action: onRecut)
            }
            if showsWholePhoto {
                cutButton(L("元の写真のまま"), icon: "photo", id: "variant.wholePhoto", compact: compact) {
                    AppEvents.feature(.wholePhoto)
                    onWholePhoto()
                }
            }
        }
    }

    private func cutButton(_ title: String, icon: String, id: String, compact: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: compact ? 4 : 6) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                Text(title)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, compact ? 9 : 12)
            .frame(height: 36)
            .background(.white.opacity(0.85), in: Capsule())
            .overlay(Capsule().stroke(line, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityIdentifier(id)
    }

}

/// One way to say it on the choose card: what kind of name it is, the word with its reading, its meaning and how it
/// differs. Its own view, equal while its word is: the card is built again on every frame while it moves (coming in, a
/// choice, new rows), and the reading's layout and the meaning's language checks (string work) ran on every one of
/// those frames (owner 2026-11-25: 「図鑑に追加するアニメーションもカクカクしてる」).
private struct ChooseRowContent: View, Equatable {
    let candidate: Candidate
    let first: Bool

    private let ink = Color(hex: 0x0B121A)
    private let muted = Color(hex: 0x5C646F)

    nonisolated static func == (a: Self, b: Self) -> Bool { a.first == b.first && a.candidate == b.candidate }

    var body: some View {
        let c = candidate
        // A typed word's `gloss` when the server sent one (#185), else the meaning's first gloss.
        let meaning = c.shownMeaning
        let note = ReaderLanguage.shown(c.distinction, hanOnlyOk: false)
        // Every row says what kind of name it is (owner 2026-10-15: 「どの候補にも必ず印を付ける」 — the film's everyday row
        // had none, and a list whose registers were all common or unknown showed no label at all).
        VStack(alignment: .leading, spacing: 4) {
            RegisterTag(register: NameRegister.of(c))
            ZhuyinWordView(headword: c.headword, zhuyin: c.zhuyin, size: first ? 30 : 23, weight: first ? .semibold : .medium,
                           color: ink, readingColor: muted, pinyin: c.pinyin)
            if !meaning.isEmpty {
                Text(meaning)
                    .scaledFont(size: 12.5)
                    .foregroundStyle(muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !note.isEmpty {
                Text(note)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(Color(hex: 0x0066CC))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 「リストにない言葉を探す」 under the choose card: a word in the display language or the learning language, looked up the
/// same way as under the photo (owner 2026-10-15). Its own view with its own text: a keystroke redraws this box alone.
/// The text lived in the whole choose screen, so every keystroke built the screen again — the card and its rows
/// measured twice (`ViewThatFits`) and the stage — and the letters and the waiting light came in jerks (owner
/// 2026-11-25: 「単語の検索欄で検索すると、青く光るバーがカクカクしているのと、入力した文字もカクカクする」).
private struct ChooseTypeField: View {
    /// A typed word is being looked up (`CaptureViewModel.isLookingUp`).
    let searching: Bool
    /// Nothing found for what was typed (shown under the field).
    let searchError: String?
    let onSearch: (String) -> Void

    @State private var typed: String = ""
    @FocusState private var typing: Bool

    private let ink = Color(hex: 0x0B121A)
    private let muted = Color(hex: 0x5C646F)
    private let line = Color(hex: 0xE0E5EB)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("リストにない言葉を探す"))
                .scaledFont(size: 12, weight: .medium)
                .foregroundStyle(muted)
            HStack(spacing: 8) {
                TextField("", text: $typed, prompt: Text(L("例: ティッシュ")).foregroundStyle(muted.opacity(0.7)))
                    .scaledFont(size: 16)
                    .foregroundStyle(ink)
                    .focused($typing)
                    .submitLabel(.search)
                    .onSubmit(submit)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Color(hex: 0xF5F8FB), in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary.opacity(typing ? 0.6 : 0.25), lineWidth: 1))
                    .accessibilityIdentifier("variant.field")
                Button(action: submit) {
                    HStack(spacing: 6) {
                        if searching { ProgressView().controlSize(.small) } else { Image(systemName: "magnifyingglass") }
                        Text(L("検索"))
                    }
                    .scaledFont(size: 15, weight: .medium)
                    .foregroundStyle(ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Color(hex: 0xEEF1F5), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(PressableStyle())
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                .accessibilityIdentifier("variant.submit")
            }
            if let searchError, !searching {
                Text(searchError)
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("variant.searchError")
            }
        }
        .padding(12)
        .background(Color.white, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(line, lineWidth: 1))
        // While the typed word is looked up, the blue-white light runs round the box (owner 2026-11-24).
        .waitBeam(searching, cornerRadius: 18, darkSurface: false)
        .shadow(color: .rgba(15, 40, 80, 0.08), radius: 14, y: 4)
    }

    private func submit() {
        let q = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !searching else { return }
        typing = false
        typed = ""
        onSearch(q)
    }
}
