import UIKit
import CryptoKit
import ImageIO

/// Pictures keyed by STORAGE PATH (signed URLs change, paths don't), in two layers:
/// - memory: decoded images (NSCache) for the screens in front of you;
/// - disk: the files themselves (Caches/images), so a picture seen once — or taken on this phone — shows at once
///   on the next launch too: before the dex has signed its links, and offline (owner 2026-10-11: 「写真を読み込む
///   時間のラグをなくす」). A storage path never changes content (every upload gets a new timestamped name), so a
///   kept file never goes stale. A thumbnail is kept under its own key (`path + DexStore.thumbSuffix`).
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    /// Disk reads running now (one per key): a screen asking twice for a picture decodes it once.
    private var reading: [String: Task<UIImage?, Never>] = [:]
    /// Files written since the last trim (the folder is trimmed every so often, not on every write).
    private var writes = 0

    /// Caches/images. The system may empty it when space runs low: it only ever holds copies.
    nonisolated private static let dir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// The folder keeps at most this much (least recently used files go first).
    nonisolated private static let maxBytes = 500 * 1024 * 1024

    init() {
        cache.countLimit = 400
        // Bounded by decoded bytes, not only by count: 400 full photos (1600 px) would be ~3 GB of bitmaps.
        cache.totalCostLimit = 160 * 1024 * 1024
        let dir = Self.dir
        Task.detached(priority: .background) { Self.trim(dir) }
    }

    // MARK: Memory

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
    }

    /// In memory under `key`, counted as `cost` bytes (`store(_:for:maxSide:)`: a picture about to be replaced by its
    /// smaller copy).
    private func set(_ image: UIImage, for key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    // MARK: Disk

    /// A picture made on this phone (a catch's photo, cut-out or selfie, a replaced photo): in memory now, and on
    /// disk, so the album and the dex show it at once after a relaunch — no download and no signed link needed.
    ///
    /// `maxSide`: kept at most this size (the size it is uploaded at). A camera photo is 12 MP or more (48 MB decoded on
    /// an iPad): put in memory as it is, it pushed the dex's pictures out of the 160 MB cache right as the catch landed,
    /// and every square of the dex had to be read again from disk — the dex looked blank behind the landing (owner
    /// 2026-10-15). It is shown at once, counted at the size it is about to be, and replaced by its smaller copy (the one
    /// written to disk) a moment later.
    func store(_ image: UIImage, for key: String, maxSide: CGFloat? = nil) {
        let png = key.lowercased().hasSuffix(".png")
        let file = Self.file(for: key)
        noteWrite()
        let side = max(image.size.width, image.size.height) * image.scale
        guard let maxSide, side > maxSide * 1.05 else {
            set(image, for: key)
            Task.detached(priority: .utility) {
                guard !FileManager.default.fileExists(atPath: file.path) else { return }
                // A cut-out keeps its transparency (PNG); photos are JPEG.
                guard let data = png ? image.pngData() : image.jpegData(compressionQuality: 0.9) else { return }
                try? data.write(to: file, options: .atomic)
            }
            return
        }
        let ratio = maxSide / side
        set(image, for: key, cost: max(1, Int(Double(Self.cost(of: image)) * Double(ratio * ratio))))
        Task {
            let small = await Task.detached(priority: .userInitiated) { ImageTools.resized(image, maxSide: maxSide) }.value
            // Still the very picture under this key (not removed, not replaced meanwhile).
            if self.image(for: key) === image { self.set(small, for: key) }
            Task.detached(priority: .utility) {
                guard !FileManager.default.fileExists(atPath: file.path) else { return }
                guard let data = png ? small.pngData() : small.jpegData(compressionQuality: 0.9) else { return }
                try? data.write(to: file, options: .atomic)
            }
        }
    }

    /// The picture from memory, else from disk (decoded off the main thread); nil when it was never kept.
    func cached(for key: String) async -> UIImage? {
        if let hit = image(for: key) { return hit }
        if let running = reading[key] { return await running.value }
        let file = Self.file(for: key)
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: file), let raw = UIImage(data: data) else { return nil }
            // Used again: the newest for the size limit (`trim` drops the least recently used).
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return raw.preparingForDisplay() ?? raw
        }
        reading[key] = task
        let img = await task.value
        reading[key] = nil
        if let img { set(img, for: key) }
        return img
    }

    // MARK: Small copies (a square of the dex, a sticker on the album)

    /// The largest side, in pixels, a small copy is decoded at for a picture drawn `points` wide or high: one of a few
    /// steps (so a picture resized a little reuses its copy), or nil past 1024 px (then the picture itself is used).
    nonisolated static func pixelStep(forPoints points: CGFloat) -> Int? {
        // 3 px a point: the sharpest screens (an iPad's 2 decodes a little more than needed, never less).
        let px = points * 3
        return [256, 384, 512, 768, 1024].first { CGFloat($0) >= px }
    }

    /// The memory key of the small copy of `key` at `maxPixel`.
    nonisolated static func smallKey(_ key: String, maxPixel: Int) -> String { "\(key)#\(maxPixel)" }

    /// The picture in memory for a drawing at `maxPixel` (its small copy, or the picture itself), or for full size.
    func image(for key: String, maxPixel: Int?) -> UIImage? {
        if let maxPixel, let small = image(for: Self.smallKey(key, maxPixel: maxPixel)) { return small }
        return image(for: key)
    }

    /// A kept picture for a drawing at `maxPixel`: decoded straight at that size from the file on disk (ImageIO's
    /// thumbnail, off the main thread), never the whole picture first — a dex of 1024 px cut-outs decoded every square
    /// at full size (4 MB each in memory, so the 160 MB cache could not even hold one screen of them, and they were
    /// decoded again on every scroll). With no size, the picture itself (`cached(for:)`).
    func kept(for key: String, maxPixel: Int?) async -> UIImage? {
        guard let maxPixel else { return await cached(for: key) }
        if let hit = image(for: key, maxPixel: maxPixel) { return hit }
        let small = Self.smallKey(key, maxPixel: maxPixel)
        if let running = reading[small] { return await running.value }
        let file = Self.file(for: key)
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard FileManager.default.fileExists(atPath: file.path),
                  let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let img = Self.downsample(source, maxPixel: maxPixel) else { return nil }
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return img
        }
        reading[small] = task
        let img = await task.value
        reading[small] = nil
        if let img { set(img, for: small) }
        return img
    }

    /// The image source's first picture at most `maxPixel` on its longest side, decoded now (not at first draw).
    nonisolated private static func downsample(_ source: CGImageSource, maxPixel: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Whether the file for this key is on disk (nothing is decoded).
    func hasFile(for key: String) -> Bool {
        FileManager.default.fileExists(atPath: Self.file(for: key).path)
    }

    /// Memory, then disk, then the network. A downloaded picture is kept on disk for next time. `maxPixel`: decoded
    /// at that size for a small drawing (`kept(for:maxPixel:)`); the file kept is the whole picture either way.
    func load(url: URL, key: String, maxPixel: Int? = nil) async -> UIImage? {
        if let hit = await kept(for: key, maxPixel: maxPixel) { return hit }
        guard let data = await Self.download(url) else { return nil }
        let file = Self.file(for: key)
        guard let img = await Task.detached(priority: .utility, operation: { () -> UIImage? in
            if let maxPixel {
                // Only a real picture is kept (an error page saved as a photo would show nothing forever).
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let small = Self.downsample(source, maxPixel: maxPixel) else { return nil }
                try? data.write(to: file, options: .atomic)
                return small
            }
            guard let raw = UIImage(data: data) else { return nil }
            try? data.write(to: file, options: .atomic)
            return raw.preparingForDisplay() ?? raw
        }).value else { return nil }
        set(img, for: maxPixel.map { Self.smallKey(key, maxPixel: $0) } ?? key)
        noteWrite()
        return img
    }

    /// Puts a picture on disk ahead of time (nothing decoded into memory): the pictures the learner is likely to
    /// open next (the review cards, the newest words). Returns false when it could not be fetched.
    @discardableResult
    func prefetch(url: URL, key: String) async -> Bool {
        if image(for: key) != nil || hasFile(for: key) { return true }
        guard let data = await Self.download(url) else { return false }
        let file = Self.file(for: key)
        let ok = await Task.detached(priority: .utility, operation: { () -> Bool in
            // Only a real picture is kept (an error page saved as a photo would show nothing forever).
            guard UIImage(data: data) != nil else { return false }
            return (try? data.write(to: file, options: .atomic)) != nil
        }).value
        if ok { noteWrite() }
        return ok
    }

    /// Signing out: the next account must not be shown this one's pictures — in memory or on disk.
    func removeAll() {
        cache.removeAllObjects()
        reading = [:]
        let dir = Self.dir
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: Pieces

    /// A 2xx answer's bytes, or nil (offline, an expired link, a missing file).
    nonisolated private static func download(_ url: URL) async -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else { return nil }
        return data
    }

    /// One file per key: the key's SHA-256 (paths hold slashes and may be long). The bundled sample word's pictures
    /// are read from the app bundle itself (`SampleSticker`): never downloaded, never cleared with the cache.
    nonisolated private static func file(for key: String) -> URL {
        if let bundled = SampleSticker.bundledImageURL(for: key) { return bundled }
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name)
    }

    private func noteWrite() {
        writes += 1
        guard writes >= 40 else { return }
        writes = 0
        let dir = Self.dir
        Task.detached(priority: .background) { Self.trim(dir) }
    }

    /// Deletes the least recently used files until the folder is within `maxBytes`.
    nonisolated private static func trim(_ dir: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        var entries: [(url: URL, date: Date, size: Int)] = files.compactMap { url -> (url: URL, date: Date, size: Int)? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url: url, date: v.contentModificationDate ?? .distantPast, size: v.fileSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        entries.sort { $0.date < $1.date }
        for e in entries {
            guard total > maxBytes else { break }
            try? FileManager.default.removeItem(at: e.url)
            total -= e.size
        }
    }

    private static func cost(of image: UIImage) -> Int {
        if let cg = image.cgImage { return cg.bytesPerRow * cg.height }
        let px = image.size.width * image.scale * image.size.height * image.scale
        return Int(max(1, px * 4))
    }
}
