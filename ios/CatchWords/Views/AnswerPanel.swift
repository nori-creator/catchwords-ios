import SwiftUI

/// review.tsx answer sheet: pinned above the tab bar after a 4-choice pick — verdict band,
/// the headword with zhuyin, the word page's meaning and example cards (scrollable), then 図鑑で見る / 次へ.
struct AnswerPanel: View {
    let sticker: Sticker
    let correct: Bool
    /// False during the tour's practice quiz (no word page opens there).
    var showsDex: Bool = true
    let onDex: () -> Void
    let onNext: () -> Void

    @Environment(DexStore.self) private var dex
    @Environment(\.appReduceMotion) private var reduceMotion
    /// Drives the entrance: the verdict colour spreads across the band, then the word and buttons rise in.
    @State private var spread: CGFloat = 0
    @State private var settled = false
    /// The live word (its meaning arrives in the reader's language after the card was made).
    private var word: Word? { dex.sticker(id: sticker.id)?.word ?? sticker.word }
    private var headword: String { word?.headword ?? "" }
    private var tint: Color { correct ? Theme.ok : Theme.destructive }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: correct ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                    .scaledFont(size: 18, weight: .bold)
                    .symbolEffect(.bounce, value: settled)
                Text(correct ? L("正解！") : L("もう一度覚えよう"))
                    .scaledFont(size: 16, weight: .bold)
            }
            .foregroundStyle(tint.mix(with: .black, by: 0.25))
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(alignment: .leading) {
                // The verdict colour spreads from the left edge, like ink soaking in.
                GeometryReader { geo in
                    tint.opacity(0.14)
                        .frame(width: geo.size.width * spread)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    ZhuyinWordView(headword: headword, zhuyin: word?.readingZhuyin, size: 26, weight: .bold, pinyin: word?.pinyin)
                    Spacer(minLength: 0)
                    PronounceCircle(text: headword, size: 46)
                }
                .padding(.top, 8)

                explain

                HStack(spacing: 10) {
                    if showsDex {
                        Button(action: onDex) {
                            Label(L("図鑑で見る"), systemImage: "book")
                                .scaledFont(size: 16, weight: .semibold)
                                .foregroundStyle(Theme.foreground)
                                .labelStyle(TintedIconLabel())
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Theme.card, in: .rect(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                    Button(action: onNext) {
                        Text(L("次へ"))
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.primary, in: .rect(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .accessibilityIdentifier("answer.next")
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .opacity(settled ? 1 : 0)
            .offset(y: settled ? 0 : 10)
        }
        .onAppear {
            if reduceMotion {
                spread = 1
                settled = true
                return
            }
            withAnimation(.easeOut(duration: 0.32)) { spread = 1 }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82).delay(0.08)) { settled = true }
        }
        .background(Theme.card)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .stroke(tint.opacity(0.7), lineWidth: 1.5)
                .mask(alignment: .top) { Rectangle().frame(height: 30) }
        }
        .shadow(color: .black.opacity(0.14), radius: 18, y: -4)
    }

    // MARK: - Meaning and example (the word page's own cards)

    /// Only the meaning in the display language and the example, drawn exactly as on the word page
    /// (owner 2026-10-14: 「復習の答え合わせの欄を表示言語での意味と例文に絞って統一して。意味と例文は単語の図鑑と
    /// 同じものを表示して。答え合わせの欄のデザインも同じにして。青い意味と例文のアイコンつけて」).
    private var learningLang: String { LanguageRules.resolveWordLanguage(stored: word?.language, headword: headword) }
    private var meaning: String { word?.meaningJa ?? "" }
    /// As on the word page: an example only when it is in the learning language.
    private var example: String {
        let e = word?.exampleSentence ?? ""
        return !e.isEmpty && e.isIn(target: learningLang) ? e : ""
    }

    @ViewBuilder
    private var explain: some View {
        if !meaning.isEmpty || !example.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !meaning.isEmpty { WordMeaningCard(meaning: meaning) }
                    if !example.isEmpty {
                        WordExampleCard(sentence: example, translation: word?.exampleTranslation,
                                        scene: ReaderLanguage.shown(word?.extras?.shownExampleScene(for: example), source: example),
                                        headword: headword,
                                        known: SentenceReadings.known(headword: headword, pinyin: word?.pinyin,
                                                                      chunks: word?.extras?.usageChunks ?? []),
                                        language: learningLang)
                    }
                }
                .padding(.vertical, 2)
                // The word page's cards, so the same guard (WordDetailView): never wider than the panel, or it slides
                // sideways while it scrolls.
                .containerRelativeFrame(.horizontal)
            }
            .frame(maxHeight: 330)
            .fixedSize(horizontal: false, vertical: true)
            .scrollBounceBehavior(.basedOnSize, axes: [.vertical, .horizontal])
            .scrollIndicators(.visible)
        }
    }
}

/// Label with a primary-tinted icon and default-coloured title.
private struct TintedIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(Theme.primary)
            configuration.title
        }
    }
}
