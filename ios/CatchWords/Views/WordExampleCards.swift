import SwiftUI

/// The word page's 「意味」 and 「例文」 cards, shared with the review's answer sheet so both show the same meaning
/// and example in the same design (owner 2026-10-14: 「復習の答え合わせの欄を表示言語での意味と例文に絞って統一して。
/// 意味と例文は単語の図鑑と同じものを表示して。答え合わせの欄のデザインも同じにして。青い意味と例文のアイコンつけて」).
struct WordMeaningCard: View {
    let meaning: String

    var body: some View {
        SectionCard(title: CardSection.meaning.title, icon: CardSection.meaning.icon) {
            Text(meaning)
                .scaledFont(size: 24, weight: .medium)
                .foregroundStyle(Theme.foreground)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .reviewBlur("meaning-tr", .translation)
        }
    }
}

/// 「例文」 with one sentence (the review's answer sheet): the same box as the word page's examples (§4).
struct WordExampleCard: View {
    let sentence: String
    let translation: String?
    var scene: String = ""
    let headword: String
    var known: [SentenceReadings.Known] = []
    var language: String = NativeAPI.targetLanguage

    var body: some View {
        DetailExamplesCard(examples: [ExampleItem(sentence: sentence, translation: translation, scene: scene.isEmpty ? nil : scene)],
                           headword: headword, chunks: [], known: known, language: language)
    }
}

/// The word page's examples before 版25 (kept for older callers): now the same box as 「例文」.
struct WordExamplesCard: View {
    let examples: [ExampleItem]
    let headword: String
    var known: [SentenceReadings.Known] = []
    var language: String = NativeAPI.targetLanguage

    var body: some View {
        DetailExamplesCard(examples: examples, headword: headword, chunks: [], known: known, language: language)
    }
}

/// The word page's 「例文」 (docs/word-detail-design.md §4, 版25): each sentence in a grey box with the number of the chunk
/// it uses above the box's top-left corner (none when it uses none), the sentence within two lines with the chunk in
/// its parts' colours, the speaker at the end of the first line, and the translation under it. No scene label (owner
/// 2026-10-24: 「場面の一言は出さない」).
struct DetailExamplesCard: View {
    let examples: [ExampleItem]
    let headword: String
    /// The chunks as the page numbers them (`usage_chunks` in the server's order, as shown).
    let chunks: [UsageChunk]
    /// The words the card already reads (`SentenceReadings.known`): they win over the dictionary in the sentences.
    var known: [SentenceReadings.Known] = []
    /// The word's learning language: only a Mandarin sentence gets readings.
    var language: String = NativeAPI.targetLanguage
    /// The example the page just jumped to from a chunk's number: its box glows blue for a moment.
    var flash: Int? = nil
    @AppStorage("reading.pref") private var readingPref: String = "zhuyin"
    @State private var readings: [String: [SentenceUnit]] = [:]

    /// Pinyin over the examples only with ピンイン chosen (owner 2026-10-25: 「注音の設定のときは例文にピンイン書かなくていい」).
    private var showsPinyin: Bool { readingPref == "pinyin" && language.hasPrefix("zh") }

    var body: some View {
        SectionCard(title: CardSection.example.title, icon: CardSection.example.icon) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(examples.enumerated()), id: \.offset) { i, ex in
                    DetailExampleRow(example: ex, index: i, headword: headword, language: language,
                                     hit: ChunkRules.exampleHit(sentence: ex.sentence, chunks: chunks, target: language),
                                     pinyin: showsPinyin ? pinyin(for: ex.sentence) : nil,
                                     flashing: flash == i)
                        .id("example-\(i)")
                }
            }
        }
        .task(id: examples.map(\.sentence).joined(separator: "\n") + "|" + readingPref) {
            guard showsPinyin else { return }
            let found = await SentenceReadings.shared.load(examples.map(\.sentence), known: known)
            withAnimation(.easeOut(duration: 0.2)) { readings = found }
        }
    }

    /// The pinyin of each character, when the server's readings of this very sentence are at hand.
    private func pinyin(for sentence: String) -> [String?]? {
        guard let units = readings[sentence] ?? SentenceReadings.shared.cached(sentence),
              units.count == sentence.count else { return nil }
        return units.map { u -> String? in
            guard let p = u.pinyin?.trimmingCharacters(in: .whitespaces), !p.isEmpty else { return nil }
            return p
        }
    }
}

/// One example of 「例文」 (§4): number, then the grey box with the sentence and its translation.
struct DetailExampleRow: View {
    let example: ExampleItem
    let index: Int
    let headword: String
    let language: String
    let hit: ChunkRules.ExampleHit?
    let pinyin: [String?]?
    var flashing: Bool = false
    @AppStorage("detail.speechRate") private var speechRate: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let hit {
                DetailNumber(n: hit.chunk + 1)
                    .padding(.leading, 2)
                    .accessibilityLabel(L("チャンク\(hit.chunk + 1)を使った例文"))
            }
            VStack(alignment: .leading, spacing: 6) {
                ExampleSentenceView(sentence: example.sentence, headword: headword, target: language, hit: hit,
                                    words: example.words, pinyin: pinyin, reserve: 38) {
                    DetailSpeakButton(text: example.sentence, style: .small)
                }
                .reviewBlur("ex-\(index)-zh", .target)
                .accessibilityAction(named: L("発音を聞く")) {
                    SoundService.shared.speak(example.sentence, rate: speechRate)
                }
                .accessibilityIdentifier("example.sentence")
                if let t = example.translation?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    Text(t)
                        .scaledFont(size: 14)
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .reviewBlur("ex-\(index)-tr", .translation)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .background(Theme.secondary, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.primary, lineWidth: 3)
                    .opacity(flashing ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: flashing)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("example.block")
    }
}

/// One example (before 版25): its label, the sentence, the translation, and the voice button.
struct ExampleBlock: View {
    let example: ExampleItem
    let headword: String
    /// The reading of each character (`SentenceReadings`); nil: the sentence alone (not read yet, or not Mandarin).
    var units: [SentenceUnit]? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                if let scene = example.scene, !scene.isEmpty { SceneTag(text: scene) }
                if let units, !units.isEmpty {
                    SentenceRuby(units: units, headword: headword, size: AppTypeScale.scaled(19, for: dynamicTypeSize), words: example.words)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("example.sentence")
                } else {
                    Text(WordHighlight.marked(example.sentence, headword: headword, words: example.words))
                        .scaledFont(size: 19)
                        .foregroundStyle(Theme.foreground)
                        .lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let t = example.translation, !t.isEmpty {
                    Text(t).scaledFont(size: 14).foregroundStyle(Theme.muted).lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PronounceCircle(text: example.sentence, size: 40)
        }
        .padding(16)
        .background(Theme.secondary, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("example.block")
    }
}

/// The scene / feeling an example is said in, as a short label right above it: the original blue design — dark blue
/// text in a pale blue capsule (owner 2026-10-15 evening: 「元の青いデザインに戻して」; the white box with a blue edge of
/// PR #34 is gone). Kept from that pass: 13 pt, and a long label wraps instead of being cut.
struct SceneTag: View {
    let text: String

    var body: some View {
        Text(text)
            .scaledFont(size: 13, weight: .semibold)
            .foregroundStyle(Theme.primaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.primary.opacity(0.12), in: Capsule())
            .accessibilityIdentifier("example.scene")
    }
}

enum WordHighlight {
    /// The sentence with every occurrence of the word drawn in the accent colour, and (C19) the formula's run `span` the
    /// same way without the wash; with `words`, a WORD JOINER inside each word so a line never breaks there
    /// (`Sentences.unbreakable`, owner 2026-10-23).
    static func marked(_ sentence: String, headword: String, size: CGFloat = 19, span: String? = nil, words: [String] = []) -> AttributedString {
        var out = AttributedString(sentence)
        if let span, !span.isEmpty {
            var searchStart = out.startIndex
            while let r = out[searchStart...].range(of: span) {
                out[r].foregroundColor = Theme.primaryInk
                out[r].font = .system(size: size, weight: .semibold)
                searchStart = r.upperBound
            }
        }
        if !headword.isEmpty {
            var searchStart = out.startIndex
            while let r = out[searchStart...].range(of: headword) {
                out[r].foregroundColor = Theme.primaryInk
                out[r].backgroundColor = Theme.primary.opacity(0.1)
                out[r].font = .system(size: size, weight: .semibold)
                searchStart = r.upperBound
            }
        }
        // The joiners go in last, from the end, so the ranges found above stay what they were.
        let joinedText = Sentences.unbreakable(sentence, words: words)
        guard joinedText != sentence else { return out }
        var consumed = 0            // characters of the original passed so far
        var after: [Int] = []       // a joiner goes after this many characters of the original
        for ch in joinedText {
            if ch == "\u{2060}" { after.append(consumed) } else { consumed += 1 }
        }
        for offset in after.reversed() {
            out.insert(AttributedString("\u{2060}"), at: out.index(out.startIndex, offsetByCharacters: offset))
        }
        return out
    }
}
