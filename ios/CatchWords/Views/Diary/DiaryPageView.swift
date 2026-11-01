import SwiftUI

/// The diary's page for one day of the album (owner 2026-10-24: 「左側に撮った写真の切り抜き、右側にその一日の撮ったものを含めた
/// 日記を書けるように…その日習ったチャンクとか例文を使って」), designed for iOS from the start (owner 2026-10-24: the web's diary was
/// not good enough) and made a book page (owner 2026-10-25: 「IPhone duoならではの美しさ…細かいディテールまでこだわって」).
/// System fonts only (no handwriting face, owner 2026-10-20); the page itself (paper, rules) is drawn by whoever holds
/// it — the book's right page (`BookSpreadView`) or the iPhone's sheet (`HomeView`).
///
/// Top to bottom:
/// 1. The running head: where the day was spent (the places of its photos), 「紙とインク」, and at the top right
///    「振り返る」 (owner 2026-10-25): the day's timeline and its words' 使い方 in parts-of-speech colours
///    (`DiaryLookBack` — on the book it takes the left page's place, on the iPhone it is a sheet).
/// 2. 「この日のことば」: the day's words as the album shows them — the cut-out and its tag. A word the text uses gets an
///    ink stamp (and a light tap of the phone the moment it is stamped); a tap on a word opens it in 「振り返る」.
///    Nothing is written into the text for the learner (owner 2026-10-25: 「習ったチャンクはタップしても日記に貼れない
///    ようにする」 — the formula chips that did are gone).
/// 3. The text, in the learning language, on the page's rules (lined / grid / dots / plain, at the text's own pitch).
///    Not being written, it is set like a printed page: the day's words and formulas the text uses are in their parts
///    of speech's colours (`ChunkKind`, owner 2026-10-25: 「使ったチャンクは日記上でも品詞ごとに色変わる」); a tap and
///    it is writing again. Kept the moment it is typed, saved by itself a moment after typing stops
///    (`DiaryStore.setText`).
/// 4. Under the text, the sentence checks (owner 2026-10-25): each sentence is checked once when it is finished
///    (`DiaryStore.check`, a moment after the typing stops); what is wrong is underlined in the print and explained in
///    a card (`SentenceNoteCard`) with the most natural way to say it.
/// 5. The foot: how many of the day's words the text has used, and 「添削する」 — the finished diary's correction
///    (`DiaryCorrectionView`, on the book's left page or as a sheet).
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
    /// 「振り返る」 shown by whoever holds the page (the book shows it on its left page), with the word to open first.
    /// nil: the page shows it as its own sheet.
    var onLookBack: ((String?) -> Void)? = nil
    /// The finished correction shown by whoever holds the page (the book: its left page). nil: a sheet.
    var onCorrection: (() -> Void)? = nil

    @Environment(DexStore.self) private var dex
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var store = DiaryStore.shared
    @FocusState private var writing: Bool
    /// 「保存しました」 shows for a moment after a save.
    @State private var savedFlash = false
    @State private var styleOpen = false
    /// 「振り返る」 as this page's own sheet, and the word it opens on.
    @State private var lookBackOpen = false
    @State private var lookBackFocus: String?
    /// The correction as this page's own sheet.
    @State private var correctionOpen = false
    /// The words already stamped on this page (a new stamp taps the phone once).
    @State private var stamped: Set<String> = []
    @AppStorage(PageRule.storageKey) private var ruleRaw: String = PageRule.lined.rawValue
    @AppStorage(InkTone.storageKey) private var inkRaw: String = InkTone.navy.rawValue

    private var rule: PageRule { PageRule(rawValue: ruleRaw) ?? .lined }
    private var ink: InkTone { InkTone(rawValue: inkRaw) ?? .navy }

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
    private var words: [Sticker] { Self.words(on: day, in: dex) }

    static func words(on day: Date, in dex: DexStore) -> [Sticker] {
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
            if !staticPrint { sentenceNotes }
            foot
        }
        .task(id: DiaryStore.monthKey(day)) { await store.loadMonth(of: day) }
        .task(id: finishedSentences) { await checkFinished() }
        .onAppear {
            stamped = used
            if !staticPrint { store.resumeChecks() }
        }
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
        .sheet(isPresented: $correctionOpen) {
            if let c = store.correction(for: day) {
                DiaryCorrectionView(day: day, correction: c) { correctionOpen = false }
                    .padding(.horizontal, 20)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color(hex: 0xFBF8F1))
            }
        }
        .sheet(isPresented: $lookBackOpen) {
            DiaryLookBack(day: day, words: words, focus: lookBackFocus) { lookBackOpen = false }
                .padding(.horizontal, 20)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: 0xFBF8F1))
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
                        LocalizedPlaceText(lat: s.lat, lng: s.lng, saved: s.locationName, custom: s.locationCustom ?? false)
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
                if !words.isEmpty { lookBackButton }
            }
        }
        .frame(minHeight: 44)
    }

    /// 「振り返る」 at the page's top right: the day's timeline and its words' 使い方.
    private var lookBackButton: some View {
        Button {
            lookBack(nil)
        } label: {
            Label(L("振り返る"), systemImage: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink.color.opacity(0.85))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(ink.color.opacity(0.08), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityIdentifier("diary.lookBack")
    }

    private func lookBack(_ focus: String?) {
        guard !staticPrint else { return }
        Haptics.selection()
        if let onLookBack {
            onLookBack(focus)
        } else {
            lookBackFocus = focus
            lookBackOpen = true
        }
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
            lookBack(head)
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
        .accessibilityHint(L("押すと使い方が開きます"))
    }

    /// The formulas natives use the word in, as blocks with their parts of speech, when they are in the learning
    /// language (the server's patterns first, then an older card's chunks).
    private func formulas(of s: Sticker) -> [UsageChunk] {
        guard let word = s.word else { return [] }
        let raw = (word.extras?.usagePatterns ?? []).map(\.chunk) + (word.extras?.usageChunks ?? [])
        var seen = Set<String>()
        return raw.compactMap { (c: UsageChunk) -> UsageChunk? in
            let t = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !c.parts.isEmpty, !t.isEmpty, t != word.headword, LanguageRules.isIn(t, target: target),
                  seen.insert(t).inserted else { return nil }
            return c
        }
    }

    // MARK: The paper

    private var textBinding: Binding<String> {
        Binding(get: { text }, set: { store.setText($0, for: day) })
    }

    /// Set like a printed page in the page's ink; the day's formulas and words the text uses in their parts of
    /// speech's colours (`ChunkKind`, the 「品詞」 colours of the word page; the word itself in its blue). A formula is
    /// coloured block by block where its whole text is written; a word alone where it stands outside one.
    private func printed(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        a.foregroundColor = ink.color
        var coloured: [Range<String.Index>] = []
        func paint(_ r: Range<String.Index>, _ color: Color) {
            guard let ar = Range<AttributedString.Index>(r, in: a) else { return }
            a[ar].foregroundColor = color
            a[ar].font = .system(size: textSize, weight: .semibold)
            coloured.append(r)
        }
        for w in words {
            let head = w.word?.headword ?? ""
            for c in formulas(of: w) {
                for found in s.ranges(of: c.text) where !coloured.contains(where: { $0.overlaps(found) }) {
                    var at = found.lowerBound
                    for part in c.parts {
                        guard let end = s.index(at, offsetBy: part.text.count, limitedBy: found.upperBound) else { break }
                        let block = at..<end
                        if !part.text.isEmpty {
                            let isHead = !head.isEmpty && part.text.contains(head)
                            paint(block, isHead ? Theme.primaryInk : ChunkKind(pos: part.pos).ink)
                        }
                        at = end
                    }
                }
            }
        }
        for head in used {
            for r in s.ranges(of: head) where !coloured.contains(where: { $0.overlaps(r) }) {
                paint(r, Theme.primaryInk)
            }
        }
        // What the sentence checks found wrong: underlined in red where the sentence stands.
        guard !staticPrint else { return a }
        for sentence in DiaryStore.sentences(in: s) where sentence.finished {
            guard let check = store.checks[sentence.text], !check.issues.isEmpty,
                  let at = s.range(of: sentence.text) else { continue }
            for issue in check.issues {
                guard let r = s.range(of: issue.wrong, range: at),
                      let ar = Range<AttributedString.Index>(r, in: a) else { continue }
                a[ar].underlineStyle = Text.LineStyle(pattern: .dot, color: SentenceNoteCard.wrongInk)
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

    /// How many of the day's words the text has used (one dot each, filled once used), and 「添削する」.
    private var foot: some View {
        VStack(alignment: .leading, spacing: 14) {
            usedRow
            if !staticPrint && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { correctRow }
        }
    }

    @ViewBuilder
    private var usedRow: some View {
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

    // MARK: Correcting

    /// The finished sentences, as one key: the check runs again only when they change.
    private var finishedSentences: [String] {
        guard !staticPrint else { return [] }
        return DiaryStore.sentences(in: text).filter { $0.finished }.map { $0.text }
    }

    /// Checks the sentences finished since the last check, a moment after the typing stops (a new keystroke starts
    /// the wait again), at most three at a time.
    private func checkFinished() async {
        guard !staticPrint, !finishedSentences.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }
        let all = DiaryStore.sentences(in: text)
        var before = ""
        var sent = 0
        for s in all {
            defer { before += s.text }
            guard s.finished, store.checks[s.text] == nil, !store.checking.contains(s.text) else { continue }
            await store.check(s.text, before: before, day: day)
            sent += 1
            if sent == 3 || Task.isCancelled { break }
        }
    }

    /// Under the text: a card for each finished sentence with something to fix or say better, in the text's order;
    /// how many are fine; a sentence being checked; why checking stopped.
    @ViewBuilder
    private var sentenceNotes: some View {
        let finished = DiaryStore.sentences(in: text).filter { $0.finished }
        let noted = finished.filter { store.checks[$0.text]?.hasNote == true }
        let fine = finished.filter { store.checks[$0.text]?.hasNote == false }.count
        let busy = finished.contains { store.checking.contains($0.text) }
        if !noted.isEmpty || fine > 0 || busy || store.checkUnavailable != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(L("1文ずつの添削"))
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .tracking(1.2)
                        .foregroundStyle(ink.color.opacity(0.5))
                    if busy { ProgressView().controlSize(.mini) }
                    Spacer()
                    if fine > 0 {
                        Label(L("\(fine)文は自然です"), systemImage: "checkmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SentenceNoteCard.fixInk)
                    }
                }
                ForEach(Array(noted.enumerated()), id: \.offset) { _, s in
                    if let c = store.checks[s.text] {
                        SentenceNoteCard(sentence: s.text, check: c, ink: ink.color)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                if let why = store.checkUnavailable {
                    Text(why)
                        .scaledFont(size: 12)
                        .foregroundStyle(ink.color.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: noted.map { $0.text })
        }
    }

    /// 「添削する」 when the diary is written: the most natural full text and the day's review. A correction already
    /// made opens again from here.
    private var correctRow: some View {
        let k = key
        let busy = store.correcting.contains(k)
        let made = store.correction(for: day) != nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    Haptics.impact(.light)
                    writing = false
                    Task {
                        if await store.correct(day) { showCorrection() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if busy {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "checkmark.seal")
                        }
                        Text(busy ? L("添削しています…") : L("添削する"))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(ink.color, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .disabled(busy)
                .accessibilityIdentifier("diary.correct")
                if made && !busy {
                    Button {
                        Haptics.selection()
                        showCorrection()
                    } label: {
                        Text(L("添削を見る"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ink.color)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .overlay(Capsule().stroke(ink.color.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("diary.correction.open")
                }
            }
            if let err = store.correctError[k] {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func showCorrection() {
        if let onCorrection { onCorrection() } else { correctionOpen = true }
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
