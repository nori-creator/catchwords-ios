import SwiftUI

/// The diary's page for one day of the album (owner 2026-10-24: 「左側に撮った写真の切り抜き、右側にその一日の撮ったものを含めた
/// 日記を書けるように…その日習ったチャンクとか例文を使って」). Designed for iOS from the start: the web's shelf, fonts and pencil are
/// not used (owner 2026-10-24: 「WEB版の日記の設計デザインチープで納得してないから、iphoneネイティブのクオリティの高い日記にいちから
/// 設計し直して」). System font only (no handwriting face, owner 2026-10-20).
///
/// Top to bottom:
/// 1. The day, and where it was spent (the places of its photos).
/// 2. 「この日のことば」: the day's words as chips — the cut-out and the headword — and under them the formulas natives use
///    them in (`usage_patterns`, the word in blue as on the word page). A tap writes the chip into the text.
/// 3. The text, in the learning language, on ruled lines drawn at the text's own pitch; kept the moment it is typed and
///    saved by itself a moment after typing stops (`DiaryStore.setText`). 「完了」 above the keyboard puts it away.
///
/// The correction is not on this page yet: the web's red pen was not adopted (owner 2026-10-24: 「赤ペンのデザインも採用しない。
/// 添削の機能は一から考え直す」); the candidates are in docs/proposals/iphone-duo.md, for the owner to choose from.
///
/// Language rules: the text and the formulas are in the learning language (R8, `LanguageRules.isIn`); the place names go
/// through the reader-language filter (`LocalizedPlaceText`).
struct DiaryPageView: View {
    let day: Date
    /// Opened as its own sheet (the iPhone's home): the day's title is on the page too.
    var standalone: Bool = false

    @Environment(DexStore.self) private var dex
    @Environment(\.displayScale) private var displayScale
    @State private var store = DiaryStore.shared
    @FocusState private var writing: Bool
    /// 「保存しました」 shows for a moment after a save.
    @State private var savedFlash = false

    /// The page's own ink (the home's dates).
    private static let paperInk = Color(hex: 0x33291F)
    /// The text's size, scaled with the type size once (the ruled lines are drawn at the same pitch).
    private var textSize: CGFloat { UIFontMetrics.default.scaledValue(for: 18) }
    private var lineGap: CGFloat { UIFontMetrics.default.scaledValue(for: 12) }
    private var linePitch: CGFloat { UIFont.systemFont(ofSize: textSize).lineHeight + lineGap }

    private var key: String { DiaryStore.key(day) }
    private var text: String { store.entry(for: day)?.text ?? "" }
    private var target: String { NativeAPI.targetLanguage }

    /// The day's words, one per word (as the album counts them), oldest first.
    private var words: [Sticker] {
        let cal = Calendar.current
        return AlbumDay.onePerWord(dex.albumStickers.filter { cal.isDate($0.takenAt, inSameDayAs: day) })
            .sorted { $0.takenAt < $1.takenAt }
    }

    /// Where the day was spent: each place once, in the order it was visited.
    private var places: [Sticker] {
        var seen = Set<String>()
        return words.filter { s in
            guard let p = s.locationName, !p.isEmpty, !seen.contains(p) else { return false }
            seen.insert(p)
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if !words.isEmpty { wordChips }
            paper
        }
        .padding(.top, standalone ? 8 : 0)
        .task(id: DiaryStore.monthKey(day)) { await store.loadMonth(of: day) }
        .onDisappear { Task { await store.save(day) } }
        .onChange(of: store.dirty.contains(key)) { was, now in
            // Dirty → clean: the save went through.
            guard was, !now, store.saveError[key] == nil else { return }
            withAnimation(.easeOut(duration: 0.2)) { savedFlash = true }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeOut(duration: 0.4)) { savedFlash = false }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("完了")) { writing = false }
                    .scaledFont(size: 16, weight: .semibold)
            }
        }
    }

    // MARK: Header

    /// 10月24日(金); a day of another year says its year.
    private static func title(_ day: Date) -> String {
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: day) == cal.component(.year, from: Date())
        return sameYear ? JPDate.monthDayWeek(day) : JPDate.yearMonthDayWeek(day)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "book.pages")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Self.paperInk.opacity(0.55))
                Text(L("日記"))
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Self.paperInk.opacity(0.55))
                Spacer()
                status
            }
            if standalone {
                Text(Self.title(day))
                    .scaledFont(size: 26, weight: .heavy)
                    .foregroundStyle(Self.paperInk)
                    .accessibilityAddTraits(.isHeader)
            }
            if !places.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "mappin")
                        .font(.system(size: 12, weight: .semibold))
                    ForEach(Array(places.prefix(3).enumerated()), id: \.offset) { i, s in
                        if i > 0 { Text("·") }
                        LocalizedPlaceText(lat: s.lat, lng: s.lng, saved: s.locationName)
                            .lineLimit(1)
                    }
                }
                .scaledFont(size: 13, weight: .medium)
                .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 10)
    }

    /// Saving / saved / could not save, at the header's right. The failure stays until a save goes through.
    @ViewBuilder
    private var status: some View {
        if store.saving.contains(key) {
            ProgressView().controlSize(.small)
        } else if let err = store.saveError[key] {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .scaledFont(size: 12, weight: .medium)
                .foregroundStyle(Theme.destructive)
                .lineLimit(1)
        } else if savedFlash {
            Label(L("保存しました"), systemImage: "checkmark")
                .scaledFont(size: 12, weight: .medium)
                .foregroundStyle(Theme.ok)
                .transition(.opacity)
        }
    }

    // MARK: Words

    private var wordChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("この日のことば"))
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 10)
            FlowRow(spacing: 8) {
                ForEach(words) { s in
                    if let head = s.word?.headword, !head.isEmpty {
                        chip(for: s, headword: head)
                    }
                }
            }
            .padding(.horizontal, 10)
            // (`shown`, not `formulas`: inside its own closure that name would be the array being declared.)
            let shown = words.flatMap { formulas(of: $0) }
            if !shown.isEmpty {
                FlowRow(spacing: 8) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, f in
                        formulaChip(f.text, headword: f.headword)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    /// The word's chip: its cut-out (or photo) and the headword, blue as on the word page.
    private func chip(for s: Sticker, headword: String) -> some View {
        let pic = dex.dexPicture(of: s)
        let isCutout = pic?.isCutout == true
        return Button {
            insert(headword)
        } label: {
            HStack(spacing: 7) {
                StickerImage(path: pic?.path, url: dex.url(for: pic?.path), contentMode: isCutout ? .fit : .fill, maxPoints: 26)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: isCutout ? 0 : 7, style: .continuous))
                Text(headword)
                    .scaledFont(size: 15, weight: .bold)
                    .foregroundStyle(Theme.primaryInk)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(minHeight: 38)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityLabel(headword)
        .accessibilityHint(L("押すと日記に入ります"))
    }

    /// The formulas natives use the word in (up to two a word), when they are in the learning language.
    private func formulas(of s: Sticker) -> [(text: String, headword: String)] {
        guard let word = s.word else { return [] }
        var texts: [String] = (word.extras?.usagePatterns ?? []).map(\.chunk.text)
        if texts.isEmpty { texts = (word.extras?.usageChunks ?? []).map(\.text) }
        var seen = Set<String>()
        var out: [(text: String, headword: String)] = []
        for raw in texts {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t != word.headword, LanguageRules.isIn(t, target: target), seen.insert(t).inserted else { continue }
            out.append((text: t, headword: word.headword))
            if out.count == 2 { break }
        }
        return out
    }

    /// A formula as one phrase, the word in blue (`ChunkLineView`'s colours, without its wheel).
    private func formulaChip(_ text: String, headword: String) -> some View {
        var attributed = AttributedString(text)
        attributed.foregroundColor = Theme.foreground
        if !headword.isEmpty, let r = attributed.range(of: headword) {
            attributed[r].foregroundColor = Theme.primaryInk
            attributed[r].font = .system(size: 15, weight: .bold)
        }
        return Button {
            insert(text)
        } label: {
            Text(attributed)
                .scaledFont(size: 15, weight: .medium)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(Theme.secondary, in: Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityLabel(text)
        .accessibilityHint(L("押すと日記に入ります"))
    }

    /// Writes a chip into the text, at its end (English gets a space before it; Chinese and Japanese do not).
    private func insert(_ piece: String) {
        Haptics.selection()
        var t = text
        if let last = t.last, !last.isWhitespace, !last.isNewline, target == "en" { t += " " }
        t += piece
        store.setText(t, for: day)
        writing = true
    }

    // MARK: Paper

    private var textBinding: Binding<String> {
        Binding(get: { text }, set: { store.setText($0, for: day) })
    }

    /// The ruled text. The lines are drawn at the text's own pitch, so each line of writing sits on one.
    private var paper: some View {
        TextField("", text: textBinding,
                  prompt: Text(L("この日のことを\(NativeAPI.targetName)で書いてみよう")).foregroundStyle(Theme.muted.opacity(0.7)),
                  axis: .vertical)
            .font(.system(size: textSize))
            .lineSpacing(lineGap)
            .foregroundStyle(Self.paperInk)
            .lineLimit(5...)
            .focused($writing)
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled(target != "en")
            .padding(.horizontal, 10)
            .padding(.vertical, lineGap / 2)
            .background(alignment: .top) {
                Canvas { ctx, size in
                    let hair = 1 / max(1, displayScale)
                    var y = linePitch
                    while y < size.height + 1 {
                        var line = Path()
                        line.move(to: CGPoint(x: 10, y: y))
                        line.addLine(to: CGPoint(x: size.width - 10, y: y))
                        ctx.stroke(line, with: .color(Self.paperInk.opacity(0.14)), lineWidth: hair)
                        y += linePitch
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { writing = true }
            .accessibilityLabel(L("日記"))
            .accessibilityIdentifier("diary.text")
    }
}
