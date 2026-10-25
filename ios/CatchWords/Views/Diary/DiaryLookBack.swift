import SwiftUI

/// 「振り返る」: the day looked back on while its diary is written (owner 2026-10-25: 「ユーザーが書くためにその日のタイムライン
/// （場所付き）スクロールしてその日の出来事を確認でき、習った単語の詳細のチャンクは品詞ごとで色分け」).
///
/// The day's timeline, oldest first: when each word was caught, where (the reader-language place name,
/// `LocalizedPlaceText`), and the word as the album shows it. A tap on a word opens its 使い方 — the same cards as the
/// word page (`PatternsCardContent`: scene, formula, example with its reading on every character), every formula in
/// its parts of speech's colours (`chunkPOSColorsOn`) with the legend under them. Nothing here writes into the diary
/// (owner 2026-10-25: 「習ったチャンクはタップしても日記に貼れないようにする」).
///
/// On the book (iPhone Duo) it takes the place of the left page, so the diary stays open on the right while the day is
/// read on the left; on the iPhone it is a sheet over the diary.
struct DiaryLookBack: View {
    let day: Date
    /// The day's words, oldest first (`DiaryPageView.words`).
    let words: [Sticker]
    /// The word to open first (a tap on its tile on the diary page).
    var focus: String? = nil
    /// Drawn on the book's paper (its ink) rather than in a sheet.
    var onPaper: Bool = false
    let onClose: () -> Void

    @Environment(DexStore.self) private var dex
    @State private var open: Set<String> = []

    private static let ink = Color(hex: 0x33291F)
    private var target: String { NativeAPI.targetLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(words.enumerated()), id: \.element.id) { i, s in
                            row(s, last: i == words.count - 1)
                                .id(s.id)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    guard let f = focus, let s = words.first(where: { $0.word?.headword == f }) else { return }
                    open.insert(s.id)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        withAnimation(.snappy) { proxy.scrollTo(s.id, anchor: .top) }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("振り返る"))
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
            .accessibilityIdentifier("diary.lookBack.close")
        }
        .padding(.top, onPaper ? 8 : 18)
        .padding(.bottom, 6)
    }

    /// One moment of the day: its time on the left with the day's line running down, then the place and the word.
    private func row(_ s: Sticker, last: Bool) -> some View {
        let head = s.word?.headword ?? ""
        let isOpen = open.contains(s.id)
        let pic = dex.dexPicture(of: s)
        let isCutout = pic?.isCutout == true
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Text(JPDate.time(s.takenAt))
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Self.ink.opacity(0.6))
                Circle()
                    .fill(Self.ink.opacity(0.45))
                    .frame(width: 7, height: 7)
            }
            .frame(width: 50)
            VStack(alignment: .leading, spacing: 8) {
                if let place = s.locationName, !place.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11, weight: .semibold))
                        LocalizedPlaceText(lat: s.lat, lng: s.lng, saved: place)
                            .lineLimit(1)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Self.ink.opacity(0.65))
                }
                Button {
                    Haptics.selection()
                    withAnimation(.snappy) {
                        if isOpen { open.remove(s.id) } else { open.insert(s.id) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        StickerImage(path: pic?.path, url: dex.url(for: pic?.path), contentMode: isCutout ? .fit : .fill, maxPoints: 56)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: isCutout ? 0 : 8, style: .continuous))
                            .shadow(color: .black.opacity(isCutout ? 0.18 : 0.12), radius: 3, y: 2)
                        WordTag(text: head, zhuyin: s.word?.readingZhuyin, pinyin: s.word?.pinyin, size: 18)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Self.ink.opacity(0.4))
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                .accessibilityLabel(head)
                .accessibilityHint(isOpen ? "" : L("押すと使い方が開きます"))
                .accessibilityIdentifier("diary.lookBack.word")
                if isOpen { usage(s) }
            }
        }
        .padding(.bottom, last ? 0 : 22)
        // The day's line, from this moment's dot down to the next.
        .background(alignment: .topLeading) {
            if !last {
                Rectangle()
                    .fill(Self.ink.opacity(0.14))
                    .frame(width: 1)
                    .padding(.leading, 25)
                    .padding(.top, 30)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The word's 使い方, in its parts of speech's colours.
    @ViewBuilder
    private func usage(_ s: Sticker) -> some View {
        let head = s.word?.headword ?? ""
        let patterns = (s.word?.extras?.usagePatterns ?? []).filter(\.hasContent)
        let chunks = (s.word?.extras?.usageChunks ?? []).filter { !$0.parts.isEmpty }
        if patterns.isEmpty && chunks.isEmpty {
            Text(L("この語の使い方はまだありません"))
                .scaledFont(size: 13)
                .foregroundStyle(Self.ink.opacity(0.55))
        } else {
            PatternsCardContent(patterns: patterns, examples: [], chunks: chunks, headword: head, target: target,
                                known: SentenceReadings.known(headword: head, pinyin: s.word?.pinyin,
                                                              chunks: chunks + patterns.map(\.chunk)),
                                refine: { Self.tidy($0, headword: head, target: target) })
                .environment(\.chunkPOSColorsOn, true)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// A formula in the page's shape (docs/chunk-rules.md C7/C8: one word one block, a degree word with its adjective),
    /// or nil when it is not a pattern.
    static func tidy(_ c: UsageChunk, headword: String, target: String) -> UsageChunk? {
        guard !c.parts.isEmpty else { return nil }
        let t = UsageChunk(parts: ChunkRules.tidy(c.parts, headword: headword, target: target, reader: L10n.lang), ja: c.ja)
        guard ChunkRules.isPattern(original: c.parts, tidied: t.parts), t.text != headword else { return nil }
        return t
    }
}
