import Foundation

/// The dex as it was last read, kept on this phone per account, learning language and display language, so the
/// home album, the dex and the review are on screen the moment the app opens (owner 2026-10-11: 「写真や復習の
/// 問題を読み込む時間のラグをなくす」). The server's read replaces it a moment later (`DexStore.load`).
/// Signing out removes every snapshot (`removeAll`), like the pictures kept on disk.
nonisolated enum DexSnapshot {
    struct Payload: Codable, Sendable {
        var version: Int
        var stickers: [Sticker]
        var albumHidden: [String]
        var placements: [Placement]
    }

    /// A photo's place on the home album page (`stickers.album_*`).
    struct Placement: Codable, Sendable {
        var id: String
        var order: Int?
        var size: String?
        var x: Double?
        var y: Double?
        var scale: Double?
        var rot: Double?
    }

    /// Raised when the shape changes: an older file is then ignored (and replaced by the next read).
    static let version = 1

    private static let dir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dex-snapshot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func file(uid: String, lang: String, reader: String) -> URL {
        dir.appendingPathComponent("\(uid)-\(lang)-\(reader).json")
    }

    static func save(_ payload: Payload, uid: String, lang: String, reader: String) {
        let encoder = JSONEncoder()
        // The same date text the server sends, so `SupabaseDate.decoder` reads it back.
        encoder.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(SupabaseDate.string(date))
        }
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: file(uid: uid, lang: lang, reader: reader), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load(uid: String, lang: String, reader: String) -> Payload? {
        guard let data = try? Data(contentsOf: file(uid: uid, lang: lang, reader: reader)),
              let payload = try? SupabaseDate.decoder.decode(Payload.self, from: data),
              payload.version == version else { return nil }
        return payload
    }

    /// Signing out or deleting the account: nothing of that account's dex stays on the phone.
    static func removeAll() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
