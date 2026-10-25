import SwiftUI

/// One usage chunk as a formula (docs/chunk-rules.md C17–C18, owner 2026-10-23): the blocks as one continuous phrase —
/// no boxes, no ＋ between them — the translation under it, and a button that reads the whole chunk, level with the
/// phrase. The same view in the word page's 「使い方パターン」 and in the previews.
///
/// - The word being learned is blue (`Theme.primaryInk`, the examples' blue; text only, no wash — owner 2026-10-23
///   evening: 「青い背景が一体感を分断」). The words it is used with are black and heavy: they are what the learner is to
///   remember (`ChunkRole.partner`). The glue (很・的・把, prepositions) is grey.
/// - A swappable block (a dashed line under it, ▾) opens a wheel of the other words natives put there — only words that
///   keep the same formula and change its meaning (C5). Picking one reads that word, swaps it into the chunk and its
///   translation; the right button reads the new chunk. Any other block reads its own word.
/// - 「品詞」 on the card (`chunk.posColors`, off by default — owner 2026-10-23): every block in its part of speech's colour.
struct ChunkLineView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    enum Size { case large, compact }

    let chunk: UsageChunk
    let headword: String
    let target: String
    var size: Size = .large
    /// Previews only: the part whose wheel is open at first.
    var startOpen: Int? = nil

    @State private var open: Int?
    /// Part index → chosen text.
    @State private var pick: [Int: String] = [:]
    /// 設定 › 発音表記: zhuyin (default) or pinyin over each block (the same choice as the word's own reading).
    @AppStorage("reading.pref") private var readingPref: String = "zhuyin"
    /// 「品詞」 on the card: the blocks in their parts of speech's colours (owner 2026-10-23: off unless asked).
    @AppStorage("chunk.posColors") private var posColors: Bool = false
    /// The diary's 「振り返る」 shows the colours whatever the card's 「品詞」 says (owner 2026-10-25: 「習った単語の詳細の
    /// チャンクは品詞ごとで色分け」).
    @Environment(\.chunkPOSColorsOn) private var posForced

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
    /// (`ZhuyinWordView`: small and faint, to the right of each hanzi — owner 2026-10-16: 「チャンクの注音も見出しと同じに」):
    /// a Mandarin chunk, 発音表記 = 注音, and a zhuyin that gives one syllable per character. nil otherwise — then the
    /// block keeps its one reading line over it (pinyin, or a reading that does not pair). Pure, so ChunkReadingTests
    /// checks it.
    static func sideZhuyin(for part: ChunkPart, target: String, pref: String) -> String? {
        guard target.hasPrefix("zh"), pref != "pinyin",
              let z = part.zhuyin?.trimmingCharacters(in: .whitespaces), !z.isEmpty,
              ZhuyinLayout.pair(part.text, z) != nil else { return nil }
        return z
    }

    private var translation: String {
        pick.isEmpty ? chunk.ja : ChunkRules.swappedTranslation(chunk.ja, original: chunk.parts, shown: shown, reader: L10n.lang)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: size == .large ? 8 : 5) {
            // The voice button stands level with the phrase (owner 2026-10-23: 「音声ボタンは必ずチャンクと同じ高さに」).
            HStack(alignment: .center, spacing: 10) {
                // One line when it fits: the blocks shrink together (text, zhuyin and pinyin alike) down to a readable
                // smallest size, and only below that do they wrap (owner 2026-10-16: 「1行に収まるよう文字を小さく」).
                // Each size is a candidate of its own, largest first (at most five: `fitScales`).
                let scales = fitScales
                ViewThatFits(in: .horizontal) {
                    oneLine(scales, 0)
                    oneLine(scales, 1)
                    oneLine(scales, 2)
                    oneLine(scales, 3)
                    oneLine(scales, 4)
                    FlowRow(spacing: wordGap(1), alignment: .chunkText) { parts(scale: scales.last ?? 1) }
                }
                Spacer(minLength: 0)
                PronounceCircle(text: ChunkRules.spoken(shown, target: target), size: size == .large ? 38 : 32)
            }
            if !translation.isEmpty {
                Text(translationText)
                    .scaledFont(size: size == .large ? 16 : 13)
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(3)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: translation)
            }
            if let i = open, let part = chunk.parts[safe: i] {
                wheel(i, part)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: open)
        .onAppear { if let startOpen { open = startOpen } }
    }

    /// The translation with the partner words' meanings in the text's colour and a little heavier (C18: what to
    /// remember), as long as nothing is swapped in (a swapped translation is read as it comes).
    private var translationText: AttributedString {
        var out = AttributedString(translation)
        guard pick.isEmpty else { return out }
        let weight = AppTypeScale.scaled(size == .large ? 16 : 13, for: dynamicTypeSize)
        for gloss in ChunkRules.partnerGlosses(chunk, headword: headword, target: target) {
            guard let r = out.range(of: gloss) else { continue }
            out[r].foregroundColor = Theme.foreground
            out[r].font = .system(size: weight, weight: .semibold)
        }
        return out
    }

    /// The block text's own size at scale 1 (owner 2026-10-23: the formula's characters at 28 pt).
    private var baseSize: CGFloat { size == .large ? 28 : 18 }

    /// The space between two blocks: the only thing that separates words now that there is no ＋.
    private func wordGap(_ scale: CGFloat) -> CGFloat { (size == .large ? 12 : 8) * scale }

    /// The sizes tried for one line, largest first: never under 80% of the normal size, and a hanzi never under 15 pt
    /// (at the reader's text size). A compact chunk is already at 18 pt, so it hardly shrinks before it wraps.
    private var fitScales: [CGFloat] {
        Self.fitScales(base: AppTypeScale.scaled(baseSize, for: dynamicTypeSize))
    }

    /// Pure, so ChunkReadingTests checks it.
    nonisolated static func fitScales(base: CGFloat) -> [CGFloat] {
        let smallest = max(0.8, min(1, 15 / max(base, 1)))
        var scales: [CGFloat] = [1]
        var s: CGFloat = 0.95
        while s > smallest + 0.001 { scales.append(s); s -= 0.05 }
        if smallest < 1 { scales.append(smallest) }
        return scales
    }

    /// The chunk on one line at the `k`-th size of `scales` (the smallest when there are fewer).
    private func oneLine(_ scales: [CGFloat], _ k: Int) -> some View {
        let scale = scales[min(k, scales.count - 1)]
        return HStack(alignment: .chunkText, spacing: wordGap(scale)) { parts(scale: scale) }
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Every block stands on the middle of its characters (`.chunkText`), not on the middle of a block — a reading over
    /// the text makes its block taller upwards (owner 2026-10-21: 「プラスは漢字の高さに合わせて」, kept for the words now
    /// that the ＋ is gone).
    @ViewBuilder
    private func parts(scale: CGFloat) -> some View {
        ForEach(Array(shown.enumerated()), id: \.offset) { i, part in
            block(i, part, scale: scale)
        }
    }

    /// The colour of a block's characters: by its role (C18), or by its part of speech when 「品詞」 is on. The headword
    /// stays blue either way (owner 2026-10-23 evening: 「青はそのままで」); the colours are barely darkened so the red
    /// stays vivid (「赤色ももう少し鮮やかな色に」).
    private func ink(role: ChunkRole, pos: String) -> Color {
        if posColors || posForced, role != .head {
            return ChunkKind(pos: pos).ink.mix(with: colorScheme == .dark ? .white : .black, by: size == .large ? 0.12 : 0.1)
        }
        switch role {
        case .head: return Theme.primaryInk
        case .partner: return Theme.foreground
        case .frame: return Theme.muted
        }
    }

    private func block(_ i: Int, _ part: ChunkPart, scale: CGFloat) -> some View {
        let original = chunk.parts[safe: i] ?? part
        let role = ChunkRules.role(original, headword: headword, target: target)
        let swappable = role != .head && ChunkRules.isSwappable(original, headword: headword, target: target)
        let isOpen = open == i
        let big = size == .large
        let ink = ink(role: role, pos: part.pos)
        let weight: Font.Weight = role == .partner ? .heavy : role == .frame ? .medium : .bold
        let charSize = AppTypeScale.scaled(baseSize * scale, for: dynamicTypeSize)
        return Button {
            SoundService.shared.speak(part.text)
            if swappable {
                Haptics.selection()
                open = isOpen ? nil : i
            }
        } label: {
            let side = Self.sideZhuyin(for: part, target: target, pref: readingPref)
            // Pinyin over each character (`PinyinRubyLine`, as the headword); a reading that does not pair one syllable
            // per character stays one line over the block.
            let perChar = side == nil && readingPref == "pinyin" && target.hasPrefix("zh")
                ? PinyinLayout.pair(part.text, pinyin: part.pinyin, zhuyin: part.zhuyin) : nil
            let reading = side == nil && perChar == nil ? Self.reading(for: part, target: target, pref: readingPref) : nil
            VStack(spacing: 1) {
                // The token's reading, small, over its text (server chunk tokens, 2026-10-15); none on older cards.
                if let reading {
                    Text(reading)
                        .scaledFont(size: (big ? 10.5 : 9) * scale, weight: .medium)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 3) {
                    if let side {
                        // The headword's own view and settings: zhuyin to the right of each character, a size up
                        // (0.36) so the symbols stay legible beside 28 pt characters.
                        ZhuyinWordView(headword: part.text, zhuyin: side, size: charSize, weight: weight, color: ink,
                                       language: "zh-TW", zhuyinScale: 0.36)
                            .contentTransition(.opacity)
                    } else if let perChar {
                        PinyinRubyLine(units: perChar, size: charSize, weight: weight, color: ink, readingColor: Theme.muted)
                            .contentTransition(.opacity)
                    } else {
                        Text(part.text)
                            .font(.system(size: charSize, weight: weight))
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                    if swappable {
                        Image(systemName: "chevron.down")
                            .scaledFont(size: (big ? 12 : 9) * scale, weight: .bold)
                            .foregroundStyle(Theme.muted)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                }
                // With pinyin over each character the row is taller upwards: its characters' middle is a little above
                // its bottom, not its centre.
                .alignmentGuide(.chunkText) { d in perChar == nil ? d[VerticalAlignment.center] : d[.bottom] - charSize * 0.6 }
            }
            .foregroundStyle(ink)
            .padding(.vertical, 2)
            // A swappable block: a dashed line under its characters (the dashed box is gone with the boxes).
            .overlay(alignment: .bottom) {
                if swappable {
                    DashedLine()
                        .stroke(ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(height: 2)
                        .padding(.trailing, (big ? 16 : 12) * scale)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle(scale: 0.94))
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
        .background(Theme.secondary.opacity(0.8), in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// A horizontal line across its frame's middle (the dashed line under a swappable block).
private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

private extension VerticalAlignment {
    /// The middle of a chunk block's characters (below its reading, when one sits over them).
    nonisolated enum ChunkText: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    nonisolated static let chunkText = VerticalAlignment(ChunkText.self)
}

extension EnvironmentValues {
    /// Every formula below in its parts of speech's colours, whatever 「品詞」 is set to (the diary's 「振り返る」).
    @Entry var chunkPOSColorsOn: Bool = false
}
