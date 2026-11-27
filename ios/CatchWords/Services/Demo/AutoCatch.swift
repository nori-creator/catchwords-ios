import UIKit

/// The whole catch played by itself, from the shutter to the word landing in the 図鑑 (owner 2026-11-27: 「カメラ撮って
/// から、図鑑に追加されるまでの全てのアニメーション　限界まで滑らかにして。カクカクなしで」), so CI can measure every part of
/// it on the real screens (`-uiDemo` with `-uiAutoCatch YES`, DEBUG builds only; nothing in a release build).
///
/// The camera tab opens, the shutter takes the demo photo (as large as a camera's, `photo`), a tag is tapped once the
/// tags are up, the first way to say it is chosen, and the GET moment and the landing play as they do for a learner.
/// With `-uiProfile YES` the main thread is sampled from the shutter to a second and a half after the landing's impact
/// (`MainProfiler`), cut at each step: shutter, tags, tap, cut, pick, get, launch, impact.
nonisolated enum AutoCatch {
    static var isOn: Bool {
        #if DEBUG
        return DemoBackend.isOn && UserDefaults.standard.bool(forKey: "uiAutoCatch")
        #else
        return false
        #endif
    }

    /// How many catches one launch plays (`-uiAutoCatchRounds`, 3 by default): the first after a cold start (on the
    /// simulator Vision runs on the CPU and the first photo's scan takes over a minute), then two with everything warm.
    static var rounds: Int {
        let n = UserDefaults.standard.integer(forKey: "uiAutoCatchRounds")
        return n > 0 ? n : 3
    }

    nonisolated(unsafe) private static var played = 0
    private static let lock = NSLock()

    /// Takes the next round's number (nil once every round has been played).
    static func nextRound() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard played < rounds else { return nil }
        played += 1
        return played
    }

    /// The round being played (0 before the first).
    static var round: Int {
        lock.lock()
        defer { lock.unlock() }
        return played
    }

    /// The demo photo at a camera's size (3024 × 4032, 12 MP): the catch's own copies, cut-outs and stand-ins are made
    /// from a photo this large on a phone, and the work they take is part of what is measured.
    static func photo(from small: UIImage) -> UIImage {
        lock.lock()
        if let made = cameraSized { lock.unlock(); return made }
        lock.unlock()
        let portrait = small.size.height >= small.size.width
        let size = portrait ? CGSize(width: 3024, height: 4032) : CGSize(width: 4032, height: 3024)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let made = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            small.draw(in: CGRect(origin: .zero, size: size))
        }
        lock.lock()
        cameraSized = made
        lock.unlock()
        return made
    }

    nonisolated(unsafe) private static var cameraSized: UIImage?
}
