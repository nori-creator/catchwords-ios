import SwiftUI
import PhotosUI

/// Word detail (WordCard.tsx): a hero card, then one white card per section that has content.
struct WordDetailView: View {
    @Environment(DexStore.self) private var dex
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppRouter.self) private var router
    @Environment(PlanStore.self) private var plan
    let sticker: Sticker
    /// DEBUG preview: open scrolled to this section so the simulator frame shows it.
    var previewFocus: CardSection? = nil

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
    /// The original photo (or, from the selfie side, the selfie), full screen: the 「元の写真」 button on the picture.
    @State private var showingOriginal: Bool = false
    @State private var viewingSelfie: Bool = false
    @State private var pickingHero: Bool = false
    @State private var refreshing: Set<CardSection> = []
    @State private var editingCaption: Bool = false
    @State private var captionDraft: String = ""
    /// Sections being filled by the server right now (web AutoFillSections).
    @State private var filling: Set<CardSection> = []
    @State private var reporting: Bool = false
    @State private var reportNote: String = ""
    @State private var isFixing: Bool = false
    /// A report or 「作り直す」 without the AI consent: the consent sheet instead (nothing is sent).
    @State private var askAIConsent: Bool = false
    @State private var isReplacing: Bool = false
    /// Photos of this word from later encounters, paged in the hero by swiping (page 0 = the main picture).
    @State private var laterPhotos: [StickerPhoto] = []
    @State private var heroPage: Int = 0
    /// ネットの画像 (web WebImagesBody): the search result, the 「別の画像」 round, and the one being applied.
    @State private var webCandidates: [WebImageCandidate] = []
    @State private var webRound: Int = 0
    @State private var webLoading: Bool = false
    @State private var applyingWeb: String?
    @State private var confirmWeb: WebImageCandidate?
    @Environment(\.appReduceMotion) private var reduceMotion

    /// The word as the dex has it now. A page opened on a catch still being saved (owner 2026-10-11: 「キャッチしたての
    /// ときその単語の詳細に進めない」 — it now opens at once) becomes the saved word in place when the save is done.
    private var current: Sticker { dex.current(sticker.id) ?? sticker }
    /// Still being saved: no id on the server yet, so nothing here asks the server about it and the edits wait
    /// (「保存しています…」 in the top bar). A word without its word id yet waits the same way for its notes.
    private var isProvisional: Bool { DexStore.isProvisional(current.id) }
    private var word: Word? { current.word }
    private var extras: WordExtras? { word?.extras }
    private var headword: String { word?.headword ?? "" }

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
        .task(id: "\(headword)|\(webRound)|\(visibleSections.contains(.webImages))") { await loadWebImages() }
        .confirmationDialog(L("いまの写真を、この画像に差し替えますか？元には戻せません。"),
                            isPresented: confirmingWeb,
                            titleVisibility: .visible, presenting: confirmWeb) { c in
            Button(L("この画像にする")) { applyWeb(c) }
            Button(L("キャンセル"), role: .cancel) {}
        }
        .onAppear { prefs.use(learningLang) }
        .onChange(of: learningLang) { _, l in prefs.use(l) }
        .onAppear { applyHeroRole(animated: false) }
        .aiConsentSheet(isPresented: $askAIConsent)
        .sheet(isPresented: $pickingHero) {
            HeroPhotoPickerSheet(sticker: current, onPick: { role in
                try await dex.setHeroRole(current, role: role)
                applyHeroRole(animated: true)
            }, onReplace: { item in
                // 写真を替える sits at the bottom of this sheet now (owner 2026-10-11).
                Task { await replacePhoto(item) }
            }, onSelfie: current.hasOwnPhoto && SelfieCamera.isAvailable && !isProvisional ? { image in
                // 自撮りを撮る, under 写真を替える (owner 2026-10-14).
                await addSelfie(image)
            } : nil)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
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
                    ProgressView().controlSize(.mini)
                    Text(L("保存しています…"))
                }
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Theme.muted)
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
            let pos = word?.partOfSpeech.map(posLabel) ?? ""
            let register = extras?.resolvedRegister.map(registerLabel)
            if !pos.isEmpty || register != nil {
                FlowRow(spacing: 8) {
                    if !pos.isEmpty { chip(pos) }
                    if let register { chip(register) }
                }
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
                    Button(Self.itemTitle(item)) { reportAndFix(item: item) }
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

    // MARK: - Photo hero (flips to the selfie like a card)

    private var frontPath: String? {
        showCutout ? (current.cutoutImageUrl ?? current.objectImageUrl ?? current.placeholderImageUrl)
            : (current.objectImageUrl ?? current.cutoutImageUrl ?? current.placeholderImageUrl)
    }
    private var hasSelfie: Bool { current.selfieImageUrl != nil }

    /// The hero, plus the photos from later encounters to swipe through.
    private var photoHero: some View {
        heroFace
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { v in
                        guard !laterPhotos.isEmpty, !showSelfie,
                              abs(v.translation.width) > abs(v.translation.height) * 1.4 else { return }
                        let next = v.translation.width < -50 ? heroPage + 1 : v.translation.width > 50 ? heroPage - 1 : heroPage
                        let clamped = min(max(next, 0), laterPhotos.count)
                        guard clamped != heroPage else { return }
                        Haptics.selection()
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.86)) { heroPage = clamped }
                    }
            )
            .overlay(alignment: .bottom) {
                if !laterPhotos.isEmpty, !showSelfie {
                    HStack(spacing: 6) {
                        ForEach(0...laterPhotos.count, id: \.self) { i in
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
                guard !laterPhotos.isEmpty else { return }
                switch dir {
                case .increment: heroPage = min(heroPage + 1, laterPhotos.count)
                case .decrement: heroPage = max(heroPage - 1, 0)
                @unknown default: break
                }
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

    /// A later encounter's photo in the hero, with when and where it was taken.
    private func laterFace(_ p: StickerPhoto, number: Int) -> some View {
        Theme.surface2  // photo placeholder (was a fixed light grey, glaring in dark mode)
            .aspectRatio(0.8, contentMode: .fit)
            .overlay {
                AsyncImage(url: URL(string: p.url)) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() } else { ProgressView() }
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Text(L("\(number)回目"))
                        .scaledFont(size: 12, weight: .bold)
                    if let d = SupabaseDate.parse(p.takenAt) {
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
            .clipShape(.rect(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("\(number)回目に撮った写真"))
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    @ViewBuilder
    private var heroFace: some View {
        if heroPage > 0, let p = laterPhotos[safe: heroPage - 1] {
            laterFace(p, number: heroPage + 1).id(p.id)
        } else {
            mainFace
        }
    }

    /// The hero's shape: a cut-out's own width ÷ height (kept between a tall 0.8 and a wide 1.8, so neither a bottle
    /// nor a long bench makes the page odd), a photo the 4:5 card.
    private func heroRatio(isCut: Bool, path: String?) -> CGFloat {
        guard isCut else { return 0.8 }
        let known = cutoutRatio ?? path.flatMap { ImageCache.shared.image(for: $0) }.map { $0.size.width / max(1, $0.size.height) }
        return min(1.8, max(0.8, known ?? 1))
    }

    private var mainFace: some View {
        let back = showSelfie
        let path = back ? current.selfieImageUrl : frontPath
        let isCut = !back && showCutout && path == current.cutoutImageUrl
        // A cut-out stands on the page by itself — no grey box around it (owner 2026-10-11); a photo keeps its card.
        return (isCut ? Color.clear : Theme.surface2)
            .aspectRatio(heroRatio(isCut: isCut || (back && current.cutoutImageUrl != nil && showCutout), path: current.cutoutImageUrl),
                         contentMode: .fit)
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
                // Full screen: the original photo from the photo side, the selfie from the selfie side.
                if hasSelfie, back ? current.selfieImageUrl != nil : originalPath != nil {
                    Button {
                        Haptics.selection()
                        viewingSelfie = back
                        showingOriginal = true
                    } label: {
                        Label(back ? L("大きく見る") : L("元の写真"), systemImage: "arrow.up.left.and.arrow.down.right")
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
                    .accessibilityIdentifier("detail.viewOriginal")
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
                    viewingSelfie = false
                    showingOriginal = true
                }
            }
            .fullScreenCover(isPresented: $showingOriginal) {
                let shown = viewingSelfie ? current.selfieImageUrl : originalPath
                OriginalPhotoViewer(path: shown, url: dex.url(for: shown, preferThumb: false))
            }
            // 長押し: この単語をどの絵で見せるか選ぶ（Web HeroPhotoPicker）。 Not while the catch is still being saved.
            .onLongPressGesture(minimumDuration: 0.45) {
                guard !isProvisional else { return }
                Haptics.impact(.medium)
                pickingHero = true
            }
            .accessibilityAction(named: L("表示する写真を選ぶ")) { if !isProvisional { pickingHero = true } }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(back ? L("自撮り写真") : L("写真"))
            .accessibilityAction(named: L("元の写真を見る")) {
                if originalPath != nil { viewingSelfie = false; showingOriginal = true }
            }
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

    /// Half-turn with the image swapped at 90° so the selfie reads as the card's back side.
    private func flip() {
        guard hasSelfie else { return }
        Haptics.impact(.light)
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { showSelfie.toggle() }
            return
        }
        let target: Double = showSelfie ? 0 : 180
        withAnimation(.easeIn(duration: 0.16)) { flipAngle = 90 } completion: {
            showSelfie.toggle()
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
                        Text(cap).font(AppFont.hand(18)).foregroundStyle(Theme.foreground.opacity(0.9))
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

    private func registerLabel(_ r: Int) -> String {
        switch r {
        case ...(-2): L("話し言葉")
        case -1: L("やや話し言葉")
        case 0: L("中立")
        case 1: L("やや書き言葉")
        default: L("書き言葉")
        }
    }

    // MARK: - Sections

    private var meaningCard: some View {
        SectionCard(title: CardSection.meaning.title, icon: CardSection.meaning.icon) {
            Text(word?.meaningJa ?? "")
                .scaledFont(size: 26, weight: .medium)
                .foregroundStyle(Theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Section routing (card-sections.ts: draw only what has content)

    /// The word's language, corrected from its headword when the stored one is wrong (I4: "lamp" saved
    /// as a Mandarin word showed measure words and a Taiwan note).
    private var learningLang: String { LanguageRules.resolveWordLanguage(stored: word?.language, headword: headword) }
    private var exampleOK: Bool { let e = word?.exampleSentence ?? ""; return !e.isEmpty && e.isIn(target: learningLang) }
    private var extraExamples: [ExampleExtra] { (extras?.examplesExtra ?? []).filter { !$0.zh.isEmpty && $0.zh.isIn(target: learningLang) } }
    private var chunks: [UsageChunk] { refinedChunks(extras?.usageChunks ?? []) }
    private var measures: [MeasureWord] { (extras?.measureWords ?? []).filter { !$0.word.isEmpty } }
    private var pronunciationText: String { nonEmpty([extras?.pronunciationTips, extras?.studyTips]) }
    /// Radicals only for Mandarin; English adds the words built from the same parts.
    private var etymologyText: String {
        switch learningLang {
        case "zh-TW": return nonEmpty([extras?.etymology, extras?.radicals.map { $0.isEmpty ? "" : L("部首: \($0)") }])
        case "en":
            let rel = (extras?.etymologyRelatives ?? []).filter { !$0.word.isEmpty }
                .map { $0.note.isEmpty ? $0.word : "\($0.word) — \($0.note)" }.joined(separator: "\n")
            return nonEmpty([extras?.etymology, rel])
        default: return nonEmpty([extras?.etymology])
        }
    }
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
        case .example: exampleOK
        case .examplesExtra: !extraExamples.isEmpty
        case .usageChunks: !chunks.isEmpty
        case .measureWords: !measures.isEmpty
        case .relatedWords: !(extras?.allRelated.isEmpty ?? true) || !(extras?.synonymDiff ?? "").isEmpty
        case .pronunciationTips: !pronunciationText.isEmpty
        case .etymology: !etymologyText.isEmpty
        case .mnemonic: !(extras?.mnemonic ?? "").isEmpty
        case .taiwanNote: learningLang == "zh-TW" && !taiwanText.isEmpty
        case .realUsage: !headword.isEmpty
        case .webImages: !webCandidates.isEmpty
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
            .environment(\.sectionRefresh, s.isExternal || !plan.serverGrantsPro || current.wordId.isEmpty
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
        case .example: exampleCard(word?.exampleSentence ?? "", word?.exampleTranslation)
        case .examplesExtra: extraExamplesCard
        case .usageChunks: chunkCard(chunks)
        case .measureWords: measureCard(measures)
        case .relatedWords: relatedCard(extras?.allRelated ?? [])
        case .pronunciationTips: textCard(s.title, icon: s.icon, pronunciationText)
        case .etymology: textCard(s.title(for: learningLang), icon: s.icon, etymologyText)
        case .mnemonic: textCard(s.title, icon: s.icon, extras?.mnemonic ?? "")
        case .taiwanNote: textCard(s.title, icon: s.icon, taiwanText)
        case .realUsage: realUsageCard
        case .webImages: webImagesCard
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

    private var extraExamplesCard: some View {
        SectionCard(title: CardSection.examplesExtra.title, icon: CardSection.examplesExtra.icon) {
            VStack(spacing: 10) {
                ForEach(extraExamples, id: \.zh) { ex in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            if !ex.scene.isEmpty {
                                Text(ex.scene)
                                    .scaledFont(size: 12, weight: .semibold)
                                    .foregroundStyle(Theme.primaryInk)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Theme.primary.opacity(0.1), in: Capsule())
                            }
                            Text(highlighted(ex.zh)).scaledFont(size: 18).lineSpacing(7)
                            if !ex.ja.isEmpty {
                                Text(ex.ja).scaledFont(size: 14).foregroundStyle(Theme.muted).lineSpacing(5)
                            }
                        }
                        Spacer(minLength: 0)
                        PronounceCircle(text: ex.zh, size: 40)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.secondary, in: .rect(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }

    // MARK: - Headword edit & report

    private func saveHeadword() {
        let next = headDraft
        isSavingHead = true
        Task {
            defer { isSavingHead = false }
            do {
                try await dex.setHeadword(current, to: next)
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
        let missing = visibleSections.filter { !$0.isExternal && !hasContent($0) }
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

    /// Web reportAndFixSection (item = auto): the AI finds the wrong item among what is on screen.
    /// What can be reported: the reading, the part of speech and every section shown with content.
    private var reportItems: [String] {
        ["pronunciation", "pos"] + visibleSections.filter { !$0.isExternal && hasContent($0) }.map(\.rawValue)
    }

    private func reportAndFix(item: String = "auto") {
        guard AIConsent.shared.isGranted else { askAIConsent = true; return }
        let note = item == "auto" ? reportNote.trimmingCharacters(in: .whitespacesAndNewlines) : ""
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
                } else if item == "auto" && done == nil {
                    showToast(L("AIは間違いを見つけられませんでした。報告として残しました"))
                } else {
                    showToast(L("報告を受け付けました。確かめてから直します"))
                }
            } catch {
                Haptics.warning()
                showToast((error as? LocalizedError)?.errorDescription ?? L("直せませんでした"))
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

    private func exampleCard(_ sentence: String, _ translation: String?) -> some View {
        SectionCard(title: L("例文"), icon: "text.quote") {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(highlighted(sentence))
                        .scaledFont(size: 19)
                        .foregroundStyle(Theme.foreground)
                        .lineSpacing(8)
                    if let t = translation, !t.isEmpty {
                        Text(t).scaledFont(size: 14).foregroundStyle(Theme.muted).lineSpacing(6)
                    }
                }
                Spacer(minLength: 0)
                PronounceCircle(text: sentence, size: 40)
            }
            .padding(16)
            .background(Theme.secondary, in: .rect(cornerRadius: 22, style: .continuous))
        }
    }

    private func highlighted(_ sentence: String) -> AttributedString {
        var out = AttributedString(sentence)
        guard !headword.isEmpty else { return out }
        var searchStart = out.startIndex
        while let r = out[searchStart...].range(of: headword) {
            out[r].foregroundColor = Theme.primaryInk
            out[r].backgroundColor = Theme.primary.opacity(0.1)
            out[r].font = .system(size: 19, weight: .semibold)
            searchStart = r.upperBound
        }
        return out
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
                HStack(spacing: 14) {
                    ForEach(ChunkKind.allCases.filter { kinds.contains($0) }, id: \.self) { k in
                        HStack(spacing: 5) {
                            Circle().fill(k.ink).frame(width: 8, height: 8)
                            Text(k.label(for: learningLang)).scaledFont(size: 13).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(.top, 12)
                if shown.contains(where: { $0.parts.contains { ChunkRules.isSwappable($0, headword: headword, target: learningLang) } }) {
                    Text(L("点線の語を押すと、ネイティブがよく入れるほかの語に入れ替えられます。"))
                        .scaledFont(size: 13)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 8)
                }
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
                    Text(n).scaledFont(size: 15).foregroundStyle(Theme.muted).lineSpacing(4)
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
                    Text(n).scaledFont(size: 15).foregroundStyle(Theme.muted).lineSpacing(4)
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

    private func textCard(_ title: String, icon: String, _ body: String) -> some View {
        SectionCard(title: title, icon: icon) {
            Text(body)
                .scaledFont(size: 15)
                .foregroundStyle(Theme.foreground.opacity(0.9))
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

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

    // MARK: - ネットの画像 (web WebImagesBody)

    private var confirmingWeb: Binding<Bool> {
        Binding(get: { confirmWeb != nil }, set: { if !$0 { confirmWeb = nil } })
    }

    /// Three pictures at a time; 「別の画像」 searches again (the web shows a different three each round).
    private var shownWeb: [WebImageCandidate] {
        let pages = max(1, Int((Double(webCandidates.count) / 3).rounded(.up)))
        let off = webRound % pages
        let page = Array(webCandidates.dropFirst(off * 3).prefix(3))
        return page.isEmpty ? Array(webCandidates.prefix(3)) : page
    }

    /// The section is drawn only once a picture has arrived (web: 画像が表示されない時はその項目を表示しない).
    private func loadWebImages() async {
        guard visibleSections.contains(.webImages), !headword.isEmpty else { return }
        webLoading = true
        defer { webLoading = false }
        let search: () async throws -> [WebImageCandidate] = { [word, headword, webRound] in
            if let word, word.headword == headword { return try await WebImages.search(word: word, round: webRound) }
            return try await WebImages.search(headword: headword, meaning: word?.meaningJa, round: webRound)
        }
        guard let found = try? await search(),
              !Task.isCancelled else { return }
        withAnimation(.snappy) { webCandidates = found }
    }

    private var webImagesCard: some View {
        SectionCard(title: CardSection.webImages.title, icon: CardSection.webImages.icon) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(shownWeb) { c in webTile(c) }
                }
                .uiReady("preview")  // CI's 「webimg」 picture waits for the pictures (DEBUG only)
                HStack(spacing: 14) {
                    Button {
                        Haptics.selection()
                        webRound += 1
                    } label: {
                        HStack(spacing: 5) {
                            if webLoading { ProgressView().controlSize(.mini) } else { Image(systemName: "arrow.clockwise") }
                            Text(L("別の画像"))
                        }
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Theme.secondary, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                    .disabled(webLoading)
                    if let url = URL(string: "https://www.google.com/search?tbm=isch&q=\(headword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                        Button { openURL(url) } label: {
                            Label(L("Google画像検索で見る"), systemImage: "arrow.up.right")
                                .scaledFont(size: 14, weight: .semibold)
                                .foregroundStyle(Theme.primaryInk)
                                .frame(minHeight: 36)
                        }
                    }
                }
                Text(L("画像をタップすると、この単語の写真にできます。"))
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func webTile(_ c: WebImageCandidate) -> some View {
        Button { pickWeb(c) } label: {
            Theme.surface2
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let img = WebImages.inlineImage(c) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        AsyncImage(url: c.previewURL) { phase in
                            if let img = phase.image { img.resizable().scaledToFill() } else { ProgressView() }
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if let name = c.credit?.name, !name.isEmpty {
                        Text(name)
                            .scaledFont(size: 10, weight: .medium)
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity)
                            .background(.black.opacity(0.5))
                    }
                }
                .overlay {
                    if applyingWeb == c.url {
                        ZStack {
                            Color.black.opacity(0.35)
                            ProgressView().tint(.white)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .disabled(applyingWeb != nil || isProvisional)
        .accessibilityLabel(L("この画像にする"))
    }

    /// A word with a photo of its own asks first: the photo is replaced and cannot come back
    /// (web applyWebImage). A word without one takes the picture as its stand-in, with its credit.
    private func pickWeb(_ c: WebImageCandidate) {
        guard applyingWeb == nil else { return }
        if current.objectImageUrl != nil || current.cutoutImageUrl != nil {
            confirmWeb = c
        } else {
            applyWeb(c)
        }
    }

    private func applyWeb(_ c: WebImageCandidate) {
        applyingWeb = c.url
        Task {
            defer { applyingWeb = nil }
            do {
                if current.objectImageUrl != nil || current.cutoutImageUrl != nil {
                    try await dex.replacePhoto(current, with: try await WebImages.image(for: c))
                } else {
                    try await dex.setPlaceholder(current, to: c)
                }
                Haptics.success()
                showToast(L("画像を変更しました"))
            } catch {
                Haptics.warning()
                showToast(L("写真を替えられませんでした"))
            }
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
                .disabled(isProvisional)
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

/// The section's 「作り直す」 button (set by the word page; the links card has none).
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

struct SectionRefresh {
    var running: Bool
    var action: () -> Void
}

extension EnvironmentValues {
    @Entry var sectionRefresh: SectionRefresh? = nil
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
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.muted.opacity(0.75))
                            .rotationEffect(.degrees(refresh.running ? 360 : 0))
                            .animation(refresh.running ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: refresh.running)
                            .frame(width: 44, height: 44)
                    }
                    .disabled(refresh.running)
                    .accessibilityLabel(L("\(title)を作り直す"))
                }
            }
            content
                .opacity(refresh?.running == true ? 0.45 : 1)
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
