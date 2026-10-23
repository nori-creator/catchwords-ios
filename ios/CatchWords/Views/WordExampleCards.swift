import SwiftUI

/// The word page's 「意味」 and 「例文」 cards, shared with the review's answer sheet so both show the same meaning
/// and example in the same design (owner 2026-10-14: 「復習の答え合わせの欄を表示言語での意味と例文に絞って統一して。
/// 意味と例文は単語の図鑑と同じものを表示して。答え合わせの欄のデザインも同じにして。青い意味と例文のアイコンつけて」).
struct WordMeaningCard: View {
    let meaning: String

    var body: some View {
        SectionCard(title: CardSection.meaning.title, icon: CardSection.meaning.icon) {
            Text(meaning)
                .scaledFont(size: 26, weight: .medium)
                .foregroundStyle(Theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 「例文」: the scene it is said in (a small label above, as on the extra examples; owner 2026-10-14
/// 「例文は追加の例文のように…状況場面感情の説明を短く例文のうえに書いて」), the sentence with the word marked, its
/// translation, and its voice.
struct WordExampleCard: View {
    let sentence: String
    let translation: String?
    var scene: String = ""
    let headword: String
    var known: [SentenceReadings.Known] = []
    var language: String = NativeAPI.targetLanguage

    var body: some View {
        WordExamplesCard(examples: [ExampleItem(sentence: sentence, translation: translation, scene: scene.isEmpty ? nil : scene)],
                         headword: headword, known: known, language: language)
    }
}

/// The word page's 「例文」 with every usage pattern's example (owner 2026-10-15: 「追加の例文」 is gone): each with its
/// short situation label right above it (only the label written for that very sentence, `ExampleItem.all`), the
/// sentence with the word marked, its translation and its voice.
struct WordExamplesCard: View {
    let examples: [ExampleItem]
    let headword: String
    /// The words the card already reads (`SentenceReadings.known`): they win over the dictionary in the sentences.
    var known: [SentenceReadings.Known] = []
    /// The word's learning language: only a Mandarin sentence gets readings.
    var language: String = NativeAPI.targetLanguage
    /// Every sentence's reading of each character (owner 2026-10-22: 「例文の漢字にピンインまたは注音をすべて書いて」).
    @State private var readings: [String: [SentenceUnit]] = [:]

    var body: some View {
        SectionCard(title: L("例文"), icon: "text.quote") {
            VStack(spacing: 10) {
                ForEach(Array(examples.enumerated()), id: \.offset) { _, ex in
                    ExampleBlock(example: ex, headword: headword,
                                 units: readings[ex.sentence] ?? (language.hasPrefix("zh") ? SentenceReadings.shared.cached(ex.sentence) : nil))
                }
            }
        }
        .task(id: examples.map(\.sentence)) {
            guard language.hasPrefix("zh") else { return }
            let found = await SentenceReadings.shared.load(examples.map(\.sentence), known: known)
            withAnimation(.easeOut(duration: 0.2)) { readings = found }
        }
    }
}

/// One example: its label, the sentence, the translation, and the voice button.
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
