import SwiftUI

/// One usage chunk as the owner approved it in 版25 (docs/word-detail-design.md §3): its number, the blocks joined by
/// ＋ on one line, and a quiet speaker, all level with the characters; the translation under it with a light bulb that
/// opens the chunk's one-line note. The same view in the word page's 「使い方チャンク」 (inside a grey box) and in the
/// previews.
///
/// - A block of the word it is used with is a box in its part of speech's colour (verb red, noun blue, adjective green).
///   The word being learned and the glue (很・要・的…) are black, as heavy as the word, with no box (owner 2026-10-24).
/// - A swappable block (dashed frame, no arrow) opens the wheel of the other words natives put there (C5, unchanged).
///   Picking one reads it and swaps it into the chunk and its translation. Any other block reads its own word.
/// - The chunk never wraps (owner 2026-10-25 「チャンクは必ず一行」): when it is too wide the boxes' padding and the ＋
///   tighten first, then the whole chunk gets smaller.
struct ChunkLineView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pageTextScale) private var pageTextScale
    enum Size { case large, compact }

    let chunk: UsageChunk
    let headword: String
    let target: String
    var size: Size = .large
    /// Previews only: the part whose wheel is open at first.
    var startOpen: Int? = nil
    /// The chunk's number on the page (nil: none drawn).
    var number: Int? = nil
    /// Tapping the number goes to the example that uses this chunk (nil: there is none, the number is plain).
    var onNumber: (() -> Void)? = nil
    /// The first-swap hint goes under this chunk's line (the first chunk with a dashed word, the first time).
    var showCoach: Bool = false
    var dismissCoach: () -> Void = {}
    /// Keys of the review blur (the chunk line and its translation).
    var reviewKey: String = ""

    @State private var open: Int?
    @State private var noteOpen = false
    /// Part index → chosen text.
    @State private var pick: [Int: String] = [:]
    /// The width the line has, and a count bumped when its width tight at full size has been measured (`fittedLine`,
    /// kept in `widths`).
    @State private var room: CGFloat = 0
    @State private var measured = 0
    /// 設定 › 発音表記: zhuyin (default) or pinyin over each block (the same choice as the word's own reading).
    @AppStorage("reading.pref") private var readingPref: String = "zhuyin"

    private var shown: [ChunkPart] {
        chunk.parts.enumerated().map { i, p in
            guard let t = pick[i], t != p.text else { return p }
            var q = p
            q.text = t
            // A word swapped in from the wheel carries its own reading when the server gave one (its `alts[]`).
            let alt = p.alts?.first { $0.text == t }
            q.pinyin = alt?.pinyin
            q.zhuyin = alt?.zhuyin
            return q
        }
    }

    /// The small reading over a block (server chunk tokens, 2026-10-15): the one the learner chose when the token has
    /// it, else the other (pinyin spelled from the zhuyin when only that came); nothing for an older card's token, and
    /// never for a Japanese or English chunk. Pure, so ChunkReadingTests checks it.
    static func reading(for part: ChunkPart, target: String, pref: String) -> String? {
        guard target.hasPrefix("zh") else { return nil }
        let zhuyin = part.zhuyin?.trimmingCharacters(in: .whitespaces)
        let pinyin = part.pinyin?.trimmingCharacters(in: .whitespaces)
        let z = (zhuyin?.isEmpty ?? true) ? nil : zhuyin
        let p = (pinyin?.isEmpty ?? true) ? nil : pinyin
        if pref == "pinyin" { return p ?? PinyinZhuyin.pinyin(fromZhuyin: z) ?? z }
        return z ?? p
    }

    /// The zhuyin drawn beside each character of a block, exactly as the word page's headword draws it
    /// (`ZhuyinWordView`: small and faint, to the right of each hanzi): a Mandarin chunk, 発音表記 = 注音, and a zhuyin that
    /// gives one syllable per character. nil otherwise. Pure, so ChunkReadingTests checks it.
    static func sideZhuyin(for part: ChunkPart, target: String, pref: String) -> String? {
        guard target.hasPrefix("zh"), pref != "pinyin",
              let z = part.zhuyin?.trimmingCharacters(in: .whitespaces), !z.isEmpty,
              ZhuyinLayout.pair(part.text, z) != nil else { return nil }
        return z
    }

    private var translation: String {
        pick.isEmpty ? chunk.ja : ChunkRules.swappedTranslation(chunk.ja, original: chunk.parts, shown: shown, reader: L10n.lang)
    }

    private var note: String? {
        guard let n = chunk.note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty else { return nil }
        return n
    }

    /// Where the translation, the note and the wheel start: under the chunk, right of the number.
    private var indent: CGFloat { number == nil ? 0 : 36 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Number, chunk and speaker on the middle of the characters (§3: 0 pt apart in the mock).
            HStack(alignment: .hanCenter, spacing: 8) {
                if let number { numberView(number) }
                fittedLine
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }
                .reviewBlur(reviewKey + "-zh", .target)
                DetailSpeakButton(text: ChunkRules.spoken(shown, target: target), style: size == .large ? .normal : .small)
            }
            if showCoach {
                SwapCoachMark(dismiss: dismissCoach)
                    .padding(.leading, indent)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
            if !translation.isEmpty || note != nil {
                HStack(alignment: .center, spacing: 2) {
                    if !translation.isEmpty {
                        Text(translationText)
                            .scaledFont(size: size == .large ? 16 : 13)
                            .foregroundStyle(Theme.muted)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                            .animation(.easeOut(duration: 0.2), value: translation)
                            .reviewBlur(reviewKey + "-tr", .translation)
                    }
                    Spacer(minLength: 0)
                    if note != nil { bulb }
                }
                .padding(.leading, indent)
                .padding(.top, 4)
                .frame(minHeight: 32)
            }
            if let i = open, let part = chunk.parts[safe: i] {
                wheel(i, part)
                    .padding(.leading, indent)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if noteOpen, let note {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "lightbulb")
                        .scaledFont(size: 15)
                        .foregroundStyle(Theme.foreground)
                        .accessibilityHidden(true)
                    Text(note)  // lang-ok: ReaderLanguage.clean (usageChunks note)
                        .scaledFont(size: 15)
                        .foregroundStyle(Theme.foreground)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, indent)
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: open)
        .animation(.easeOut(duration: 0.2), value: noteOpen)
        .onAppear { if let startOpen { open = startOpen } }
    }

    @ViewBuilder
    private func numberView(_ n: Int) -> some View {
        if let onNumber {
            Button(action: onNumber) {
                DetailNumber(n: n)
                    .frame(width: 28, height: 36)
                    .contentShape(.rect)
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(Text(verbatim: "\(n)"))
            .accessibilityHint(L("押すと使った例文へ"))
        } else {
            DetailNumber(n: n)
                .frame(width: 28, height: 36)
        }
    }

    /// The white-and-black bulb (no colour): opens and closes the note under the translation.
    private var bulb: some View {
        Button {
            Haptics.selection()
            noteOpen.toggle()
        } label: {
            Image(systemName: "lightbulb")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.foreground)
                .frame(width: 34, height: 34)
                .background(noteOpen ? Theme.card : Color.clear, in: Circle())
                .contentShape(Circle().inset(by: -5))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(L("解説"))
        .accessibilityValue(noteOpen ? L("表示中") : L("非表示"))
    }

    /// The translation with the partner words' meanings in the text's colour and a little heavier (what to remember),
    /// as long as nothing is swapped in (a swapped translation is read as it comes).
    private var translationText: AttributedString {
        var out = AttributedString(translation)
        guard pick.isEmpty else { return out }
        let weight = detailFontSize(size == .large ? 16 : 13, dynamicTypeSize, pageTextScale)
        for gloss in ChunkRules.partnerGlosses(chunk, headword: headword, target: target) {
            guard let r = out.range(of: gloss) else { continue }
            out[r].foregroundColor = Theme.foreground
            out[r].font = .system(size: weight, weight: .semibold)
        }
        return out
    }

    /// The block text's own size at scale 1 (§3: 24 pt).
    private var baseSize: CGFloat { size == .large ? 24 : 18 }

    /// The sizes the chunk tried before 版25 (largest first, never under 80 % nor a hanzi under 15 pt). Kept for the
    /// previews and ChunkReadingTests; the page now tightens first and then shrinks further (`body`), never wrapping.
    nonisolated static func fitScales(base: CGFloat) -> [CGFloat] {
        let smallest = max(0.8, min(1, 15 / max(base, 1)))
        var scales: [CGFloat] = [1]
        var s: CGFloat = 0.95
        while s > smallest + 0.001 { scales.append(s); s -= 0.05 }
        if smallest < 1 { scales.append(smallest) }
        return scales
    }

    /// The chunk on one line: `tight` narrows the boxes' sides and the ＋ (tried before anything gets smaller).
    /// The chunk on one line at the largest size that fits (§3: always one line): roomy at full size, else tight and as
    /// small as needed, down to 0.52. Worked out from the line's width measured once (tight, full size), which is
    /// remembered — not by building and measuring every size in turn (a `ViewThatFits` of nine): that held the word page
    /// for seconds as it opened (owner 2026-10-31: 「単語の詳細が表示されるまでのラグがある」). Until the width is known
    /// the line is laid out unseen, for a frame.
    @ViewBuilder
    private var fittedLine: some View {
        let _ = measured   // read, so a measurement draws the line again
        if let natural = Self.widths[widthKey], room > 0 {
            let f = Self.fit(natural: natural, room: room, looseExtra: looseExtra)
            oneLine(tight: f.tight, scale: f.scale)
        } else {
            oneLine(tight: true, scale: 1)
                .opacity(0)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
                    guard w > 0 else { return }
                    Self.widths[widthKey] = w
                    measured += 1   // draw again, now at its size
                }
        }
    }

    /// The sizes the line may take below full size, largest first.
    static let fitScales: [CGFloat] = [1, 0.92, 0.85, 0.8, 0.75, 0.68, 0.6, 0.52]

    /// The size the line is drawn at, from its width tight at full size (`natural`), the room it has and how much wider the
    /// roomy line is: roomy at full size when that fits, else the largest tight size that fits (a little room kept for
    /// what does not shrink with the size, such as the boxes' lines), else the smallest. Pure, so it can be tested.
    static func fit(natural: CGFloat, room: CGFloat, looseExtra: CGFloat) -> (tight: Bool, scale: CGFloat) {
        if natural + looseExtra <= room { return (false, 1) }
        let usable = room * 0.97
        let scale = fitScales.first { natural * $0 <= usable } ?? fitScales[fitScales.count - 1]
        return (true, scale)
    }

    /// How much wider the roomy line is than the tight one at full size: the boxes' wider sides and the wider space
    /// around each ＋.
    private var looseExtra: CGFloat {
        let boxes = chunk.parts.filter { ChunkRules.role($0, headword: headword, target: target) == .partner }.count
        let pluses = max(0, shown.count - 1)
        return CGFloat(boxes) * 2 * (12 - 7) + CGFloat(pluses) * 2 * (0.22 - 0.08) * charSize(1)
    }

    /// What the line's width depends on: its words, their readings and the text size.
    private var widthKey: String {
        shown.map { "\($0.text)/\($0.zhuyin ?? "")/\($0.pinyin ?? "")" }.joined(separator: "+")
            + "|\(readingPref)|\(target)|\(charSize(1))|\(headword)"
    }

    /// Lines' widths tight at full size, by `widthKey`: a page opened again draws its chunks at once.
    private static var widths: [String: CGFloat] = [:]

    private func oneLine(tight: Bool, scale: CGFloat) -> some View {
        HStack(alignment: .hanCenter, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, part in
                if i > 0 { plus(tight: tight, scale: scale) }
                block(i, part, tight: tight, scale: scale)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func charSize(_ scale: CGFloat) -> CGFloat { detailFontSize(baseSize, dynamicTypeSize, pageTextScale) * scale }

    private func plus(tight: Bool, scale: CGFloat) -> some View {
        let s = charSize(scale)
        return Text(verbatim: "＋")
            .font(.system(size: s * 0.7, weight: .bold))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, s * (tight ? 0.08 : 0.22))
            .alignmentGuide(.hanCenter) { d in d[VerticalAlignment.center] }
            .accessibilityHidden(true)
    }

    private func block(_ i: Int, _ part: ChunkPart, tight: Bool, scale: CGFloat) -> some View {
        let original = chunk.parts[safe: i] ?? part
        let role = ChunkRules.role(original, headword: headword, target: target)
        let swappable = role != .head && ChunkRules.isSwappable(original, headword: headword, target: target)
        let boxed = role == .partner
        let kind = ChunkKind(pos: part.pos)
        let ink: Color = boxed ? kind.ink.mix(with: Theme.foreground, by: 0.18) : Theme.foreground
        let weight: Font.Weight = boxed ? .bold : .heavy
        let s = charSize(scale)
        let perChar = readingPref == "pinyin" && target.hasPrefix("zh")
            ? PinyinLayout.pair(part.text, pinyin: part.pinyin, zhuyin: part.zhuyin) : nil
        let corner = 12 * scale
        return Button {
            SoundService.shared.speak(part.text)
            if swappable {
                Haptics.selection()
                if showCoach { dismissCoach() }
                open = open == i ? nil : i
            }
        } label: {
            Group {
                if target.hasPrefix("zh") {
                    // At exactly this size: the word itself shows no zhuyin (pinyin with ピンイン chosen).
                    RubyWord(text: part.text, zhuyin: part.zhuyin, pinyin: part.pinyin, size: s, weight: weight, color: ink,
                             hideZhuyin: role == .head)
                } else {
                    Text(part.text)
                        .font(.system(size: s, weight: weight))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .contentTransition(.opacity)
            // The middle of the characters, under a pinyin line when one sits over them.
            .alignmentGuide(.hanCenter) { d in perChar == nil ? d[VerticalAlignment.center] : d[.bottom] - s * 0.6 }
            .padding(.horizontal, boxed ? (tight ? 7 : 12) * scale : 2 * scale)
            .padding(.vertical, 4 * scale)
            .frame(minHeight: 52 * scale)
            .background {
                if boxed {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Theme.card.mix(with: kind.ink, by: swappable ? 0.04 : 0.09))
                }
            }
            .overlay {
                if boxed {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(kind.ink.opacity(swappable ? 0.6 : 0.35),
                                      style: StrokeStyle(lineWidth: 1.5, dash: swappable ? [5, 3] : []))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityLabel(part.text)
        .accessibilityHint(swappable ? L("ほかの語に入れ替えられます") : "")
        .accessibilityAddTraits(role == .head ? .isHeader : [])
    }

    /// The words natives put in this part, the current one first; each with its meaning (C6).
    private func wheel(_ i: Int, _ part: ChunkPart) -> some View {
        let choices = ChunkRules.choices(part)
        let selection = Binding<String>(
            get: { pick[i] ?? part.text },
            set: { t in
                pick[i] = t == part.text ? nil : t
                Haptics.selection()
                SoundService.shared.speak(t)
            }
        )
        return HStack(spacing: 8) {
            Picker(L("ほかの語"), selection: selection) {
                ForEach(choices, id: \.text) { c in
                    HStack(spacing: 10) {
                        Text(c.text).scaledFont(size: 18, weight: .semibold).foregroundStyle(Theme.foreground)
                        if !c.ja.isEmpty {
                            Text(c.ja).scaledFont(size: 14).foregroundStyle(Theme.muted)  // lang-ok: filtered in ReaderLanguage.resolve (alts)
                        }
                    }
                    .tag(c.text)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: size == .large ? 132 : 110)
            .clipped()
            Button {
                open = nil
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("閉じる"))
        }
        .padding(.horizontal, 6)
        .background(Theme.card, in: .rect(cornerRadius: 14, style: .continuous))
    }
}
