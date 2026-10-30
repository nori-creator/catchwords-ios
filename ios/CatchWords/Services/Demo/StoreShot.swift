#if DEBUG
import Foundation
import UIKit

/// App Store screenshots taken on CI (`-uiStore YES`, with `-uiDemo`): the demo backend is seeded with the words and
/// pictures of `ios/StoreShots/store.json` (copied with its pictures into `Library/Caches/store/` by the workflow), and
/// the app opens on the screen the launch arguments name. Everything on screen is the real app — the real tabs, the real
/// dex, word page, review and camera — so the pictures show it as it looks on the device that takes them (iPhone Duo's
/// inner and outer screens, owner 2026-10-30).
///
/// Launch arguments (all optional): `-uiStoreTab home|dex|review|camera`, `-uiStoreDex cover|map|grid|list`,
/// `-uiStoreWord <sticker id>` (its word page opens), `-uiStoreSection <CardSection raw value>` (the page scrolled to it),
/// `-uiStoreMapDay yyyy-MM-dd`, `-uiStoreMemory YES` (the review's memory list open).
nonisolated enum StoreShot {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "uiStore") }

    static var dir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("store", isDirectory: true)
    }

    /// `store.json`, or nil when store mode is off or the file is missing.
    static var pack: [String: Any]? {
        guard isOn, let data = try? Data(contentsOf: dir.appendingPathComponent("store.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    /// A picture copied next to `store.json`.
    static func file(_ name: String) -> Data? {
        guard isOn, !name.isEmpty else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(name))
    }

    private static func arg(_ key: String) -> String? {
        guard isOn, let v = UserDefaults.standard.string(forKey: key), !v.isEmpty else { return nil }
        return v
    }

    static var tab: String? { arg("uiStoreTab") }
    static var dexMode: String? { arg("uiStoreDex") }
    static var word: String? { arg("uiStoreWord") }
    static var section: String? { arg("uiStoreSection") }
    static var memoryOpen: Bool { isOn && UserDefaults.standard.bool(forKey: "uiStoreMemory") }
    /// `-uiStorePortrait YES`: the Duo's inner screen is shot held upright (it lies sideways when opened flat).
    static var portraitOnly: Bool { isOn && UserDefaults.standard.bool(forKey: "uiStorePortrait") }

    /// The map's day (`-uiStoreMapDay`), local midnight.
    static var mapDay: Date? {
        guard let s = arg("uiStoreMapDay") else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s).map { Calendar.current.startOfDay(for: $0) }
    }

    /// The camera's viewfinder picture (`camera_photo` in `store.json`).
    static var cameraPhoto: UIImage? {
        guard let name = pack?["camera_photo"] as? String, let data = file(name) else { return nil }
        return UIImage(data: data)
    }

    /// The screen has settled: CI takes the picture after this file appears.
    static func ready() {
        guard isOn else { return }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ui-ready", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data().write(to: dir.appendingPathComponent("store"))
    }
}
#endif
