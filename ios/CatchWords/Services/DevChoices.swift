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

    /// The sound of a choice made in 設定 (owner 2026-10-20: 「最適な音を複数提案して」), compared on the device from
    /// 設定 › 開発者 › 開発者の試し. The one picked there plays for everyone on this device; "pick" until then.
    static let settingsSoundKey = "dev.sfx.settings"
    @MainActor static let settingsSoundChoices: [(value: String, sfx: SFX, label: String)] = [
        ("pick", .c6PickTick3, "A"), ("pop", .ccPop, "B"), ("choose", .c6Choose, "C"), ("tick", .ccTick, "D"),
    ]
    @MainActor static var settingsSound: String {
        let v = UserDefaults.standard.string(forKey: settingsSoundKey) ?? "pick"
        return settingsSoundChoices.contains { $0.value == v } ? v : "pick"
    }
    @MainActor static var settingsSoundSFX: SFX {
        settingsSoundChoices.first { $0.value == settingsSound }?.sfx ?? .c6PickTick3
    }

    /// The 設定 wheels: the app's own (`TickWheel`, ticking every row, the default) or the system wheel, to compare on
    /// the device (owner 2026-10-20). The system one only for a signed-in developer who picked it.
    static let wheelKey = "dev.settings.wheel"
    static let wheelApp = "app"
    static let wheelSystem = "system"

    /// The simulator previews (`-uiPreview tabbar-b`) draw a developer's choice without an account behind them.
    nonisolated(unsafe) static var previewing = false

    /// Once per launch, before anything is drawn: the retired trial keys go (a stored "b" from the old trial never
    /// brings the raised disc back on its own).
    static func migrate() {
        for key in retiredKeys where UserDefaults.standard.object(forKey: key) != nil {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
