import SwiftUI

/// One word found in しらべる, before it is in the dex.
///
/// From the top: its picture (pick another from the strip under it — the one picked becomes the word's picture in the
/// dex), the word with its reading and its sound (played once on opening), its meaning, then what only an AI writes for a
/// learner — each character's meaning and why together they mean this (「字から覚える」), which of the search's words to
/// use when (「使い分け」), one short sentence Taiwanese people say — and at the bottom 「図鑑に追加」. The card (its
/// examples, chunks and the rest of the word page) is made from the moment the page opens, so adding is quick; the word
/// then opens in the dex like any other.
struct LookupEntryView: View {
    @Environment(DexStore.self) private var dex
    @Environment(\.dismiss) private var dismiss
    let siblings: [LookupEntry]
    var onOpenWord: (Sticker) -> Void

    @State private var entry: LookupEntry
    @State private var pictures: [WebImageCandidate] = []
    @State private var picturesLoaded = false
    @State private var picked: WebImageCandidate?
    @State private var units: [SentenceUnit]?
    @State private var adding = false
    @State private var added = false
    @State private var failure: String?
    @State private var spoken: String = ""
    @AppStorage("reading.pref") private var readingPref: String = "zhuyin"

    init(entry: LookupEntry, siblings: [LookupEntry], onOpenWord: @escaping (Sticker) -> Void) {
        _entry = State(initialValue: entry)
        self.siblings = siblings
        self.onOpenWord = onOpenWord
    }

    private var owned: Sticker? {
        dex.stickers.first { !$0.isSample && $0.word?.headword == entry.headword }
    }
    private var others: [LookupEntry] { siblings.filter { $0.headword != entry.headword } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                picture
                head
                if !entry.chars.isEmpty { charsCard }
                if !others.isEmpty { compareCard }
                if !entry.example.isEmpty { exampleCard }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .id(entry.headword)
            .transition(.opacity)
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { addBar }
        .background(AppBackground().ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: entry.headword) { await open() }
        .uiReady("lookup-entry")
    }

    // MARK: Top

    private var topBar: some View {
        HStack {
            Button {
                SoundService.shared.pon(open: false)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .accessibilityLabel(L("戻る"))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: Picture

    private var picture: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                LinearGradient(colors: [Theme.accent, Theme.inset], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let p = picked {
                    LookupPicture(candidate: p, contentMode: .fill)
                        .transition(.opacity)
                        .id(p.id)
                } else if picturesLoaded {
                    // No picture found: the word itself, large, on the soft blue.
                    Text(entry.headword)
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(Theme.primaryInk.opacity(0.85))
                        .minimumScaleFactor(0.4)
                        .padding(24)
                } else {
                    ProgressView().tint(Theme.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.border, lineWidth: 1))
            .overlay(alignment: .bottomLeading) {
                if let name = picked?.credit?.name, !name.isEmpty {
                    Text(L("写真: \(name)"))
                        .scaledFont(size: 11, weight: .medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(10)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: picked?.id)

            if pictures.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pictures.prefix(6)) { c in
                            Button {
                                Haptics.selection()
                                picked = c
                            } label: {
                                LookupPicture(candidate: c, contentMode: .fill, thumb: true)
                                    .frame(width: 64, height: 64)
                                    .clipShape(.rect(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14)
                                        .stroke(picked?.id == c.id ? Theme.primary : Theme.border, lineWidth: picked?.id == c.id ? 3 : 1))
                            }
                            .buttonStyle(PressableStyle(scale: 0.94))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityLabel(L("写真を選ぶ"))
            }
        }
    }

    // MARK: Word

    private var head: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                ZhuyinWordView(headword: entry.headword, zhuyin: entry.zhuyin, size: 44, weight: .semibold, pinyin: entry.pinyin)
                Spacer(minLength: 0)
                Button {
                    SoundService.shared.speak(entry.headword)
                    Haptics.selection()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Theme.primary, in: Circle())
                        .shadow(color: Theme.primary.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel(L("発音を聞く"))
            }
            Text(entry.gloss)  // lang-ok: LookupEntry.readerSafe (ReaderLanguage.shown)
                .scaledFont(size: 24, weight: .bold)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            if !entry.senses.isEmpty {
                Text(entry.senses.joined(separator: L10n.current.listSeparator))  // lang-ok: LookupEntry.readerSafe (ReaderLanguage.shown)
                    .scaledFont(size: 16)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LookupTags(entry: entry, owned: owned != nil)
        }
        .padding(.top, 6)
    }

    // MARK: 字から覚える

    private var charsCard: some View {
        LookupCard(title: L("字から覚える"), symbol: "square.grid.2x2") {
            VStack(alignment: .leading, spacing: 14) {
                let tiles = HStack(alignment: .center, spacing: 6) {
                    ForEach(Array(entry.chars.enumerated()), id: \.offset) { i, c in
                        if i > 0 {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.muted.opacity(0.6))
                        }
                        VStack(spacing: 4) {
                            Text(reading(of: c, at: i))
                                .scaledFont(size: 13, weight: .medium)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                            Text(c.char)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(Theme.foreground)
                            Text(c.meaning)  // lang-ok: LookupEntry.readerSafe (ReaderLanguage.shown)
                                .scaledFont(size: 13, weight: .medium)
                                .foregroundStyle(Theme.primaryInk)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 72, maxWidth: .infinity)
                        .background(Theme.inset, in: .rect(cornerRadius: 16))
                    }
                }
                if entry.chars.count > 4 {
                    ScrollView(.horizontal, showsIndicators: false) { tiles }
                } else {
                    tiles
                }
                if !entry.why.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.gold)
                            .padding(.top, 2)
                        Text(entry.why)  // lang-ok: LookupEntry.readerSafe (ReaderLanguage.shown)
                            .scaledFont(size: 16)
                            .foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The character's reading the way the learner reads (設定 › 発音表記): zhuyin when the word's zhuyin has one
    /// syllable per character, else the pinyin.
    private func reading(of c: LookupChar, at i: Int) -> String {
        if readingPref != "pinyin" {
            let parts = entry.zhuyin.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if parts.count == entry.chars.count { return parts[i] }
        }
        return c.pinyin
    }

    // MARK: 使い分け

    private var compareCard: some View {
        LookupCard(title: L("使い分け"), symbol: "arrow.left.arrow.right") {
            VStack(alignment: .leading, spacing: 12) {
                if !entry.nuance.isEmpty {
                    Text(entry.nuance)  // lang-ok: LookupEntry.readerSafe (ReaderLanguage.shown)
                        .scaledFont(size: 16)
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(L("ほかの言い方"))
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Theme.muted)
                FlowRow(spacing: 8) {
                    ForEach(others) { o in
                        Button {
                            SoundService.shared.pon(open: true)
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { entry = o }
                        } label: {
                            HStack(spacing: 6) {
                                Text(o.headword)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Theme.foreground)
                                Text(o.gloss)  // lang-ok: LookupEntry.readerSafe (ReaderLanguage.shown)
                                    .scaledFont(size: 13)
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(Theme.secondary, in: Capsule())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }

    // MARK: Example

    private var exampleCard: some View {
        LookupCard(title: L("例文"), symbol: "text.quote") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if let units, !units.isEmpty {
                            SentenceRuby(units: units, headword: entry.headword, size: 22)
                        } else {
                            Text(entry.example)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Theme.foreground)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        SoundService.shared.speak(entry.example)
                        Haptics.selection()
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 40, height: 40)
                            .background(Theme.accent.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .accessibilityLabel(L("例文を聞く"))
                }
                if !entry.exampleTranslation.isEmpty {
                    Text(entry.exampleTranslation)  // lang-ok: LookupEntry.readerSafe (ReaderLanguage.shown)
                        .scaledFont(size: 15)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Add

    private var addBar: some View {
        VStack(spacing: 8) {
            if let failure {
                Text(failure)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.destructive)
                    .multilineTextAlignment(.center)
            }
            if let owned {
                Button {
                    SoundService.shared.pon(open: true)
                    onOpenWord(owned)
                } label: {
                    Label(L("図鑑で開く"), systemImage: "book")
                        .scaledFont(size: 17, weight: .bold)
                        .foregroundStyle(Theme.primaryInk)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().stroke(Theme.primary.opacity(0.4), lineWidth: 1.5))
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("lookup.open")
            } else {
                Button { add() } label: {
                    HStack(spacing: 8) {
                        if adding {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: added ? "checkmark" : "plus")
                                .font(.system(size: 17, weight: .bold))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        Text(added ? L("図鑑に追加されました") : L("図鑑に追加"))
                            .scaledFont(size: 17, weight: .bold)
                            .contentTransition(.opacity)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(added ? Theme.ok : Theme.primary, in: Capsule())
                    .shadow(color: (added ? Theme.ok : Theme.primary).opacity(0.35), radius: 14, y: 6)
                }
                .buttonStyle(PressableStyle())
                .disabled(adding || added)
                .accessibilityIdentifier("lookup.add")
                Text(L("図鑑と復習に入ります"))
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .mask(LinearGradient(colors: [.black.opacity(0), .black, .black], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: added)
    }

    // MARK: Work

    private func open() async {
        failure = nil
        added = false
        units = nil
        // The sound once, on opening (the word page does the same).
        if spoken != entry.headword {
            spoken = entry.headword
            SoundService.shared.speak(entry.headword)
        }
        // The card is made now, so 「図鑑に追加」 has it at hand (only for a word not in the dex yet).
        if owned == nil { _ = LookupService.shared.card(for: entry) }
        async let found: [WebImageCandidate] = (try? await WebImages.search(
            headword: entry.headword, meaning: entry.gloss, imageQuery: entry.imageQuery.isEmpty ? nil : entry.imageQuery,  // lang-ok: sent to the image search, not shown
            avoid: nil, category: entry.categoryKey, language: NativeAPI.targetLanguage)) ?? []
        if !entry.example.isEmpty {
            let known = SentenceReadings.known(headword: entry.headword, pinyin: entry.pinyin, chunks: [])
            let got = await SentenceReadings.shared.load([entry.example], known: known)
            units = got[entry.example]
        }
        let list = await found
        withAnimation(.easeOut(duration: 0.25)) {
            pictures = list
            picked = list.first
            picturesLoaded = true
        }
    }

    private func add() {
        guard !adding, !added else { return }
        adding = true
        failure = nil
        Haptics.impact(.medium)
        let e = entry
        let picture = picked
        Task {
            defer { adding = false }
            guard let card = await LookupService.shared.card(for: e).value else {
                Haptics.warning()
                failure = L("カードを作れませんでした。もう一度お試しください。")
                return
            }
            do {
                let sticker = try await dex.saveLookup(e, card: card, picture: picture)
                Haptics.success()
                SoundService.shared.play(.ccPop)
                added = true
                try? await Task.sleep(for: .milliseconds(650))
                onOpenWord(sticker)
            } catch {
                Haptics.warning()
                failure = SaveFailure.message(for: error)
            }
        }
    }
}

/// A white card with a small titled header, the same for every part of the entry.
struct LookupCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Theme.muted)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.border, lineWidth: 1))
    }
}

/// An internet picture (or an AI one sent inline) for a word.
struct LookupPicture: View {
    let candidate: WebImageCandidate
    var contentMode: ContentMode = .fill
    var thumb: Bool = false

    var body: some View {
        if let inline = WebImages.inlineImage(candidate) {
            Image(uiImage: inline).resizable().aspectRatio(contentMode: contentMode)
        } else {
            AsyncImage(url: thumb ? candidate.previewURL : URL(string: candidate.url)) { phase in
                if let img = phase.image {
                    img.resizable().aspectRatio(contentMode: contentMode)
                } else {
                    Theme.inset
                }
            }
        }
    }
}
