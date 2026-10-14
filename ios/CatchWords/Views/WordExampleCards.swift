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

    var body: some View {
        SectionCard(title: L("例文"), icon: "text.quote") {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    if !scene.isEmpty { SceneTag(text: scene) }
                    Text(WordHighlight.marked(sentence, headword: headword))
                        .scaledFont(size: 19)
                        .foregroundStyle(Theme.foreground)
                        .lineSpacing(8)
                    if let t = translation, !t.isEmpty {
                        Text(t).scaledFont(size: 14).foregroundStyle(Theme.muted).lineSpacing(6)
                    }
                }
                Spacer(minLength: 0)
                PronounceCircle(text: sentence, size: 40)
            }
            .padding(16)
            .background(Theme.secondary, in: .rect(cornerRadius: 22, style: .continuous))
        }
    }
}

/// The scene / feeling an example is said in, as a small blue label above it.
struct SceneTag: View {
    let text: String

    var body: some View {
        Text(text)
            .scaledFont(size: 12, weight: .semibold)
            .foregroundStyle(Theme.primaryInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.primary.opacity(0.1), in: Capsule())
    }
}

enum WordHighlight {
    /// The sentence with every occurrence of the word drawn in the accent colour.
    static func marked(_ sentence: String, headword: String, size: CGFloat = 19) -> AttributedString {
        var out = AttributedString(sentence)
        guard !headword.isEmpty else { return out }
        var searchStart = out.startIndex
        while let r = out[searchStart...].range(of: headword) {
            out[r].foregroundColor = Theme.primaryInk
            out[r].backgroundColor = Theme.primary.opacity(0.1)
            out[r].font = .system(size: size, weight: .semibold)
            searchStart = r.upperBound
        }
        return out
    }
}
