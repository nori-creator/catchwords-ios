import SwiftUI

/// One usage chunk as a formula (docs/chunk-rules.md, web ChunkLine): blocks joined by ＋, the translation
/// under them, and a button that reads the whole chunk. The same view in word detail and the review answer.
///
/// - The word being learned is a fixed, bolder block (C2).
/// - A swappable block (dashed, ▾) opens a wheel of the words natives put there (C5/C6). Picking one
///   reads that word, swaps it into the chunk and its translation; the right button reads the new chunk.
/// - Any other block reads its own word.
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
        HStack(alignment: .center, spacing: size == .large ? 10 : 8) {
            VStack(alignment: .leading, spacing: size == .large ? 8 : 5) {
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
                    FlowRow(spacing: 4) { parts(scale: scales.last ?? 1) }
                }
                if !translation.isEmpty {
                    Text(translation)
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
            Spacer(minLength: 0)
            PronounceCircle(text: ChunkRules.spoken(shown, target: target), size: size == .large ? 50 : 36)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: open)
        .onAppear { if let startOpen { open = startOpen } }
    }

    /// The block text's own size at scale 1.
    private var baseSize: CGFloat { size == .large ? 20 : 15 }

    /// The sizes tried for one line, largest first: never under 80% of the normal size, and a hanzi never under 15 pt
    /// (at the reader's text size). A compact chunk is already at 15 pt, so it only wraps.
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
        HStack(spacing: 4) { parts(scale: scales[min(k, scales.count - 1)]) }
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func parts(scale: CGFloat) -> some View {
        ForEach(Array(shown.enumerated()), id: \.offset) { i, part in
            HStack(spacing: 4) {
                if i > 0 {
                    Text("+")
                        .scaledFont(size: (size == .large ? 15 : 12) * scale, weight: .bold)
                        .foregroundStyle(Theme.muted.opacity(0.45))
                        .accessibilityHidden(true)
                }
                block(i, part, scale: scale)
            }
        }
    }

    private func block(_ i: Int, _ part: ChunkPart, scale: CGFloat) -> some View {
        let kind = ChunkKind(pos: part.pos)
        let original = chunk.parts[safe: i] ?? part
        let isHead = !headword.isEmpty && LanguageRules.mentionsHeadword(original.text, headword: headword, target: target)
        let swappable = !isHead && ChunkRules.isSwappable(original, headword: headword, target: target)
        let isOpen = open == i
        let big = size == .large
        return Button {
            SoundService.shared.speak(part.text)
            if swappable {
                Haptics.selection()
                open = isOpen ? nil : i
            }
        } label: {
            let side = Self.sideZhuyin(for: part, target: target, pref: readingPref)
            // Pinyin (or a reading that does not pair one syllable per character) stays one line over the block.
            let reading = side == nil ? Self.reading(for: part, target: target, pref: readingPref) : nil
            let ink = kind.ink.mix(with: colorScheme == .dark ? .white : .black, by: big ? 0.3 : 0.25)
            VStack(spacing: 1) {
                // The token's reading, small, over its text (server chunk tokens, 2026-10-15); none on older cards.
                if let reading {
                    Text(reading)
                        .scaledFont(size: (big ? 10.5 : 9) * scale, weight: .medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .opacity(0.8)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 3) {
                    if let side {
                        // The headword's own view and settings: zhuyin to the right of each character.
                        ZhuyinWordView(headword: part.text, zhuyin: side,
                                       size: AppTypeScale.scaled(baseSize * scale, for: dynamicTypeSize),
                                       weight: .bold, color: ink, language: "zh-TW")
                            .contentTransition(.opacity)
                    } else {
                        Text(part.text)
                            .scaledFont(size: baseSize * scale, weight: .bold)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                    if swappable {
                        Image(systemName: "chevron.down")
                            .scaledFont(size: (big ? 11 : 9) * scale, weight: .bold)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                }
            }
            // Darker ink on the light page, lighter on the dark one (mixing with black vanished in dark mode).
            .foregroundStyle(ink)
            .padding(.horizontal, (big ? 12 : 10) * scale)
            .padding(.vertical, reading == nil && side == nil ? 0 : 4)
            .frame(minHeight: big ? 48 : 34)
            .background(kind.ink.opacity(isHead ? 0.15 : swappable ? 0.04 : 0.08), in: .rect(cornerRadius: big ? 12 : 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: big ? 12 : 10, style: .continuous)
                    .stroke(kind.ink.opacity(isHead ? 0.78 : swappable ? 0.6 : 0.35),
                            style: StrokeStyle(lineWidth: isHead ? (big ? 2.5 : 2) : 1.5, dash: swappable ? [4, 3] : []))
            }
            .shadow(color: kind.ink.opacity(isHead ? 0.18 : 0), radius: 6, y: 2)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(part.text)
        .accessibilityHint(swappable ? L("ほかの語に入れ替えられます") : "")
        .accessibilityAddTraits(isHead ? .isHeader : [])
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
                    // Keep a native Text row: a stack with custom view modifiers can become unsupported content.
                    // Its attributed text preserves the word and the smaller, muted gloss beside it.
                    wheelLabel(c).tag(c.text)
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

    private func wheelLabel(_ choice: ChunkAlt) -> Text {
        var word = AttributedString(choice.text)
        word.font = .system(size: AppTypeScale.scaled(18, for: dynamicTypeSize), weight: .semibold)
        word.foregroundColor = Theme.foreground
        if !choice.ja.isEmpty {
            var gloss = AttributedString("  \(choice.ja)")  // lang-ok: reader's gloss from alts or degreeGloss
            gloss.font = .system(size: AppTypeScale.scaled(14, for: dynamicTypeSize))
            gloss.foregroundColor = Theme.muted
            word.append(gloss)
        }
        return Text(word)
    }
}
