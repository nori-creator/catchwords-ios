import SwiftUI

/// The diary's page for one day of the album (owner 2026-10-24: 「左側に撮った写真の切り抜き、右側にその一日の撮ったものを含めた
/// 日記を書けるように…その日習ったチャンクとか例文を使って」), designed for iOS from the start (owner 2026-10-24: the web's diary was
/// not good enough) and made a book page (owner 2026-10-25: 「IPhone duoならではの美しさ…細かいディテールまでこだわって」).
/// System fonts only (no handwriting face, owner 2026-10-20); the page itself (paper, rules) is drawn by whoever holds
/// it — the book's right page (`BookSpreadView`) or the iPhone's sheet (`HomeView`).
///
/// Top to bottom:
/// 1. The running head: where the day was spent (the places of its photos), and 「紙とインク」.
/// 2. 「この日のことば」: the day's words as the album shows them — the cut-out and its tag. A tap writes the word into
///    the text; a word the text uses gets an ink stamp (and a light tap of the phone the moment it is stamped).
///    Under them, the formulas natives use those words in (`usage_patterns`): a tap writes the formula.
/// 3. The text, in the learning language, on the page's rules (lined / grid / dots / plain, at the text's own pitch).
///    Not being written, it is set like a printed page, the day's words marked as with a highlighter; a tap and it is
///    writing again. Kept the moment it is typed, saved by itself a moment after typing stops (`DiaryStore.setText`).
/// 4. The foot: how many of the day's words the text has used, and whether it is saved.
///
/// Inside a page being turned (`staticPrint`) nothing here is live: no text field (a text field cannot be drawn into a
/// page curl), no buttons.
///
/// Language rules: the text and the formulas are in the learning language (R8, `LanguageRules.isIn`); the place names go
/// through the reader-language filter (`LocalizedPlaceText`).
struct DiaryPageView: View {
    let day: Date
    /// Opened as its own sheet (the iPhone's home): the day's title is on the page too.
    var standalone: Bool = false
    /// Drawn inside a page being turned: printed only, nothing to touch.
    var staticPrint: Bool = false

    @Environment(DexStore.self) private var dex
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var store = DiaryStore.shared
    @FocusState private var writing: Bool
    /// 「保存しました」 shows for a moment after a save.
    @State private var savedFlash = false
    @State private var styleOpen = false
    /// The words already stamped on this page (a new stamp taps the phone once).
    @State private var stamped: Set<String> = []
    @AppStorage(PageRule.storageKey) private var ruleRaw: String = PageRule.lined.rawValue
    @AppStorage(InkTone.storageKey) private var inkRaw: String = InkTone.navy.rawValue

    private var rule: PageRule { PageRule(rawValue: ruleRaw) ?? .lined }
    private var ink: InkTone { InkTone(rawValue: inkRaw) ?? .navy }

    /// The highlighter on the day's words, in the printed text.
    static let marker = Color(hex: 0xFFE39A, opacity: 0.75)
    /// The stamp's ink.
    static let stampInk = Color(hex: 0xB23A32)

    /// The text's size, scaled with the type size once (the rules are drawn at the same pitch).
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
            .filter { !($0.word?.headword ?? "").isEmpty }
    }

    /// The day's headwords the text uses.
    private var used: Set<String> {
        Set(words.compactMap { $0.word?.headword }.filter { !$0.isEmpty && text.contains($0) })
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
            runningHead
            if standalone { title }
            if !words.isEmpty { wordsShelf }
            paper
            foot
        }
        .task(id: DiaryStore.monthKey(day)) { await store.loadMonth(of: day) }
        .onAppear { stamped = used }
        .onDisappear { if !staticPrint { Task { await store.save(day) } } }
        .onChange(of: used) { old, now in
            guard !staticPrint else { return }
            let fresh = now.subtracting(stamped)
            stamped = now
            if !fresh.isEmpty, !old.isSuperset(of: now) { Haptics.impact(.soft) }
        }
        .onChange(of: store.dirty.contains(key)) { was, now in
            // Dirty → clean: the save went through.
            guard was, !now, store.saveError[key] == nil else { return }
            withAnimation(.easeOut(duration: 0.2)) { savedFlash = true }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeOut(duration: 0.4)) { savedFlash = false }
            }
        }
        .sheet(isPresented: $styleOpen) {
            DiaryStyleSheet()
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            // Only a live page has a text field, so only it ever brings up the keyboard this belongs to.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("完了")) { writing = false }
                    .scaledFont(size: 16, weight: .semibold)
            }
        }
    }

    // MARK: Head

    /// 10月24日(金); a day of another year says its year.
    static func title(_ day: Date) -> String {
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: day) == cal.component(.year, from: Date())
        return sameYear ? JPDate.monthDayWeek(day) : JPDate.yearMonthDayWeek(day)
    }

    /// The running head: small, spaced out, in the page's ink — the places on the left, 「紙とインク」 on the right.
    private var runningHead: some View {
        HStack(alignment: .center, spacing: 8) {
            if places.isEmpty {
                Text(L("日記"))
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .tracking(1.5)
                    .foregroundStyle(ink.color.opacity(0.55))
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(places.prefix(3).enumerated()), id: \.offset) { i, s in
                        if i > 0 {
                            Text(verbatim: "·").foregroundStyle(ink.color.opacity(0.35))
                        }
                        LocalizedPlaceText(lat: s.lat, lng: s.lng, saved: s.locationName)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .serif))
                .tracking(1.2)
                .foregroundStyle(ink.color.opacity(0.55))
            }
            Spacer(minLength: 8)
            status
            if !staticPrint {
                Button {
                    Haptics.selection()
                    styleOpen = true
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ink.color.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .background(ink.color.opacity(0.07), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityLabel(L("紙とインク"))
                .accessibilityIdentifier("diary.style")
            }
        }
        .frame(minHeight: 44)
    }

    private var title: some View {
        Text(Self.title(day))
            .font(.system(size: 28, weight: .bold, design: .serif))
            .foregroundStyle(ink.color)
            .accessibilityAddTraits(.isHeader)
    }

    /// Saving / saved / could not save. The failure stays until a save goes through.
    @ViewBuilder
    private var status: some View {
        if staticPrint {
            EmptyView()
        } else if store.saving.contains(key) {
            ProgressView().controlSize(.mini)
        } else if let err = store.saveError[key] {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .scaledFont(size: 12, weight: .medium)
                .foregroundStyle(Theme.destructive)
                .lineLimit(1)
        } else if savedFlash {
            Label(L("保存しました"), systemImage: "checkmark")
                .scaledFont(size: 12, weight: .medium)
                .foregroundStyle(ink.color.opacity(0.6))
                .transition(.opacity)
        }
    }

    // MARK: The day's words

    private var wordsShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("この日のことば"))
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .tracking(1.2)
                .foregroundStyle(ink.color.opacity(0.5))
            FlowRow(spacing: 14) {
                ForEach(Array(words.enumerated()), id: \.element.id) { i, s in
                    stickerTile(s, index: i)
                }
            }
            let shown = words.flatMap { formulas(of: $0) }
            if !shown.isEmpty {
                FlowRow(spacing: 8) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, f in
                        formulaChip(f.text, headword: f.headword)
                    }
                }
            }
        }
    }

    /// A word as the album shows it — its cut-out (or photo) and its tag, set at a slight angle like something pasted
    /// in — with the stamp once the text uses it.
    private func stickerTile(_ s: Sticker, index i: Int) -> some View {
        let head = s.word?.headword ?? ""
        let pic = dex.dexPicture(of: s)
        let isCutout = pic?.isCutout == true
        let tilt: Double = i.isMultiple(of: 2) ? -3 : 2.5
        let isUsed = used.contains(head)
        return Button {
            insert(head)
        } label: {
            VStack(spacing: -8) {
                StickerImage(path: pic?.path, url: dex.url(for: pic?.path), contentMode: isCutout ? .fit : .fill, maxPoints: 68)
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: isCutout ? 0 : 8, style: .continuous))
                    .shadow(color: .black.opacity(isCutout ? 0.2 : 0.14), radius: 3, y: 2)
                WordTag(text: head, zhuyin: s.word?.readingZhuyin, pinyin: s.word?.pinyin, tilt: -tilt * 0.6, size: 16)
            }
            .rotationEffect(.degrees(tilt))
            .overlay(alignment: .topTrailing) {
                if isUsed {
                    StampMark(color: Self.stampInk)
                        .offset(x: 8, y: -6)
                        .transition(reduceMotion ? .opacity : .scale(scale: 2.2).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.5), value: isUsed)
            .padding(.vertical, 4)
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .disabled(staticPrint)
        .accessibilityLabel(head)
        .accessibilityValue(isUsed ? L("日記で使った") : "")
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

    /// A formula as one phrase on a hairline tab, the word in blue (`ChunkLineView`'s colours, without its wheel).
    private func formulaChip(_ phrase: String, headword: String) -> some View {
        var attributed = AttributedString(phrase)
        attributed.foregroundColor = ink.color
        if !headword.isEmpty, let r = attributed.range(of: headword) {
            attributed[r].foregroundColor = Theme.primaryInk
            attributed[r].font = .system(size: 15, weight: .bold)
        }
        return Button {
            insert(phrase)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ink.color.opacity(0.45))
                Text(attributed)
                    .scaledFont(size: 15, weight: .medium)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .overlay(Capsule().stroke(ink.color.opacity(0.18), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .disabled(staticPrint)
        .accessibilityLabel(phrase)
        .accessibilityHint(L("押すと日記に入ります"))
    }

    /// Writes a word or a formula into the text, at its end (English gets a space before it; Chinese and Japanese do
    /// not), and goes on writing.
    private func insert(_ piece: String) {
        guard !staticPrint, !piece.isEmpty else { return }
        Haptics.selection()
        var t = text
        if let last = t.last, !last.isWhitespace, !last.isNewline, target == "en" { t += " " }
        t += piece
        store.setText(t, for: day)
        writing = true
    }

    // MARK: The paper

    private var textBinding: Binding<String> {
        Binding(get: { text }, set: { store.setText($0, for: day) })
    }

    /// Set like a printed page: the ink colour, the day's words marked as with a highlighter.
    private func printed(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        a.foregroundColor = ink.color
        for head in used {
            for r in s.ranges(of: head) {
                if let ar = Range<AttributedString.Index>(r, in: a) { a[ar].backgroundColor = Self.marker }
            }
        }
        return a
    }

    private var showsPrint: Bool { staticPrint || (!writing && !text.isEmpty) }

    /// The text on the page's rules. Printed when not being written; the field stays underneath, so a tap on the print
    /// goes straight on writing where it is.
    private var paper: some View {
        ZStack(alignment: .topLeading) {
            if !staticPrint {
                TextField("", text: textBinding,
                          prompt: Text(L("この日のことを\(NativeAPI.targetName)で書いてみよう")).foregroundStyle(ink.color.opacity(0.35)),
                          axis: .vertical)
                    .font(.system(size: textSize))
                    .lineSpacing(lineGap)
                    .foregroundStyle(ink.color)
                    .tint(ink.color)
                    .lineLimit(8...)
                    .focused($writing)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(target != "en")
                    .opacity(showsPrint ? 0 : 1)
                    .accessibilityLabel(L("日記"))
                    .accessibilityIdentifier("diary.text")
            }
            if showsPrint {
                Text(printed(text))
                    .font(.system(size: textSize))
                    .lineSpacing(lineGap)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !staticPrint else { return }
                        writing = true
                    }
                    .accessibilityAddTraits(staticPrint ? [] : .isButton)
                    .accessibilityHint(staticPrint ? "" : L("押すと書けます"))
            }
        }
        .padding(.vertical, lineGap / 2)
        .frame(maxWidth: .infinity, minHeight: linePitch * 9, alignment: .topLeading)
        .background(alignment: .top) {
            PageRules(rule: rule, ink: ink, pitch: linePitch)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !staticPrint else { return }
            writing = true
        }
        .animation(.easeOut(duration: 0.18), value: showsPrint)
    }

    // MARK: The foot

    /// How many of the day's words the text has used: one dot each, filled once used.
    @ViewBuilder
    private var foot: some View {
        if !words.isEmpty {
            HStack(spacing: 8) {
                Text(L("使ったことば"))
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .tracking(1)
                HStack(spacing: 4) {
                    ForEach(words) { s in
                        Circle()
                            .fill(used.contains(s.word?.headword ?? "") ? Self.stampInk.opacity(0.85) : .clear)
                            .overlay(Circle().stroke(ink.color.opacity(0.3), lineWidth: 1))
                            .frame(width: 7, height: 7)
                    }
                }
                Text(verbatim: "\(used.count) / \(words.count)")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .monospacedDigit()
                Spacer()
            }
            .foregroundStyle(ink.color.opacity(0.55))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: used)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The ink stamp a used word gets: a round frame and a tick, pressed in a little crooked.
struct StampMark: View {
    var color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.85), lineWidth: 1.6)
            Circle().inset(by: 3).stroke(color.opacity(0.5), lineWidth: 0.6)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(color.opacity(0.9))
        }
        .frame(width: 26, height: 26)
        .background(Circle().fill(.white.opacity(0.35)))
        .rotationEffect(.degrees(-14))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
