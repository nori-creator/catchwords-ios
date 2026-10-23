import SwiftUI

/// 「使い方パターン」 (owner 2026-10-23, docs/chunk-rules.md C17): one card per way natives use the word — the general
/// situation it is said in, the formula (`ChunkLineView`), its translation, and a sentence that uses that very formula —
/// most used first. A card made before the patterns (no `usage_patterns`) shows what it has in the same place, the old
/// way: its examples, then its chunks (the content is never rewritten on its own — owner 2026-10-23).
/// Under them, the legend of the parts of speech when 「品詞」 is on.
struct PatternsCardContent: View {
    let patterns: [UsagePattern]
    /// An older card's examples and chunks (`ExampleItem.all` / `refinedChunks`), for a card without patterns.
    let examples: [ExampleItem]
    let chunks: [UsageChunk]
    let headword: String
    let target: String
    /// The words the card already reads (`SentenceReadings.known`): they win over the dictionary in the sentences.
    let known: [SentenceReadings.Known]
    /// A pattern's chunk in the shape the page shows it (`refinedChunks` rules); nil when it is not shown.
    let refine: (UsageChunk) -> UsageChunk?
    @AppStorage("chunk.posColors") private var posColors: Bool = false
    /// Every sentence's reading of each character (owner 2026-10-22: 「例文の漢字にピンインまたは注音をすべて書いて」).
    @State private var readings: [String: [SentenceUnit]] = [:]

    private var sentences: [String] {
        patterns.map(\.example.zh).filter { !$0.isEmpty } + examples.map(\.sentence)
    }

    private func units(for sentence: String) -> [SentenceUnit]? {
        readings[sentence] ?? (target.hasPrefix("zh") ? SentenceReadings.shared.cached(sentence) : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !patterns.isEmpty {
                ForEach(Array(patterns.enumerated()), id: \.offset) { _, pat in
                    PatternBlock(pattern: pat, chunk: refine(pat.chunk), headword: headword, target: target,
                                 units: units(for: pat.example.zh))
                }
            } else {
                ForEach(Array(examples.enumerated()), id: \.offset) { _, ex in
                    ExampleBlock(example: ex, headword: headword, units: units(for: ex.sentence))
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(chunks.enumerated()), id: \.offset) { i, chunk in
                        if i > 0 { Divider().overlay(Theme.border) }
                        ChunkLineView(chunk: chunk, headword: headword, target: target)
                            .padding(.vertical, 12)
                    }
                }
            }
            if posColors { legend }
        }
        .task(id: sentences) {
            guard target.hasPrefix("zh"), !sentences.isEmpty else { return }
            let found = await SentenceReadings.shared.load(sentences, known: known)
            withAnimation(.easeOut(duration: 0.2)) { readings = found }
        }
    }

    /// The kinds of block in every formula shown, in their colours. The legend wraps between its items, never inside
    /// one (owner 2026-10-15: under the English UI the labels broke into cramped lines).
    private var legend: some View {
        let parts = patterns.map(\.chunk).flatMap(\.parts) + chunks.flatMap(\.parts)
        let kinds = Set(parts.map { ChunkKind(pos: $0.pos) })
        return FlowRow(spacing: 12) {
            ForEach(ChunkKind.allCases.filter { kinds.contains($0) }, id: \.self) { k in
                HStack(spacing: 5) {
                    Circle().fill(k.ink).frame(width: 8, height: 8)
                    Text(k.label(for: target)).scaledFont(size: 13).foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                .fixedSize()
                .frame(minWidth: 56, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 4)
    }
}

/// One pattern: the scene over the formula, the formula with its translation, the example under it in its own pale
/// face, and the note folded at the bottom — one bordered card, so the three read as one unit (owner 2026-10-23:
/// 「状況、チャンク、例文の一体感」).
struct PatternBlock: View {
    let pattern: UsagePattern
    /// The formula as shown (tidied); nil when the page does not show it (then the scene and the example stand alone).
    let chunk: UsageChunk?
    let headword: String
    let target: String
    /// The example's reading of each character; nil: the sentence alone.
    var units: [SentenceUnit]? = nil
    @State private var showNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !pattern.scene.isEmpty {
                PatternSceneTag(text: pattern.scene)  // lang-ok: ReaderLanguage.clean (usagePatterns)
            }
            if let chunk {
                ChunkLineView(chunk: chunk, headword: headword, target: target)
            }
            if !pattern.example.zh.isEmpty {
                PatternExampleView(example: pattern.example, formula: pattern.chunk, headword: headword, target: target, units: units)
            }
            if !pattern.note.isEmpty { noteRow }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, pattern.note.isEmpty ? 12 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pattern.block")
    }

    /// 「このパターンのポイント」: folded until asked (owner 2026-10-23 evening's review: 「原則は閉じた状態に」).
    private var noteRow: some View {
        Button {
            withAnimation(.snappy) { showNote.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 2)
                Text(showNote ? pattern.note : L("このパターンのポイント"))  // lang-ok: ReaderLanguage.clean (usagePatterns)
                    .scaledFont(size: 13)
                    .foregroundStyle(showNote ? Theme.foreground : Theme.muted)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .scaledFont(size: 11, weight: .bold)
                    .foregroundStyle(Theme.muted)
                    .rotationEffect(.degrees(showNote ? 180 : 0))
                    .padding(.top, 3)
            }
            .frame(minHeight: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("このパターンのポイント"))
    }
}

/// The situation a formula is said in: a short line in the reader's language in a pale blue label with a speech bubble.
struct PatternSceneTag: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left")
                .scaledFont(size: 12, weight: .semibold)
            Text(text)
                .scaledFont(size: 13, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.primaryInk)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Theme.primary.opacity(0.08), in: .rect(cornerRadius: 9, style: .continuous))
        .accessibilityIdentifier("pattern.scene")
    }
}

/// A pattern's example in its pale face, a size down from the formula (owner 2026-10-23: 「あくまでもチャンクがメイン」):
/// a small 「例文」 heading with the voice button at its right end, the sentence across the whole width with the
/// formula's run and the word in blue, the translation under it. A line never breaks inside a word (`words`).
struct PatternExampleView: View {
    let example: PatternExample
    /// The formula as the server wrote it (with its swappable words), to find its run in the sentence (C19).
    let formula: UsageChunk
    let headword: String
    let target: String
    var units: [SentenceUnit]? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var span: String? { ChunkRules.spanText(of: formula, in: example.zh, target: target) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "text.quote")
                    .scaledFont(size: 11, weight: .bold)
                Text(L("例文"))
                    .tracking(0.6)
                    .scaledFont(size: 11, weight: .bold)
                Spacer(minLength: 0)
                PronounceCircle(text: example.zh, size: 28)
            }
            .foregroundStyle(Theme.primaryInk)
            .frame(minHeight: 28)
            if let units, !units.isEmpty {
                SentenceRuby(units: units, headword: headword, size: AppTypeScale.scaled(17, for: dynamicTypeSize),
                             span: span, words: example.words)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("pattern.sentence")
            } else {
                Text(WordHighlight.marked(example.zh, headword: headword, size: 17, span: span, words: example.words))
                    .scaledFont(size: 17)
                    .foregroundStyle(Theme.foreground)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pattern.sentence")
            }
            if !example.ja.isEmpty {
                Text(example.ja)  // lang-ok: ReaderLanguage.clean (usagePatterns)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.inset, in: .rect(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pattern.example")
    }
}
