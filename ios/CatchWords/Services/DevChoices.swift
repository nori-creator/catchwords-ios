import Foundation

/// 設定 › 開発者 › 開発者の試し: alternatives the owner compares on the device before one is kept (owner 2026-10-15: the
/// camera tab's look, the tick of the map's timeline, the tick of the Settings pickers). Plain UserDefaults keys, read
/// where each thing is drawn or played; the defaults are the recommended ones, and nothing here reaches the server.
nonisolated enum DevChoices {
    /// The camera item of the tab bar: "a" a filled blue disc in the bar (default), "b" a disc raised above the bar's
    /// edge, "c" the blue icon with a light capsule behind it.
    static let tabBarKey = "dev.tabbar.variant"
    static let tabBarDefault = "a"
    /// The tick when a word passes the reading line of the Collection map's timeline: "off", "1" (default), "2", "3".
    static let timelineTickKey = "dev.sfx.timeline"
    /// The tick when a Settings pill is chosen or a wheel passes a value: "off", "1" (default), "2", "3".
    static let pickerTickKey = "dev.sfx.picker"
    static let tickDefault = "1"

    static var tabBar: String {
        let v = UserDefaults.standard.string(forKey: tabBarKey) ?? tabBarDefault
        return ["a", "b", "c"].contains(v) ? v : tabBarDefault
    }

    /// Which alternative (1–3) is on for a tick key; nil = off.
    static func tick(_ key: String) -> Int? {
        let v = UserDefaults.standard.string(forKey: key) ?? tickDefault
        guard let n = Int(v), (1...3).contains(n) else { return nil }
        return n
    }
}
