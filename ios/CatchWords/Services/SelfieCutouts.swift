import UIKit
import CryptoKit

/// The home album's selfies cut down to the people and what they hold (owner 2026-10-14: 「ホームに表示する自撮りも
/// 元の画像ではなく、自撮りに写る人物とその単語の対象に絞って切り抜いてほしい」). Made on this phone with Vision
/// (`CutoutService.liftPeople`), one at a time, and kept only in this phone's image cache (`ImageCache`, emptied at
/// sign-out) — never uploaded, so nothing is left on the server when a word or the account is deleted.
/// A selfie with no person in it is remembered for this account and shown as it is.
@Observable
final class SelfieCutouts {
    static let shared = SelfieCutouts()

    enum State { case ready, noPerson, pending }

    /// Selfies whose cut-out is in the image cache (under `key(for:)`).
    private(set) var ready: Set<String> = []
    /// Selfies with no person to cut out, or that could not be read this time: shown as they are.
    private(set) var none: Set<String> = []
    /// Goes up each time a selfie's cut-out is replaced by the learner's own (`setLearnerCut`): the views showing it
    /// read the cache again (their task ids carry it; `ready` alone does not change then).
    private(set) var revision = 0

    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var running = false
    /// This account's selfies with no person, from earlier launches (read once; not observed, so reading it while
    /// a screen draws changes nothing).
    @ObservationIgnored private var remembered: (uid: String, paths: Set<String>)?

    /// The cut-out's key in the image cache (a `.png` key keeps its transparency on disk).
    static func key(for selfiePath: String) -> String { selfiePath + ".person.png" }

    private static func noneKey(_ uid: String) -> String { "selfie.person.none.\(uid)" }

    func state(for path: String) -> State {
        if ready.contains(path) { return .ready }
        if none.contains(path) || rememberedNone().contains(path) { return .noPerson }
        return .pending
    }

    /// Asks for this selfie's cut-out (a no-op when it is done, failed or already waiting).
    func request(_ path: String, dex: DexStore) {
        guard !ready.contains(path), !none.contains(path), !rememberedNone().contains(path), !queue.contains(path) else { return }
        queue.append(path)
        guard !running else { return }
        running = true
        Task(priority: .utility) {
            while !queue.isEmpty {
                let next = queue.removeFirst()
                await make(next, dex: dex)
            }
            running = false
        }
    }

    /// The cut-out was not found in the cache any more (the system emptied it): make it again.
    func forget(_ path: String) {
        ready.remove(path)
    }

    /// 囲んで切り抜き直す on the selfie (owner 2026-11-07: 「自撮りでも切り抜き修正できるようにして」): `cut` (on
    /// transparency) is this selfie's cut-out from now on — on the word page and the album. Kept on this phone only,
    /// like the cut-out Vision makes, but in Application Support, not the cache, so the system emptying the cache
    /// brings the learner's drawing back instead of Vision's (`make` reads it first). Never uploaded.
    func setLearnerCut(_ path: String, cut: UIImage) {
        let key = Self.key(for: path)
        ImageCache.shared.forget(key)
        ImageCache.shared.store(cut, for: key, maxSide: 1024)
        if let data = cut.pngData() {
            let file = Self.learnerFile(for: path)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        none.remove(path)
        if let uid = SupabaseClient.shared.userId {
            var kept = rememberedNone()
            if kept.remove(path) != nil {
                remembered = (uid, kept)
                UserDefaults.standard.set(Array(kept), forKey: Self.noneKey(uid))
            }
        }
        ready.insert(path)
        revision += 1
    }

    /// Application Support/selfie-cuts/<sha256 of the selfie's path>.png: the learner's own cut-out of that selfie.
    nonisolated private static func learnerFile(for path: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("selfie-cuts", isDirectory: true)
        let name = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return base.appendingPathComponent(name + ".png")
    }

    nonisolated private static var learnerDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("selfie-cuts", isDirectory: true)
    }

    #if DEBUG
    /// `-uiPreview`: a selfie's cut-out as a phone would have made it (Vision does not run on the simulator).
    func seedForPreview(_ path: String, cutout: UIImage) {
        ImageCache.shared.set(cutout, for: Self.key(for: path))
        none.remove(path)
        ready.insert(path)
    }
    #endif

    /// Signing out or the account deleted: the learner's own cut-outs go with the cache (the next account must not see
    /// this one's selfies).
    func reset(deleting uid: String? = nil) {
        queue = []
        ready = []
        none = []
        remembered = nil
        revision += 1
        if let uid { UserDefaults.standard.removeObject(forKey: Self.noneKey(uid)) }
        try? FileManager.default.removeItem(at: Self.learnerDir)
    }

    private func make(_ path: String, dex: DexStore) async {
        let key = Self.key(for: path)
        if await ImageCache.shared.cached(for: key) != nil {
            ready.insert(path)
            return
        }
        // The learner's own cut-out of this selfie, if they drew one (survives the cache being emptied).
        let own = Self.learnerFile(for: path)
        if let data = try? Data(contentsOf: own), let cut = UIImage(data: data) {
            ImageCache.shared.store(cut, for: key, maxSide: 1024)
            ready.insert(path)
            return
        }
        var photo = await ImageCache.shared.cached(for: path)
        if photo == nil {
            await dex.prefetchPictures([path])
            if let url = dex.url(for: path, preferThumb: false) { photo = await ImageCache.shared.load(url: url, key: path) }
        }
        guard let photo else {
            // Not readable now (offline): shown as it is this time, tried again next launch.
            none.insert(path)
            return
        }
        if let cut = await CutoutService.liftPeople(from: photo) {
            ImageCache.shared.store(cut, for: key, maxSide: 1024)
            ready.insert(path)
        } else {
            none.insert(path)
            if let uid = SupabaseClient.shared.userId {
                var kept = rememberedNone()
                kept.insert(path)
                remembered = (uid, kept)
                UserDefaults.standard.set(Array(kept), forKey: Self.noneKey(uid))
            }
        }
    }

    private func rememberedNone() -> Set<String> {
        guard let uid = SupabaseClient.shared.userId else { return [] }
        if let r = remembered, r.uid == uid { return r.paths }
        let paths = Set(UserDefaults.standard.stringArray(forKey: Self.noneKey(uid)) ?? [])
        remembered = (uid, paths)
        return paths
    }
}
