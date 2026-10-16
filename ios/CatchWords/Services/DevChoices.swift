import Foundation

/// 設定 › 開発者 › 開発者の試し: alternatives the owner compares on the device before one is kept (owner 2026-10-15: the
/// camera tab's look, the tick of the map's timeline, the tick of the Settings pickers). Plain UserDefaults keys, read
/// where each thing is drawn or played; the defaults are the shipped ones, and nothing here reaches the server.
nonisolated enum DevChoices {
    /// The camera item of the tab bar. "original" (the default, and the only shipped look — owner 2026-10-16): the bar
    /// as it was before 2026-10-15, the blue camera icon in the row. "b": the blue disc raised above the bar's edge, kept
    /// for a later release (docs/backlog.md). Any other value kept from before (the old "a" / "c") reads as "original".
    static let tabBarKey = "dev.tabbar.variant"
    static let tabBarDefault = "original"
    static let tabBarRaised = "b"
    /// The tick when a word passes the reading line of the Collection map's timeline: "off", "1", "2", "3" (default,
    /// owner 2026-10-16).
    static let timelineTickKey = "dev.sfx.timeline"
    static let timelineTickDefault = "3"
    /// The tick when a Settings pill is chosen: "off" (default, owner 2026-10-16), "1", "2", "3". The wheels' own
    /// click while they turn is not this one (`WheelTicker`).
    static let pickerTickKey = "dev.sfx.picker"
    static let pickerTickDefault = "off"

    static var tabBar: String {
        UserDefaults.standard.string(forKey: tabBarKey) == tabBarRaised ? tabBarRaised : tabBarDefault
    }

    /// The default of a tick key.
    static func tickDefault(_ key: String) -> String {
        key == timelineTickKey ? timelineTickDefault : pickerTickDefault
    }

    /// Which alternative (1–3) is on for a tick key; nil = off.
    static func tick(_ key: String) -> Int? {
        let v = UserDefaults.standard.string(forKey: key) ?? tickDefault(key)
        guard let n = Int(v), (1...3).contains(n) else { return nil }
        return n
    }
}
