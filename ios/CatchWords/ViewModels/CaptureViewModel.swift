import SwiftUI
import CoreLocation

/// The catch: camera → (selfie) → processing → select → celebrate (a new word, or a re-encounter) → dex.
enum CaptureStep: Equatable {
    case camera
    case selfie
    case processing
    case select
    /// The word was chosen: its cut-out, the word and its voice, and 「図鑑に追加」. A word already in the dex (`owned`,
    /// web `reencounter`) has the same moment: its photo is added to that word.
    case celebrate
    /// Web `offlineSaved`: analysis failed; the photo is kept in "解析待ち".
    case failed(String, retryable: Bool)
}

@Observable
final class CaptureViewModel {
    var step: CaptureStep = .camera
    var photo: UIImage?
    var selfie: UIImage?
    var candidates: [Candidate] = []
    /// The words found for what was typed ("違う単語を入力"), the everyday one first: the choose screen lists them
    /// (覚える単語を選ぶ), and they stay listed under the photo when it is closed.
    var typedCandidates: [Candidate] = []
    /// What was typed for `typedCandidates` (the choose screen's line under its title).
    var typedQuery: String = ""
    /// Goes up each time a lookup brings words: the photo screen opens the choose screen on them (never straight on to
    /// the catch, owner 2026-10-15 — 犬 typed in Japanese must never add 犬 as a Mandarin word without a choice).
    var typedRound: Int = 0
    /// The thing the word was typed for (typed on its choose screen): its cut-out is the sticker. nil = typed under the
    /// photo (the photo's main subject is lifted).
    var searchObject: CatchObject?
    var picked: Candidate?
    var details: CardDetails?
    var cutout: UIImage?
    var isCutting: Bool = false
    var isLoadingDetails: Bool = false
    var isLookingUp: Bool = false
    /// The owned-word check runs between the tap and the celebration (capture.tsx:905-919).
    var isCheckingOwned: Bool = false
    var caption: String = ""
    /// The spoken one-liner next to the memo (web VoiceCaptionButton).
    var placeName: String?
    var location: CLLocation?
    let captureType: String = "photo"
    var restoredPendingId: String?
    /// Inline error under "違う単語を入力" (web `input.notTargetLang`).
    var searchError: String?
    /// One-line notice (web toast).
    var toast: String?
    /// The failure was "no connection" (web shows WifiOff; otherwise Sparkles).
    var failedOffline: Bool = false

    /// The objects in the photo (candidates grouped per object, each with its Vision cut-out, box and point):
    /// the candidates screen puts each word on its object, the celebration shows the object's cut-out.
    var objects: [CatchObject] = []
    private var masksTask: Task<InstanceMasks?, Never>?
    /// This photo's catch scan (v10: bracket, light pen, tags as the names come). Kept for the run, so going back
    /// from the celebration shows the words as they were instead of replaying it. nil = no scan (a preview).
    var scan: CatchScanSession?

    // Re-encounter ("また会えた！")
    var owned: OwnedWord?
    /// Set the moment the re-encounter's photo is handed to its background save (`CaptureView.recordReencounter`).
    var reencCount: Int?

    // Film v6: the choose screen and the GET moment share one timeline (CatchStage.swift).
    /// The choice P on `CCClock` when the word was chosen on the choose screen (nil = chosen elsewhere: a typed word).
    var stageOrigin: Double?
    /// How long after P the choose screen hands over to the GET screen (`Film6.handoff`), nil = no choose screen.
    var stageHandoff: Double?
    /// The picked thing's box in the photo (0–1), for the sticker while the cut-out is not ready.
    var pickedBox: CGRect?
    /// The choose screen has turned the photo into the app's light page (the status bar turns dark).
    var lightStage: Bool = false
    /// The stage's colours and the sticker's stand-in, worked out once on the choose screen.
    var stagePalette: StagePalette?
    var stageFallback: UIImage?

    /// runToken: "cancel" only discards stale results; in-flight work is never killed mid-save.
    private var runToken: Int = 0
    private var cutoutTask: Task<Void, Never>?
    private var detailsTask: Task<CardDetails?, Never>?
    /// Cards already being generated for this photo, by headword.
    private var detailsCache: [String: Task<CardDetails?, Never>] = [:]
    /// Words the server refused to make in the learning language (`NOT_TARGET_LANGUAGE`), by `detailsKey`.
    @ObservationIgnored private var refusedWords: Set<String> = []
    /// "Is this word already in the dex?" — started for each object's first word as soon as the words are found, so
    /// a tap opens the celebration at once instead of waiting for the round trip (0.6–1.0 s measured 2026-10-10;
    /// owner: 「ただ待たされる時間は苦痛」). nil = that check failed (asked again at the tap).
    @ObservationIgnored private var ownedChecks: [String: Task<OwnedCheck?, Never>] = [:]
    /// The photos, uploaded while the celebration is on screen (`DexStore.preupload`). Handed to the save
    /// (`handOffUploads`); dropped ones are deleted again (`dropUploads`).
    private(set) var uploads: CatchPreupload?
    @ObservationIgnored private weak var uploadsStore: DexStore?
    /// Detection may finish while the user is still taking the selfie.
    private var detectOutcome: Result<[Candidate], Error>?
    /// The photo is kept in "解析待ち" from the shutter on (capture.tsx enqueueCapture), and
    /// released only when its job is done: saved, re-encountered, or the user starts over.
    private(set) var pendingId: String?

    init() {
        // The automatic retry of 「解析待ち」 leaves alone the photo this screen is working on.
        PendingRetry.shared.register(self)
    }

    /// Starts analysis immediately; the selfie prompt covers the wait (web: "ものと一緒に、もう一枚").
    func analyze(_ image: UIImage, askSelfie: Bool = false) {
        runToken += 1
        let token = runToken
        // A word check still running belongs to the old run: its result is dropped, so its flag must not
        // keep blocking taps on the new run's words.
        isCheckingOwned = false
        isLoadingDetails = false
        photo = image
        selfie = nil
        candidates = []
        typedCandidates = []
        searchObject = nil
        picked = nil
        details = nil
        detailsTask = nil
        detailsCache = [:]
        dropUploads()
        cutoutTask?.cancel()
        isCutting = false
        cutout = nil
        detectOutcome = nil
        searchError = nil
        owned = nil
        objects = []
        stageOrigin = nil
        stageHandoff = nil
        pickedBox = nil
        lightStage = false
        stagePalette = nil
        stageFallback = nil
        step = askSelfie ? .selfie : .processing
        ownedChecks = [:]
        // One foreground-instance request per photo, started with the server call and reused for every object.
        masksTask?.cancel()
        masksTask = Task<InstanceMasks?, Never> { await CutoutService.instanceMasks(from: image) }
        // Every instance's cut-out is rendered while the AI is still naming the things (they used to be rendered
        // after the server answered, between the answer and the words on screen). The tags' places inside the
        // instances (`InstanceMasks.anchors`, quick) are measured first.
        let masksForCuts = masksTask
        Task.detached(priority: .utility) {
            guard let masks = await masksForCuts?.value else { return }
            _ = masks.anchors()
            masks.prerenderCuts()
        }
        // The scan's outlines, traced from the same masks while the AI is naming the things.
        let session = CatchScanSession()
        scan = session
        Task {
            let masks = await masksForCuts?.value
            let lines = await Task.detached(priority: .userInitiated) { masks?.outlines() ?? [] }.value
            session.setOutlines(lines, at: Date())
        }
        // A photo restored from the queue is never queued again (one entry per photo, not per retry).
        // Every new photo gets its own entry (an earlier photo's entry stays in 「解析待ち」).
        if let rid = restoredPendingId {
            pendingId = rid
        } else {
            pendingId = PendingQueue.shared.add(image: image, reason: L("解析中"), lat: nil, lng: nil)?.id
        }
        // A photo opened from the queue goes through the automatic retry's path: the words it already
        // found are used as they are, and an analysis of this photo running there is joined, not repeated.
        let restoredId = restoredPendingId

        Task {
            async let loc = LocationService.shared.current()
            do {
                let found: [Candidate]
                if let restoredId {
                    found = try await PendingRetry.shared.suggest(for: restoredId, image: image)
                } else {
                    found = try await AIService.shared.suggest(image: image)
                }
                guard token == runToken else { return }
                let masks = await masksTask?.value
                let size = image.size
                let built = await Task.detached(priority: .userInitiated) {
                    CatchObject.build(candidates: found, masks: masks, photoSize: size)
                }.value
                guard token == runToken else { return }
                objects = built
                scan?.setNames(built, at: Date())
                detectOutcome = .success(found)
                prefetchOwnedChecks(found)
            } catch {
                guard token == runToken else { return }
                detectOutcome = .failure(error)
                if let pid = pendingId {
                    PendingQueue.shared.updateReason(id: pid, reason: Self.reason(error))
                }
            }
            if step != .selfie { advanceAfterDetect() }
            let here = await loc
            guard token == runToken else { return }
            location = here
            if let here {
                let name = await LocationService.shared.placeName(for: here)
                guard token == runToken else { return }
                placeName = name
            }
        }
    }

    /// "いますぐもう一度試す": same photo, same queue entry.
    func retry() {
        guard let p = photo else { reset(); return }
        restoredPendingId = pendingId
        // The selfie belongs to this photo: a retry keeps it.
        let keptSelfie = selfie
        analyze(p)
        selfie = keptSelfie
    }

    func finishSelfie(_ image: UIImage?) {
        guard step == .selfie else { return }
        selfie = image
        if detectOutcome == nil {
            withAnimation(.easeInOut(duration: 0.3)) { step = .processing }
        } else {
            advanceAfterDetect()
        }
    }

    private func advanceAfterDetect() {
        guard let outcome = detectOutcome else { return }
        switch outcome {
        case .success(let found):
            candidates = found
            // No tap here: the scan sounds and taps each tag as it comes up (`CatchScanSession`).
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { step = .select }
        case .failure(let error):
            let retryable = (error as? APIError)?.isRetryable ?? true
            failedOffline = { if case .offline? = error as? APIError { return true }; return false }()
            Haptics.warning()
            step = .failed(Self.reason(error), retryable: retryable)
        }
    }

    static func reason(_ error: Error) -> String {
        if case .timeout? = error as? APIError { return L("通信に時間がかかっています。写真は端末に保存しました。") }
        return (error as? LocalizedError)?.errorDescription ?? L("解析に失敗しました。")
    }

    /// "違う単語を入力" under the photo or on a thing's choose screen (`suggestWordCandidates`, any language — the
    /// display language or the learning language): the photo stays the sticker (`object`: the thing it was typed for,
    /// whose cut-out is used) and the screen stays put. Whatever was found — one word or several — opens the choose
    /// screen (覚える単語を選ぶ, owner 2026-10-15: a typed word went straight to the catch, so 犬 typed in Japanese became
    /// the Mandarin word 犬): each word with what kind of name it is, the everyday one first, and the learner picks; then
    /// the GET moment as for a tag. A miss is shown inline, never as a full-screen failure. A word whose headword is not
    /// written in the learning language alone (ボクサーパンツ typed in Japanese must never become a Mandarin headword,
    /// `LanguageRules.headwordSaveable`) is never offered.
    func search(text: String, object: CatchObject? = nil) {
        runToken += 1
        let token = runToken
        isCheckingOwned = false
        ownedChecks = [:]
        searchError = nil
        searchObject = object
        isLookingUp = true
        Task {
            defer { if token == runToken { isLookingUp = false } }
            do {
                let raw = try await AIService.shared.candidates(for: text, scene: placeName)
                guard token == runToken else { return }
                let found = NameRegister.finalized(Self.saveable(raw))
                guard !found.isEmpty else { throw APIError.message(Self.notTargetWordFound) }
                typedQuery = text
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { typedCandidates = found }
                typedRound += 1
            } catch {
                guard token == runToken else { return }
                Haptics.warning()
                let message: String = {
                    if case .message(let m)? = error as? APIError { return m }
                    if Self.isNotTargetLanguage(error) { return Self.notTargetWordFound }
                    return (error as? LocalizedError)?.errorDescription ?? Self.notTargetLang
                }()
                searchError = message
            }
        }
    }

    /// input.notTargetLang (web i18n), with the learning language filled in.
    static var notTargetLang: String { L("学習している言語の単語が見つかりませんでした。別の言い方で調べてみてください。") }

    /// No word of the learning language came out of what was typed (the app's own check, or the server's
    /// `NOT_TARGET_LANGUAGE`: neither the AI's headword nor the typed word is in the learning language).
    static var notTargetWordFound: String {
        switch NativeAPI.targetLanguage {
        case "en": L("英語の単語が見つかりませんでした。別の言葉で試してください")
        case "ja": L("日本語の単語が見つかりませんでした。別の言葉で試してください")
        default: L("台湾華語の単語が見つかりませんでした。別の言葉で試してください")
        }
    }

    /// The server refused to make the word because it is not in the learning language (server #183).
    nonisolated static func isNotTargetLanguage(_ error: Error) -> Bool {
        if case .server(_, let m)? = error as? APIError { return m.contains("NOT_TARGET_LANGUAGE") }
        return false
    }

    /// The candidates whose headword can be saved for the learning language (`LanguageRules.headwordSaveable`): a
    /// headword with the reader's own language in it (kana or English in a Mandarin word) is dropped, never saved.
    static func saveable(_ found: [Candidate], target: String = NativeAPI.targetLanguage) -> [Candidate] {
        found.filter { LanguageRules.headwordSaveable($0.headword, target: target) }
    }

    private struct OwnedCheck: Decodable { let owned: OwnedWord? }

    /// The owned-word check for `headword` in this run: the one already running (or done), else a new one.
    private func ownedCheck(for headword: String) -> Task<OwnedCheck?, Never> {
        if let running = ownedChecks[headword] { return running }
        let task = Task<OwnedCheck?, Never> {
            try? await NativeAPI.call(
                "checkOwnedWord",
                ["headword": headword, "language": NativeAPI.targetLanguage],
                as: OwnedCheck.self, timeout: 15
            )
        }
        ownedChecks[headword] = task
        return task
    }

    /// Starts the owned-word check of each object's first word (the word a tap usually picks) as the words appear.
    private func prefetchOwnedChecks(_ found: [Candidate]) {
        for words in CatchObject.groups(found) {
            if let first = words.first { _ = ownedCheck(for: first.headword) }
        }
    }

    /// A word was tapped on its object (or typed under the photo, `object` nil). The owned-word check (usually
    /// already answered, `prefetchOwnedChecks`) decides between the celebration and the re-encounter; the card's
    /// details are generated from the tap on and never waited for (`provisionalDetails`). The sticker is the
    /// object's cut-out (cut-out mode on), else the photo.
    /// Which candidate was picked (web `logCandidatePick`): its place in the server's order and how many there
    /// were — never the word. The developer settings count Top-1 / Top-3 per AI model from it. A word from the
    /// photo's tags is `photo`; a word found by typing after the photo is `native_search` (the photo's words
    /// missed it). Nothing waits for it and a failure is ignored.
    private func logPick(_ word: Candidate, object: CatchObject?, typed: Bool) {
        let via: String
        let rank: Int
        let count: Int
        if !typed, object != nil, let i = candidates.firstIndex(where: { AIService.sameSuggestion($0, word) }) {
            via = "photo"
            rank = i + 1
            count = candidates.count
        } else if typed || object == nil, photo != nil {
            via = "native_search"
            rank = (typedCandidates.firstIndex(where: { $0.headword == word.headword }) ?? 0) + 1
            count = max(typedCandidates.count, rank)
        } else {
            return
        }
        let r = min(rank, 50)
        let n = min(max(count, rank), 50)
        Task { _ = try? await NativeAPI.call("logCandidatePick", ["via": via, "rank": r, "n": n], timeout: 15) }
    }

    /// `stage`: chosen on the choose screen (film v6): `origin` is the choice P and the GET screen opens no sooner than
    /// `handoffAt` (both `CCClock`), once the choose screen's card has folded away — the owned-word check usually
    /// answered long before.
    /// `typed`: the word was typed (under the photo or on a thing's choose screen), not one of the photo's names.
    func choose(_ word: Candidate, object: CatchObject?, typed: Bool = false, stage: (origin: Double, handoffAt: Double)? = nil) {
        UITestTrace.log("choose \(word.headword) checking=\(isCheckingOwned) step=\(step) token=\(runToken)")
        guard !isCheckingOwned else { return }
        // Never a headword in another language (owner 2026-10-15): asked to look again instead of saving it.
        guard LanguageRules.headwordSaveable(word.headword, target: NativeAPI.targetLanguage) else {
            Haptics.warning()
            searchError = Self.notTargetWordFound
            return
        }
        let token = runToken
        logPick(word, object: object, typed: typed)
        stageOrigin = stage?.origin
        stageHandoff = stage.map { $0.handoffAt - $0.origin }
        pickedBox = object?.box
        picked = word
        // Decided again for this word by the owned-word check below.
        owned = nil
        reencCount = nil
        details = nil
        detailsTask = nil
        searchError = nil
        cutoutTask?.cancel()
        isCutting = false
        cutout = nil
        dropUploads()
        Haptics.impact(.light)
        // Every catch is cut out (owner 2026-10-11: the 切り抜きモード setting is gone).
        if let cut = object?.cut {
            cutout = cut
        } else {
            // No cut-out for this object (or a typed word): lift the subject under its tag (`anchor`: inside its Vision
            // instance when it has one, else the AI's point), so the sticker is the thing the tag was on.
            startCutout(near: object?.anchor)
        }
        isCheckingOwned = true
        loadDetails(for: word)
        let early = ownedCheck(for: word.headword)
        Task {
            // Usually finished already (started when the words appeared). One that failed is asked once more now.
            var found = await early.value
            if found == nil, token == runToken, picked == word {
                ownedChecks[word.headword] = nil
                found = await ownedCheck(for: word.headword).value
            }
            UITestTrace.log("choose.checked \(word.headword) owned=\(found?.owned != nil) failed=\(found == nil)"
                            + " sameRun=\(token == runToken) samePick=\(picked == word)")
            guard token == runToken, picked == word else { return }
            // The choose screen's card folds away before the next screen opens.
            if let at = stage?.handoffAt {
                let left = at - CCClock.now
                if left > 0 { try? await Task.sleep(for: .seconds(left)) }
                guard token == runToken, picked == word else { return }
            }
            isCheckingOwned = false
            if let o = found?.owned {
                owned = o
                reencCount = nil
                // An owned word gets no card: stop generating it (the request is cancelled with its task).
                let key = Self.detailsKey(word)
                detailsCache[key]?.cancel()
                detailsCache[key] = nil
                detailsTask = nil
                isLoadingDetails = false
                // The same GET moment and dex finale as a new word (owner 2026-10-15): the choose screen's stage
                // goes on in the same frame; only the words and the save differ (CatchCelebrationView, CaptureView).
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step = .celebrate }
            } else {
                // Fail open: a broken check must never block a new catch.
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step = .celebrate }
                // Started at the tap; one that already failed (silently, before the celebration) is tried once more.
                if details == nil, !isLoadingDetails { loadDetails(for: word) }
            }
        }
    }

    /// The celebration's 「戻る」: back to the photo's words (nothing was saved).
    func backToCandidates() {
        runToken += 1
        cutoutTask?.cancel()
        isCutting = false
        isCheckingOwned = false
        isLoadingDetails = false
        picked = nil
        details = nil
        detailsTask = nil
        cutout = nil
        owned = nil
        reencCount = nil
        stageOrigin = nil
        stageHandoff = nil
        lightStage = false
        stagePalette = nil
        stageFallback = nil
        dropUploads()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { step = .select }
    }

    /// Cut-out mode: cutting starts the moment a word is tapped, never delays the celebration,
    /// and is awaited only right before saving (capture.tsx: 図鑑に入れる前に切り抜きが揃っていること).
    /// `point`: 0–1 of the photo, top-left origin (nil = the main subject).
    private func startCutout(near point: CGPoint?) {
        guard let photo, cutout == nil else { return }
        cutoutTask?.cancel()
        isCutting = true
        cutoutTask = Task {
            let lifted = await CutoutService.liftSubject(from: photo, near: point)
            guard !Task.isCancelled else { return }
            isCutting = false
            if let lifted {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { cutout = lifted }
            }
        }
    }

    /// The sticker while there is no cut-out: the photo round the picked thing (a typed word: the whole photo).
    func stickerFallback() -> UIImage? {
        StickerCrop.image(photo, box: pickedBox) ?? picked.map { Self.textCard(for: $0.headword) }
    }

    /// Waits for a cut-out that is still running (a failed one simply leaves the photo).
    func awaitCutout() async {
        guard isCutting, let task = cutoutTask else { return }
        await task.value
    }

    /// The card for the picked word, generated from the tap on. A card that fails no longer sends the learner back
    /// to the words (it did, with 「カード生成に失敗しました」): the catch can be saved without it, from the word's
    /// own fields (`provisionalDetails`), and the detail page writes the notes when it is opened.
    private func loadDetails(for candidate: Candidate) {
        let token = runToken
        isLoadingDetails = true
        let key = Self.detailsKey(candidate)
        let task = detailsCache[key] ?? Task<CardDetails?, Never> {
            do {
                return try await AIService.shared.cardDetails(for: candidate)
            } catch {
                if Self.isNotTargetLanguage(error) { self.refusedWords.insert(key) }
                return nil
            }
        }
        detailsCache[key] = task
        detailsTask = task
        Task {
            let d = await task.value
            if d == nil, detailsCache[key] == task { detailsCache[key] = nil }   // a failure is never reused
            guard token == runToken, picked == candidate else { return }
            isLoadingDetails = false
            if let d {
                withAnimation(.easeOut(duration: 0.3)) { details = d }
            } else if refusedWords.contains(key), step == .celebrate, owned == nil {
                // The server cannot make it a word of the learning language (`NOT_TARGET_LANGUAGE`): never saved
                // under a headword in another language — back to the words, with what to do.
                backToCandidates()
                Haptics.warning()
                searchError = Self.notTargetWordFound
            }
        }
    }

    private static func detailsKey(_ c: Candidate) -> String { c.headword + "|" + (c.categoryKey ?? "") }

    /// The photos go up while the celebration is on screen, so 「図鑑に追加」 only saves the row.
    func startUploads(using dex: DexStore) {
        guard let photo, uploads == nil else { return }
        uploadsStore = dex
        uploads = dex.preupload(photo: photo, cutout: cutout, selfie: selfie)
    }

    /// The catch is being saved from `draft`: uploads it carries now belong to that save (never deleted here);
    /// ones it did not take (the images changed since) belong to no catch.
    func handOffUploads(to draft: CatchDraft) {
        if draft.uploads != nil { uploads = nil } else { dropUploads() }
    }

    /// The word they were uploaded for was left before it was saved: the files belong to no catch.
    private func dropUploads() {
        if let pre = uploads { uploadsStore?.discardPreupload(pre) }
        uploads = nil
    }

    /// 「図鑑に追加」 when the card is not here yet (owner 2026-10-10: 「ただ待たされる時間は苦痛」): the catch is
    /// saved at once from the picked word's own fields (reading, meaning, category — the web's hint card, capture.tsx
    /// confirmWord), and the card still being generated (`cardStillComing`) fills the notes in behind the dex
    /// (`DexStore.fillCard`). Nothing here is a made-up value: the empty fields are filled only from the real card.
    func provisionalDetails() -> CardDetails? {
        guard let picked else { return nil }
        // The headword's rule first (CategoryRules): a typed word comes with no category, and the photo's quick
        // answer can be the wrong one.
        let category = CategoryRules.normalize(headword: picked.headword, key: picked.categoryKey)
        return CardDetails(categoryKey: category, exampleSentence: "", exampleTranslation: "", extras: WordExtras())
    }

    /// The card being generated for the picked word (nil = none running).
    var cardStillComing: Task<CardDetails?, Never>? { details == nil ? detailsTask : nil }

    func draft(details d: CardDetails) -> CatchDraft? {
        guard let picked else { return nil }
        let base = photo ?? Self.textCard(for: picked.headword)
        return CatchDraft(
            candidate: picked, details: d, photo: base, cutout: cutout, selfie: selfie,
            caption: caption, location: location, placeName: placeName, captureType: captureType,
            // Only while they are still the very images being saved (else `save` uploads these ones).
            uploads: uploads.flatMap { $0.matches(photo: base, cutout: cutout, selfie: selfie) ? $0 : nil }
        )
    }

    /// The catch was saved (or re-encountered): the queued photo's job is done.
    func releasePending() {
        if let pid = pendingId {
            PendingQueue.shared.remove(id: pid)
            PendingRetry.shared.forget(pid)
        }
        pendingId = nil
        restoredPendingId = nil
    }

    /// 「図鑑に追加」 (and a re-encounter's record): the dex opens before the save has finished. The queued photo is
    /// handed to that background save (this screen no longer owns it, so `reset` keeps it) and hidden from 「解析待ち」
    /// meanwhile; the save removes it when done, or shows it again when it fails.
    func detachPendingForSave() -> String? {
        let pid = pendingId
        pendingId = nil
        restoredPendingId = nil
        if let pid { PendingQueue.shared.setSaving(pid, true) }
        return pid
    }

    /// "もう一枚撮る" from the failure panel keeps the photo in "解析待ち" (that is what it promised).
    func keepPendingAndReset() {
        pendingId = nil
        restoredPendingId = nil
        reset()
    }

    func restore(_ item: PendingCatch) {
        guard let img = PendingQueue.shared.image(for: item) else {
            PendingQueue.shared.remove(id: item.id)
            return
        }
        restoredPendingId = item.id
        pendingId = item.id
        analyze(img)
    }

    /// Goes up with every notice, even the same text twice (the celebration re-enables its button on each one).
    var toastCount: Int = 0

    func showToast(_ text: String) {
        toastCount += 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.25)) { if toast == text { toast = nil } }
        }
    }

    /// Starting over throws the queued photo away too (otherwise "解析待ち" piles up).
    func reset() {
        runToken += 1
        cutoutTask?.cancel()
        isCutting = false
        masksTask?.cancel()
        masksTask = nil
        objects = []
        scan = nil
        if let pid = pendingId {
            PendingQueue.shared.remove(id: pid)
            PendingRetry.shared.forget(pid)
        }
        pendingId = nil
        photo = nil
        selfie = nil
        candidates = []
        typedCandidates = []
        searchObject = nil
        picked = nil
        details = nil
        detailsTask = nil
        detailsCache = [:]
        ownedChecks = [:]
        dropUploads()
        cutout = nil
        caption = ""
        placeName = nil
        location = nil
        restoredPendingId = nil
        detectOutcome = nil
        isLookingUp = false
        isCheckingOwned = false
        isLoadingDetails = false
        searchError = nil
        failedOffline = false
        owned = nil
        reencCount = nil
        stageOrigin = nil
        stageHandoff = nil
        pickedBox = nil
        lightStage = false
        stagePalette = nil
        stageFallback = nil
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step = .camera }
    }

    /// Text catches get a generated "word card" image so the dex always has a surface.
    static func textCard(for text: String) -> UIImage {
        let size = CGSize(width: 900, height: 900)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(red: 0.16, green: 0.61, blue: 1, alpha: 1).cgColor,
                          UIColor(red: 0, green: 0.38, blue: 0.88, alpha: 1).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: text.count > 3 ? 150 : 230, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: style,
            ]
            let str = NSAttributedString(string: text, attributes: attrs)
            let bounds = str.boundingRect(with: CGSize(width: size.width - 80, height: size.height), options: .usesLineFragmentOrigin, context: nil)
            str.draw(in: CGRect(x: 40, y: (size.height - bounds.height) / 2, width: size.width - 80, height: bounds.height))
        }
    }
}
