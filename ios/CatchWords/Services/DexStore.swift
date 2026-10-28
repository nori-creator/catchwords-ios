import SwiftUI
import CoreLocation
import Photos

/// Everything needed to save one catch.
struct CatchDraft {
    let candidate: Candidate
    let details: CardDetails?
    let photo: UIImage
    let cutout: UIImage?
    let selfie: UIImage?
    let caption: String
    let location: CLLocation?
    let placeName: String?
    let captureType: String
    /// Photos already uploaded while the card was on screen (card catch); nil = upload while saving.
    var uploads: CatchPreupload? = nil
    /// The catch's own id, sent as `client_catch_id`: the server answers with the sticker it already made for it, so a
    /// save tried again after a dropped answer never makes a second one (the same id on every try, `PendingSave`).
    var catchId: String = UUID().uuidString.lowercased()
    /// Photos already in storage from an earlier try (「保存待ち」): only the row is saved.
    var uploaded: CatchUploads? = nil
    /// The learning language it was caught in (nil: the current one). A 「保存待ち」 catch keeps its own.
    var language: String? = nil
}

/// A card catch's photos going up while its card is on screen (`DexStore.preupload`). `ts` names the files,
/// so the provisional dex entry (`addProvisional`) shows them from the cache under the very same paths.
struct CatchPreupload {
    let uid: String
    let ts: Int
    let photo: UIImage
    let cutout: UIImage?
    let selfie: UIImage?
    let task: Task<CatchUploads, Error>

    /// Still the very images a draft would save (the cut-out may have been replaced since).
    func matches(photo p: UIImage, cutout c: UIImage?, selfie s: UIImage?) -> Bool {
        photo === p && cutout === c && selfie === s
    }
}

/// Storage paths of a catch's photos.
nonisolated struct CatchUploads: Sendable {
    let object: String?
    let cutout: String?
    let selfie: String?
}

enum SaveOutcome {
    case created(Sticker)
    case reencounter(Sticker)

    var sticker: Sticker {
        switch self {
        case .created(let s), .reencounter(let s): s
        }
    }
}

/// The user's dex, read from and written to the SAME Supabase project as the web app.
@Observable
final class DexStore {
    /// Every change also goes to the copy kept on this phone (`scheduleSnapshot`): the next launch shows it at once.
    var stickers: [Sticker] = [] {
        didSet { stickersVersion &+= 1 }
    }
    /// Counts every change of `stickers` (the headword index below is rebuilt after one).
    @ObservationIgnored private var stickersVersion = 0
    /// The stickers by normalised headword, oldest first, for `dexPictures` — every square of the gallery looked
    /// through every sticker on each update (several a second during a landing, owner 2026-10-20: stutter).
    @ObservationIgnored private var headwordIndex: (version: Int, lang: String, map: [String: [Sticker]])?
    var isLoading: Bool = false
    var hasLoaded: Bool = false
    var loadError: String?
    var signed: [String: URL] = [:]
    /// Paths the storage answered for without the file (a cut-out whose upload never landed, a photo removed): the
    /// dex shows the word's next picture instead of an empty square.
    var missingPaths: Set<String> = []
    /// Cut-outs that came out (almost) empty — a speck of the photo, 8–15 KB where a real one is hundreds (owner
    /// 2026-10-14: 「図鑑にまだ表示されてないものがある」): found when the picture is drawn (`StickerImage`), and the
    /// word's photo is shown instead.
    var blankCutouts: Set<String> = []

    /// A cut-out was drawn and found (almost) empty.
    func markBlankCutout(_ path: String) {
        guard !blankCutouts.contains(path) else { return }
        blankCutouts.insert(path)
    }
    /// This account's photos waiting in 「解析待ち」 (kept up to date by the queue itself).
    var pending: [PendingCatch] { PendingQueue.shared.items }
    /// sticker id → review state (memory badges). Stickers without a review get no badge.
    var reviews: [String: ReviewState] = [:]

    private let client = SupabaseClient.shared
    private var language: String { NativeAPI.targetLanguage }
    /// Stickers `save` put in since the last `load` started: a load whose rows were read before such a save
    /// landed keeps them instead of dropping them.
    @ObservationIgnored private var savedSinceLoad: Set<String> = []

    // MARK: Reader language (word_explanations)
    /// word id → the shared `words` row as stored, before choosing what this reader sees.
    private var sharedWords: [String: Word] = [:]
    /// word id → this reader's explanation (for `readerKey`).
    private var explanations: [String: ReaderLanguage.Explanation] = [:]
    /// word id → the examples and chunks of this reader's level band (`getWordExplanation` → `level`, docs/sharing-rules.md).
    private var levels: [String: ReaderLanguage.LevelContent] = [:]
    /// word id → the meaning written in the reader's language (`getReaderMeanings`).
    private var readerMeanings: [String: String] = [:]
    /// The display language the two tables above were read for.
    private var readerKey = ""

    private static let baseColumns =
        "id,word_id,object_image_url,cutout_image_url,selfie_image_url,caption,location_name,lat,lng,taken_at,capture_type,shelf_key"
    /// Columns that came with later migrations (the web reads them the same way, in stages). If the
    /// server doesn't have one yet the dex still loads without it.
    nonisolated(unsafe) private static var optionalColumns = ["hero_role", "placeholder_image_url", "placeholder_credit", "level_band"]
    private static var selectColumns: String {
        ([baseColumns] + optionalColumns + ["word:words(*)"]).joined(separator: ",")
    }

    /// Runs a stickers query; drops an optional column the server says it doesn't have and tries again.
    private func selectStickers(_ query: (String) -> String) async throws -> Data {
        while true {
            do {
                return try await client.rest("GET", query(Self.selectColumns))
            } catch {
                let text = "\(error)"
                guard let missing = Self.optionalColumns.first(where: { text.contains($0) }) else { throw error }
                Self.optionalColumns.removeAll { $0 == missing }
            }
        }
    }

    func load() async {
        PendingQueue.shared.reload()
        // Local guest (no account): an empty dex, not a skeleton that never ends.
        guard client.session != nil else {
            loadError = nil
            hasLoaded = true
            return
        }
        let uid = client.userId
        isLoading = true
        savedSinceLoad = []
        defer { isLoading = false }
        do {
            // Every page, like the web's listMyStickers (one capped read silently dropped the oldest
            // words of a big dex — and the cap counted other languages' words too).
            var rows: [Sticker] = []
            for page in 0..<Self.maxPages {
                let offset = page * Self.pageSize
                let data = try await selectStickers {
                    "stickers?select=\($0)&order=taken_at.desc,id.desc&limit=\(Self.pageSize)&offset=\(offset)"
                }
                // Off the main thread: a page of 500 words with their cards is megabytes of JSON.
                let chunk = try await Self.decodeOffMain([Sticker].self, from: data)
                rows += chunk
                if chunk.count < Self.pageSize { break }
            }
            // Signed out (or another account signed in) while this was loading: drop the result.
            guard client.userId == uid else { return }
            // The pictures' links are asked for now, the newest words first, while the album's hidden photos and
            // places are read — they used to wait for those two reads and the reviews' (a photo not kept on this
            // phone stayed blank for all of them).
            let signing = Task { await self.signPaths(for: rows) }
            async let hidden: Void = loadAlbumHidden()
            async let places: Void = loadAlbumPlacements()
            await hidden
            await places
            guard client.userId == uid else { return }
            // Only the words of the language being learned (web listMyStickers → matchesTargetLanguage).
            // A catch still being saved in the background stays on screen (its save swaps it for the real row).
            let provisional = stickers.filter { Self.isProvisional($0.id) && ($0.word?.matches(language) ?? true) }
            // A catch saved while the rows were being read (not among them yet) stays too.
            let rowIds = Set(rows.map(\.id))
            let savedMeanwhile = stickers.filter { savedSinceLoad.contains($0.id) && !rowIds.contains($0.id) }
            // A cut-out attached on this phone while the rows were being read (the background cut-outs) is kept: a
            // row read just before it landed would put the photo back for a moment (photo → cut-out → photo).
            var madeHere: [String: (object: String?, cutout: String)] = [:]
            for s in stickers { if let c = s.cutoutImageUrl { madeHere[s.id] = (s.objectImageUrl, c) } }
            let fresh = rows.map { row -> Sticker in
                guard row.cutoutImageUrl == nil, let kept = madeHere[row.id], kept.object == row.objectImageUrl else { return row }
                var r = row
                r.cutoutImageUrl = kept.cutout
                return r
            }
            stickers = provisional + savedMeanwhile + present(fresh.filter { $0.word?.matches(language) ?? true })
            serverAnswered = true
            // 「保存待ち」 words of this language that are not on screen yet (launch without a snapshot, a language switch).
            restoreUnsaved()
            installSample()
            loadError = nil
            hasLoaded = true
            UITestTrace.once("dex read from the server", "words=\(stickers.count)")
            // Kept on this phone at once (the next launch shows these rows from its first frame), not only once the
            // reviews and every link are read — an app sent away before that left no snapshot (owner 2026-10-20:
            // Home's photos took 20 s to show at launch).
            scheduleSnapshot()
            // The cut-outs still missing (every picture is cut out, owner 2026-10-11), behind the album: its photos
            // show at once and fade into their cut-outs as they are made.
            CutoutBackfill.shared.start(dex: self)
            await loadReviews()
            await signing.value
            UITestTrace.once("picture links signed")
            guard client.userId == uid else { return }
            // Behind the screen: the re-encounter photos the dex squares cycle through, and the newest pictures put
            // on disk.
            Task { await loadEncounterPhotos() }
            prefetchNewest()
            scheduleSnapshot()
        } catch {
            guard client.userId == uid, !(error is CancellationError) else { return }
            loadError = (error as? LocalizedError)?.errorDescription ?? L("図鑑を読み込めませんでした。")
        }
    }

    private static let pageSize = 500
    private static let maxPages = 40

    /// Every row of a read, a page at a time. The server returns at most 1000 rows per request whatever
    /// `limit` says, so a single `limit=3000` read silently dropped the rest (memory badges, due counts
    /// and album placements of a big dex). `path` must have a stable `order`.
    private func readAll<T: Decodable>(_ path: String, as: T.Type, decoder: JSONDecoder,
                                       pageSize: Int = 1000, maxPages: Int = 20) async throws -> [T] {
        try await client.restAll(path, as: T.self, decoder: decoder, pageSize: pageSize, maxPages: maxPages)
    }

    func reloadReviews() async { await loadReviews() }

    func sticker(id: String) -> Sticker? { stickers.first { $0.id == id } }

    /// Provisional id → the saved sticker that took its place (`save(replacing:)`).
    private var adoptedIds: [String: String] = [:]

    /// The sticker now standing for `id`: a page opened on a catch still being saved keeps its provisional id, and
    /// becomes the saved word in place once the save is done (owner 2026-10-11: 「キャッチしたてのときその単語の
    /// 詳細に進めない」 — the page now opens at once).
    func current(_ id: String) -> Sticker? { sticker(id: adoptedIds[id] ?? id) }

    /// When reviews come due (for おまかせ reminders).
    /// This learning language's cards only (R1).
    var upcomingDueTimes: [Date] {
        let mine = Set(stickers.map(\.id))
        return reviews.filter { mine.contains($0.key) }.values.compactMap(\.dueAt)
    }

    /// The photos the home album shows (the ones taken off the album stay in the dex only).
    /// Re-encounter photos are pages too, on the day they were met (`albumEncounters`).
    var albumStickers: [Sticker] { (stickers + albumEncounters).filter { !albumHidden.contains($0.id) } }
    /// How many of this account's photos are off the album (the ones still in the dex or met again).
    var albumHiddenCount: Int { (stickers + albumEncounters).filter { albumHidden.contains($0.id) }.count }

    /// True when this headword is already in the dex (scan "取得済み").
    func owns(headword: String) -> Bool { stickers.contains { $0.word?.headword == headword } }

    /// Level index (0–5) for every sticker that has a review — feeds the memory bar.
    var memoryLevelCounts: [Int] {
        var out = Array(repeating: 0, count: 6)
        for s in stickers {
            if let p = memoryPercent(for: s) { out[MemoryBadge.level(p)] += 1 }
        }
        return out
    }

    /// Every review row, a page of 1000 at a time (as `readAll`), each page decoded off the main thread.
    private func loadReviews() async {
        let uid = client.userId
        let path = "reviews?select=id,sticker_id,ease,interval_days,repetitions,last_reviewed_at,due_at&order=id.asc"
        var rows: [ReviewState] = []
        do {
            for page in 0..<20 {
                let data = try await client.rest("GET", "\(path)&limit=1000&offset=\(page * 1000)")
                let chunk = try await Self.decodeOffMain([ReviewState].self, from: data)
                rows += chunk
                if chunk.count < 1000 { break }
            }
        } catch {
            return
        }
        guard client.userId == uid else { return }
        reviews = Dictionary(rows.map { ($0.stickerId, $0) }, uniquingKeysWith: { a, _ in a })
        keepSampleReview()
    }

    /// Same number the review screen shows (srs.ts retentionNow; origin = last review, else the catch).
    func memoryPercent(for sticker: Sticker) -> Int? {
        guard let r = reviews[sticker.id] else { return nil }
        return MemoryMath.percent(intervalDays: r.intervalDays, ease: r.ease, last: r.lastReviewedAt ?? sticker.takenAt)
    }

    /// The small companion the web uploads next to a photo (`<path>.thumb.webp`, since 2026-07).
    static let thumbSuffix = ".thumb.webp"

    func url(for path: String?, preferThumb: Bool = true) -> URL? {
        guard let path else { return nil }
        if preferThumb, let t = signed[path + Self.thumbSuffix] { return t }
        return signed[path]
    }

    /// `rows` newest first (as read): the pictures on screen first — the album's and the dex's own picture of each
    /// word before its others.
    private func signPaths(for rows: [Sticker]) async {
        var paths: [String] = []
        for s in rows {
            let all = [s.homePath, s.dexImagePath, s.cutoutImageUrl, s.objectImageUrl, s.selfieImageUrl, s.placeholderImageUrl]
            for p in all.compactMap({ $0 }) where signed[p] == nil {
                paths.append(p)
            }
        }
        await sign(paths)
    }

    /// Server rows decoded off the main thread.
    nonisolated private static func decodeOffMain<T: Decodable & Sendable>(_ type: T.Type, from data: Data) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try SupabaseDate.decoder.decode(T.self, from: data) }.value
    }

    // MARK: - Signed links on demand

    /// When each path's link was made. Links last 6 hours (`signedURLs`); older than 5 they are made again.
    @ObservationIgnored private var signedAt: [String: Date] = [:]
    @ObservationIgnored private var signQueue: Set<String> = []
    @ObservationIgnored private var signTask: Task<Void, Never>?
    /// The last time a link was made again because it failed (at most once every 2 minutes per path).
    @ObservationIgnored private var forcedAt: [String: Date] = [:]
    /// Paths whose link failed and is being made again: the new link replaces the old one (`applySigned`).
    @ObservationIgnored private var forced: Set<String> = []
    private static let linkLifetime: TimeInterval = 5 * 3600

    /// Signs the paths (and their thumbnails) in batches of 100 pairs, in the order given (the first batch holds the
    /// pictures on screen), up to 4 batches at a time — one after another, a big dex's last pictures waited for every
    /// batch before them (and a set's random order put the newest words anywhere among them). A failed batch is simply
    /// asked again later.
    private func sign(_ paths: [String]) async {
        var seen = Set<String>()
        // The sample word's pictures are in the app bundle: nothing to sign.
        let unique = paths.filter { !SampleSticker.isSamplePath($0) && seen.insert($0).inserted }
        guard !unique.isEmpty, client.session != nil else { return }
        let uid = client.userId
        let chunks = stride(from: 0, to: unique.count, by: 100).map { Array(unique[$0..<min($0 + 100, unique.count)]) }
        let client = self.client
        let suffix = Self.thumbSuffix
        // Batch i's paths with their thumbnails' (4 at most in flight; the next starts as one comes back).
        let requests = chunks.map { chunk in (chunk: chunk, all: chunk.flatMap { [$0, $0 + suffix] }) }
        await withTaskGroup(of: (chunk: [String], map: [String: URL]?).self) { group in
            var next = 0
            while next < min(4, requests.count) {
                let r = requests[next]
                next += 1
                group.addTask {
                    let map = try? await client.signedURLs(for: r.all)
                    return (r.chunk, map)
                }
            }
            while let done = await group.next() {
                if next < requests.count {
                    let r = requests[next]
                    next += 1
                    group.addTask {
                        let map = try? await client.signedURLs(for: r.all)
                        return (r.chunk, map)
                    }
                }
                guard let map = done.map, client.userId == uid else { continue }
                applySigned(map, for: done.chunk)
            }
        }
    }

    private func applySigned(_ map: [String: URL], for chunk: [String]) {
        let now = Date()
        // A link still fresh is kept: the same path signed twice at once (the dex read and a picture on screen asking)
        // swapped its URL, and a picture's download is keyed on its URL — it started over (`StickerImage`). A link
        // asked for because it failed (`forced`) is always replaced.
        for (key, url) in map {
            let base = key.hasSuffix(Self.thumbSuffix) ? String(key.dropLast(Self.thumbSuffix.count)) : key
            if signed[key] != nil, !forced.contains(base), let at = signedAt[base], now.timeIntervalSince(at) < Self.linkLifetime {
                continue
            }
            signed[key] = url
        }
        for p in chunk where map[p] != nil {
            if forced.remove(p) != nil || signedAt[p].map({ now.timeIntervalSince($0) >= Self.linkLifetime }) ?? true {
                signedAt[p] = now
            }
        }
        let gone = chunk.filter { map[$0] == nil && map[$0 + Self.thumbSuffix] == nil }
        if !gone.isEmpty { missingPaths.formUnion(gone) }
        let back = chunk.filter { map[$0] != nil && missingPaths.contains($0) }
        if !back.isEmpty { missingPaths.subtract(back) }
    }

    /// A picture on screen has no working link (`StickerImage`): sign it now, together with any others asked for in
    /// the same moment. `force`: the link failed (expired, or the request broke) — a new one, at most every 2 minutes.
    func requestSigning(_ path: String, force: Bool = false) {
        guard client.session != nil, !path.isEmpty else { return }
        if force {
            if let last = forcedAt[path], Date().timeIntervalSince(last) < 120 { return }
            forcedAt[path] = Date()
            forced.insert(path)
        } else if signed[path] != nil, let at = signedAt[path], Date().timeIntervalSince(at) < Self.linkLifetime {
            return
        }
        signQueue.insert(path)
        guard signTask == nil else { return }
        signTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self else { return }
            let batch = Array(self.signQueue)
            self.signQueue = []
            self.signTask = nil
            await self.sign(batch)
        }
    }

    /// Back in the app after a long time: every link older than 5 hours is made again before a picture needs it.
    func refreshStaleLinks() {
        let now = Date()
        let stale = signedAt.filter { now.timeIntervalSince($0.value) > Self.linkLifetime }.map(\.key)
        guard !stale.isEmpty else { return }
        Task { await sign(stale) }
    }

    // MARK: - The dex kept on this phone (shown at once on launch)

    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    /// The server's read has put its rows on screen (the snapshot, read at the same time, must not replace them).
    @ObservationIgnored private var serverAnswered = false

    /// Before the server answers: the dex as it was last read on this phone for this account, learning language
    /// and display language (`DexSnapshot`). Only on an empty dex; `load` replaces it a moment later.
    ///
    /// The file is read and decoded off the main thread (a big dex's snapshot is megabytes of JSON: decoding it on the
    /// main thread held the first screen), at the same time as the server's read; whichever comes second never
    /// replaces the server's answer.
    func restoreSnapshot() async {
        guard stickers.isEmpty, let uid = client.userId else { return }
        let lang = language
        let reader = L10n.lang
        let saved = await Task.detached(priority: .userInitiated) {
            DexSnapshot.load(uid: uid, lang: lang, reader: reader)
        }.value
        guard let saved, !serverAnswered, stickers.isEmpty, client.userId == uid, language == lang else { return }
        stickers = saved.stickers
        albumHidden = Set(saved.albumHidden).union(localAlbumHidden())
        var places: [String: DayLayoutSticker] = [:]
        for p in saved.placements {
            places[p.id] = DayLayoutSticker(id: p.id, albumOrder: p.order, albumSize: p.size.flatMap(AlbumSize.init(rawValue:)),
                                            albumX: p.x, albumY: p.y, albumScale: p.scale, albumRot: p.rot)
        }
        albumPlacements = places
        hasLoaded = true
        restoreUnsaved()
        installSample()
        UITestTrace.once("dex snapshot restored", "words=\(stickers.count)")
    }

    /// Writes the snapshot a moment after the dex changed (many changes in a row are written once).
    private func scheduleSnapshot() {
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.persistSnapshot()
        }
    }

    private func persistSnapshot() {
        // Only a dex the server has answered for (never an empty one before the first read).
        guard hasLoaded, let uid = client.userId else { return }
        let placements = albumPlacements.values.map {
            DexSnapshot.Placement(id: $0.id, order: $0.albumOrder, size: $0.albumSize?.rawValue,
                                  x: $0.albumX, y: $0.albumY, scale: $0.albumScale, rot: $0.albumRot)
        }
        let payload = DexSnapshot.Payload(version: DexSnapshot.version,
                                          stickers: stickers.filter { !Self.isProvisional($0.id) && !$0.isSample },
                                          albumHidden: Array(albumHidden), placements: placements)
        let lang = language
        let reader = L10n.lang
        Task.detached(priority: .utility) { DexSnapshot.save(payload, uid: uid, lang: lang, reader: reader) }
    }

    // MARK: - Pictures put on disk ahead

    /// The newest words' pictures as their pages and the review show them (the cut-out, full size), so opening
    /// one never waits for a download. Low priority, one at a time; already kept files are skipped.
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?

    private func prefetchNewest(limit: Int = 60) {
        prefetchTask?.cancel()
        let paths = stickers.prefix(limit).compactMap(\.dexImagePath)
        prefetchTask = Task(priority: .utility) { [weak self] in
            for path in paths {
                guard let self, !Task.isCancelled else { return }
                guard !ImageCache.shared.hasFile(for: path), let url = self.url(for: path, preferThumb: false) else { continue }
                await ImageCache.shared.prefetch(url: url, key: path)
            }
        }
    }

    /// Puts these pictures (full size) on disk now — the review's next cards. Signs them first when needed.
    func prefetchPictures(_ paths: [String]) async {
        let missing = paths.filter { signed[$0] == nil }
        if !missing.isEmpty { await sign(missing) }
        for path in paths where !ImageCache.shared.hasFile(for: path) {
            guard let url = url(for: path, preferThumb: false) else { continue }
            await ImageCache.shared.prefetch(url: url, key: path)
        }
    }

    // MARK: - Re-encounter photos (the dex square cycles through them)

    /// sticker id → the pictures of its re-encounters (`encounters`), oldest first: the cut-out when there is one.
    var encounterPhotos: [String: [DexPicture]] = [:]
    /// sticker id → the picture of a re-encounter just recorded on this phone: its word's square shows it first,
    /// as the star flies it in (owner 2026-10-11: 「同じ単語でも図鑑に追加するアニメーションを追加して」).
    private var freshEncounters: [String: DexPicture] = [:]

    /// One read of every re-encounter photo of this account (RLS: the owner's own rows), signed together.
    /// A server without the photo columns, or no connection, leaves the squares on their one picture.
    func loadEncounterPhotos() async {
        struct Row: Decodable {
            let id: String?
            let sticker_id: String
            let image_path: String?
            let cutout_path: String?
            let location_name: String?
            let created_at: Date?
        }
        guard let uid = client.userId,
              let rows = try? await readAll("encounters?select=id,sticker_id,image_path,cutout_path,location_name,created_at&user_id=eq.\(uid)&order=created_at.asc,id.asc",
                                            as: Row.self, decoder: SupabaseDate.decoder),
              client.userId == uid else { return }
        var out: [String: [DexPicture]] = [:]
        var entries: [EncounterEntry] = []
        for r in rows {
            let cut = r.cutout_path.flatMap { $0.isEmpty ? nil : $0 }
            let image = r.image_path.flatMap { $0.isEmpty ? nil : $0 }
            if let id = r.id, let at = r.created_at, cut != nil || image != nil {
                entries.append(EncounterEntry(id: id, stickerId: r.sticker_id, image: image, cutout: cut,
                                              place: r.location_name, at: at))
            }
            guard let p = cut ?? image, out[r.sticker_id]?.contains(where: { $0.path == p }) != true else { continue }
            out[r.sticker_id, default: []].append(DexPicture(path: p, isCutout: cut != nil))
        }
        encounterPhotos = out
        // A re-encounter recorded on this phone meanwhile (its row may not be readable yet) keeps its album page.
        let pendingLocal = encounterEntries.filter { e in
            e.id.hasPrefix("local-") && !entries.contains { $0.stickerId == e.stickerId && abs($0.at.timeIntervalSince(e.at)) < 120 }
        }
        encounterEntries = entries + pendingLocal
        // The album shows the photo or the cut-out (設定 › ホームに表示する写真): both are signed.
        let paths = out.values.flatMap { $0 }.map(\.path) + entries.flatMap { [$0.image, $0.cutout].compactMap { $0 } }
        await sign(paths.filter { signed[$0] == nil })
    }

    // MARK: - Re-encounters in the home album

    /// A re-encounter with a photo (`encounters`): a page of the home album on the day it was met, like a catch
    /// (owner 2026-10-15: 再会した単語の切り抜きもホームのアルバムに出す).
    nonisolated struct EncounterEntry: Equatable, Sendable {
        let id: String
        let stickerId: String
        let image: String?
        let cutout: String?
        let place: String?
        let at: Date
    }

    /// Every re-encounter photo of this account, oldest first (read with `loadEncounterPhotos`; one recorded on this
    /// phone is added at once by `recordEncounter`).
    private(set) var encounterEntries: [EncounterEntry] = []

    #if DEBUG
    /// `-uiPreview`: re-encounters as the server would list them (the word page's slideshow).
    func seedEncountersForPreview(_ entries: [EncounterEntry]) { encounterEntries = entries }
    #endif

    /// Album entries for re-encounters carry this prefix before the encounter's id (they are not stickers).
    nonisolated static let encounterAlbumPrefix = "encounter-"

    nonisolated static func isEncounterAlbumEntry(_ id: String) -> Bool { id.hasPrefix(encounterAlbumPrefix) }

    /// The re-encounter photos as album entries: the new photo and its cut-out, the place and day it was met, standing
    /// for the word it was met again as (this learning language's words only).
    var albumEncounters: [Sticker] {
        guard !encounterEntries.isEmpty else { return [] }
        let byId = Dictionary(stickers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return encounterEntries.compactMap { e in
            guard let base = byId[e.stickerId] else { return nil }
            return Sticker(id: Self.encounterAlbumPrefix + e.id, wordId: base.wordId, objectImageUrl: e.image,
                           cutoutImageUrl: e.cutout, selfieImageUrl: nil, caption: nil, locationName: e.place,
                           takenAt: e.at, captureType: base.captureType, word: base.word)
        }
    }

    /// The word an album entry opens: a re-encounter's page is its word's own sticker.
    func albumOwner(_ s: Sticker) -> Sticker {
        guard Self.isEncounterAlbumEntry(s.id) else { return s }
        let eid = String(s.id.dropFirst(Self.encounterAlbumPrefix.count))
        guard let e = encounterEntries.first(where: { $0.id == eid }), let base = sticker(id: e.stickerId) else { return s }
        return base
    }

    /// Every picture of the word this square stands for (web `DexCyclingPhoto`): the square's own first, then the
    /// word's other catches, then the re-encounters — each the cut-out where there is one. At most 8. A re-encounter
    /// just recorded on this phone comes before all of them (`freshEncounters`).
    func dexPictures(for sticker: Sticker) -> [DexPicture] {
        let key = DexCatalog.norm(sticker.word?.headword ?? "", lang: language)
        let others = key.isEmpty ? [] : (stickersByHeadword()[key] ?? []).filter { $0.id != sticker.id }
        var out: [DexPicture] = []
        for s in [sticker] + others {
            if let p = freshEncounters[s.id], !out.contains(where: { $0.path == p.path }) { out.append(p) }
        }
        for s in [sticker] + others {
            let own = dexPicture(of: s).map { [$0] } ?? []
            for p in own + (encounterPhotos[s.id] ?? []) where !out.contains(where: { $0.path == p.path }) {
                out.append(p)
            }
        }
        return Array(out.prefix(8))
    }

    private func stickersByHeadword() -> [String: [Sticker]] {
        let lang = language
        if let c = headwordIndex, c.version == stickersVersion, c.lang == lang { return c.map }
        var map: [String: [Sticker]] = [:]
        for s in stickers {
            let k = DexCatalog.norm(s.word?.headword ?? "", lang: lang)
            if !k.isEmpty { map[k, default: []].append(s) }
        }
        for k in map.keys { map[k]?.sort { $0.takenAt < $1.takenAt } }
        headwordIndex = (stickersVersion, lang, map)
        return map
    }

    /// A word's own dex picture: the cut-out, else the photo, else its internet stand-in — skipping a file the
    /// storage does not have (that left the square blank).
    func dexPicture(of s: Sticker) -> DexPicture? {
        if let c = s.cutoutImageUrl, !missingPaths.contains(c), !blankCutouts.contains(c) {
            return DexPicture(path: c, isCutout: true)
        }
        if let o = s.objectImageUrl, !missingPaths.contains(o) { return DexPicture(path: o, isCutout: false) }
        if let p = s.placeholderImageUrl, !missingPaths.contains(p) { return DexPicture(path: p, isCutout: false) }
        return nil
    }

    /// Puts in memory, from the phone's copies, the pictures a catch's landing shows first: the squares of the category
    /// the word lands in (owner 2026-10-15: the dex went blank during the add animation — every square of the freshly drawn
    /// dex page was read from disk while it rose). Started on the GET moment and again on 「図鑑に追加」; squares further
    /// away load as they come on screen, as ever.
    func warmLanding(headword: String, categoryKey: String?) {
        let category = DexCatalog.item(headword: headword, lang: language)?.category ?? DexCatalog.category(forKey: categoryKey)
        let words = DexBook.words(stickers, lang: language).filter { DexBook.category(of: $0, lang: language) == category }
        for w in words.prefix(40) {
            guard let p = dexPicture(of: w) else { continue }
            let key = signed[p.path + Self.thumbSuffix] != nil ? p.path + Self.thumbSuffix : p.path
            guard ImageCache.shared.image(for: key) == nil else { continue }
            Task(priority: .userInitiated) { _ = await ImageCache.shared.cached(for: key) }
        }
    }

    // MARK: - Save a catch

    /// Saves a new catch through the web's own `saveSticker` (stickers.functions.ts): the same
    /// word upsert, extras merge (service role), first-catch event and
    /// duplicate guard as the web. Photos are uploaded first, one at a time (`upload`); a failed cutout or
    /// selfie never blocks the catch.
    ///
    /// `ts` names the uploaded files (a provisional entry made by `addProvisional` already shows the photos
    /// under those names). `replacing`: that provisional entry is swapped for the saved one in place, and
    /// `adopted` runs at that very moment (the caller moves anything pointing at the provisional id).
    ///
    /// A failure is thrown as a `CatchSaveError` naming the step (photos or row) with the photos already in storage, so
    /// the caller keeps the word in 「保存待ち」 and a retry saves the row with them. Every try sends the catch's own id
    /// (`client_catch_id`): when the first answer was lost after the server had saved it, the retry gets that sticker back.
    ///
    /// `holdCategory`: a catch still landing — when the server filed the word under another category than its provisional
    /// entry, its square keeps the provisional one until `settleLanding` (the landing is over).
    func save(_ draft: CatchDraft, ts given: Int? = nil, replacing provisionalId: String? = nil, holdCategory: Bool = false,
              adopted: ((Sticker) -> Void)? = nil) async throws -> SaveOutcome {
        guard let uid = client.userId else { throw APIError.unauthorized }
        guard let card = draft.details else { throw APIError.message(L("カード生成に失敗しました")) }
        let paths: CatchUploads
        if let done = draft.uploaded {
            // A 「保存待ち」 catch whose photos went up on an earlier try: only the row is saved — after the cut-out and the
            // selfie that did not go up then (each may fail: the catch is saved without it).
            let stamp = Self.uploadStamp()
            var cut = done.cutout
            if cut == nil { cut = await uploadPNG(draft.cutout, uid: uid, ts: stamp, kind: "cutout") }
            var sel = done.selfie
            if sel == nil, let found = try? await uploadJPEG(draft.selfie, uid: uid, ts: stamp, kind: "selfie") { sel = found }
            paths = CatchUploads(object: done.object, cutout: cut, selfie: sel)
        } else if let pre = draft.uploads, pre.uid == uid, let done = try? await pre.task.value {
            // The card catch's photos went up while the card was on screen (`preupload`): only the row is saved.
            paths = done
        } else {
            // Nothing uploaded ahead (or that upload failed: a fresh stamp then, since uploads never overwrite
            // a file it may have written).
            let ts = draft.uploads == nil ? (given ?? Self.uploadStamp()) : Self.uploadStamp()
            do {
                paths = try await upload(photo: draft.photo, cutout: draft.cutout, selfie: draft.selfie, uid: uid, ts: ts)
            } catch {
                guard client.userId == uid else { throw Self.accountChanged }
                throw CatchSaveError(stage: .upload, underlying: error, uploads: nil)
            }
        }
        // The save runs behind the dex (card catch): someone may have signed out, or into another account,
        // meanwhile. The row then must never be written to the account now signed in.
        guard client.userId == uid else { throw Self.accountChanged }
        let obj = paths.object
        let cut = paths.cutout
        let selfieRef = paths.selfie

        let word = Self.wordFields(draft.candidate, card)
        let caption = draft.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = draft.language ?? NativeAPI.targetLanguage
        let data: [String: Any] = [
            "client_catch_id": draft.catchId,
            "word": word,
            // Custom shelves are gone from the app (owner 2026-10-02): never ask the server to make one.
            "new_shelf": NSNull(),
            "language": language,
            "object_path": orNull(obj),
            "cutout_path": orNull(cut),
            "selfie_path": orNull(selfieRef),
            "caption": orNull(caption.isEmpty ? nil : caption),
            "location_name": orNull(draft.placeName),
            "lat": orNull(draft.location?.coordinate.latitude),
            "lng": orNull(draft.location?.coordinate.longitude),
        ]
        struct Saved: Decodable {
            let id: String
            let wordId: String?
            enum CodingKeys: String, CodingKey { case id, wordId = "word_id" }
        }
        let saved: Saved
        do {
            // Safe to send twice: the server answers a second time with the sticker it made for this `client_catch_id`.
            saved = try await NativeAPI.call("saveSticker", data, as: Saved.self, timeout: 45, asUser: uid, retryOnDrop: true)
        } catch {
            if Self.isAccountChanged(error) || client.userId != uid { throw Self.accountChanged }
            throw CatchSaveError(stage: .save, underlying: error, uploads: paths)
        }
        // Saved to the account that caught it; only this phone's list may now belong to someone else.
        guard client.userId == uid else { throw Self.accountChanged }

        cacheLocal(path: obj, image: draft.photo)
        cacheLocal(path: cut, image: draft.cutout)
        cacheLocal(path: selfieRef, image: draft.selfie)
        // Its cut-out did not go up (after its tries): the catch is saved without it, and the very cut-out is kept and
        // attached a little later (`CutoutBackfill.keep`: the album and the dex get their sticker then).
        if cut == nil, let lost = draft.cutout {
            CutoutBackfill.keep(lost, for: saved.id)
            let sid = saved.id
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard let self, let s = self.sticker(id: sid), CutoutBackfill.needsCutout(s) else { return }
                await CutoutBackfill.shared.make(for: s, dex: self)
            }
        }
        let sticker: Sticker
        if let fresh = try? await fetchSticker(id: saved.id), client.userId == uid {
            sticker = fresh
        } else {
            // The catch IS saved — only reading it back failed (the connection dropped right after).
            // Reporting a failure here made the learner save it again; show it from what was sent
            // instead (the next dex load replaces it with the server's row).
            sticker = present([Sticker(
                id: saved.id, wordId: saved.wordId ?? "", objectImageUrl: obj, cutoutImageUrl: cut,
                selfieImageUrl: selfieRef, caption: caption.isEmpty ? nil : caption, locationName: draft.placeName,
                takenAt: Date(), captureType: draft.captureType, word: Self.localWord(word, id: saved.wordId ?? "", language: language),
                lat: draft.location?.coordinate.latitude, lng: draft.location?.coordinate.longitude
            )])[0]
        }
        guard client.userId == uid else { throw Self.accountChanged }
        if let provisionalId { adoptedIds[provisionalId] = sticker.id }
        if let provisionalId { unsaved[provisionalId] = nil }
        var shown = sticker
        if language == self.language {
            stickers.removeAll { $0.id == sticker.id }
            savedSinceLoad.insert(sticker.id)
            if holdCategory, let provisionalId, let old = stickers.first(where: { $0.id == provisionalId }),
               DexBook.category(of: old, lang: language) != DexBook.category(of: sticker, lang: language) {
                let held = HeldCategory(key: old.word?.categoryKey, shelf: old.shelfKey,
                                        realKey: sticker.word?.categoryKey, realShelf: sticker.shelfKey)
                heldCategories[sticker.id] = held
                shown.word?.categoryKey = held.key
                shown.shelfKey = held.shelf
            }
            if let provisionalId, let i = stickers.firstIndex(where: { $0.id == provisionalId }) {
                stickers[i] = shown
            } else {
                stickers.insert(shown, at: 0)
            }
        } else if let provisionalId {
            // Saved for another learning language than the one shown now: it belongs to that dex, not this one.
            stickers.removeAll { $0.id == provisionalId }
        }
        retireSample(ifDuplicating: shown)
        adopted?(shown)
        scheduleSnapshot()
        // The photos are already in the local cache under these paths (`cacheLocal` above): signing never holds
        // the landing or the caller.
        Task { await signPaths(for: [sticker]) }
        saveToPhotosIfEnabled(draft.photo)
        return .created(shown)
    }

    /// A word just saved whose square keeps, until its landing is over, the category its provisional entry landed in
    /// (2026-10-15: 花束, caught before its card came, landed in その他; its saved row — filed under 花 by the server — came
    /// back mid-flight and the square jumped to another category card, leaving the dex blank where it had landed).
    private struct HeldCategory {
        let key: String?
        let shelf: String?
        let realKey: String?
        let realShelf: String?
    }

    @ObservationIgnored private var heldCategories: [String: HeldCategory] = [:]

    /// The landing of `id` is over: its square goes to the category the server filed it under.
    func settleLanding(_ id: String) {
        guard let held = heldCategories.removeValue(forKey: id) else { return }
        replace(id) { old in
            var s = applyReader(old)
            s.word?.categoryKey = held.realKey
            s.shelfKey = held.realShelf
            return s
        }
    }

    /// A save that finished (or stopped) after its account was left. Nothing is shown to whoever is signed in now.
    static let accountChanged = APIError.server(409, "account changed")

    static func isAccountChanged(_ error: Error) -> Bool {
        if case .server(409, "account changed")? = SaveFailure.root(error) as? APIError { return true }
        return false
    }

    // MARK: - Uploads ahead (card catch: the photos go up while the card is on screen)

    /// Starts uploading a catch's photos now, named by a stamp chosen here (a provisional entry made later
    /// shows them from the cache under the same names). nil when signed out.
    func preupload(photo: UIImage, cutout: UIImage?, selfie: UIImage?) -> CatchPreupload? {
        guard let uid = client.userId else { return nil }
        let ts = Self.uploadStamp()
        let task = Task<CatchUploads, Error> {
            try await upload(photo: photo, cutout: cutout, selfie: selfie, uid: uid, ts: ts)
        }
        return CatchPreupload(uid: uid, ts: ts, photo: photo, cutout: cutout, selfie: selfie, task: task)
    }

    /// Photos uploaded ahead for a card that was then left (another word, a new photo, starting over): they
    /// belong to no catch, so they are deleted again once their upload has finished. Best effort.
    func discardPreupload(_ pre: CatchPreupload) {
        let client = client
        Task {
            guard let done = try? await pre.task.value else { return }
            for path in [done.object, done.cutout, done.selfie].compactMap({ $0 }) {
                try? await client.removeObject(path: path, bucket: "stickers")
            }
        }
    }

    /// Photo, cut-out and selfie, one at a time, the photo first and alone; a failed cut-out or selfie never blocks the
    /// catch. Owner 2026-10-15: on a Wi-Fi that dropped connections during the larger uploads, the three sent together on
    /// one connection went down together — nothing of the strawberry cake reached storage in five tries, not even its
    /// photo. Each picture is tried again on its own (`send`), drawn in 8 bits, and a cut-out kept within its budget
    /// (`ImageTools.pngUpload`).
    func upload(photo: UIImage, cutout: UIImage?, selfie: UIImage?, uid: String, ts: Int) async throws -> CatchUploads {
        let obj = try await uploadJPEG(photo, uid: uid, ts: ts, kind: "object")
        let cut = await uploadPNG(cutout, uid: uid, ts: ts, kind: "cutout")
        let sel: String? = try? await uploadJPEG(selfie, uid: uid, ts: ts, kind: "selfie")
        return CatchUploads(object: obj, cutout: cut, selfie: sel)
    }

    // MARK: - Optimistic catch (card catch: the dex opens at once, the save finishes behind it)

    /// Ids of entries shown before their save has finished. Never sent to the server.
    static let provisionalPrefix = "local-"

    static func isProvisional(_ id: String) -> Bool { id.hasPrefix(provisionalPrefix) }

    /// Milliseconds, the uploaded files' name stamp.
    static func uploadStamp() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    /// Shows the catch in the dex right away, before `save` has run: the same word fields `save` sends, the
    /// photos put in the image cache under the very names `save(ts:)` uploads them to (so the saved entry
    /// shows the same pictures with no reload). Returns the entry and the stamp to hand to `save`.
    /// No row is written: an app kill leaves no entry behind (the photo itself stays in 「解析待ち」; photos
    /// uploaded ahead by `preupload` may stay in storage, unreferenced).
    func addProvisional(_ draft: CatchDraft) -> (sticker: Sticker, ts: Int)? {
        guard let uid = client.userId, let card = draft.details else { return nil }
        // Photos already going up for this card: their names (the saved entry then shows the same pictures).
        let ts = draft.uploads.flatMap { $0.uid == uid ? $0.ts : nil } ?? Self.uploadStamp()
        let obj = "\(uid)/\(ts)-object.jpg"
        let cut: String? = draft.cutout == nil ? nil : "\(uid)/\(ts)-cutout.png"
        let selfie: String? = draft.selfie == nil ? nil : "\(uid)/\(ts)-selfie.jpg"
        cacheLocal(path: obj, image: draft.photo)
        cacheLocal(path: cut, image: draft.cutout)
        cacheLocal(path: selfie, image: draft.selfie)
        let caption = draft.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let sticker = Sticker(
            id: Self.provisionalPrefix + UUID().uuidString, wordId: "", objectImageUrl: obj, cutoutImageUrl: cut,
            selfieImageUrl: selfie, caption: caption.isEmpty ? nil : caption, locationName: draft.placeName,
            takenAt: Date(), captureType: draft.captureType,
            word: Self.localWord(Self.wordFields(draft.candidate, card), id: ""),
            lat: draft.location?.coordinate.latitude, lng: draft.location?.coordinate.longitude
        )
        stickers.insert(sticker, at: 0)
        return (sticker, ts)
    }

    /// The background save could not be kept for a retry (signed out meanwhile): the provisional entry goes. Never a
    /// word that was saved (its provisional id was adopted): a failure that comes later never takes a saved word away.
    func discardProvisional(_ id: String) {
        guard Self.isProvisional(id), adoptedIds[id] == nil else { return }
        stickers.removeAll { $0.id == id }
    }

    // MARK: - 「保存待ち」 (a catch whose save failed stays in the dex and is saved again)

    /// Provisional id → its entry in 「解析待ち」 (`PendingCatch.save`), for every catch whose save failed. The word stays in
    /// the dex where it landed, marked 「保存待ち」 (owner 2026-10-15: after 「保存に失敗しました」 花束 and 草莓蛋糕 were gone
    /// from the dex), and is saved again on its own (`PendingRetry`) or from its page — with the same `client_catch_id`,
    /// so a save whose answer was lost is never made twice.
    private(set) var unsaved: [String: String] = [:]
    /// 「保存待ち」 catches being saved right now (by entry id): never two saves of the same catch at once.
    private(set) var retrying: Set<String> = []

    func isUnsaved(_ stickerId: String) -> Bool { unsaved[stickerId] != nil }

    /// A 「保存待ち」 word being saved again right now.
    func isRetrying(_ stickerId: String) -> Bool { unsaved[stickerId].map { retrying.contains($0) } ?? false }

    /// Why a 「保存待ち」 word is waiting (its last failure, in the display language).
    func unsavedReason(_ stickerId: String) -> String? {
        guard let pid = unsaved[stickerId] else { return nil }
        return PendingQueue.shared.item(id: pid)?.reason
    }

    /// The save of a provisional entry failed: everything to save it again is kept with its photo in 「解析待ち」 (a new
    /// entry when the photo had none), the entry stays in the dex as 「保存待ち」. Returns the entry's id (nil: nothing could
    /// be kept — no card at all). Kept for the account signed in now (`PendingQueue`).
    @discardableResult
    func keepUnsaved(_ draft: CatchDraft, provisional: String, ts: Int, pendingId: String?, error: Error) -> String? {
        guard let card = draft.details else { return nil }
        let reason = SaveFailure.message(for: error)
        let id: String
        if let pendingId, PendingQueue.shared.item(id: pendingId) != nil {
            id = pendingId
        } else if let added = PendingQueue.shared.add(image: draft.photo, reason: reason, lat: draft.location?.coordinate.latitude,
                                                      lng: draft.location?.coordinate.longitude) {
            id = added.id
        } else {
            return nil
        }
        let landed = (error as? CatchSaveError)?.uploads ?? draft.uploaded
        let pending = PendingSave(
            catchId: draft.catchId, provisionalId: provisional, ts: ts, language: draft.language ?? language,
            candidate: draft.candidate, card: card.raw, categoryKey: card.categoryKey, exampleSentence: card.exampleSentence,
            exampleTranslation: card.exampleTranslation, caption: draft.caption, placeName: draft.placeName,
            lat: draft.location?.coordinate.latitude, lng: draft.location?.coordinate.longitude, captureType: draft.captureType,
            takenAt: sticker(id: provisional)?.takenAt ?? Date(), hasCutout: draft.cutout != nil, hasSelfie: draft.selfie != nil,
            uploads: landed.map { SavedUploads($0) }, readerLang: L10n.lang
        )
        PendingQueue.shared.markUnsaved(id: id, save: pending, cutout: draft.cutout, selfie: draft.selfie, reason: reason)
        unsaved[provisional] = id
        return id
    }

    /// The 「保存待ち」 words of this account and learning language, back in the dex (launch, a reload, another learning
    /// language): an app kill never loses them. Their pictures come from the phone (the image cache, else the files kept
    /// with the photo).
    func restoreUnsaved() {
        guard let uid = client.userId else { return }
        for item in PendingQueue.shared.unsavedItems() {
            guard let ps = item.save, ps.language == language else { continue }
            unsaved[ps.provisionalId] = item.id
            guard !stickers.contains(where: { $0.id == ps.provisionalId }) else { continue }
            let obj = ps.uploads?.object ?? "\(uid)/\(ps.ts)-object.jpg"
            let cut: String? = ps.hasCutout ? (ps.uploads?.cutout ?? "\(uid)/\(ps.ts)-cutout.png") : nil
            let selfie: String? = ps.hasSelfie ? (ps.uploads?.selfie ?? "\(uid)/\(ps.ts)-selfie.jpg") : nil
            if !ImageCache.shared.hasFile(for: obj), let img = PendingQueue.shared.image(for: item) { cacheLocal(path: obj, image: img) }
            if let cut, !ImageCache.shared.hasFile(for: cut), let img = PendingQueue.shared.cutout(for: item) { cacheLocal(path: cut, image: img) }
            if let selfie, !ImageCache.shared.hasFile(for: selfie), let img = PendingQueue.shared.selfie(for: item) {
                cacheLocal(path: selfie, image: img)
            }
            let caption = ps.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let entry = Sticker(
                id: ps.provisionalId, wordId: "", objectImageUrl: obj, cutoutImageUrl: cut, selfieImageUrl: selfie,
                caption: caption.isEmpty ? nil : caption, locationName: ps.placeName, takenAt: ps.takenAt,
                captureType: ps.captureType,
                word: Self.localWord(Self.wordFields(ps.candidate, ps.details, readerLang: ps.readerLang ?? L10n.lang), id: "",
                                     language: ps.language),
                lat: ps.lat, lng: ps.lng
            )
            stickers.insert(entry, at: 0)
        }
    }

    /// Saves a 「保存待ち」 catch again: the same word, card and photos (only those not in storage yet go up), the same
    /// `client_catch_id`. Done: the entry becomes the saved sticker in place and leaves 「解析待ち」. A failure is kept as its
    /// new reason (and in the developer log) and thrown; the word stays.
    @discardableResult
    func retryUnsaved(pendingId: String) async throws -> SaveOutcome {
        guard let item = PendingQueue.shared.item(id: pendingId), let ps = item.save else { throw CancellationError() }
        guard !retrying.contains(pendingId) else { throw CancellationError() }
        retrying.insert(pendingId)
        defer { retrying.remove(pendingId) }
        PendingQueue.shared.setSaving(pendingId, true)
        let photo = PendingQueue.shared.image(for: item) ?? CaptureViewModel.textCard(for: ps.candidate.headword)
        let location: CLLocation? = {
            guard let lat = ps.lat, let lng = ps.lng else { return nil }
            return CLLocation(latitude: lat, longitude: lng)
        }()
        var draft = CatchDraft(candidate: ps.candidate, details: ps.details, photo: photo, cutout: PendingQueue.shared.cutout(for: item),
                               selfie: PendingQueue.shared.selfie(for: item), caption: ps.caption, location: location,
                               placeName: ps.placeName, captureType: ps.captureType)
        draft.catchId = ps.catchId
        draft.uploaded = ps.uploads?.uploads
        draft.language = ps.language
        let provisional = ps.provisionalId
        do {
            let outcome = try await save(draft, replacing: stickers.contains { $0.id == provisional } ? provisional : nil)
            PendingQueue.shared.remove(id: pendingId)
            PendingRetry.shared.forget(pendingId)
            unsaved[provisional] = nil
            DevLog.shared.add("save", "\(ps.candidate.headword): saved on a retry (\(outcome.sticker.id))")
            return outcome
        } catch {
            if let landed = (error as? CatchSaveError)?.uploads {
                PendingQueue.shared.updateSave(id: pendingId) { $0.uploads = SavedUploads(landed) }
            }
            if !Self.isAccountChanged(error), !(error is CancellationError) {
                PendingQueue.shared.updateReason(id: pendingId, reason: SaveFailure.message(for: error))
                DevLog.shared.add("save", SaveFailure.log(error, headword: ps.candidate.headword) + " (retry)")
            }
            PendingQueue.shared.setSaving(pendingId, false)
            throw error
        }
    }

    #if DEBUG
    /// DEBUG previews (`-uiPreview unsaved`): this entry shown as 「保存待ち」 without a save having run.
    func previewUnsaved(_ stickerId: String, pendingId: String) { unsaved[stickerId] = pendingId }
    #endif

    /// Saves the 「保存待ち」 word shown as `stickerId` again (its page's 「もう一度保存」).
    @discardableResult
    func retryUnsaved(stickerId: String) async throws -> SaveOutcome {
        guard let pid = unsaved[stickerId] else { throw CancellationError() }
        return try await retryUnsaved(pendingId: pid)
    }

    /// The learner threw a 「保存待ち」 word away (its page's 削除, or swiped off 「解析待ち」): the entry, its kept photo and
    /// any photos already in storage go. Nothing was written to the server for it.
    func discardUnsaved(pendingId: String) {
        let ps = PendingQueue.shared.item(id: pendingId)?.save
        PendingQueue.shared.remove(id: pendingId)
        PendingRetry.shared.forget(pendingId)
        if let ps {
            unsaved[ps.provisionalId] = nil
            stickers.removeAll { $0.id == ps.provisionalId }
            if let up = ps.uploads {
                let client = client
                Task {
                    for path in [up.object, up.cutout, up.selfie].compactMap({ $0 }) {
                        try? await client.removeObject(path: path, bucket: "stickers")
                    }
                }
            }
        }
    }

    /// The `words` fields `saveSticker` gets for a catch.
    private static func wordFields(_ c: Candidate, _ card: CardDetails, readerLang: String = L10n.lang) -> [String: Any] {
        let raw = card.raw
        func text(_ key: String, _ fallback: String) -> String {
            let v = raw?[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return v.isEmpty ? fallback : v
        }
        var word: [String: Any] = [
            // The picked name is the headword (capture.tsx `selectedHead`), not the card's own guess.
            "headword": c.headword,
            "reading_zhuyin": text("reading_zhuyin", c.zhuyin),
            "pinyin": text("pinyin", c.pinyin),
            "meaning_ja": text("meaning_ja", c.meaningJa.isEmpty ? c.headword : c.meaningJa),
            "part_of_speech": text("part_of_speech", c.pos.isEmpty ? NativeAPI.defaultPos : c.pos),
            "category_key": text("category_key", card.categoryKey),
            "example_sentence": text("example_sentence", card.exampleSentence),
            "example_translation": text("example_translation", card.exampleTranslation),
        ]
        // The meaning and notes are this reader's (the candidate's and the card's are written in the display language):
        // marked so (`explain_lang`), the shared row's rule (`ReaderLanguage.sharedTextIsFor`) shows them to this reader
        // while the word is shown from these fields, and a server without its receipts stores the right mark.
        var extras: [String: Any] = [:]
        if let e = raw?["extras"], case .object = e, let obj = e.foundation as? [String: Any] { extras = obj }
        if ((extras["explain_lang"] as? String) ?? "").isEmpty { extras["explain_lang"] = readerLang }
        word["extras"] = extras
        // The word's exam level is not used on iOS (owner 2026-10-03). The server's own value from `generateCard`
        // is handed back untouched when there is one: without it saveSticker would store its default "TOCFL-2"
        // (stickers.functions.ts SaveStickerInput), which is wrong for English and Japanese words.
        if let lv = raw?["level"]?.string, !lv.isEmpty {
            word["level"] = lv
        } else if raw == nil {
            // Saved before its card arrived (`CaptureViewModel.provisionalDetails`): an empty level is stored as none
            // (never the "TOCFL-2" default), and the card fills it in later (`fillCard`).
            word["level"] = ""
        }
        return word
    }

    /// A catch saved before its card arrived (「図鑑に追加」 no longer waits for it, owner 2026-10-10): the card's notes
    /// go to the reader's explanation and fill the word's empty shared columns (`updateWordExtras` — the same path as
    /// the detail page's `generateExplanation`; it never overwrites what is already there).
    func fillCard(wordId: String, card: CardDetails) async {
        guard let raw = card.raw, case .object = raw else { return }
        let fields = raw.foundation as? [String: Any] ?? [:]
        guard let extras = fields["extras"] as? [String: Any] else { return }
        var data: [String: Any] = ["word_id": wordId, "extras": extras]
        var patch: [String: Any] = [:]
        for k in ["reading_zhuyin", "pinyin", "part_of_speech", "level", "example_sentence", "example_translation", "meaning_ja"] {
            if let v = fields[k] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { patch[k] = v }
        }
        if !patch.isEmpty { data["patch"] = patch }
        _ = try? await NativeAPI.call("updateWordExtras", data, timeout: 30)
    }

    /// A `Word` made from the fields sent to `saveSticker` (shown until the server's row is read).
    private static func localWord(_ fields: [String: Any], id: String, language: String? = nil) -> Word? {
        var w = fields
        w["id"] = id
        w["language"] = language ?? NativeAPI.targetLanguage
        // The headword stands in for a missing meaning only in what is sent (`wordFields`): never shown as the meaning.
        if (w["meaning_ja"] as? String) == (w["headword"] as? String) { w["meaning_ja"] = "" }
        // Shown through the same reader-language rule as the server's words (a 保存待ち word caught in another
        // display language shows only its learning-language parts).
        return (try? JSONSerialization.data(withJSONObject: w)).flatMap { try? JSONDecoder().decode(Word.self, from: $0) }
            .map { ReaderLanguage.resolve($0, explanation: nil, readerMeaning: nil, reader: L10n.lang) }
    }

    private func fetchSticker(id: String) async throws -> Sticker {
        let data = try await selectStickers { "stickers?id=eq.\(id)&select=\($0)&limit=1" }
        guard let s = try SupabaseDate.decoder.decode([Sticker].self, from: data).first else { throw APIError.decoding }
        return present([s])[0]
    }

    // MARK: - Reader language

    /// Remembers the shared words and returns the stickers as this reader should see them.
    private func present(_ rows: [Sticker]) -> [Sticker] {
        for s in rows { if let w = s.word { sharedWords[s.wordId] = w } }
        if readerKey != L10n.lang {
            readerKey = L10n.lang
            explanations = [:]
            levels = [:]
            readerMeanings = [:]
        }
        let out = rows.map(applyReader)
        let missing = Set(rows.map(\.wordId)).subtracting(readerMeanings.keys)
        if !missing.isEmpty { Task { await loadReaderMeanings(Array(missing)) } }
        return out
    }

    private func applyReader(_ s: Sticker) -> Sticker {
        guard let shared = sharedWords[s.wordId] ?? s.word else { return s }
        var s = s
        // A word saved under the band rule shows only its band's examples and chunks — none until they are read (S6).
        let level = levels[s.wordId] ?? (ReaderLanguage.LevelContent.isBand(s.levelBand)
            ? ReaderLanguage.LevelContent(band: s.levelBand ?? "") : nil)
        s.word = ReaderLanguage.resolve(shared, explanation: explanations[s.wordId],
                                        readerMeaning: readerMeanings[s.wordId], reader: L10n.lang, level: level)
        // Still landing: the category it landed in (`settleLanding`).
        if let held = heldCategories[s.id] {
            s.word?.categoryKey = held.key
            s.shelfKey = held.shelf
        }
        return s
    }

    /// The display language changed: drop what was read for the old one and read again.
    func readerLanguageChanged() {
        guard readerKey != L10n.lang else { return }
        readerKey = L10n.lang
        explanations = [:]
        levels = [:]
        readerMeanings = [:]
        // The sample word is written again for the new language from its file (`applyReader` would blank it: its text
        // is marked for the old one). Provisional entries and the sample have no word id to ask the server about.
        stickers = stickers.map { $0.isSample ? (SampleSticker.make(reader: L10n.lang, takenAt: $0.takenAt) ?? $0) : applyReader($0) }
        let ids = Array(Set(stickers.map(\.wordId))).filter { !$0.isEmpty }
        Task { await loadReaderMeanings(ids, afterLanguageSwitch: true) }
    }

    // MARK: - The sample word (SampleSticker: on this phone only)

    /// This account's words, the bundled sample left out (praise, the widgets, the statistics count the learner's own).
    var wordCount: Int { stickers.filter { !$0.isSample }.count }

    /// Puts the sample word in the dex when this account has it (`SampleSticker.isEnabled`): after onboarding, and at
    /// every read of the dex (it is kept in no snapshot and on no server). A real 珍珠奶茶 retires it for good.
    func installSample() {
        guard let uid = client.userId, language == "zh-TW", SampleSticker.isEnabled(userId: uid) else { return }
        guard !stickers.contains(where: { $0.isSample }) else { return }
        let key = DexCatalog.norm(SampleSticker.headword, lang: language)
        if stickers.contains(where: { !$0.isSample && DexCatalog.norm($0.word?.headword ?? "", lang: language) == key }) {
            SampleSticker.markDeleted(userId: uid)
            return
        }
        guard SampleSticker.image() != nil,
              let sample = SampleSticker.make(reader: L10n.lang, takenAt: SampleSticker.addedAt(userId: uid)) else { return }
        SampleSticker.seedReadings()
        let at = stickers.firstIndex { $0.takenAt < sample.takenAt } ?? stickers.count
        stickers.insert(sample, at: at)
        keepSampleReview()
    }

    /// The learner caught the real word: the sample has done its job.
    func retireSample(ifDuplicating saved: Sticker) {
        guard !saved.isSample, let sample = stickers.first(where: { $0.isSample }),
              DexCatalog.norm(saved.word?.headword ?? "", lang: language) == DexCatalog.norm(sample.word?.headword ?? "", lang: language)
        else { return }
        stickers.removeAll { $0.isSample }
        reviews[sample.id] = nil
        SampleSticker.markDeleted(userId: client.userId)
    }

    /// The sample's review state (kept on this phone) next to the server's rows, whenever those are read again.
    private func keepSampleReview() {
        guard let uid = client.userId, stickers.contains(where: { $0.isSample }) else { return }
        reviews[SampleSticker.id] = SampleSticker.reviewState(userId: uid)
    }

    /// web `getReaderMeanings`: the meanings written in the reader's language, 200 words at a time.
    private func loadReaderMeanings(_ ids: [String], afterLanguageSwitch: Bool = false) async {
        let lang = L10n.lang
        var i = 0
        while i < ids.count {
            let chunk = Array(ids[i..<min(i + 200, ids.count)])
            i += 200
            guard let got = try? await NativeAPI.call("getReaderMeanings", ["word_ids": chunk, "explain_lang": lang],
                                                      as: [String: String?].self, timeout: 30),
                  lang == L10n.lang else { continue }
            for id in chunk { readerMeanings[id] = (got[id] ?? nil) ?? "" }
        }
        guard lang == L10n.lang else { return }
        stickers = stickers.map(applyReader)
        scheduleSnapshot()
        // The widget was redrawn right after a language switch, before these meanings came: again with them (else the
        // word of the day has no meaning until the next foreground). Only then — at launch the widget is written once
        // the dex is read, and a second write would load its pictures while the dex shows its first ones.
        if afterLanguageSwitch { WidgetBridge.refresh(dex: self) }
    }

    /// Words whose explanation is being written for this reader right now (the detail page shows
    /// those sections as filling). Owned by the store, so leaving the page does not cancel it.
    private(set) var generatingWords: Set<String> = []

    /// web StickerSheet: read this reader's explanation of the word; when there is none for exactly
    /// this reader, write one (`generateCard` → `updateWordExtras`, which files it under the reader's
    /// key on the server) in the background.
    func loadExplanation(wordId: String, target: String) async {
        struct Res: Decodable { let picked: ReaderLanguage.Explanation?; let unavailable: Bool?; let level: ReaderLanguage.LevelContent? }
        let lang = L10n.lang
        let l1 = ReaderLanguage.l1(native: ReaderLanguage.native, target: target)
        guard let r = try? await NativeAPI.call("getWordExplanation", ["word_id": wordId, "explain_lang": lang, "l1": l1],
                                                as: Res.self, timeout: 20),
              lang == L10n.lang else { return }
        if let p = r.picked { explanations[wordId] = p } else { explanations.removeValue(forKey: wordId) }
        if let lv = r.level { levels[wordId] = lv } else { levels.removeValue(forKey: wordId) }
        stickers = stickers.map { $0.wordId == wordId ? applyReader($0) : $0 }
        if r.unavailable == true { return }
        await ProfileStore.syncLanguageToServer()
        // Writing a new explanation uses the AI (`generateCard`): only with the AI consent.
        guard AIConsent.shared.isGranted, ReaderLanguage.serverWritesIn(lang), ReaderLanguage.needsGeneration(r.picked, lang: lang, l1: l1, level: r.level),
              let shared = sharedWords[wordId], !generatingWords.contains(wordId) else { return }
        generatingWords.insert(wordId)
        Task {
            defer { generatingWords.remove(wordId) }
            await generateExplanation(word: shared, shown: r.picked, lang: lang, l1: l1)
            guard lang == L10n.lang,
                  let again = try? await NativeAPI.call("getWordExplanation", ["word_id": wordId, "explain_lang": lang, "l1": l1],
                                                        as: Res.self, timeout: 20),
                  let p = again.picked else { return }
            explanations[wordId] = p
            if let lv = again.level { levels[wordId] = lv }
            stickers = stickers.map { $0.wordId == wordId ? applyReader($0) : $0 }
        }
    }

    private func generateExplanation(word: Word, shown: ReaderLanguage.Explanation?, lang: String, l1: String) async {
        guard let raw = try? await NativeAPI.call("generateCard", ["headword": word.headword, "targetLanguage": word.language ?? language], timeout: 60),
              let card = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              var fresh = card["extras"] as? [String: Any] else { return }
        // Keep what is already on screen and only fill what was empty (web keepShownFields), so the
        // chunks the learner is reading do not swap into different ones when the new notes arrive.
        if let shownRaw = await shownExtras(wordId: word.id, shown: shown, lang: lang, l1: l1) {
            let filled: (Any) -> Bool = { v in
                if let a = v as? [Any] { return !a.isEmpty }
                if let s = v as? String { return !s.trimmingCharacters(in: .whitespaces).isEmpty }
                return !(v is NSNull)
            }
            for (k, v) in shownRaw where filled(v) && k != "explain_lang" && k != "explain_l1" { fresh[k] = v }
        }
        var data: [String: Any] = ["word_id": word.id, "extras": fresh]
        // Shared columns are written only when they are really missing (web shouldWriteSharedColumns).
        let missing = [word.meaningJa, word.readingZhuyin ?? word.pinyin ?? "", word.exampleSentence ?? ""]
            .contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        if missing {
            var patch: [String: Any] = [:]
            for k in ["reading_zhuyin", "pinyin", "part_of_speech", "example_sentence", "example_translation", "meaning_ja"] {
                if let v = card[k] as? String, !v.isEmpty { patch[k] = v }
            }
            if !patch.isEmpty { data["patch"] = patch }
        }
        _ = try? await NativeAPI.call("updateWordExtras", data, timeout: 30)
    }

    /// The extras the learner is looking at right now, raw (only when they are this reader's own or the
    /// shared ones written in the reader's language).
    private func shownExtras(wordId: String, shown: ReaderLanguage.Explanation?, lang: String, l1: String) async -> [String: Any]? {
        if shown != nil { return nil }
        guard let data = try? await client.rest("GET", "words?id=eq.\(wordId)&select=extras&limit=1"),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let ex = rows.first?["extras"] as? [String: Any] else { return nil }
        let mark = (ex["explain_lang"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        return mark == lang ? ex : nil
    }

    /// Re-encounter (web `recordReencounter`): this photo is added to the word you already own,
    /// with where you met it again. No quiz, and the review interval is not moved (`recalled: null`).
    ///
    /// Owner 2026-10-11 (「同じ単語の画像を撮ったときに、追加するまでに時間が無駄にかかる」): the dex shows the photo at
    /// once — it is put in the image cache under the names it is uploaded to and comes first in its word's square
    /// (`freshEncounters`) — while the uploads (the cut-out at 800 px: it is only drawn in the small dex square) and
    /// the record run; the sticker is no longer read back afterwards. The caller runs this behind the screens
    /// (`CaptureView.recordReencounter`). A failure takes the photo out of the square again and is thrown. A failed cut-out never
    /// blocks the record; a photo that cannot be uploaded does (it stays in 「解析待ち」).
    func recordEncounter(owned: OwnedWord, photo: UIImage?, cutout: UIImage?,
                         location: CLLocation?, placeName: String?) async throws -> (count: Int, photoSaved: Bool) {
        guard let uid = client.userId else { throw APIError.unauthorized }
        let ts = Self.uploadStamp()
        let sid = owned.stickerId
        // The very paths `uploadJPEG` / `uploadPNG` write below.
        let imageName: String? = photo == nil ? nil : "\(uid)/\(ts)-encounter.jpg"
        let cutoutName: String? = cutout == nil ? nil : "\(uid)/\(ts)-encounter-cutout.png"
        cacheLocal(path: imageName, image: photo)
        cacheLocal(path: cutoutName, image: cutout)
        let shown: DexPicture? = (cutoutName ?? imageName).map { DexPicture(path: $0, isCutout: cutoutName != nil) }
        if let shown {
            encounterPhotos[sid, default: []].append(shown)
            freshEncounters[sid] = shown
        }
        // Its page in the home album at once, on today's page like a new catch (the read after the record names it).
        let albumEntry: EncounterEntry? = shown == nil ? nil : EncounterEntry(id: "local-\(ts)", stickerId: sid, image: imageName, cutout: cutoutName,
                                                              place: placeName, at: Date())
        if let albumEntry { encounterEntries.append(albumEntry) }
        struct Recorded: Decodable {
            let encounterCount: Int?
            enum CodingKeys: String, CodingKey { case encounterCount = "encounter_count" }
        }
        do {
            // One at a time, the photo first (`upload(photo:cutout:selfie:)`).
            let image = try await uploadJPEG(photo, uid: uid, ts: ts, kind: "encounter")
            let cut = await uploadPNG(cutout, uid: uid, ts: ts, kind: "encounter-cutout", maxSide: 800)
            if photo != nil && image == nil { throw APIError.message(L("記録に失敗しました")) }
            let res = try await NativeAPI.call("recordEncounter", [
                "sticker_id": sid,
                "recalled": NSNull(),
                "lat": orNull(location?.coordinate.latitude),
                "lng": orNull(location?.coordinate.longitude),
                "location_name": orNull(placeName),
                "image_path": orNull(image),
                "cutout_path": orNull(cut),
            ], as: Recorded.self, timeout: 30, asUser: uid)
            StickerPhoto.invalidate(sid)
            return (res.encounterCount ?? owned.encounterCount + 1, image != nil || cut != nil)
        } catch {
            // Signed out (or into another account) meanwhile: that account's dex is gone already; nothing is told.
            guard client.userId == uid else { throw Self.accountChanged }
            // Not added: the square goes back to the pictures it had.
            if let shown {
                encounterPhotos[sid]?.removeAll { $0.path == shown.path }
                if freshEncounters[sid]?.path == shown.path { freshEncounters[sid] = nil }
            }
            if let albumEntry { encounterEntries.removeAll { $0 == albumEntry } }
            throw error
        }
    }

    private func uploadJPEG(_ image: UIImage?, uid: String, ts: Int, kind: String) async throws -> String? {
        // Encoded off the main thread: this runs while the reward animation plays.
        guard let image,
              let up = await Task.detached(priority: .userInitiated, operation: { ImageTools.jpegUpload(image) }).value
        else { return nil }
        let path = "\(uid)/\(ts)-\(kind).jpg"
        try await send(up, path: path, contentType: "image/jpeg", kind: kind)
        return path
    }

    /// Cutout failures never block the catch (the catch is saved without it, and it is attached later:
    /// `CutoutBackfill.keep`).
    private func uploadPNG(_ image: UIImage?, uid: String, ts: Int, kind: String, maxSide: CGFloat = 1024) async -> String? {
        guard let image,
              let up = await Task.detached(priority: .userInitiated, operation: { ImageTools.pngUpload(image, maxSide: maxSide) }).value
        else { return nil }
        let path = "\(uid)/\(ts)-\(kind).png"
        do {
            try await send(up, path: path, contentType: "image/png", kind: kind)
            return path
        } catch {
            return nil
        }
    }

    /// Sends one picture, tried again when the connection dropped or could not be made (`UploadRetry`: after 1, 2 and 4 s;
    /// a try after the first counts a file already there as sent). Every failed try goes to the developer log with which
    /// picture, its size, the try's number and the error (its URLError code or HTTP status).
    private func send(_ up: ImageTools.UploadData, path: String, contentType: String, kind: String) async throws {
        try await UploadRetry.run(sleep: retrySleepOverride) { attempt in
            do {
                if let fake = sendUploadOverride {
                    try await fake(up.data, path, contentType, attempt > 1)
                } else {
                    try await client.upload(up.data, path: path, contentType: contentType, existsIsDone: attempt > 1)
                }
                if attempt > 1 || up.shrunk || up.sourceBits > 8 {
                    DevLog.shared.add("upload", "\(kind) sent on try \(attempt): \(up.summary)")
                }
            } catch {
                DevLog.shared.add("upload", "\(kind) try \(attempt) failed \(up.summary): \(APIError.describe(error))")
                throw error
            }
        }
    }

    /// Tests: stands in for storage (data, path, content type, another try of the same file) and for the waits.
    @ObservationIgnored var sendUploadOverride: ((Data, String, String, Bool) async throws -> Void)?
    @ObservationIgnored var retrySleepOverride: ((TimeInterval) async -> Void)?

    /// A picture taken on this phone goes into the cache under its storage path — in memory and on disk, so the
    /// album and the dex show it at once, also after a relaunch, without downloading it back.
    /// At most the size it is uploaded at (1600 px, a cut-out 1024 px): a full camera photo in memory pushed the dex's own
    /// pictures out of the cache just as the catch landed (`ImageCache.store(_:for:maxSide:)`).
    private func cacheLocal(path: String?, image: UIImage?) {
        guard let path, let image, ImageCache.shared.image(for: path) == nil else { return }
        ImageCache.shared.store(image, for: path, maxSide: path.hasSuffix(".png") ? 1024 : 1600)
    }

    private func saveToPhotosIfEnabled(_ image: UIImage) {
        let enabled = UserDefaults.standard.object(forKey: "photos.sync") as? Bool ?? true
        guard enabled else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        }
    }

    // MARK: - Edit

    /// Replaces the word's photo (web `replaceStickerPhoto`): the date and place you met it are kept;
    /// the old cut-out is dropped so a new one can be made from the new photo.
    func replacePhoto(_ sticker: Sticker, with image: UIImage) async throws {
        guard let uid = client.userId else { throw APIError.unauthorized }
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        guard let path = try await uploadJPEG(image, uid: uid, ts: ts, kind: "object") else {
            throw APIError.message(L("写真を読み込めませんでした。"))
        }
        _ = try await NativeAPI.call("replaceStickerPhoto", ["sticker_id": sticker.id, "object_path": path])
        // Kept at the size it was uploaded at (a full camera photo decoded slowly at every launch after).
        ImageCache.shared.store(image, for: path, maxSide: 1600)
        StickerPhoto.invalidate(sticker.id)
        await reload(stickerId: sticker.id)
        if let fresh = self.sticker(id: sticker.id) { await signPaths(for: [fresh]) }
    }

    /// Words already given an internet picture this launch (use-auto-hero.ts triedRef). A failed try is
    /// forgotten, so a word that only met a bad connection is not left without a picture for good.
    private var heroTried: Set<String> = []

    /// A word with no picture of its own gets one from the internet as its stand-in (web useAutoHero:
    /// 「単語の詳細の見出しの画像はネットからその単語を表す画像を添付して」). A word with a photo, a
    /// selfie or a stand-in already is never touched.
    func autoHero(_ sticker: Sticker) async {
        guard !sticker.hasOwnPhoto, sticker.placeholderImageUrl == nil, !heroTried.contains(sticker.id),
              let word = sticker.word else { return }
        heroTried.insert(sticker.id)
        let candidates: [WebImageCandidate]
        do {
            candidates = try await WebImages.search(word: word)
        } catch {
            heroTried.remove(sticker.id)
            return
        }
        // The first that downloads (only the first was tried: one from a host the phone could not fetch left the
        // word without a picture every time).
        for c in candidates.prefix(4) {
            if (try? await setPlaceholder(sticker, to: c)) != nil { return }
        }
        heroTried.remove(sticker.id)
    }

    /// Words in the dex with no picture at all get their internet stand-in one at a time (the dex showed an empty
    /// square for them, owner 2026-10-14: 「図鑑に表示されてない単語がある」).
    @ObservationIgnored private var heroQueue: [String] = []
    @ObservationIgnored private var heroRunning = false

    func autoHeroSoon(_ sticker: Sticker) {
        guard !sticker.hasOwnPhoto, sticker.placeholderImageUrl == nil, !heroTried.contains(sticker.id),
              !heroQueue.contains(sticker.id), !Self.isProvisional(sticker.id) else { return }
        heroQueue.append(sticker.id)
        guard !heroRunning else { return }
        heroRunning = true
        Task {
            while !heroQueue.isEmpty {
                let id = heroQueue.removeFirst()
                if let s = self.sticker(id: id) { await autoHero(s) }
            }
            heroRunning = false
        }
    }

    /// Makes an internet picture the word's stand-in (web setStickerPlaceholder). It is not the
    /// learner's photo, so a photo taken later still comes first.
    func setPlaceholder(_ sticker: Sticker, to candidate: WebImageCandidate) async throws {
        guard let uid = client.userId else { throw APIError.unauthorized }
        let image = try await WebImages.image(for: candidate)
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        guard let path = try await uploadJPEG(ImageTools.resized(image, maxSide: 1024), uid: uid, ts: ts, kind: "placeholder") else {
            throw APIError.decoding
        }
        _ = try await NativeAPI.call("setStickerPlaceholder", [
            "sticker_id": sticker.id, "placeholder_path": path, "placeholder_credit": candidate.creditPayload,
        ])
        ImageCache.shared.store(image, for: path, maxSide: 1024)
        await reload(stickerId: sticker.id)
        if let fresh = self.sticker(id: sticker.id) { await signPaths(for: [fresh]) }
    }

    func addCutout(to sticker: Sticker, image: UIImage) async throws {
        guard let uid = client.userId else { throw APIError.unauthorized }
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        guard let path = await uploadPNG(image, uid: uid, ts: ts, kind: "cutout") else {
            throw APIError.message(L("切り抜きの保存に失敗しました。"))
        }
        _ = try await NativeAPI.call("attachStickerCutout", ["sticker_id": sticker.id, "cutout_path": path])
        // At the size it was uploaded at (`uploadPNG`): a cut-out lifted from a camera photo is far bigger, and the
        // album decoded it at full size at every launch.
        ImageCache.shared.store(image, for: path, maxSide: 1024)
        replace(sticker.id) { old in
            var s = old
            s.cutoutImageUrl = path
            return s
        }
    }

    /// A selfie taken later for a word that has none (web PhotoAddButtons → `attachStickerSelfie`).
    func addSelfie(to sticker: Sticker, image: UIImage) async throws {
        guard let uid = client.userId else { throw APIError.unauthorized }
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        guard let path = try await uploadJPEG(image, uid: uid, ts: ts, kind: "selfie") else {
            throw APIError.message(L("写真の保存に失敗しました。"))
        }
        _ = try await NativeAPI.call("attachStickerSelfie", ["sticker_id": sticker.id, "selfie_path": path])
        ImageCache.shared.store(image, for: path, maxSide: 1600)
        replace(sticker.id) { old in
            var s = old
            s.selfieImageUrl = path
            return s
        }
    }

    /// Saves the sticker's one-line note (ひと言). Empty clears it.
    func updateCaption(_ sticker: Sticker, caption: String) async throws {
        // The server keeps 500 characters (stickers.functions.ts CAPTION_MAX).
        let trimmed = String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        _ = try await NativeAPI.call("updateStickerCaption", ["sticker_id": sticker.id, "caption": trimmed])
        // Change only the caption: rebuilding the sticker field by field dropped the chosen picture,
        // the stand-in image and its credit until the next reload.
        replace(sticker.id) { old in
            var s = old
            s.caption = trimmed.isEmpty ? nil : trimmed
            return s
        }
    }

    /// Points this sticker at another headword (setStickerHeadword). The shared `words` row is never rewritten.
    func setHeadword(_ sticker: Sticker, to raw: String) async throws {
        let head = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty, head.count <= 60 else { throw APIError.message(L("単語を入れてください。")) }
        if sticker.word?.headword == head { return }
        // Never a headword in another language (kana or English in a Mandarin word): stopped here before the server.
        guard LanguageRules.headwordSaveable(head, target: NativeAPI.targetLanguage) else {
            throw APIError.message(Self.notTargetHeadword)
        }
        do {
            // The server checks the language, reuses or creates the word row (its contents are
            // filled in afterwards by the detail page's auto-fill, as on the web).
            _ = try await NativeAPI.call("setStickerHeadword", ["sticker_id": sticker.id, "headword": head])
        } catch let APIError.server(_, message) where message.contains("NOT_TARGET_LANGUAGE") {
            throw APIError.message(Self.notTargetHeadword)
        }
        await reload(stickerId: sticker.id)
    }

    /// The headword was not in the learning language: what to type instead.
    static var notTargetHeadword: String {
        NativeAPI.targetLanguage == "en" ? L("英語の単語を入れてください。")
            : NativeAPI.targetLanguage == "ja" ? L("日本語の単語を入れてください。") : L("繁体字（台湾華語）の単語を入れてください。")
    }

    /// Dictionary error report → `entry_reports` (reports.functions.ts). Lands in the admin review queue.
    // MARK: - Home album (web album-hidden.functions.ts)

    /// Photos taken off the home album. They stay in the dex; only the album page skips them.
    var albumHidden: Set<String> = []

    /// The photo just taken off the album with ✕: Home offers 「元に戻す」 for a few seconds (owner 2026-10-20: 「ホームの
    /// 画像をバツで消した時に戻す方法がない」 — the tray at the album's end was out of sight).
    var albumUndo: String?

    /// The ones the server holds (the rest of `albumHidden` is kept on this phone only).
    @ObservationIgnored private var serverAlbumHidden: Set<String> = []

    /// Photos taken off the album that the server could not record (web album-hidden.ts keeps them in localStorage
    /// the same way). Owner 2026-10-14: 「ホーム画面の画像を長押ししてバツ押しても、画像が消えない」 — the server answered
    /// `saved: false` and the app put the photo back every time.
    private static func localHiddenKey(_ uid: String) -> String { "album.hidden.local.\(uid)" }

    private func localAlbumHidden() -> Set<String> {
        guard let uid = client.userId else { return [] }
        return Set(UserDefaults.standard.stringArray(forKey: Self.localHiddenKey(uid)) ?? [])
    }

    private func setLocalAlbumHidden(_ ids: Set<String>) {
        guard let uid = client.userId else { return }
        UserDefaults.standard.set(Array(ids), forKey: Self.localHiddenKey(uid))
    }

    func loadAlbumHidden() async {
        struct Res: Decodable { let ids: [String] }
        let uid = client.userId
        guard let r = try? await NativeAPI.call("listAlbumHidden", [:], as: Res.self), client.userId == uid else {
            albumHidden.formUnion(localAlbumHidden())
            return
        }
        serverAlbumHidden = Set(r.ids)
        // A photo the server now holds no longer needs the phone's copy.
        let local = localAlbumHidden().subtracting(serverAlbumHidden)
        setLocalAlbumHidden(local)
        albumHidden = serverAlbumHidden.union(local)
    }

    /// Takes a photo off the album (or puts it back) at once. The server keeps it when it can; when it cannot,
    /// this phone does, so the photo never comes back by itself. False only when putting back a photo the server
    /// still holds failed (it would return on the next read).
    @discardableResult
    func setAlbumHidden(_ id: String, hidden: Bool) async -> Bool {
        if hidden { albumHidden.insert(id) } else { albumHidden.remove(id) }
        struct Res: Decodable { let saved: Bool }
        // A re-encounter's page is not a sticker: this phone keeps it (the server's list holds sticker ids only).
        var ok = false
        if !Self.isEncounterAlbumEntry(id), !id.hasPrefix(SampleSticker.prefix) {
            ok = (try? await NativeAPI.call("setAlbumHidden", ["sticker_id": id, "hidden": hidden], as: Res.self))?.saved ?? false
        }
        var local = localAlbumHidden()
        if hidden {
            if ok { serverAlbumHidden.insert(id); local.remove(id) } else { local.insert(id) }
        } else {
            local.remove(id)
            if ok { serverAlbumHidden.remove(id) }
        }
        setLocalAlbumHidden(local)
        let putBackFailed = !hidden && !ok && serverAlbumHidden.contains(id)
        if putBackFailed { albumHidden.insert(id) }
        scheduleSnapshot()
        return !putBackFailed
    }

    /// Where the learner placed each photo on the album page (web album_x / album_y / album_scale /
    /// album_rot / album_order / album_size). Read on its own so a database without these columns
    /// never breaks the dex (web listMyStickers keeps the same fallback).
    var albumPlacements: [String: DayLayoutSticker] = [:]

    func loadAlbumPlacements() async {
        struct Row: Decodable {
            let id: String
            let album_order: Int?
            let album_size: String?
            let album_x: Double?
            let album_y: Double?
            let album_scale: Double?
            let album_rot: Double?
        }
        let uid = client.userId
        guard let rows = try? await readAll("stickers?select=id,album_order,album_size,album_x,album_y,album_scale,album_rot&order=id.asc",
                                            as: Row.self, decoder: JSONDecoder()),
              client.userId == uid else { return }
        var out: [String: DayLayoutSticker] = localEncounterPlacements()
        for r in rows {
            out[r.id] = DayLayoutSticker(id: r.id, albumOrder: r.album_order, albumSize: r.album_size.flatMap(AlbumSize.init(rawValue:)),
                                         albumX: r.album_x, albumY: r.album_y, albumScale: r.album_scale, albumRot: r.album_rot)
        }
        albumPlacements = out
    }

    /// Where the learner placed re-encounter pages on the album (they have no `stickers.album_*` columns): kept on
    /// this phone, per account.
    nonisolated private struct LocalPlacement: Codable, Sendable {
        var order: Int?
        var size: String?
        var x: Double?
        var y: Double?
        var scale: Double?
        var rot: Double?
    }

    private static func encounterPlacementsKey(_ uid: String) -> String { "album.encounterPlacements.\(uid)" }

    private func localEncounterPlacements() -> [String: DayLayoutSticker] {
        guard let uid = client.userId, let data = UserDefaults.standard.data(forKey: Self.encounterPlacementsKey(uid)),
              let saved = try? JSONDecoder().decode([String: LocalPlacement].self, from: data) else { return [:] }
        var out: [String: DayLayoutSticker] = [:]
        for (id, p) in saved {
            out[id] = DayLayoutSticker(id: id, albumOrder: p.order, albumSize: p.size.flatMap(AlbumSize.init(rawValue:)),
                                       albumX: p.x, albumY: p.y, albumScale: p.scale, albumRot: p.rot)
        }
        return out
    }

    private func saveLocalEncounterPlacements() {
        guard let uid = client.userId else { return }
        var out: [String: LocalPlacement] = [:]
        for (id, d) in albumPlacements where Self.isEncounterAlbumEntry(id) {
            out[id] = LocalPlacement(order: d.albumOrder, size: d.albumSize?.rawValue, x: d.albumX, y: d.albumY,
                                     scale: d.albumScale, rot: d.albumRot)
        }
        if let data = try? JSONEncoder().encode(out) { UserDefaults.standard.set(data, forKey: Self.encounterPlacementsKey(uid)) }
    }

    /// Saves one day's arrangement (web `saveAlbumLayout`). Returns false if nothing was saved.
    func saveAlbumLayout(_ items: [(id: String, order: Int, size: AlbumSize, place: AlbumPlacement)]) async -> Bool {
        // A catch still being saved has no server id yet: it is left out (it keeps its automatic place).
        // Re-encounter pages are kept on this phone (`saveLocalEncounterPlacements`), not sent.
        let payload: [[String: Any]] = items.filter {
            !Self.isProvisional($0.id) && !Self.isEncounterAlbumEntry($0.id) && !$0.id.hasPrefix(SampleSticker.prefix)
        }.map { i in
            ["sticker_id": i.id, "order": i.order, "size": i.size.rawValue,
             "x": AlbumLayout.clamp(i.place.x, 0, 1), "y": AlbumLayout.clamp(i.place.y, 0, 8),
             "scale": AlbumLayout.clamp(i.place.scale, 0.45, 2.6), "rot": AlbumLayout.clamp(i.place.rot, -180, 180)]
        }
        if !payload.isEmpty {
            guard (try? await NativeAPI.call("saveAlbumLayout", ["items": payload], timeout: 30)) != nil else { return false }
        }
        for i in items {
            var d = albumPlacements[i.id] ?? DayLayoutSticker(id: i.id)
            d.albumOrder = i.order
            d.albumSize = i.size
            d.albumX = i.place.x
            d.albumY = i.place.y
            d.albumScale = i.place.scale
            d.albumRot = i.place.rot
            albumPlacements[i.id] = d
        }
        if items.contains(where: { Self.isEncounterAlbumEntry($0.id) }) { saveLocalEncounterPlacements() }
        scheduleSnapshot()
        return true
    }

    /// Which picture shows this word on its detail page (web setStickerHeroRole; nil = default order).
    func setHeroRole(_ sticker: Sticker, role: String?) async throws {
        struct Saved: Decodable { let saved: Bool }
        let res: Saved = try await NativeAPI.call("setStickerHeroRole", [
            "sticker_id": sticker.id, "hero_role": role.map { $0 as Any } ?? NSNull(),
        ], as: Saved.self)
        guard res.saved else { throw APIError.message(L("まだ保存できません。サーバの更新を待ってください。")) }
        replace(sticker.id) { old in
            var s = old
            s.heroRole = role
            return s
        }
    }

    /// Re-reads one sticker (and its word) after the server changed it.
    func reload(stickerId: String) async {
        guard let fresh = try? await fetchSticker(id: stickerId) else { return }
        replace(stickerId) { old in
            var s = fresh
            s.lat = old.lat
            s.lng = old.lng
            return s
        }
    }

    /// Sections never asked for any more: 発音のコツ・覚え方 and 語源・部首 (the server stops writing them, owner 2026-10-15),
    /// ネットの画像, and the extra examples (「例文」 shows those the card came with; nothing fetches more on its own).
    nonisolated static let retiredSections: Set<String> = ["pronunciation_tips", "mnemonic", "web_images", "etymology",
                                                          "etymology_diagram", "radicals", "examples_extra"]

    /// Web `regenerateCardSection`. `onlyIfEmpty` = first fill of a missing section (free, like the web's
    /// AutoFillSections); otherwise a full rewrite of the section (Pro on the web).
    func fillSection(wordId: String, section: String, onlyIfEmpty: Bool) async -> Bool {
        // 発音のコツ・覚え方・語源・部首 are no longer on the word page, and the server stops writing them (owner 2026-10-15).
        guard !Self.retiredSections.contains(section) else { return false }
        // Written in the server's language of this account: not before the screen's language has reached it.
        await ProfileStore.syncLanguageToServer()
        guard ReaderLanguage.serverWritesIn(L10n.lang) else { return false }
        struct Res: Decodable { let ok: Bool?; let filled: Bool? }
        let r = try? await NativeAPI.call("regenerateCardSection", [
            "word_id": wordId, "section": section, "only_if_empty": onlyIfEmpty,
        ], as: Res.self, timeout: 60)
        let ok = r?.ok == true || r?.filled == true
        // The section is written to this reader's rows (their language's, and for examples and chunks their band's —
        // docs/sharing-rules.md): read those again, or the page keeps showing what it read before.
        if r?.filled == true { await rereadExplanation(wordId: wordId) }
        return ok
    }

    /// Reads this reader's explanation and band content of the word again (no generation — `loadExplanation` does that).
    private func rereadExplanation(wordId: String) async {
        struct Res: Decodable { let picked: ReaderLanguage.Explanation?; let level: ReaderLanguage.LevelContent? }
        let lang = L10n.lang
        let target = sharedWords[wordId]?.language ?? language
        let l1 = ReaderLanguage.l1(native: ReaderLanguage.native, target: target)
        guard let r = try? await NativeAPI.call("getWordExplanation", ["word_id": wordId, "explain_lang": lang, "l1": l1],
                                                as: Res.self, timeout: 20),
              lang == L10n.lang else { return }
        if let p = r.picked { explanations[wordId] = p }
        if let lv = r.level { levels[wordId] = lv }
        stickers = stickers.map { $0.wordId == wordId ? applyReader($0) : $0 }
    }

    /// Web `reportAndFixSection`: the AI finds which item is wrong (from the one-line note and what is
    /// on screen), checks it against the dictionary, and fixes only that item.
    struct ReportFix: Decodable {
        let fixed: Bool
        let item: String?
        let by: String?
        /// The AI (and its backup) did not answer: the report is recorded, nothing was rewritten (server 2026-10-14;
        /// an older server answered 500 instead).
        let aiFailed: Bool?
        /// Not fixed on the spot: the server drafts a fix in the background and applies it only when another AI passes
        /// it, and tells the developer (server #187: a free learner's report, or a report without a chosen item).
        let queued: Bool?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fixed = (try? c.decodeIfPresent(Bool.self, forKey: .fixed)) ?? false
            item = (try? c.decodeIfPresent(String.self, forKey: .item)) ?? nil
            by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? nil
            aiFailed = (try? c.decodeIfPresent(Bool.self, forKey: .aiFailed)) ?? nil
            queued = (try? c.decodeIfPresent(Bool.self, forKey: .queued)) ?? nil
        }

        private enum CodingKeys: String, CodingKey { case fixed, item, by, aiFailed, queued }
    }

    func reportAndFix(wordId: String, item: String = "auto", candidates: [String], note: String) async throws -> ReportFix {
        try await NativeAPI.call("reportAndFixSection", [
            "word_id": wordId, "item": item, "candidates": Array(candidates.prefix(24)), "note": String(note.prefix(500)),
        ], as: ReportFix.self, timeout: 90)
    }

    private func replace(_ id: String, _ transform: (Sticker) -> Sticker) {
        guard let i = stickers.firstIndex(where: { $0.id == id }) else { return }
        stickers[i] = transform(stickers[i])
        scheduleSnapshot()
    }

    /// Web `deleteSticker`: the row and its photo files (and thumbnails) go together.
    func delete(_ sticker: Sticker) async throws {
        if sticker.isSample {
            // Never on the server: it leaves this phone, and never comes back for this account.
            stickers.removeAll { $0.id == sticker.id }
            reviews[sticker.id] = nil
            SampleSticker.markDeleted(userId: client.userId)
            scheduleSnapshot()
            return
        }
        _ = try await NativeAPI.call("deleteSticker", ["sticker_id": sticker.id])
        stickers.removeAll { $0.id == sticker.id }
        scheduleSnapshot()
    }

    func refreshPending() {
        PendingQueue.shared.reload()
    }

    /// Signing out / switching accounts: nothing of this account stays in memory for the next one.
    func reset() {
        snapshotTask?.cancel()
        serverAnswered = false
        prefetchTask?.cancel()
        stickers = []
        encounterPhotos = [:]
        freshEncounters = [:]
        encounterEntries = []
        adoptedIds = [:]
        unsaved = [:]
        signedAt = [:]
        forcedAt = [:]
        sharedWords = [:]
        explanations = [:]
        levels = [:]
        readerMeanings = [:]
        signed = [:]
        reviews = [:]
        albumHidden = []
        serverAlbumHidden = []
        albumPlacements = [:]
        heroTried = []
        heroQueue = []
        missingPaths = []
        blankCutouts = []
        loadError = nil
        hasLoaded = false
        PendingQueue.shared.reload()
    }

    nonisolated static func enc(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+,()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

/// JSON `null` for a missing value (`JSONSerialization` bodies).
private func orNull(_ value: Any?) -> Any { value ?? NSNull() }

/// One picture a dex square can show: its storage path, and whether it is a cut-out (drawn whole, on nothing).
nonisolated struct DexPicture: Hashable, Sendable {
    let path: String
    let isCutout: Bool
}
