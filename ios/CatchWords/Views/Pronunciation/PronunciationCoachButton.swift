import SwiftUI

/// The word page's microphone beside the speaker: opens 発音チェック (`PronunciationCoachView`) in its own sheet. Shown
/// only for Taiwan Mandarin words whose reading gives one tone per character. Kept in this one small view so the word
/// page itself gains nothing but the button (CLAUDE.md: 「単語の頁には手を入れない」 for anything heavier).
struct PronunciationCoachButton: View {
    let headword: String
    let zhuyin: String?
    let pinyin: String?
    let language: String

    @State private var open = false

    var body: some View {
        if language == "zh-TW", let tones = WordTones.make(headword: headword, zhuyin: zhuyin, pinyin: pinyin) {
            Button {
                Haptics.selection()
                open = true
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.primaryInk)
                    .frame(width: 40, height: 40)
                    .background(Theme.primary.opacity(0.12), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(L("発音をチェック"))
            .accessibilityIdentifier("detail.pronCoach")
            .sheet(isPresented: $open) {
                PronunciationCoachView(word: tones, zhuyin: zhuyin, pinyin: pinyin, language: language)
                    .presentationDetents([.large])
            }
        }
    }
}
