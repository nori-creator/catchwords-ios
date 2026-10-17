import Foundation

/// 設定 › 開発者 › 開発者の試し: an alternative a developer can see on the device before it ships. Only the camera tab's
/// look is left (the sound choices were decided, owner 2026-10-16). A plain UserDefaults key, read where the bar is
/// drawn; nothing here reaches the server.
nonisolated enum DevChoices {
    /// The camera item of the tab bar. "original" (the default, and the only shipped look): the bar as it was before
    /// 2026-10-15, the blue camera icon in the row. "b": the blue disc raised above the bar's edge, kept for a later
    /// release (docs/backlog.md). A new key (2026-10-16): the owner's iPad still held "b" from the trial under the old
    /// key and showed the raised disc; that key is removed once at launch (`migrate`), so B shows only if picked again.
    static let tabBarKey = "dev.tabbar.choice.v2"
    static let tabBarDefault = "original"
    static let tabBarRaised = "b"
    /// The keys of the earlier trials (the old tab-bar choice and the two sound choices), removed at launch.
    static let retiredKeys = ["dev.tabbar.variant", "dev.sfx.timeline", "dev.sfx.picker"]

    static var tabBar: String {
        UserDefaults.standard.string(forKey: tabBarKey) == tabBarRaised ? tabBarRaised : tabBarDefault
    }

    /// Once per launch, before anything is drawn: the retired trial keys go (a stored "b" from the old trial never
    /// brings the raised disc back on its own).
    static func migrate() {
        for key in retiredKeys where UserDefaults.standard.object(forKey: key) != nil {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
