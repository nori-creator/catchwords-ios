import SwiftUI
import PhotosUI

/// Word detail (WordCard.tsx): a hero card, then one white card per section that has content.
struct WordDetailView: View {
    @Environment(DexStore.self) private var dex
    /// Today's review round (optional: previews have none); told when this page changes the sticker's headword.
    @Environment(ReviewStore.self) private var review: ReviewStore?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppRouter.self) private var router
    @Environment(PlanStore.self) private var plan
    let sticker: Sticker
    /// DEBUG preview: open scrolled to this section so the simulator frame shows it.
    var previewFocus: CardSection? = nil
    /// DEBUG preview: the selfie side opens on the selfie as it was taken (its 「元の写真」).
    var previewSelfieOriginal: Bool = false

    @State private var isAddingSelfie: Bool = false
    @AppStorage("reading.pref") private var readingPref: String = "zhuyin"
    @State private var autoplayed: String = ""
    @State private var prefs: CardPrefsStore = .shared
    @State private var showSections: Bool = false
    @State private var editingHead: Bool = false
    @State private var headDraft: String = ""
    @State private var isSavingHead: Bool = false
    @State private var toast: String?
    @State private var confirmDelete: Bool = false
    @State private var showSelfie: Bool = false
    @State private var flipAngle: Double = 0
    /// The front shows the cut-out wherever the word has one (owner 2026-10-09 / 2026-10-11); a choice made in the
    /// long-press picker (元の写真) swaps it for this visit.
    @State private var showCutout: Bool = true
    /// The cut-out's width ÷ height once it is drawn: the hero takes the cut-out's own shape (no empty box above
    /// and below it, owner 2026-10-11: 「単語の詳細のページの上の余白なくして」).
    @State private var cutoutRatio: CGFloat?
    /// The original photo, full screen: the photo side's 「元の写真」 button, or a tap on a picture without a selfie.
    @State private var showingOriginal: Bool = false
    /// The selfie side shows the selfie as it was taken instead of its cut-out (its 「元の写真」 button).
    @State private var selfieOriginal: Bool = false
    /// The selfie's and its cut-out's width ÷ height once drawn (the selfie is shown whole, at its own shape).
    @State private var selfieRatio: CGFloat?
    @State private var selfieCutRatio: CGFloat?
    @State private var pickingHero: Bool = false
    @State private var refreshing: Set<CardSection> = []
    @State private var editingCaption: Bool = false
    @State private var captionDraft: String = ""
    /// Sections being filled by the server right now (web AutoFillSections).
    @State private var filling: Set<CardSection> = []
    @State private var reporting: Bool = false
    @State private var reportNote: String = ""
    /// The item picked under 「違う項目を選ぶ」: asks what is wrong with it before sending (nil = none).
    @State private var reportItem: String?
    @State private var isFixing: Bool = false
    /// A report or 「作り直す」 without the AI consent: the consent sheet instead (nothing is sent).
    @State private var askAIConsent: Bool = false
    @State private var isReplacing: Bool = false
    /// Photos of this word from later encounters (the server's list, used when the dex has none of its re-encounters),
    /// paged in the hero by swiping and by the slideshow (page 0 = the main picture).
    @State private var laterPhotos: [StickerPhoto] = []
    @State private var heroPage: Int = 0
    /// Later pictures' cut-outs' width ÷ height once drawn, by id.
    @State private var laterRatios: [String: CGFloat] = [:]
    /// A finger is on the hero or swiping it (the slideshow waits; a swipe the scroll view takes over resets by
    /// itself), the hero is on screen, and which way the last slide went.
    @State private var touching: Bool = false
    @GestureState private var swiping: Bool = false
    @State private var heroVisible: Bool = true
    @State private var slideForward: Bool = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appReduceMotion) private var reduceMotion

    /// The word as the dex has it now. A page opened on a catch still being saved (owner 2026-10-11: 「キャッチしたての
    /// ときその単語の詳細に進めない」 — it now opens at once) becomes the saved word in place when the save is done.
    private var current: Sticker { dex.current(sticker.id) ?? sticker }
    /// Still being saved: no id on the server yet, so nothing here asks the server about it and the edits wait
    /// (「保存しています…」 in the top bar). A word without its word id yet waits the same way for its notes.
    private var isProvisional: Bool { DexStore.isProvisional(current.id) }
    /// Its save failed and it waits to be saved again (「保存待ち」): kept in the dex, never removed (owner 2026-10-15).
    private var isUnsaved: Bool { dex.isUnsaved(current.id) }
    private var word: Word? { current.word }
    private var extras: WordExtras? { word?.extras }
    private var headword: String { word?.headword ?? "" }

    /// A selfie can be taken for this word (its own photo, a front camera, already saved).
    private var canTakeSelfie: Bool { current.hasOwnPhoto && SelfieCamera.isAvailable && !isProvisional }

    /// 自撮りを撮る in the long-press photo sheet, under 写真を替える (owner 2026-10-14); nil = not offered.
    private var selfieHandler: ((UIImage) async -> Void)? {
        guard canTakeSelfie else { return nil }
        return { image in await addSelfie(image) }
    }

    /// The question for an item picked under 「違う項目を選ぶ」, and whether it is open.
    private var reportItemTitle: String { L("「\(Self.itemTitle(reportItem))」のどこが違いましたか？") }
    private var reportItemShown: Binding<Bool> {
        Binding(get: { reportItem != nil }, set: { shown in if !shown { reportItem = nil } })
    }

    /// The learner's own pictures; a word caught without one shows its internet stand-in instead.
    private var photos: [String] {
        let own = [current.cutoutImageUrl, current.objectImageUrl].compactMap { $0 }
        return own.isEmpty ? [current.placeholderImageUrl].compactMap { $0 } : own
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    if isUnsaved { unsavedBanner }
                    if !photos.isEmpty { photoHero }
                    metaCard
                    heroCard
                    if !isProvisional { EncounterHistoryView(stickerId: current.id) }
                    // Web WordCard: no frequency/register meters and no separate "使う場面" card
                    // (owner: メーターいらない). Register is a chip word in the header only.
                    ForEach(visibleSections.filter { hasContent($0) || isFilling($0) }) { section in
                        if hasContent(section) {
                            sectionView(section)
                                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity))
                        } else {
                            SectionSkeleton(title: section.title, icon: section.icon)
                                .transition(.opacity)
                        }
                    }
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(
                LinearGradient(colors: [Theme.background, Theme.backgroundDeep], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .onAppear {
                if let f = previewFocus {
                    Task { try? await Task.sleep(for: .milliseconds(400)); proxy.scrollTo(f.id, anchor: .top) }
                }
            }
            }
        }
        .alert(L("ひと言"), isPresented: $editingCaption) {
            TextField(L("その場のメモ"), text: $captionDraft)
            Button(L("キャンセル"), role: .cancel) {}
            Button(L("保存")) {
                let text = captionDraft
                Task {
                    do { try await dex.updateCaption(current, caption: text); Haptics.success() }
                    catch { Haptics.warning(); showToast(L("保存できませんでした。もう一度お試しください。")) }
                }
            }
        }
        // Keyed on the word id and the sticker id: a catch saved while its page is open runs these once it is saved.
        .task(id: current.wordId + "|" + L10n.lang) { await autoFill() }
        .task(id: current.id) { if !isProvisional { await dex.autoHero(current) } }
        // The developer's 「作り直す」 gate (`AdminAccess.isAdmin`) is asked here too, not only on 設定: asked once
        // per account, so a word page opened before 設定 ever was still offers it to an admin.
        .task { await AdminAccess.shared.refresh() }
        // An example shown without its scene label is still shown; why it has none goes to the developer log.
        .task(id: current.id + "|" + L10n.lang + "|labels") {
            for line in ExampleItem.missingLabels(sentence: word?.exampleSentence, extras: extras, target: learningLang) {
                DevLog.shared.add("example", "\(headword) \(line)")
            }
        }
        // Every picture is cut out (owner 2026-10-11): a photo without a cut-out yet gets one now, behind the page
        // (the scissors button is gone). Never for a catch still being saved (`needsCutout`).
        .task(id: current.id + "|cutout") {
            if CutoutBackfill.needsCutout(current) { await CutoutBackfill.shared.make(for: current, dex: dex) }
        }
        .task(id: sticker.id + "|play") {
            // The word is read once when its page opens (web WordCard autoplay, 400 ms) — keyed on the page's own
            // sticker, so a catch saved while its page is open is not read a second time.
            guard autoplayed != sticker.id else { return }
            autoplayed = sticker.id
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { SoundService.shared.speak(headword) }
        }
        .onAppear { prefs.use(learningLang) }
        .onChange(of: learningLang) { _, l in prefs.use(l) }
        .onAppear {
            applyHeroRole(animated: false)
            if previewSelfieOriginal { selfieOriginal = true }
        }
        .aiConsentSheet(isPresented: $askAIConsent)
        .sheet(isPresented: $pickingHero) {
            HeroPhotoPickerSheet(sticker: current, onPick: { role in
                try await dex.setHeroRole(current, role: role)
                applyHeroRole(animated: true)
            }, onReplace: { item in
                // 写真を替える sits at the bottom of this sheet now (owner 2026-10-11).
                Task { await replacePhoto(item) }
            }, onSelfie: selfieHandler)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
        // A picked item: what is wrong with it goes with the report (it went empty, so the fix was made blind —
        // 尺 photographed as a ruler but explained as a measure word, owner 2026-10-14).
        .alert(reportItemTitle, isPresented: reportItemShown) {
            TextField(L("例: 写真の物ではなく別の意味になっている（書かなくても大丈夫）"), text: $reportNote)
            Button(L("キャンセル"), role: .cancel) { reportItem = nil }
            Button(L("直してもらう")) {
                let item = reportItem ?? "auto"
                reportItem = nil
                reportAndFix(item: item)
            }
        } message: {
            Text(L("書いた内容をAIに伝えて、その項目だけを直します。"))
        }
        .alert(L("どこが違いましたか？"), isPresented: $reporting) {
            TextField(L("例: 読み方が違う（書かなくても大丈夫）"), text: $reportNote)
            Button(L("キャンセル"), role: .cancel) {}
            Button(L("直してもらう")) { reportAndFix() }
        } message: {
            Text(L("AIが間違っている項目を見つけ、辞書と照らして、その項目だけを直します。"))
        }
        .alert(L("単語を直す"), isPresented: $editingHead) {
            TextField(learningLang == "en" ? L("英語で入力") : learningLang == "ja" ? L("日本語で入力") : L("繁体字で入力"), text: $headDraft)
            Button(L("キャンセル"), role: .cancel) {}
            Button(L("直す")) { saveHeadword() }
        } message: {
            Text(L("この写真が指す単語だけを変えます。中身は新しく作ります。"))
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Theme.toastInk.opacity(0.92), in: Capsule())
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .confirmationDialog(L("この単語を図鑑から削除しますか？"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("削除"), role: .destructive) {
                // A 「保存待ち」 word was never written to the server: it is thrown away here, and the catch is not counted.
                if let pid = dex.unsaved[current.id] {
                    dex.discardUnsaved(pendingId: pid)
                    dex.refreshPending()
                    plan.undoCatch()
                    dismiss()
                    return
                }
                Task {
                    do {
                        try await dex.delete(current)
                        dismiss()
                    } catch {
                        Haptics.warning()
                        let reason = (error as? LocalizedError)?.errorDescription ?? ""
                        showToast(reason.isEmpty ? L("削除できませんでした。通信を確かめてください。") : reason)
                    }
                }
            }
        }
    }

    // MARK: - Top bar & hero

    private var topBar: some View {
        HStack {
            Text(headword)
                .scaledFont(size: 15, weight: .medium)
                .foregroundStyle(Theme.muted)
            if isProvisional {
                HStack(spacing: 5) {
                    if isUnsaved && !dex.isRetrying(current.id) {
                        Image(systemName: "icloud.and.arrow.up")
                        Text(L("保存待ち"))
                    } else {
                        ProgressView().controlSize(.mini)
                        Text(L("保存しています…"))
                    }
                }
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(isUnsaved ? Theme.primaryInk : Theme.muted)
                .accessibilityElement(children: .combine)
            }
            Spacer()
            Button {
                Haptics.selection()
                showSections = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(L("表示する項目と順番"))
            .accessibilityIdentifier("detail.sections")
            .popover(isPresented: $showSections, arrowEdge: .top) {
                SectionsPanel(prefs: prefs)
                    .accessibilityIdentifier("detail.sections.panel")
                    .presentationCompactAdaptation(.popover)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(L("閉じる"))
            .accessibilityIdentifier("detail.close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(Theme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    /// The headword, its reading, part of speech and register. Tighter than before (owner 2026-10-11: 「単語の見出しの
    /// 項目の余白を減らして」); the error report moved to the bottom of the page, beside 削除 (as on the web).
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ZhuyinWordView(headword: headword, zhuyin: word?.readingZhuyin, size: 38, weight: .heavy, pinyin: word?.pinyin, language: learningLang)
                    .opacity(isSavingHead ? 0.4 : 1)
                Button {
                    headDraft = headword
                    editingHead = true
                } label: {
                    Group {
                        if isSavingHead { ProgressView() } else { Image(systemName: "pencil") }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
                }
                .disabled(isSavingHead || isProvisional)
                .accessibilityLabel(L("単語を直す"))
                Spacer(minLength: 8)
                PronounceCircle(text: headword, size: 50)
            }
            // The part of speech only. The register chip (中立 / 書き言葉 / 話し言葉) is gone (owner 2026-10-15): the server
            // no longer writes it; an old card's `register_scale` is still decoded and simply not shown.
            let pos = word?.partOfSpeech.map(posLabel) ?? ""
            if !pos.isEmpty {
                FlowRow(spacing: 8) { chip(pos) }
            }
            // The reading line only when the zhuyin ruby cannot be drawn (web hides it otherwise). With ピンイン chosen
            // the headword already carries it over each character.
            if readingPref != "pinyin", (word?.readingZhuyin ?? "").isEmpty, let p = word?.pinyin, !p.isEmpty {
                Text(p).scaledFont(size: 14).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(light: 0xEAF3FE, dark: 0x0F2442), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 26, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    /// web ReportButton: let the AI find what is wrong, or point at the item yourself. At the bottom of the page,
    /// beside 削除 (owner 2026-10-11, as on the web 2026-10-02).
    private var reportMenu: some View {
        Menu {
            Button(L("AIに探してもらう"), systemImage: "sparkle.magnifyingglass") {
                guard AIConsent.shared.isGranted else { askAIConsent = true; return }
                reportNote = ""
                reporting = true
            }
            Section(L("違う項目を選ぶ")) {
                ForEach(reportItems, id: \.self) { item in
                    Button(Self.itemTitle(item)) {
                        guard AIConsent.shared.isGranted else { askAIConsent = true; return }
                        reportNote = ""
                        reportItem = item
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isFixing { ProgressView().controlSize(.mini) } else { Image(systemName: "flag") }
                Text(isFixing ? L("直しています…") : L("報告"))
            }
            .scaledFont(size: 16, weight: .semibold)
            .foregroundStyle(Theme.foreground.opacity(0.8))
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .background(Theme.secondary, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .disabled(isFixing || current.wordId.isEmpty)
        .accessibilityLabel(L("この語の誤りを報告"))
        .accessibilityIdentifier("detail.report")
    }

    /// The learner's visible sections that exist for this word's language.
    private var visibleSections: [CardSection] {
        let all = CardSection.sections(for: learningLang)
        return prefs.visible.filter { all.contains($0) }
    }

    /// Being written right now: one section (auto-fill) or the reader's whole explanation.
    private func isFilling(_ s: CardSection) -> Bool {
        filling.contains(s) || (!s.isExternal && dex.generatingWords.contains(current.wordId))
    }

    private func posLabel(_ pos: String) -> String {
        let map: [String: String] = ["N": L("名詞"), "V": L("動詞"), "VS": L("状態動詞"), "ADV": L("副詞"), "M": L("量詞"), "PREP": L("前置詞")]
        if let ja = map[pos.uppercased()] { return "\(pos) · \(ja)" }
        // English and Japanese part-of-speech words are shown in the display language, never as stored.
        let en: [String: String] = ["noun": L("名詞"), "verb": L("動詞"), "adjective": L("形容詞"), "adverb": L("副詞"),
                                    "preposition": L("前置詞"), "phrase": L("フレーズ"), "pronoun": L("代名詞"),
                                    "conjunction": L("接続詞"), "interjection": L("感動詞")]
        if let t = en[pos.lowercased()] { return t }
        if let t = L10n.translation(pos) { return t }
        let japaneseOnOtherScreen = L10n.lang != "ja" && !pos.isIn(target: "en")
        return ReaderLanguage.looksWrong(pos, reader: L10n.lang) || japaneseOnOtherScreen ? "" : pos
    }

    // MARK: - Photo hero (flips to the selfie like a card; slides through the word's photos)

    private var frontPath: String? {
        showCutout ? (current.cutoutImageUrl ?? current.objectImageUrl ?? current.placeholderImageUrl)
            : (current.objectImageUrl ?? current.cutoutImageUrl ?? current.placeholderImageUrl)
    }
    private var hasSelfie: Bool { current.selfieImageUrl != nil }

    /// A later encounter's picture in the hero: the re-encounter's cut-out where it saved one, else its photo — shown
    /// like the first one (owner 2026-10-15: the second and later photos were not cut-outs). Read from the dex's
    /// re-encounters (with their cut-outs); a server without them falls back to the photo list (`listStickerPhotos`,
    /// photos only).
    private struct LaterPhoto: Identifiable, Equatable {
        let id: String
        /// The storage path (signed by the dex); nil = only a signed link from the photo list.
        let path: String?
        let link: String?
        let isCutout: Bool
        let takenAt: Date?
        let place: String?
    }

    private var laterFaces: [LaterPhoto] {
        let met = dex.encounterEntries.filter { $0.stickerId == current.id }.sorted { $0.at < $1.at }
        if !met.isEmpty {
            return met.map { e in
                LaterPhoto(id: e.id, path: e.cutout ?? e.image, link: nil, isCutout: e.cutout != nil, takenAt: e.at, place: e.place)
            }
        }
        return laterPhotos.map { p in
            LaterPhoto(id: p.id, path: nil, link: p.url, isCutout: false, takenAt: SupabaseDate.parse(p.takenAt), place: p.place)
        }
    }

    /// Seconds each photo stays before the next slides in (owner 2026-10-15: 1枚目→2枚目→…→最後→1枚目 automatically).
    static let slideInterval: Double = 3

    /// The slideshow waits while a finger is on the photo, while the selfie or an original photo is shown, while the
    /// photo sheet is open, while the photo is off screen and while the app is in the background.
    private var slidePaused: Bool {
        touching || swiping || showSelfie || selfieOriginal || showingOriginal || pickingHero || !heroVisible || scenePhase != .active
    }

    /// The hero, plus the photos from later encounters: they slide by every few seconds and can be swiped through.
    private var photoHero: some View {
        let later = laterFaces
        return ZStack {
            heroFace(later)
                .id(heroPage)
                .transition(slideTransition)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .updating($swiping) { _, state, _ in state = true }
                .onEnded { v in
                    guard !later.isEmpty, !showSelfie,
                          abs(v.translation.width) > abs(v.translation.height) * 1.4 else { return }
                    let next = v.translation.width < -50 ? heroPage + 1 : v.translation.width > 50 ? heroPage - 1 : heroPage
                    let clamped = min(max(next, 0), later.count)
                    guard clamped != heroPage else { return }
                    Haptics.selection()
                    slide(to: clamped, forward: clamped > heroPage)
                }
        )
        .overlay(alignment: .bottom) {
            if !later.isEmpty, !showSelfie {
                HStack(spacing: 6) {
                    ForEach(0...later.count, id: \.self) { i in
                        Capsule().fill(.white.opacity(i == heroPage ? 1 : 0.5))
                            .frame(width: i == heroPage ? 18 : 7, height: 7)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.35), in: Capsule())
                .padding(.bottom, 14)
                .animation(.snappy, value: heroPage)
                .accessibilityHidden(true)
            }
        }
        .accessibilityAdjustableAction { dir in
            guard !later.isEmpty else { return }
            switch dir {
            case .increment: heroPage = min(heroPage + 1, later.count)
            case .decrement: heroPage = max(heroPage - 1, 0)
            @unknown default: break
            }
        }
        .onScrollVisibilityChange(threshold: 0.3) { heroVisible = $0 }
        // Keyed on the page shown too: each photo gets its full time, also after a swipe.
        .task(id: "\(later.count)|\(heroPage)|\(slidePaused)") { await autoSlide(count: later.count) }
        // The selfie's cut-out (its people and what they hold) is made on this phone before the card is turned.
        .task(id: current.selfieImageUrl ?? "") {
            if let p = current.selfieImageUrl, !isProvisional { SelfieCutouts.shared.request(p, dex: dex) }
        }
        // Keyed on the photo too: a replaced photo reloads the list while the page is open. A catch still being
        // saved has no photos on the server yet (the list is read once it is saved).
        .task(id: "\(current.id)|\(current.objectImageUrl ?? "")") {
            guard !isProvisional else { return }
            let all = await StickerPhoto.load(stickerId: current.id)
            laterPhotos = all.filter { !$0.first }
            heroPage = 0
        }
    }

    /// The next photo slides in from the right (from the left going back); with Reduce Motion they cross-fade.
    private var slideTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
                           removal: .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity))
    }

    private func slide(to page: Int, forward: Bool) {
        slideForward = forward
        withAnimation(reduceMotion ? .easeInOut(duration: 0.4) : .spring(response: 0.55, dampingFraction: 0.9)) { heroPage = page }
    }

    /// After `slideInterval` the next photo, the last one followed by the first again. Only with more than one photo.
    private func autoSlide(count: Int) async {
        guard count > 0, !slidePaused else { return }
        try? await Task.sleep(for: .seconds(Self.slideInterval))
        guard !Task.isCancelled, !slidePaused else { return }
        slide(to: (heroPage + 1) % (count + 1), forward: true)
    }

    @ViewBuilder
    private func heroFace(_ later: [LaterPhoto]) -> some View {
        if heroPage > 0, let p = later[safe: heroPage - 1] {
            laterFace(p, number: heroPage + 1)
        } else {
            mainFace
        }
    }

    /// A later encounter's picture, shown like the first one — its cut-out standing on the page, or its photo on the
    /// card — with when and where it was taken.
    private func laterFace(_ p: LaterPhoto, number: Int) -> some View {
        let url = p.path.flatMap { dex.url(for: $0, preferThumb: false) } ?? p.link.flatMap { URL(string: $0) }
        return Group {
            if p.isCutout {
                Color.clear
                    .aspectRatio(min(1.8, max(0.8, laterRatios[p.id] ?? 1)), contentMode: .fit)
                    .overlay {
                        StickerImage(path: p.path, url: url, contentMode: .fit, onLoad: { size in
                            guard size.height > 0 else { return }
                            withAnimation(.easeOut(duration: 0.2)) { laterRatios[p.id] = size.width / size.height }
                        })
                        .padding(14)
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 7)
                        .allowsHitTesting(false)
                    }
            } else {
                Theme.surface2  // photo placeholder (was a fixed light grey, glaring in dark mode)
                    .aspectRatio(0.8, contentMode: .fit)
                    .overlay {
                        if p.path != nil {
                            StickerImage(path: p.path, url: url, contentMode: .fill)
                                .allowsHitTesting(false)
                        } else {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image { img.resizable().scaledToFill() } else { ProgressView() }
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Text(L("\(number)回目"))
                    .scaledFont(size: 12, weight: .bold)
                if let d = p.takenAt {
                    Text(JPDate.monthDay(d)).scaledFont(size: 12, monospacedDigit: true)
                }
                if let place = p.place, !place.isEmpty {
                    Text(place).scaledFont(size: 12).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(12)
        }
        .contentShape(.rect(cornerRadius: 28))
        // A finger on the photo holds the slideshow (the long press itself does nothing here).
        .onLongPressGesture(minimumDuration: 60, perform: {}, onPressingChanged: { pressing in touching = pressing })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(number)回目に撮った写真"))
    }

    /// The hero's shape: a cut-out's own width ÷ height (kept between a tall 0.8 and a wide 1.8, so neither a bottle
    /// nor a long bench makes the page odd), a photo the 4:5 card.
    private func heroRatio(isCut: Bool, path: String?) -> CGFloat {
        guard isCut else { return 0.8 }
        let known = cutoutRatio ?? path.flatMap { ImageCache.shared.image(for: $0) }.map { $0.size.width / max(1, $0.size.height) }
        return min(1.8, max(0.8, known ?? 1))
    }

    /// The selfie side shows the selfie's cut-out — its people and the thing they hold (`SelfieCutouts`) — once this
    /// phone has made it, with 「元の写真」 at the top to see the selfie as it was taken (owner 2026-10-15:
    /// 「タップしたら自撮りになり、自撮りもデフォルトでは切り抜きを表示し、右上に元の写真ボタンを表示し、元の自撮り画像を
    /// 見えるようにする」).
    private var selfieCutReady: Bool {
        current.selfieImageUrl.map { SelfieCutouts.shared.state(for: $0) == .ready } ?? false
    }

    @ViewBuilder
    private func faceBody(back: Bool) -> some View {
        if back, let selfie = current.selfieImageUrl {
            if selfieCutReady && !selfieOriginal {
                Color.clear
                    .aspectRatio(min(1.8, max(0.6, selfieCutRatio ?? 0.8)), contentMode: .fit)
                    .overlay {
                        SelfieCutoutImage(path: selfie) { size in
                            guard size.height > 0 else { return }
                            withAnimation(.easeOut(duration: 0.2)) { selfieCutRatio = size.width / size.height }
                        }
                        .padding(14)
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 7)
                        .allowsHitTesting(false)
                    }
                    .transition(.opacity)
            } else {
                // The selfie as it was taken: the whole picture at its own shape, as wide as the page — never cut to
                // the word's cut-out's shape (it was, and showed small and cropped).
                Theme.surface2
                    .aspectRatio(selfieRatio ?? 0.75, contentMode: .fit)
                    .overlay {
                        StickerImage(path: selfie, url: dex.url(for: selfie, preferThumb: false), contentMode: .fit,
                                     onLoad: { size in
                                         guard size.height > 0 else { return }
                                         withAnimation(.easeOut(duration: 0.2)) { selfieRatio = size.width / size.height }
                                     })
                            .allowsHitTesting(false)
                            .id(selfie)
                    }
                    .transition(.opacity)
            }
        } else {
            let path = frontPath
            let isCut = showCutout && path == current.cutoutImageUrl
            // A cut-out stands on the page by itself — no grey box around it (owner 2026-10-11); a photo keeps its card.
            (isCut ? Color.clear : Theme.surface2)
                .aspectRatio(heroRatio(isCut: isCut, path: current.cutoutImageUrl), contentMode: .fit)
                .overlay {
                    StickerImage(path: path, url: dex.url(for: path, preferThumb: false), contentMode: isCut ? .fit : .fill,
                                 onLoad: isCut ? { size in
                                     guard size.height > 0 else { return }
                                     withAnimation(.easeOut(duration: 0.2)) { cutoutRatio = size.width / size.height }
                                 } : nil)
                        .padding(isCut ? 14 : 0)
                        .shadow(color: .black.opacity(isCut ? 0.2 : 0), radius: 10, y: 7)
                        .allowsHitTesting(false)
                        .id(path)
                }
        }
    }

    private var mainFace: some View {
        let back = showSelfie
        let path = back ? current.selfieImageUrl : frontPath
        return faceBody(back: back)
            .overlay(alignment: .bottomTrailing) {
                // With a selfie, a tap anywhere on the picture turns the card (photo ⇄ selfie), as the hint says
                // (owner 2026-10-14: 「タップすると自撮りへと書いてるのに元の画像が見える。2つを両立させて」); the
                // original photo has its own button at the top.
                if hasSelfie {
                    Text(back ? L("タップで戻る") : L("タップで自撮りへ"))
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if back {
                    // The selfie's own 「元の写真」: the selfie as it was taken, in place; again (切り抜き) back to the
                    // cut-out. Only when there is a cut-out to go back to (「大きく見る」 is gone).
                    if selfieCutReady {
                        heroButton(selfieOriginal ? L("切り抜き") : L("元の写真"),
                                   icon: selfieOriginal ? "chevron.backward" : "arrow.up.left.and.arrow.down.right",
                                   id: "detail.selfieOriginal") {
                            withAnimation(.easeInOut(duration: 0.25)) { selfieOriginal.toggle() }
                        }
                    }
                } else if hasSelfie, originalPath != nil {
                    // The photo side's original photo, full screen.
                    heroButton(L("元の写真"), icon: "arrow.up.left.and.arrow.down.right", id: "detail.viewOriginal") {
                        showingOriginal = true
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                // An internet picture says whose it is (Unsplash asks for the photographer's name).
                if !back, path != nil, path == current.placeholderImageUrl, let name = current.placeholderCredit?.name, !name.isEmpty {
                    Label(name, systemImage: "camera")
                        .scaledFont(size: 12, weight: .semibold)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(12)
                        .allowsHitTesting(false)
                        .accessibilityLabel(L("撮影：\(name)"))
                }
            }
            .clipShape(.rect(cornerRadius: 28, style: .continuous))
            // A plain photo: no foil, glare or tilt over it (owner 2026-10-09).
            .scaleEffect(x: back ? -1 : 1)
            .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
            .contentShape(.rect(cornerRadius: 28))
            .onTapGesture {
                // With a selfie: turn the card. Without one: the original photo, full screen.
                if hasSelfie {
                    flip()
                } else if originalPath != nil {
                    Haptics.selection()
                    showingOriginal = true
                }
            }
            .fullScreenCover(isPresented: $showingOriginal) {
                OriginalPhotoViewer(path: originalPath, url: dex.url(for: originalPath, preferThumb: false))
            }
            // 長押し: この単語をどの絵で見せるか選ぶ（Web HeroPhotoPicker）。 Not while the catch is still being saved.
            // A finger on the photo also holds the slideshow.
            .onLongPressGesture(minimumDuration: 0.45, perform: {
                guard !isProvisional else { return }
                Haptics.impact(.medium)
                pickingHero = true
            }, onPressingChanged: { pressing in touching = pressing })
            .accessibilityAction(named: L("表示する写真を選ぶ")) { if !isProvisional { pickingHero = true } }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(back ? L("自撮り写真") : L("写真"))
            .accessibilityAction(named: L("元の写真を見る")) {
                if back, selfieCutReady {
                    selfieOriginal = true
                } else if originalPath != nil {
                    showingOriginal = true
                }
            }
    }

    /// A small dark capsule button on the picture (top right).
    private func heroButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Label(title, systemImage: icon)
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.55), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .accessibilityIdentifier(id)
    }

    /// The photo as it was taken (not the cut-out); a word with no photo of its own shows its stand-in.
    private var originalPath: String? {
        current.objectImageUrl ?? current.placeholderImageUrl ?? current.cutoutImageUrl
    }

    /// Shows the side the learner chose (`hero_role`): the selfie is the card's back, the cut-out a toggle.
    private func applyHeroRole(animated: Bool) {
        let role = current.heroRole
        let wantSelfie = role == "selfie" && hasSelfie
        let change = {
            // Opening the page always starts on the cut-out (owner 2026-10-09: the dex shows cut-outs); a choice
            // just made in the picker (animated) is shown at once.
            if animated, role == "cutout" || role == "object" { showCutout = role == "cutout" && current.cutoutImageUrl != nil }
            if wantSelfie != showSelfie {
                showSelfie = wantSelfie
                flipAngle = wantSelfie ? 180 : 0
            }
        }
        if animated && !reduceMotion {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78), change)
        } else {
            change()
        }
    }

    /// Half-turn with the image swapped at 90° so the selfie reads as the card's back side. The selfie side always
    /// opens on its cut-out.
    private func flip() {
        guard hasSelfie else { return }
        Haptics.impact(.light)
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) {
                showSelfie.toggle()
                selfieOriginal = false
            }
            return
        }
        let target: Double = showSelfie ? 0 : 180
        withAnimation(.easeIn(duration: 0.16)) { flipAngle = 90 } completion: {
            showSelfie.toggle()
            selfieOriginal = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { flipAngle = target }
        }
    }

    // MARK: - Meta (when and where it was taken; the one-liner only when one was written)

    /// The top of the page is when and where the photo was taken (owner 2026-10-11: 「単語の詳細の一番上は撮った詳しい
    /// 時刻と場所だけ」). The one-liner shows only when one was written at the catch (still editable with its pencil);
    /// the memory curve is no longer on this page (the review screen has it).
    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(JPDate.full(current.takenAt))
                    .scaledFont(size: 15, weight: .medium, monospacedDigit: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } icon: {
                Image(systemName: "clock").scaledFont(size: 14)
            }
            .foregroundStyle(Theme.foreground.opacity(0.8))
            .frame(minHeight: 30, alignment: .leading)
            .accessibilityIdentifier("detail.takenAt")
            if mapsURL != nil { placeButton }
            if let cap = current.caption, !cap.isEmpty {
                Divider().overlay(Theme.border).padding(.vertical, 4)
                Button {
                    captionDraft = cap
                    editingCaption = true
                } label: {
                    HStack(alignment: .center) {
                        // The app's own font, not the handwriting (owner 2026-10-15).
                        Text(cap).scaledFont(size: 17).foregroundStyle(Theme.foreground.opacity(0.9))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "pencil").font(.system(size: 16)).foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 40, alignment: .trailing)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .disabled(isProvisional)
                .accessibilityLabel(L("ひと言を編集"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    /// Where it was taken, by name (never 「地図を開く」 in place of the name); a tap opens Maps there.
    private var placeButton: some View {
        Button {
            if let url = mapsURL { openURL(url) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse").scaledFont(size: 14)
                LocalizedPlaceText(lat: current.lat, lng: current.lng, saved: current.locationName, fallback: L("撮影地"))
                    .scaledFont(size: 15, weight: .semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").scaledFont(size: 12, weight: .semibold).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.primaryInk)
            .frame(minHeight: 36)
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityIdentifier("detail.place")
    }

    private var mapsURL: URL? {
        let q = (current.locationName ?? headword).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let lat = current.lat, let lng = current.lng { return URL(string: "https://maps.apple.com/?ll=\(lat),\(lng)&q=\(q)") }
        if let name = current.locationName, !name.isEmpty { return URL(string: "https://maps.apple.com/?q=\(q)") }
        return nil
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 13, weight: .semibold)
            .foregroundStyle(Theme.foreground.opacity(0.8))
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(Theme.secondary, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - Sections

    private var meaningCard: some View {
        WordMeaningCard(meaning: word?.meaningJa ?? "")
    }

    // MARK: - Section routing (card-sections.ts: draw only what has content)

    /// The word's language, corrected from its headword when the stored one is wrong (I4: "lamp" saved
    /// as a Mandarin word showed measure words and a Taiwan note).
    private var learningLang: String { LanguageRules.resolveWordLanguage(stored: word?.language, headword: headword) }
    /// 「例文」: the main example and every other usage pattern's example (`ExampleItem.all`).
    private var examples: [ExampleItem] {
        ExampleItem.all(sentence: word?.exampleSentence, translation: word?.exampleTranslation, extras: extras, target: learningLang)
    }
    private var chunks: [UsageChunk] { refinedChunks(extras?.usageChunks ?? []) }
    private var measures: [MeasureWord] { (extras?.measureWords ?? []).filter { !$0.word.isEmpty } }
    private var taiwanText: String { nonEmpty([extras?.taiwanNote, extras?.trivia, extras?.usageNote]) }
    private var forms: [(String, String)] {
        guard let f = extras?.forms else { return [] }
        return [(L("複数形"), f.plural), (L("過去形"), f.past), (L("過去分詞"), f.pastParticiple), (L("-ing 形"), f.ing),
                (L("三単現"), f.third), (L("比較級"), f.comparative), (L("最上級"), f.superlative)].filter { !$1.isEmpty }
    }
    private var kanjiParts: [KanjiPart] { (extras?.kanjiBreakdown ?? []).filter { !$0.kanji.trimmingCharacters(in: .whitespaces).isEmpty } }
    private var conjugations: [ConjugationRow] { (extras?.conjugation ?? []).filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty } }
    private var counterWords: [CounterWord] { (extras?.counters ?? []).filter { !$0.word.isEmpty } }
    private var phrasals: [PhrasalVerb] { (extras?.phrasalVerbs ?? []).filter { !$0.phrase.isEmpty } }

    private func nonEmpty(_ parts: [String?]) -> String {
        parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private func hasContent(_ s: CardSection) -> Bool {
        switch s {
        case .meaning: !(word?.meaningJa ?? "").isEmpty
        case .example: !examples.isEmpty
        // Gone from the word page (owner 2026-10-15, `CardSection.isRemoved`), whatever an older card still holds.
        case .examplesExtra, .webImages, .pronunciationTips, .mnemonic, .etymology: false
        case .usageChunks: !chunks.isEmpty
        case .measureWords: !measures.isEmpty
        case .relatedWords: !(extras?.allRelated.isEmpty ?? true) || !(extras?.synonymDiff ?? "").isEmpty
        case .taiwanNote: learningLang == "zh-TW" && !taiwanText.isEmpty
        case .realUsage: !headword.isEmpty
        case .forms: !forms.isEmpty
        case .countability: extras?.countability != nil
        case .phrasalVerbs: !phrasals.isEmpty
        case .stress: !(extras?.stress?.syllables.isEmpty ?? true)
        case .cultureNote: !(extras?.cultureNote ?? "").isEmpty
        case .kanjiBreakdown: !kanjiParts.isEmpty
        case .conjugation: !conjugations.isEmpty
        case .politeness: !(extras?.politeness ?? "").isEmpty
        case .counters: !counterWords.isEmpty
        case .pitchAccent: !(extras?.pitchAccent ?? "").isEmpty
        case .wordOrigin: !(extras?.wordOrigin ?? "").isEmpty
        case .japanNote: !(extras?.japanNote ?? "").isEmpty
        }
    }

    @ViewBuilder
    private func sectionView(_ s: CardSection) -> some View {
        sectionBody(s)
            // 「作り直す」 is Pro on the server (`runSectionRegen` refuses free accounts with 「項目の再生成は Pro 限定です」),
            // so like the web (`WordCard` canRegen = isPro) the button is only offered when the SERVER counts this
            // account as Pro. A StoreKit-only Pro is not enough until the server checks Apple purchases, and
            // while in-app purchase is unavailable web Pro does not unlock it either (`PlanStore.inAppPurchaseAvailable`).
            // Not for a catch still being saved (no word on the server yet).
            // Also for the developer (an admin account: the server lets admins write sections again too), and only for
            // the sections the server can write again (`CardSection.isRegenerable`; owner 2026-10-16: 「全部の項目を
            // 作り直せるように」).
            .environment(\.sectionRefresh, !s.isRegenerable || !(plan.serverGrantsPro || AdminAccess.shared.isAdmin)
                         || current.wordId.isEmpty
                         ? nil : SectionRefresh(running: refreshing.contains(s)) { regenerate(s) })
    }

    /// Web 「作り直す」 (regenerateCardSection): this one item is written again at the learner's level.
    private func regenerate(_ s: CardSection) {
        guard !refreshing.contains(s) else { return }
        guard AIConsent.shared.isGranted else { askAIConsent = true; return }
        Haptics.impact(.light)
        let wordId = current.wordId
        withAnimation(.snappy) { _ = refreshing.insert(s) }
        Task {
            let ok = await dex.fillSection(wordId: wordId, section: s.rawValue, onlyIfEmpty: false)
            await dex.reload(stickerId: current.id)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { _ = refreshing.remove(s) }
            if ok { Haptics.success() } else { Haptics.warning(); showToast(L("作り直せませんでした。少し待ってからお試しください")) }
        }
    }

    @ViewBuilder
    private func sectionBody(_ s: CardSection) -> some View {
        switch s {
        case .meaning: meaningCard
        case .example: WordExamplesCard(examples: examples, headword: headword)
        case .examplesExtra, .webImages, .pronunciationTips, .mnemonic, .etymology: EmptyView()
        case .usageChunks: chunkCard(chunks)
        case .measureWords: measureCard(measures)
        case .relatedWords: relatedCard(extras?.allRelated ?? [])
        // 台湾メモ: no line under its sentences (owner 2026-10-15); the other prose sections keep theirs.
        case .taiwanNote: textCard(s.title, icon: s.icon, taiwanText, ruled: false)
        case .realUsage: realUsageCard
        case .forms: formsCard
        case .countability: countabilityCard
        case .phrasalVerbs: phrasalCard
        case .stress: stressCard
        case .cultureNote: textCard(s.title, icon: s.icon, extras?.cultureNote ?? "")
        case .kanjiBreakdown: kanjiCard
        case .conjugation: conjugationCard
        case .politeness: textCard(s.title, icon: s.icon, extras?.politeness ?? "")
        case .counters: countersCard
        case .pitchAccent: textCard(s.title, icon: s.icon, extras?.pitchAccent ?? "")
        case .wordOrigin: textCard(s.title, icon: s.icon, extras?.wordOrigin ?? "")
        case .japanNote: textCard(s.title, icon: s.icon, extras?.japanNote ?? "")
        }
    }

    /// extras.ts MAX_CHUNK_CHARS (8) / MAX_CHUNK_WORDS_EN (4 words, 28 chars) / MAX_CHUNK_CHARS_JA (12).
    private func tooLong(_ c: UsageChunk) -> Bool {
        switch learningLang {
        case "en":
            let words = c.parts.map(\.text).joined(separator: " ").split(separator: " ")
            return words.count > 4 || words.joined(separator: " ").count > 28
        case "ja": return c.text.count > 12
        default: return c.text.count > 8
        }
    }

    /// refineUsageChunks (extras.ts): drop measure-word patterns, sentences, too-long chunks, headword-only, duplicates; keep 5.
    private func refinedChunks(_ raw: [UsageChunk]) -> [UsageChunk] {
        let mwords = Set(measures.map(\.word))
        var seen = Set<String>()
        var out: [UsageChunk] = []
        for r in raw where !r.parts.isEmpty {
            // docs/chunk-rules.md: one word is one block (C7), a Mandarin adjective gets its degree word (C8).
            let c = UsageChunk(parts: ChunkRules.tidy(r.parts, headword: headword, target: learningLang, reader: L10n.lang), ja: r.ja)
            guard ChunkRules.isPattern(original: r.parts, tidied: c.parts) else { continue }
            let text = c.text
            if tooLong(r) || text == headword { continue }
            // R20: a chunk that does not contain the word it teaches ("很+甜" for 芒果) is not shown.
            if !LanguageRules.mentionsHeadword(c.parts.map(\.text).joined(separator: " "), headword: headword, target: learningLang) { continue }
            // C15: a pattern with a word cut out (嘴邊肉＋切) or a translation that copies the word (嘴邊肉をする).
            if ChunkRules.isBroken(c, headword: headword, target: learningLang) { continue }
            if text.contains(where: { "。！？!?".contains($0) }) { continue }
            if c.parts.contains(where: { $0.pos.uppercased() == "M" || mwords.contains($0.text) }) { continue }
            if mwords.contains(where: { !$0.isEmpty && text.contains($0) }) { continue }
            if !seen.insert(text).inserted { continue }
            out.append(c)
            if out.count == 5 { break }
        }
        return out
    }

    // MARK: - Headword edit & report

    private func saveHeadword() {
        let next = headDraft
        isSavingHead = true
        Task {
            defer { isSavingHead = false }
            do {
                try await dex.setHeadword(current, to: next)
                // Today's review round must not keep the old word as this card's answer (貓眼 → 門, 2026-10-15), even
                // when the reload after the change failed and the dex still holds the old sticker.
                let head = next.trimmingCharacters(in: .whitespacesAndNewlines)
                review?.headwordChanged(stickerId: current.id, to: head, reloaded: dex.sticker(id: current.id))
                Haptics.success()
                showToast(L("単語を直しました"))
            } catch {
                Haptics.warning()
                showToast((error as? LocalizedError)?.errorDescription ?? L("直せませんでした"))
            }
        }
    }

    /// Web AutoFillSections: visible sections that are still empty are written by the server in
    /// parallel (free, `only_if_empty`), then revealed together — never one by one popping in.
    private func autoFill() async {
        // A run cancelled midway (another word / language) returns without clearing: no skeletons left behind.
        filling = []
        // A catch still being saved has no word on the server yet: this runs again once it has (keyed on its id).
        guard !current.wordId.isEmpty else { return }
        // First this reader's own explanation (written in their display language); while it is being
        // written, the empty sections show as filling instead of another language's notes.
        let target = word?.language ?? NativeAPI.targetLanguage
        await dex.loadExplanation(wordId: current.wordId, target: target)
        // A whole explanation is being written for this reader: its sections arrive together.
        guard !Task.isCancelled, !dex.generatingWords.contains(current.wordId) else { return }
        // Writing the missing sections uses the AI: not without the consent (they stay empty, never "filling").
        guard AIConsent.shared.isGranted else { return }
        // 「例文」 shows the examples the card came with (the main one and `examples_extra`); more are never fetched here.
        let missing = visibleSections.filter { !$0.isExternal && !hasContent($0) && Self.wantsAutoFill($0, extras: extras) }
        guard !missing.isEmpty else { return }
        let wordId = current.wordId
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) { filling = Set(missing) }
        await withTaskGroup(of: Void.self) { group in
            for section in missing {
                group.addTask { @MainActor in
                    _ = await dex.fillSection(wordId: wordId, section: section.rawValue, onlyIfEmpty: true)
                }
            }
        }
        await dex.reload(stickerId: current.id)
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { filling = [] }
    }

    /// Whether an empty visible section is filled in by the server (`regenerateCardSection` only_if_empty): only the
    /// sections still on the page.
    static func wantsAutoFill(_ s: CardSection, extras: WordExtras?) -> Bool {
        // Off the page, never asked for (their absence is not something to fill): 発音のコツ・覚え方・ネットの画像 and
        // 語源・部首 (owner 2026-10-15; the server stops writing them), and the extra examples — 「例文」 shows those the card
        // came with, and nothing ever fetches more on its own (owner 2026-10-15).
        !s.isRemoved
    }

    /// Web reportAndFixSection (item = auto): the AI finds the wrong item among what is on screen.
    /// What can be reported: the reading, the part of speech and every section shown with content.
    private var reportItems: [String] {
        ["pronunciation", "pos"] + visibleSections.filter { !$0.isExternal && hasContent($0) }.map(\.rawValue)
    }

    private func reportAndFix(item: String = "auto") {
        guard AIConsent.shared.isGranted else { askAIConsent = true; return }
        let note = reportNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordId = current.wordId
        let candidates = reportItems
        isFixing = true
        Task {
            defer { isFixing = false }
            do {
                let r = try await dex.reportAndFix(wordId: wordId, item: item, candidates: candidates, note: note)
                await dex.reload(stickerId: current.id)
                Haptics.success()
                // web ReportButton: fixed / the AI found nothing (kept as a report) / recorded to be checked.
                let done = r.item ?? (item == "auto" ? nil : item)
                if r.fixed, let done {
                    showToast(L("「\(Self.itemTitle(done))」を直しました"))
                } else if r.queued == true {
                    // Fixed in the background once a second AI agrees; the page shows it the next time it opens.
                    showToast(L("報告を受け付けました。確認して自動で直します（直ったら次に開いたときに反映されます）"))
                } else if r.aiFailed == true {
                    showToast(L("報告を受け付けました。AIが応答せず、自動では直せませんでした"))
                } else if item == "auto" && done == nil {
                    showToast(L("AIは間違いを見つけられませんでした。報告として残しました"))
                } else {
                    showToast(L("報告を受け付けました。確かめてから直します"))
                }
            } catch {
                Haptics.warning()
                if let api = error as? APIError, case .server(let code, _) = api, code >= 500 {
                    // The server's AI did not answer (2026-10-14: the AI provider refused every call, and the
                    // learner saw only 「サーバーエラー（500）」).
                    showToast(L("AIが応答せず、直せませんでした。時間をおいてもう一度お試しください"))
                } else {
                    showToast((error as? LocalizedError)?.errorDescription ?? L("直せませんでした"))
                }
            }
        }
    }

    private static func itemTitle(_ item: String?) -> String {
        switch item {
        case "pronunciation": L("発音・読み")
        case "pos": L("品詞")
        case let key?: CardSection(rawValue: key)?.title ?? key
        default: L("項目")
        }
    }


    private func addSelfie(_ image: UIImage) async {
        isAddingSelfie = true
        defer { isAddingSelfie = false }
        do {
            try await dex.addSelfie(to: current, image: image)
            Haptics.success()
        } catch {
            Haptics.warning()
            showToast(L("保存できませんでした。もう一度お試しください。"))
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeOut(duration: 0.25)) { if toast == text { toast = nil } }
        }
    }

    private func highlighted(_ sentence: String) -> AttributedString {
        WordHighlight.marked(sentence, headword: headword)
    }

    private func chunkCard(_ chunks: [UsageChunk]) -> some View {
        let shown = Array(chunks.prefix(5))
        let kinds = Set(shown.flatMap { $0.parts.map { ChunkKind(pos: $0.pos) } })
        return SectionCard(title: L("使い方チャンク"), icon: "square.grid.2x2") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, chunk in
                    ChunkLineView(chunk: chunk, headword: headword, target: learningLang)
                        .padding(.vertical, 14)
                    Divider().overlay(Theme.border)
                }
                // The legend wraps between its items, never inside one (owner 2026-10-15: under the English UI
                // "Stative verb (adjective)" and "Particle / preposition" broke into cramped lines).
                FlowRow(spacing: 12) {
                    ForEach(ChunkKind.allCases.filter { kinds.contains($0) }, id: \.self) { k in
                        HStack(spacing: 5) {
                            Circle().fill(k.ink).frame(width: 8, height: 8)
                            Text(k.label(for: learningLang)).scaledFont(size: 13).foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                        .fixedSize()
                        .frame(minWidth: 56, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 12)
                // No hint under the legend about the dotted words (owner 2026-10-16): the dotted line says it.
            }
        }
    }

    private func measureCard(_ items: [MeasureWord]) -> some View {
        SectionCard(title: L("量詞"), icon: "number") {
            VStack(spacing: 10) {
                ForEach(items, id: \.word) { m in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            // Shown as it is said: 一 + the measure word (web: 「一份」).
                            let said = m.word.hasPrefix("一") ? m.word : "一" + m.word  // l10n-ignore (target word)
                            let reading = m.word.hasPrefix("一") ? m.zhuyin : m.zhuyin.map { "ㄧ " + $0 }  // l10n-ignore (target word)
                            ZhuyinWordView(headword: said, zhuyin: reading, size: 32, weight: .heavy, language: "zh-TW")
                            if let n = m.note, !n.isEmpty {
                                Text(n).scaledFont(size: 15).foregroundStyle(Theme.muted).lineSpacing(4)
                            }
                        }
                        Spacer(minLength: 0)
                        PronounceCircle(text: m.word.hasPrefix("一") ? m.word : "一" + m.word, size: 50)  // l10n-ignore (target word)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(Theme.secondary, in: .rect(cornerRadius: 26, style: .continuous))
                }
            }
        }
    }

    private func relatedCard(_ items: [RelatedWord]) -> some View {
        let groups: [(String, String)] = [("syn", L("類義語")), ("ant", L("反義語")), ("rel", L("関連語"))]
        let diff = (extras?.synonymDiff ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return SectionCard(title: L("類義語・反義語・関連語"), icon: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.0) { kind, label in
                    let rows = items.filter { $0.kind == kind }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(label).scaledFont(size: 14).foregroundStyle(Theme.muted)
                            ForEach(rows, id: \.word) { r in
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        relatedPill(r, kind: kind)
                                        if !r.note.isEmpty {
                                            Text(r.note).scaledFont(size: 15).foregroundStyle(Theme.muted).lineSpacing(4)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    PronounceCircle(text: r.word, size: 50)
                                }
                            }
                        }
                    }
                }
                // How the near-synonyms differ: it made the section count as filled but was never drawn.
                if !diff.isEmpty {
                    SentenceRows(text: diff, color: Theme.muted)
                }
            }
        }
    }

    /// A word pill with its zhuyin beside each character: plain for synonyms, violet for related words,
    /// rose for antonyms (web RelatedWords).
    private func relatedPill(_ r: RelatedWord, kind: String) -> some View {
        let tint: Color = switch kind {
        case "rel": Color(hex: 0x3B3FB6)
        case "ant": Color(hex: 0xC2410C)
        default: Theme.foreground
        }
        let fill: Color = switch kind {
        case "rel": Color(hex: 0xE4E6FB)
        case "ant": Color(hex: 0xFDE7DC)
        default: Theme.card
        }
        return ZhuyinWordView(headword: r.word, zhuyin: r.reading.isEmpty ? nil : r.reading, size: 30, weight: .bold,
                              color: tint, readingColor: tint.opacity(0.6), language: learningLang)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(fill, in: Capsule())
            .overlay(Capsule().stroke(kind == "syn" ? Theme.border : .clear, lineWidth: 1.2))
    }

    // MARK: - English sections

    private var formsCard: some View {
        SectionCard(title: CardSection.forms.title, icon: CardSection.forms.icon) {
            VStack(spacing: 0) {
                ForEach(Array(forms.enumerated()), id: \.offset) { i, row in
                    HStack(spacing: 12) {
                        Text(row.0).scaledFont(size: 14).foregroundStyle(Theme.muted)
                            .frame(width: 118, alignment: .leading)
                        Text(row.1).scaledFont(size: 20, weight: .semibold).foregroundStyle(Theme.foreground)
                        Spacer(minLength: 0)
                        PronounceCircle(text: row.1, size: 36)
                    }
                    .padding(.vertical, 10)
                    if i < forms.count - 1 { Divider().overlay(Theme.border) }
                }
            }
        }
    }

    private var countabilityCard: some View {
        let c = extras?.countability
        let kind: String = switch c?.kind ?? "" {
        case "uncountable": L("数えられない（不可算）")
        case "both": L("意味によって両方")
        default: L("数えられる（可算）")
        }
        return SectionCard(title: CardSection.countability.title, icon: CardSection.countability.icon) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(kind)
                        .scaledFont(size: 15, weight: .semibold).foregroundStyle(Theme.primaryInk)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.primary.opacity(0.1), in: Capsule())
                    if let a = c?.article.trimmingCharacters(in: .whitespaces), !a.isEmpty {
                        // The server sends either the bare article ("an") or the whole phrase ("a coffee").
                        let phrase = a.localizedCaseInsensitiveContains(headword) ? a : "\(a) \(headword)"
                        Text(phrase).scaledFont(size: 20, weight: .semibold).foregroundStyle(Theme.foreground)
                    }
                }
                if let n = c?.note, !n.isEmpty {
                    SentenceRows(text: n, color: Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var phrasalCard: some View {
        SectionCard(title: CardSection.phrasalVerbs.title, icon: CardSection.phrasalVerbs.icon) {
            VStack(spacing: 10) {
                ForEach(phrasals, id: \.phrase) { p in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.phrase).scaledFont(size: 20, weight: .bold).foregroundStyle(Theme.foreground)
                            if !p.meaning.isEmpty { Text(p.meaning).scaledFont(size: 15).foregroundStyle(Theme.muted) }
                            if !p.example.isEmpty, p.example.isIn(target: "en") {
                                Text(p.example).scaledFont(size: 15).italic().foregroundStyle(Theme.foreground.opacity(0.85))
                            }
                        }
                        Spacer(minLength: 0)
                        PronounceCircle(text: p.example.isEmpty ? p.phrase : p.example, size: 40)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.secondary, in: .rect(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }

    /// The syllables with the stressed one large and in colour (PREsent / preSENT).
    private var stressCard: some View {
        let st = extras?.stress
        let sy = st?.syllables ?? []
        return SectionCard(title: CardSection.stress.title, icon: CardSection.stress.icon) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    ForEach(Array(sy.enumerated()), id: \.offset) { i, part in
                        let primary = i == st?.primary
                        let secondary = i == st?.secondary
                        Text(primary ? part.uppercased() : part)
                            .scaledFont(size: primary ? 30 : 22, weight: primary ? .heavy : (secondary ? .semibold : .regular))
                            .foregroundStyle(primary ? Theme.primaryInk : Theme.foreground.opacity(secondary ? 0.85 : 0.6))
                        if i < sy.count - 1 { Text("·").scaledFont(size: 20).foregroundStyle(Theme.muted) }
                    }
                    Spacer(minLength: 0)
                    PronounceCircle(text: headword, size: 40)
                }
                if let n = st?.note, !n.isEmpty {
                    SentenceRows(text: n, color: Theme.muted)
                }
            }
        }
    }

    // MARK: - Japanese sections

    /// Each kanji large, with its meaning and on / kun readings (生活 = せい / 生まれる = う / 生ビール = なま).
    private var kanjiCard: some View {
        SectionCard(title: CardSection.kanjiBreakdown.title, icon: CardSection.kanjiBreakdown.icon) {
            VStack(spacing: 10) {
                ForEach(Array(kanjiParts.enumerated()), id: \.offset) { _, k in
                    HStack(alignment: .center, spacing: 16) {
                        Text(k.kanji)
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(Theme.foreground)
                            .frame(width: 64, height: 64)
                            .background(Theme.card, in: .rect(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border))
                        VStack(alignment: .leading, spacing: 5) {
                            if !k.meaning.isEmpty {
                                Text(k.meaning).scaledFont(size: 17, weight: .semibold).foregroundStyle(Theme.foreground)
                            }
                            if !k.on.isEmpty { readingRow(L("音読み"), k.on) }
                            if !k.kun.isEmpty { readingRow(L("訓読み"), k.kun) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Theme.secondary, in: .rect(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }

    private func readingRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).scaledFont(size: 12, weight: .semibold).foregroundStyle(Theme.muted)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Theme.card, in: Capsule())
            Text(value).scaledFont(size: 15).foregroundStyle(Theme.foreground.opacity(0.85))
        }
    }

    private var conjugationCard: some View {
        SectionCard(title: CardSection.conjugation.title, icon: CardSection.conjugation.icon) {
            VStack(spacing: 0) {
                ForEach(Array(conjugations.enumerated()), id: \.offset) { i, row in
                    HStack(spacing: 12) {
                        Text(row.form).scaledFont(size: 14).foregroundStyle(Theme.muted)
                            .frame(width: 118, alignment: .leading)
                        Text(row.text).scaledFont(size: 20, weight: .semibold).foregroundStyle(Theme.foreground)
                        Spacer(minLength: 0)
                        PronounceCircle(text: row.text, size: 36)
                    }
                    .padding(.vertical, 10)
                    if i < conjugations.count - 1 { Divider().overlay(Theme.border) }
                }
            }
        }
    }

    private var countersCard: some View {
        SectionCard(title: CardSection.counters.title, icon: CardSection.counters.icon) {
            VStack(spacing: 10) {
                ForEach(counterWords, id: \.word) { c in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            ZhuyinWordView(headword: c.word, zhuyin: c.reading, size: 32, weight: .heavy, language: "ja")
                            if !c.note.isEmpty {
                                Text(c.note).scaledFont(size: 15).foregroundStyle(Theme.muted).lineSpacing(4)
                            }
                        }
                        Spacer(minLength: 0)
                        PronounceCircle(text: c.word, size: 50)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(Theme.secondary, in: .rect(cornerRadius: 26, style: .continuous))
                }
            }
        }
    }

    /// The prose sections: one sentence per row with a thin line under each, instead of one block of prose (owner
    /// 2026-10-14: 「読みやすいように文の下に線に書いて」). `ruled` false: the rows without the lines and with the tight
    /// spacing the prose had before the lines came (台湾メモ, owner 2026-10-15: without its lines the ruled rows' gaps
    /// read as 「行間が広すぎる」).
    private func textCard(_ title: String, icon: String, _ body: String, ruled: Bool = true) -> some View {
        SectionCard(title: title, icon: icon) {
            SentenceRows(text: body, ruled: ruled)
        }
    }

    /// Prose cut into sentences (`Sentences.split`, Utilities/Sentences.swift).
    static func sentences(_ text: String) -> [String] { Sentences.split(text) }

    /// The language whose sites the links open. Old rows have no `language`: then the headword's script
    /// decides (kana → ja, Han → zh-TW, Latin → en), so a Mandarin word never opens English dictionaries
    /// just because the learner now studies English. A Han-only headword is Japanese only for a Japanese
    /// learner (kanji words fit both); a headword with no telling script falls back to the learning language.
    private var linkLanguage: String {
        if let stored = word?.language?.trimmingCharacters(in: .whitespaces), !stored.isEmpty { return stored }
        let c = LanguageRules.counts(headword)
        if c.kana > 0 { return "ja" }
        if c.han > 0 { return NativeAPI.targetLanguage == "ja" ? "ja" : "zh-TW" }
        if c.latin > 0 { return "en" }
        return NativeAPI.targetLanguage
    }

    /// real-usage-links.ts: where native speakers of the learning language actually use the word.
    private var realUsageLinks: [(emoji: String, label: String, url: String)] {
        let q = headword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? headword
        let path = headword.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? headword
        switch linkLanguage {
        case "en":
            return [
                ("🎬", L("YouTubeで聞く"), "https://www.youtube.com/results?search_query=\(q)&sp=EgIQAQ%253D%253D&gl=US&hl=en"),
                ("🗣️", L("YouGlishで発音例"), "https://youglish.com/pronounce/\(path)/english/us"),
                ("💬", L("Redditで見る"), "https://www.reddit.com/search/?q=\(q)"),
                ("📷", L("Instagram で見る"), "https://www.instagram.com/explore/tags/\(path)/"),
                ("📰", L("英語のサイトで検索"), "https://www.google.com/search?q=\(q)&hl=en&gl=US&cr=countryUS&lr=lang_en"),
                ("📖", "Merriam-Webster", "https://www.merriam-webster.com/dictionary/\(path)"),  // l10n-ignore (name)
            ]
        case "ja":
            return [
                ("🎬", L("YouTubeで聞く"), "https://www.youtube.com/results?search_query=\(q)&sp=EgIQAQ%253D%253D&gl=JP&hl=ja"),
                ("🗣️", L("YouGlishで発音例"), "https://youglish.com/pronounce/\(path)/japanese"),
                ("💬", L("Xで見る"), "https://x.com/search?q=\(q)&lang=ja"),
                ("🙋", L("Yahoo!知恵袋で見る"), "https://chiebukuro.yahoo.co.jp/search?p=\(q)"),
                ("📰", L("日本のサイトで検索"), "https://www.google.com/search?q=\(q)&hl=ja&gl=JP&cr=countryJP&lr=lang_ja"),
                ("📖", L("Weblio辞書"), "https://www.weblio.jp/content/\(path)"),
                ("📚", L("コトバンク"), "https://kotobank.jp/search?q=\(q)"),
                ("🔎", "Jisho.org", "https://jisho.org/search/\(path)"),
            ]
        default:
            return [
                ("🎬", L("YouTubeで聞く"), "https://www.youtube.com/results?search_query=\(q)&sp=EgIQAQ%253D%253D&gl=TW&hl=zh-TW"),
                ("🗣️", L("YouGlishで発音例"), "https://youglish.com/pronounce/\(path)/chinese/tw"),
                ("💬", L("Dcardで見る"), "https://www.dcard.tw/search?query=\(q)"),
                ("🧵", L("Threads で見る"), "https://www.threads.com/search?q=\(q)"),
                ("📰", L("台湾のサイトで検索"), "https://www.google.com/search?q=\(q)&hl=zh-TW&gl=TW&cr=countryTW&lr=lang_zh-TW"),
                ("📖", L("教育部國語辭典簡編本"), "https://dict.concised.moe.edu.tw/search.jsp?word=\(q)"),
            ]
        }
    }

    private var realUsageCard: some View {
        SectionCard(title: L("実際の使われ方"), icon: "film") {
            VStack(spacing: 10) {
                ForEach(realUsageLinks, id: \.label) { link in
                    Button {
                        if let url = URL(string: link.url) { openURL(url) }
                    } label: {
                        HStack(spacing: 14) {
                            Text(link.emoji).scaledFont(size: 20)
                            Text(link.label).scaledFont(size: 17, weight: .semibold).foregroundStyle(Theme.foreground)
                            Spacer()
                            Image(systemName: "arrow.up.right.square").scaledFont(size: 16).foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .background(Theme.secondary, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            }
        }
    }

    /// 「保存待ち」: why the save failed (the real kind of failure, `SaveFailure`), that the word is kept, and 「もう一度保存」.
    private var unsavedBanner: some View {
        let running = dex.isRetrying(current.id)
        let reason = L10n.readerSafe(dex.unsavedReason(current.id) ?? "", fallback: "")
        return VStack(alignment: .leading, spacing: 8) {
            Label(L("まだ保存できていません"), systemImage: "icloud.and.arrow.up")
                .scaledFont(size: 16, weight: .bold)
                .foregroundStyle(Theme.foreground)
            if !reason.isEmpty {
                Text(reason)
                    .scaledFont(size: 14)
                    .foregroundStyle(Theme.foreground.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L("この単語は図鑑に残してあります。つながると自動でもう一度保存します。"))
                .scaledFont(size: 13)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                retrySave()
            } label: {
                HStack(spacing: 8) {
                    if running { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: "arrow.clockwise") }
                    Text(running ? L("保存しています…") : L("もう一度保存"))
                }
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.96))
            .disabled(running)
            .accessibilityIdentifier("detail.retrySave")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.6), in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.primary.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.unsaved")
    }

    /// 「もう一度保存」: the same save again (`DexStore.retryUnsaved`); done, the page turns into the saved word in place.
    private func retrySave() {
        let id = current.id
        Task {
            do {
                try await dex.retryUnsaved(stickerId: id)
                dex.refreshPending()
                Haptics.success()
                showToast(L("図鑑に保存しました"))
            } catch is CancellationError {
                // Already being saved (the automatic retry).
            } catch {
                Haptics.warning()
                showToast(L("まだ保存できていません：\(SaveFailure.message(for: error))"))
            }
        }
    }

    /// The bottom of the page: 報告 beside 削除 (as on the web). The 「〇日前にキャッチしました」 line is gone, and
    /// 写真を替える (owner 2026-10-11) and 自撮りを撮る (owner 2026-10-14) moved into the long-press photo sheet.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isAddingSelfie {
                Label(L("保存しています…"), systemImage: "camera")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Theme.muted)
            }
            if isReplacing {
                Label(L("替えています…"), systemImage: "photo.badge.arrow.down")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 10) {
                Spacer()
                reportMenu
                Button { confirmDelete = true } label: {
                    Label(L("削除"), systemImage: "trash")
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(Theme.destructive)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 48)
                        .background(Theme.destructive.opacity(0.08), in: Capsule())
                        .overlay(Capsule().stroke(Theme.destructive.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                // A 「保存待ち」 word can be thrown away (it was never saved); one being saved right now cannot.
                .disabled(isProvisional && !isUnsaved)
            }
        }
        .padding(.top, 6)
    }

    /// 写真を替える (from the long-press photo sheet): upload + web replaceStickerPhoto; the new photo is cut out too.
    private func replacePhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = await ImageTools.downsampledInBackground(data) else {
            showToast(L("写真を読み込めませんでした。"))
            return
        }
        isReplacing = true
        defer { isReplacing = false }
        do {
            try await dex.replacePhoto(current, with: img)
            Haptics.success()
            showToast(L("写真を替えました"))
            if let lifted = await CutoutService.liftSubject(from: img) {
                try? await dex.addCutout(to: current, image: lifted)
            }
        } catch {
            Haptics.warning()
            showToast((error as? LocalizedError)?.errorDescription ?? L("写真を替えられませんでした"))
        }
    }

}

/// A selfie's cut-out — its people and the thing they hold — made on this phone (`SelfieCutouts`, kept in the image
/// cache only). A cut-out the system emptied from the cache is made again.
struct SelfieCutoutImage: View {
    let path: String
    var onLoad: ((CGSize) -> Void)? = nil

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .task(id: path) {
            let key = SelfieCutouts.key(for: path)
            if let hit = ImageCache.shared.image(for: key) {
                image = hit
                onLoad?(hit.size)
                return
            }
            if let kept = await ImageCache.shared.cached(for: key) {
                withAnimation(.easeOut(duration: 0.25)) { image = kept }
                onLoad?(kept.size)
            } else {
                SelfieCutouts.shared.forget(path)
            }
        }
    }
}

/// The original photo, full screen (a tap on the word page's picture). The ✕, a tap, or a swipe down closes it.
struct OriginalPhotoViewer: View {
    let path: String?
    let url: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var drag: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .opacity(1 - Double(min(0.6, abs(drag) / 500)))
                .ignoresSafeArea()
            StickerImage(path: path, url: url, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: drag)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { v in drag = v.translation.height }
                        .onEnded { v in
                            if abs(v.translation.height) > 110 || abs(v.predictedEndTranslation.height) > 260 {
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = 0 }
                            }
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("元の写真"))
                .accessibilityAddTraits(.isImage)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .padding(.trailing, 16)
            .padding(.top, 8)
            .accessibilityLabel(L("閉じる"))
            .accessibilityIdentifier("detail.original.close")
        }
        .accessibilityAction(.escape) { dismiss() }
    }
}

/// The section's 「作り直す」 button (set by the word page; the links card has none).
struct SectionRefresh {
    var running: Bool
    var action: () -> Void
}

extension EnvironmentValues {
    @Entry var sectionRefresh: SectionRefresh? = nil
}

/// Explanatory prose, one sentence per row with a hairline under each (`Sentences.split`). Each row may break between
/// any two Japanese / Chinese characters (`Sentences.wrappable`), so a line fills the card's width instead of moving a
/// whole word down early. VoiceOver reads the sentence as written.
/// The line under each row is two device pixels (`hairline`): a one-pixel line (½ pt on an iPad) that fell between two
/// pixel rows was drawn as two faint half-pixels and vanished on the light card, so on the owner's iPad some sentences
/// of 台湾メモ had no line (2026-10-15). The spacing between the ruled sentences stays as it was.
struct SentenceRows: View {
    let text: String
    var size: CGFloat = 15
    var color: Color = Theme.foreground.opacity(0.9)
    /// The line under each sentence. 台湾メモ has none (owner 2026-10-15), and without the lines its rows sit as close
    /// as the prose block did before the lines came (`tightPadding`; owner 2026-10-15 evening: 「行間が広すぎる」 — the
    /// ruled rows' 10 pt above and below each sentence read as empty gaps once the lines were gone).
    var ruled: Bool = true
    @Environment(\.displayScale) private var displayScale

    /// Above and below each sentence: room for the line between ruled rows; next to nothing without the lines.
    static let ruledPadding: CGFloat = 10
    static let tightPadding: CGFloat = 2

    var body: some View {
        let lines = Sentences.split(text)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(Sentences.wrappable(line))
                    .scaledFont(size: size)
                    .foregroundStyle(color)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, ruled ? Self.ruledPadding : Self.tightPadding)
                    .overlay(alignment: .bottom) {
                        if ruled { Rectangle().fill(Theme.border).frame(height: Self.hairline(displayScale)) }
                    }
                    .accessibilityLabel(line)
                    .accessibilityIdentifier("sentence.row")
            }
        }
    }

    /// Two device pixels: at least one whole pixel is covered wherever the line lands (1 pt on an iPad, ⅔ pt on a
    /// 3× iPhone).
    static func hairline(_ scale: CGFloat) -> CGFloat { 2 / max(1, scale) }
}

/// White section card with a blue round icon and title (card-sections + section-icon.ts).
struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    @Environment(\.sectionRefresh) private var refresh

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.primary, in: Circle())
                Text(title).scaledFont(size: 19, weight: .bold).foregroundStyle(Theme.foreground)
                Spacer()
                if let refresh {
                    Button(action: refresh.action) {
                        // The button's mark crossfades while the section is being written (the reference video's
                        // label change).
                        Image(systemName: refresh.running ? "sparkles" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(refresh.running ? Theme.primary : Theme.muted.opacity(0.75))
                            .contentTransition(.symbolEffect(.replace))
                            .animation(.easeInOut(duration: 0.3), value: refresh.running)
                            .frame(width: 44, height: 44)
                    }
                    .disabled(refresh.running)
                    .accessibilityLabel(L("\(title)を作り直す"))
                    .accessibilityIdentifier("section.regenerate")
                }
            }
            // The old content breaks into dust, the new gathers back (`RegenDust`, owner 2026-10-16).
            content
                .regenDust(refresh?.running == true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

/// Chunk colors by grammatical role: noun blue, verb red, stative green, adverb gold.
enum ChunkKind: CaseIterable, Hashable {
    case noun, verb, stative, adverb, particle

    init(pos: String) {
        let p = pos.uppercased()
        if p.hasPrefix("ADV") || p == "D" { self = .adverb }
        // Japanese particles (を・に・が) and English prepositions / articles: the glue between the words.
        else if ["P", "PART", "PREP", "DET", "ART"].contains(p) || p.contains("助詞") || p.contains("前置") { self = .particle }  // l10n-ignore (matching server POS)
        else if p.hasPrefix("VS") || p == "A" || p == "C" || p.contains("形容") || p.contains("状態") { self = .stative }  // l10n-ignore (matching server POS)
        else if p.hasPrefix("V") || p.contains("動") { self = .verb }  // l10n-ignore (matching server POS)
        else { self = .noun }
    }

    var ink: Color {
        switch self {
        case .noun: Theme.primary
        case .verb: Color(hex: 0xE5484D)
        case .stative: Color(hex: 0x2FA84F)
        case .adverb: Color(hex: 0xA08A2E)
        case .particle: Color(hex: 0x7C8798)
        }
    }

    var label: String {
        switch self {
        case .noun: L("名詞")
        case .verb: L("動詞")
        case .stative: L("状態動詞(形容詞)")
        case .adverb: L("副詞")
        case .particle: L("助詞・前置詞")
        }
    }

    /// 「状態動詞」 is a Mandarin grammar term; English and Japanese call it an adjective.
    func label(for target: String) -> String {
        self == .stative && target != "zh-TW" ? L("形容詞") : label
    }
}

/// A section being written by the server: the card's frame with a soft moving sheen.
struct SectionSkeleton: View {
    let title: String
    let icon: String
    @State private var phase: CGFloat = -1
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        SectionCard(title: title, icon: icon) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach([0.92, 0.7, 0.8], id: \.self) { w in
                    RoundedRectangle(cornerRadius: 6).fill(Theme.secondary)
                        .frame(height: 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: w, y: 1, anchor: .leading)
                }
            }
            .overlay {
                GeometryReader { g in
                    LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.45)
                        .offset(x: phase * g.size.width * 1.4)
                }
                .mask(VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 6).frame(height: 14) }
                })
                .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(L("\(title)を作っています"))
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                phase = -1
                withAnimation(.easeInOut(duration: 1.2)) { phase = 1 }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }
}
