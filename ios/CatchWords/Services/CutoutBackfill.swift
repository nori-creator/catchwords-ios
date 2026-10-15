import UIKit

/// Every picture is cut out (owner 2026-10-11: 「切り抜きモードは消して。すべての画像切抜く」). A word whose own photo
/// has no cut-out yet — caught on the web (cut-outs were dropped there on 2026-10-01), on an older version of the
/// app, or one whose cut-out failed at the time — gets one made on this phone with the same lift as at the shutter
/// (Vision, on device, free) and attached to the word (`attachStickerCutout`), one at a time behind the screens.
/// A photo in which Vision finds no subject is remembered for this account and not tried again.
@Observable
final class CutoutBackfill {
    static let shared = CutoutBackfill()

    @ObservationIgnored private var task: Task<Void, Never>?
    /// Words being cut out right now (the word page asks too when it opens one without a cut-out).
    @ObservationIgnored private var running: Set<String> = []
    /// Words of this run still to be cut out. The home album waits for their cut-out instead of showing the photo
    /// first and swapping it a moment later (owner 2026-10-14: 「元の画像が一瞬表示されて、すぐ切り抜きになる」).
    private(set) var queued: Set<String> = []
    /// True once the first run of this launch is planned (or 8 s after launch, so a dex that cannot be read never
    /// keeps the album waiting). Before that, every photo still without a cut-out waits.
    private(set) var planned = false
    @ObservationIgnored private var triedCache: (uid: String, ids: Set<String>)?

    private init() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.planned = true
        }
    }

    /// The home album should wait for this word's cut-out (it is about to be made) rather than draw its photo.
    func awaitsCutout(_ s: Sticker) -> Bool {
        guard Self.needsCutout(s) else { return false }
        if planned { return queued.contains(s.id) }
        guard let uid = SupabaseClient.shared.userId else { return false }
        return !tried(uid).contains(s.id)
    }

    private func tried(_ uid: String) -> Set<String> {
        if let c = triedCache, c.uid == uid { return c.ids }
        let ids = Set(UserDefaults.standard.stringArray(forKey: Self.triedKey(uid)) ?? [])
        triedCache = (uid, ids)
        return ids
    }

    enum Outcome { case made, noSubject, failed }

    /// Words tried in one run at most (the rest wait for the next launch).
    private static let perRun = 40

    private static func triedKey(_ uid: String) -> String { "cutout.tried.\(uid)" }

    /// A photo of the learner's own, still without a cut-out (a typed word's text card is never cut out).
    static func needsCutout(_ s: Sticker) -> Bool {
        s.cutoutImageUrl == nil && s.objectImageUrl != nil && !DexStore.isProvisional(s.id) && s.captureType != "text"
    }

    /// Starts working through the words without a cut-out (after a dex read). Does nothing while a run is going.
    func start(dex: DexStore) {
        guard task == nil else { return }
        guard let uid = SupabaseClient.shared.userId else { planned = true; return }
        let tried = tried(uid)
        let todo = dex.stickers.filter { Self.needsCutout($0) && !tried.contains($0.id) }.prefix(Self.perRun).map(\.id)
        queued = Set(todo)
        planned = true
        guard !todo.isEmpty else { return }
        task = Task(priority: .utility) { [weak self] in
            var noSubject = tried
            for id in todo {
                guard let self, !Task.isCancelled, SupabaseClient.shared.userId == uid else { break }
                // The word may have changed meanwhile (a cut-out attached elsewhere, the word deleted).
                guard let current = dex.sticker(id: id), Self.needsCutout(current) else { self.queued.remove(id); continue }
                if await self.make(for: current, dex: dex) == .noSubject {
                    noSubject.insert(id)
                    UserDefaults.standard.set(Array(noSubject), forKey: Self.triedKey(uid))
                    self.triedCache = (uid, noSubject)
                }
                // Done either way: the album shows the cut-out, or the photo when none could be made.
                self.queued.remove(id)
                try? await Task.sleep(for: .milliseconds(150))
            }
            self?.queued = []
            self?.task = nil
        }
    }

    /// Signing out: the run stops (it belongs to the account that left).
    func stop() {
        task?.cancel()
        task = nil
        running = []
        queued = []
        triedCache = nil
    }

    // MARK: - Cut-outs whose upload failed at the catch

    /// The folder of cut-outs made at the catch that could not be uploaded then (owner 2026-10-15: the catch is saved
    /// without its cut-out rather than failing, and the very cut-out — the thing the learner picked — is attached later).
    private static let keptDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("pending-cutouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func keptURL(_ stickerId: String) -> URL {
        keptDir.appendingPathComponent(stickerId.filter { $0.isLetter || $0.isNumber || $0 == "-" } + ".png")
    }

    /// Keeps a catch's cut-out until it is attached (`make(for:)` uses it instead of cutting the photo again).
    static func keep(_ image: UIImage, for stickerId: String) {
        let url = keptURL(stickerId)
        Task.detached(priority: .utility) {
            guard let png = ImageTools.pngUpload(image)?.data else { return }
            try? png.write(to: url, options: .atomic)
        }
    }

    /// The cut-out kept for this word, if its upload is still to be done.
    static func kept(for stickerId: String) -> UIImage? {
        UIImage(contentsOfFile: keptURL(stickerId).path)
    }

    static func forget(_ stickerId: String) {
        try? FileManager.default.removeItem(at: keptURL(stickerId))
    }

    /// Cuts this word's photo out now and attaches the cut-out — or attaches the cut-out kept from its catch, when its
    /// upload failed then (`keep`). The photo comes from the cache when it is kept, else from its link.
    @discardableResult
    func make(for sticker: Sticker, dex: DexStore) async -> Outcome {
        guard Self.needsCutout(sticker), let path = sticker.objectImageUrl, !running.contains(sticker.id) else { return .failed }
        running.insert(sticker.id)
        defer { running.remove(sticker.id) }
        if let kept = Self.kept(for: sticker.id) {
            do {
                try await dex.addCutout(to: sticker, image: kept)
                Self.forget(sticker.id)
                DevLog.shared.add("upload", "\(sticker.word?.headword ?? sticker.id): cut-out kept from the catch attached later")
                return .made
            } catch {
                return .failed
            }
        }
        var image = await ImageCache.shared.cached(for: path)
        if image == nil {
            // Signed (when needed) and put on disk, then read from there.
            await dex.prefetchPictures([path])
            if let url = dex.url(for: path, preferThumb: false) {
                image = await ImageCache.shared.load(url: url, key: path)
            }
        }
        guard let image else { return .failed }
        guard let lifted = await CutoutService.liftSubject(from: image) else { return .noSubject }
        do {
            try await dex.addCutout(to: sticker, image: lifted)
            return .made
        } catch {
            return .failed
        }
    }
}
