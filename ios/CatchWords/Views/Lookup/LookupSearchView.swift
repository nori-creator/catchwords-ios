import SwiftUI

/// しらべる — the dictionary (owner 2026-11-08: 「辞書の代わりになるようにしたい」). Opened from the magnifier at the top of
/// the home screen.
///
/// - Type anything: a word of the display language, the learning language's characters, a reading (tones optional).
/// - While typing, the learner's own words that match come up at once (「あなたの図鑑」) — no AI, no wait.
/// - The search key (or 「「…」をしらべる」) looks it up (`lookupWord`): the spinner turns in the field itself, nothing
///   else takes the screen (owner 2026-10-08 for typed searches: 「検索ボタンを押したらその場でくるくる」).
/// - An entry opens its page (`LookupEntryView`): read it, hear it, and add it to the dex.
struct LookupSearchView: View {
    @Environment(DexStore.self) private var dex
    @Environment(\.dismiss) private var dismiss
    /// Opens a word of the dex (its page): the search closes first.
    var onOpenWord: (Sticker) -> Void
    /// Previews: the query typed and its answer already in.
    var preset: (query: String, result: LookupResult?)? = nil

    @State private var query = ""
    @State private var result: LookupResult?
    @State private var searching = false
    @State private var failure: String?
    @State private var needsConsent = false
    @State private var showConsent = false
    @State private var path: [LookupEntry] = []
    @State private var round = 0
    @State private var service = LookupService.shared
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The answer on screen belongs to what is typed now (typing on hides it until the next search).
    private var shownResult: LookupResult? {
        guard let result, result.query == String(trimmed.prefix(60)) else { return nil }
        return result
    }
    private var own: [Sticker] { LookupMatch.own(dex.stickers.filter { !$0.isSample }, query: trimmed) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if trimmed.isEmpty {
                        intro
                    } else {
                        if !own.isEmpty { ownSection }
                        if searching {
                            LookupSkeleton()
                        } else if needsConsent {
                            consentCard
                        } else if let failure {
                            failureCard(failure)
                        } else if let r = shownResult {
                            resultSection(r)
                        } else {
                            searchRow
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .top, spacing: 0) { searchBar }
            .background(AppBackground().ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LookupEntry.self) { entry in
                LookupEntryView(entry: entry, siblings: shownResult?.entries ?? result?.entries ?? [entry], onOpenWord: onOpenWord)
            }
        }
        .sheet(isPresented: $showConsent) {
            AIConsentView(onDecided: { agreed in
                showConsent = false
                if agreed { needsConsent = false; search() }
            })
        }
        .onAppear {
            service.loadRecents()
            if let preset {
                query = preset.query
                if let r = preset.result { result = r }
            } else {
                focused = true
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: searching)
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: shownResult?.entries.count)
        .uiReady("lookup")
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(focused ? Theme.primary : Theme.muted)
                TextField(L("言葉・漢字・読みでしらべる"), text: $query)
                    .scaledFont(size: 17)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { search() }
                    .onChange(of: query) { _, _ in
                        // A new query: the old answer's error or consent note goes; its answer hides by itself.
                        failure = nil
                        if needsConsent { needsConsent = false }
                    }
                    .accessibilityIdentifier("lookup.field")
                if searching {
                    ProgressView().controlSize(.small).tint(Theme.primary)
                } else if !query.isEmpty {
                    Button {
                        Haptics.selection()
                        query = ""
                        result = nil
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.muted.opacity(0.7))
                    }
                    .accessibilityLabel(L("消す"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().stroke(focused ? Theme.primary.opacity(0.55) : Theme.border, lineWidth: focused ? 1.5 : 1))
            .shadow(color: Theme.primary.opacity(focused ? 0.12 : 0), radius: 12, y: 4)
            .animation(.easeOut(duration: 0.2), value: focused)

            Button {
                SoundService.shared.pon(open: false)
                dismiss()
            } label: {
                Text(L("閉じる"))
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(Theme.primaryInk)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("lookup.close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .mask(LinearGradient(colors: [.black, .black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: Nothing typed yet

    private var intro: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("しらべる"))
                    .scaledFont(size: 34, weight: .bold)
                    .foregroundStyle(Theme.foreground)
                Text(L("見かけた言葉を、その場で。"))
                    .scaledFont(size: 16)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.top, 6)

            if !service.recents.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        LookupSectionTitle(L("最近しらべた言葉"))
                        Spacer()
                        Button(L("すべて消す")) {
                            Haptics.selection()
                            withAnimation(.snappy) { service.clearRecents() }
                        }
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(Theme.muted)
                    }
                    FlowRow(spacing: 8) {
                        ForEach(service.recents, id: \.self) { q in
                            Button { run(q) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.muted)
                                    Text(q)
                                        .scaledFont(size: 15, weight: .medium)
                                        .foregroundStyle(Theme.foreground)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 38)
                                .background(Theme.card, in: Capsule())
                                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                            }
                            .buttonStyle(PressableStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation(.snappy) { service.forget(q) }
                                } label: { Label(L("履歴から消す"), systemImage: "trash") }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                LookupSectionTitle(L("こんな言葉で引けます"))
                VStack(spacing: 0) {
                    ForEach(Array(examples.enumerated()), id: \.offset) { i, ex in
                        Button { run(ex.query) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: ex.symbol)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.primary)
                                    .frame(width: 36, height: 36)
                                    .background(Theme.accent.opacity(0.7), in: .rect(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ex.label)
                                        .scaledFont(size: 13)
                                        .foregroundStyle(Theme.muted)
                                    Text(ex.query)
                                        .scaledFont(size: 17, weight: .semibold)
                                        .foregroundStyle(Theme.foreground)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.muted.opacity(0.6))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < examples.count - 1 { Divider().padding(.leading, 64) }
                    }
                }
                .background(Theme.card, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1))
            }
        }
    }

    private struct Example {
        let symbol: String
        let label: String
        let query: String
    }

    /// What can be typed: a word of the reader's own language, and for Mandarin the characters and the bare pinyin.
    private var examples: [Example] {
        var out = [Example(symbol: "character.bubble", label: L("あなたの言葉で"), query: L("傘"))]
        if NativeAPI.targetLanguage.hasPrefix("zh") {
            out.append(Example(symbol: "character", label: L("漢字で"), query: "雨傘"))  // l10n-ignore (learning-language sample)
            out.append(Example(symbol: "textformat.abc", label: L("読みで（声調なしでも）"), query: "yusan"))
        }
        return out
    }

    // MARK: Typing

    private var ownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LookupSectionTitle(L("あなたの図鑑"))
            VStack(spacing: 0) {
                ForEach(Array(own.enumerated()), id: \.element.id) { i, s in
                    Button {
                        Haptics.selection()
                        onOpenWord(s)
                    } label: {
                        LookupOwnRow(sticker: s)
                    }
                    .buttonStyle(.plain)
                    if i < own.count - 1 { Divider().padding(.leading, 76) }
                }
            }
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1))
        }
    }

    private var searchRow: some View {
        Button { search() } label: {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.primary, in: Circle())
                Text(L("「\(trimmed)」をしらべる"))
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
                Spacer()
                Image(systemName: "return")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted.opacity(0.6))
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("lookup.search")
    }

    // MARK: The answer

    @ViewBuilder
    private func resultSection(_ r: LookupResult) -> some View {
        if r.entries.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.muted.opacity(0.6))
                Text(L("見つかりませんでした"))
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundStyle(Theme.foreground)
                Text(L("別の言い方や、読みでも引けます。"))
                    .scaledFont(size: 15)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                LookupSectionTitle(L("辞書"))
                ForEach(Array(r.entries.enumerated()), id: \.element.id) { i, e in
                    VStack(alignment: .leading, spacing: 8) {
                        if i == 0 && r.entries.count > 1 {
                            Label(L("いちばんよく使う言い方"), systemImage: "star.fill")
                                .scaledFont(size: 12, weight: .semibold)
                                .foregroundStyle(Theme.primaryInk)
                                .labelStyle(LookupTightLabel())
                        }
                        NavigationLink(value: e) {
                            LookupEntryRow(entry: e, owned: dex.owns(headword: e.headword))
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                        .simultaneousGesture(TapGesture().onEnded { SoundService.shared.pon(open: true) })
                        .accessibilityIdentifier("lookup.entry.\(i)")
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("AI の利用に同意すると、しらべるが使えます。"), systemImage: "sparkles")
                .scaledFont(size: 16, weight: .medium)
                .foregroundStyle(Theme.foreground)
            Button {
                showConsent = true
            } label: {
                Text(L("同意して使う"))
                    .scaledFont(size: 16, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(18)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1))
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .scaledFont(size: 15)
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)
            Button(L("もう一度")) { search() }
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(Theme.primaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: Actions

    private func run(_ q: String) {
        query = q
        search()
    }

    private func search() {
        let q = trimmed
        guard !q.isEmpty, !searching else { return }
        focused = false
        failure = nil
        needsConsent = false
        Haptics.impact(.light)
        service.remember(q)
        if let hit = service.cached(q) {
            result = hit
            return
        }
        round += 1
        let mine = round
        searching = true
        Task {
            defer { if mine == round { searching = false } }
            do {
                let r = try await service.lookup(q)
                guard mine == round else { return }
                result = r
                if r.entries.isEmpty { Haptics.warning() } else { Haptics.success() }
            } catch {
                guard mine == round else { return }
                Haptics.warning()
                if case .aiConsentRequired? = error as? APIError {
                    needsConsent = true
                } else {
                    failure = L10n.readerSafe((error as? LocalizedError)?.errorDescription ?? "",
                                              fallback: L("通信に失敗しました。もう一度お試しください。"))
                }
            }
        }
    }
}

// MARK: - Rows

/// A dictionary entry in the list: the word with its reading, its meaning, where it is used, and (when the search
/// split) how it differs from the others.
struct LookupEntryRow: View {
    let entry: LookupEntry
    let owned: Bool
    @AppStorage("reading.pref") private var readingPref: String = "zhuyin"

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                ZhuyinWordView(headword: entry.headword, zhuyin: entry.zhuyin, size: 28, weight: .semibold, pinyin: entry.pinyin)
                Text(entry.gloss)  // lang-ok: LookupEntry.readerSafe (ReaderLanguage.shown)
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                LookupTags(entry: entry, owned: owned)
                if !entry.nuance.isEmpty {
                    Text(entry.nuance)  // lang-ok: LookupEntry.readerSafe (ReaderLanguage.shown)
                        .scaledFont(size: 14)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1))
        .contentShape(.rect(cornerRadius: 18))
    }
}

/// The small labels under a meaning: in the dex, a proper noun, where it is used. None for an everyday word.
struct LookupTags: View {
    let entry: LookupEntry
    var owned: Bool = false

    var body: some View {
        let tags = items
        if !tags.isEmpty {
            HStack(spacing: 6) {
                ForEach(tags, id: \.text) { t in
                    HStack(spacing: 4) {
                        if let s = t.symbol { Image(systemName: s).font(.system(size: 10, weight: .bold)) }
                        Text(t.text).scaledFont(size: 12, weight: .semibold)
                    }
                    .foregroundStyle(t.ink)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(t.fill, in: Capsule())
                }
            }
        }
    }

    private struct Tag {
        let text: String
        let symbol: String?
        let ink: Color
        let fill: Color
    }

    private var items: [Tag] {
        var out: [Tag] = []
        if owned { out.append(Tag(text: L("図鑑にあり"), symbol: "checkmark", ink: Theme.ok, fill: Theme.ok.opacity(0.12))) }
        if entry.proper { out.append(Tag(text: L("固有名詞"), symbol: nil, ink: Color(hex: 0x9A5B00), fill: Theme.gold.opacity(0.22))) }
        if let u = entry.usageLabel { out.append(Tag(text: u, symbol: nil, ink: Theme.muted, fill: Theme.secondary)) }
        return out
    }
}

/// One of the learner's own words matching what is typed: its picture, the word and its meaning.
private struct LookupOwnRow: View {
    @Environment(DexStore.self) private var dex
    let sticker: Sticker

    var body: some View {
        HStack(spacing: 14) {
            LookupThumb(url: dex.url(for: sticker.heroPath))
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                ZhuyinWordView(headword: sticker.word?.headword ?? "", zhuyin: sticker.word?.readingZhuyin, size: 20,
                               weight: .semibold, pinyin: sticker.word?.pinyin)
                if let m = sticker.word?.meaningJa, !m.isEmpty {
                    Text(m).scaledFont(size: 14).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// A word's picture as a small rounded square (a soft placeholder while it loads or when there is none).
struct LookupThumb: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Theme.inset)
            if let url {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFit().padding(4) }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 12))
    }
}

/// A section's small title (the same weight and colour everywhere in しらべる).
struct LookupSectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .scaledFont(size: 13, weight: .semibold)
            .foregroundStyle(Theme.muted)
            .textCase(nil)
    }
}

/// A label with its icon close to the text.
struct LookupTightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10, weight: .bold))
            configuration.title
        }
    }
}

/// Rows standing in for the answer while it comes (the shape of the real rows, breathing).
private struct LookupSkeleton: View {
    @State private var on = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LookupSectionTitle(L("辞書"))
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.secondary).frame(width: 110, height: 30)
                    RoundedRectangle(cornerRadius: 5).fill(Theme.secondary).frame(width: 170, height: 16)
                    RoundedRectangle(cornerRadius: 5).fill(Theme.secondary.opacity(0.7)).frame(maxWidth: .infinity).frame(height: 12)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1))
                .opacity(on ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever().delay(Double(i) * 0.12), value: on)
            }
        }
        .onAppear { on = true }
        .accessibilityLabel(L("しらべています"))
    }
}
