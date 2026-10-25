import SwiftUI

/// What the sentence check found in one finished sentence, under the diary's text (owner 2026-10-25: 「ここが間違ってる
/// 単語や文法を指してここが間違ってると修整され、ユーザが言いたいことの最も自然なフレーズな文も表示される」): the sentence
/// with its wrong parts struck through in red, each fix in green with why, then the most natural way to say it.
struct SentenceNoteCard: View {
    let sentence: String
    let check: SentenceCheck
    /// The page's ink.
    let ink: Color

    static let wrongInk = Color(hex: 0xC2362B)
    static let fixInk = Color(hex: 0x1E8A4C)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(marked)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(check.issues.enumerated()), id: \.offset) { _, issue in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Self.kindLabel(issue.kind))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Self.wrongInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Self.wrongInk.opacity(0.1), in: Capsule())
                        Text(issue.wrong)
                            .font(.system(size: 15, weight: .semibold))
                            .strikethrough(color: Self.wrongInk)
                            .foregroundStyle(Self.wrongInk)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ink.opacity(0.45))
                        Text(issue.fix)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Self.fixInk)
                    }
                    let why = ReaderLanguage.shown(issue.explain)
                    if !why.isEmpty {
                        Text(why)
                            .scaledFont(size: 13)
                            .foregroundStyle(ink.opacity(0.75))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !check.natural.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L("一番自然な言い方"), systemImage: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.primaryInk)
                    Text(check.natural)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ink)
                        .textSelection(.enabled)
                    let note = ReaderLanguage.shown(check.naturalNote)
                    if !note.isEmpty {
                        Text(note)
                            .scaledFont(size: 13)
                            .foregroundStyle(ink.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.primary.opacity(0.06), in: .rect(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.55), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ink.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// The sentence with its wrong parts in red, struck through.
    private var marked: AttributedString {
        var a = AttributedString(sentence)
        a.foregroundColor = ink
        for issue in check.issues {
            guard let r = a.range(of: issue.wrong) else { continue }
            a[r].foregroundColor = Self.wrongInk
            a[r].strikethroughStyle = Text.LineStyle(pattern: .solid, color: Self.wrongInk)
        }
        return a
    }

    static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "word": L("単語")
        case "grammar": L("文法")
        case "order": L("語順")
        case "particle": L("助詞")
        case "measure": L("量詞")
        default: L("その他")
        }
    }
}

/// The finished diary's correction (owner 2026-10-25): the most natural full text of what the learner meant, with the
/// reading on every character (the app's way, `SentenceRuby`), the coach's words on what they wrote about, today's
/// mistakes, what they tend to get wrong, and phrases natives would use. On the book it takes the left page's place
/// (the diary stays on the right); on the iPhone it is a sheet.
struct DiaryCorrectionView: View {
    let day: Date
    let correction: DiaryCorrection
    var onPaper: Bool = false
    let onClose: () -> Void

    @State private var readings: [String: [SentenceUnit]] = [:]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let ink = Color(hex: 0x33291F)

    /// The natural text sentence by sentence (each gets its reading), and the phrases.
    private var sentences: [String] {
        DiaryStore.sentences(in: correction.natural).map { $0.text } + correction.phrases.map(\.zh)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    naturalSection
                    let coach = ReaderLanguage.shown(correction.feedback)
                    if !coach.isEmpty {
                        section(L("講評"), icon: "text.bubble") {
                            Text(coach)
                                .scaledFont(size: 15)
                                .foregroundStyle(Self.ink.opacity(0.85))
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !correction.mistakes.isEmpty { mistakesSection }
                    let tendencies = correction.tendencies.map { ReaderLanguage.shown($0) }.filter { !$0.isEmpty }
                    if !tendencies.isEmpty {
                        section(L("間違えやすいところ"), icon: "exclamationmark.bubble") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(tendencies.enumerated()), id: \.offset) { _, t in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Circle().fill(SentenceNoteCard.wrongInk.opacity(0.7)).frame(width: 6, height: 6)
                                        Text(t)
                                            .scaledFont(size: 14)
                                            .foregroundStyle(Self.ink.opacity(0.85))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    if !correction.phrases.isEmpty { phrasesSection }
                }
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .task(id: correction.natural) {
            guard NativeAPI.targetLanguage.hasPrefix("zh") else { return }
            let found = await SentenceReadings.shared.load(sentences, known: [])
            withAnimation(.easeOut(duration: 0.2)) { readings = found }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("添削"))
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .tracking(1.2)
                    .foregroundStyle(Self.ink.opacity(0.5))
                Text(DiaryPageView.title(day))
                    .font(.system(size: onPaper ? 26 : 24, weight: .bold, design: .serif))
                    .foregroundStyle(Self.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Self.ink.opacity(0.75))
                    .frame(width: 34, height: 34)
                    .background(Self.ink.opacity(0.07), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .accessibilityLabel(L("閉じる"))
            .accessibilityIdentifier("diary.correction.close")
        }
        .padding(.top, onPaper ? 8 : 18)
        .padding(.bottom, 6)
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Self.ink.opacity(0.6))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The most natural full text, sentence by sentence with each character's reading.
    private var naturalSection: some View {
        section(L("一番自然な全文"), icon: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(DiaryStore.sentences(in: correction.natural).enumerated()), id: \.offset) { _, s in
                    ruby(s.text, size: 18)
                }
                HStack {
                    Spacer()
                    PronounceCircle(text: correction.natural, size: 32)
                }
            }
            .padding(14)
            .background(.white.opacity(0.6), in: .rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Self.ink.opacity(0.1), lineWidth: 1))
        }
    }

    private var mistakesSection: some View {
        section(L("今日の間違い"), icon: "pencil.and.list.clipboard") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(correction.mistakes.enumerated()), id: \.offset) { _, m in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(m.wrong)
                                .font(.system(size: 16, weight: .semibold))
                                .strikethrough(color: SentenceNoteCard.wrongInk)
                                .foregroundStyle(SentenceNoteCard.wrongInk)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Self.ink.opacity(0.45))
                            Text(m.fix)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(SentenceNoteCard.fixInk)
                        }
                        let why = ReaderLanguage.shown(m.explain)
                        if !why.isEmpty {
                            Text(why)
                                .scaledFont(size: 14)
                                .foregroundStyle(Self.ink.opacity(0.75))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var phrasesSection: some View {
        section(L("使うと自然なフレーズ"), icon: "quote.bubble") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(correction.phrases.enumerated()), id: \.offset) { _, p in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center) {
                            ruby(p.zh, size: 17)
                            Spacer(minLength: 0)
                            PronounceCircle(text: p.zh, size: 28)
                        }
                        let meaning = ReaderLanguage.shown(p.ja)
                        if !meaning.isEmpty {
                            Text(meaning).scaledFont(size: 14, weight: .semibold).foregroundStyle(Self.ink.opacity(0.8))
                        }
                        let when = ReaderLanguage.shown(p.note)
                        if !when.isEmpty {
                            Text(when)
                                .scaledFont(size: 13)
                                .foregroundStyle(Self.ink.opacity(0.65))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.55), in: .rect(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    /// A sentence in the learning language with the reading on every character (the app's way), or alone until the
    /// reading has come.
    @ViewBuilder
    private func ruby(_ text: String, size: CGFloat) -> some View {
        if let units = readings[text] ?? SentenceReadings.shared.cached(text), !units.isEmpty {
            SentenceRuby(units: units, headword: "", size: AppTypeScale.scaled(size, for: dynamicTypeSize))
        } else {
            Text(text)
                .font(.system(size: AppTypeScale.scaled(size, for: dynamicTypeSize), weight: .medium))
                .foregroundStyle(Self.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
