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
    /// The keys of the earlier trials (the old tab-bar choice, the sound choices, the 設定 wheel — decided, owner
    /// 2026-10-20: sound A and the app's own wheel), removed at launch.
    static let retiredKeys = ["dev.tabbar.variant", "dev.sfx.timeline", "dev.sfx.picker", "dev.sfx.settings", "dev.settings.wheel"]

    static var tabBar: String {
        UserDefaults.standard.string(forKey: tabBarKey) == tabBarRaised ? tabBarRaised : tabBarDefault
    }

    /// The camera's shutter sound (owner 2026-10-20: 「カメラのシャッター音の案を考えて」), compared on the device. A is
    /// the sound until now (its low thump was the complaint); B, a light two-stage click, until one is picked.
    static let shutterKey = "dev.sfx.shutter"
    static let shutterDefault = "light"
    @MainActor static let shutterChoices: [(value: String, sfx: SFX, label: String)] = [
        ("current", .ccShutter, "A"), ("light", .ccShutterLight, "B"), ("soft", .ccShutterSoft, "C"),
        ("digital", .ccShutterDigital, "D"),
    ]
    @MainActor static var shutterSFX: SFX {
        let v = UserDefaults.standard.string(forKey: shutterKey) ?? shutterDefault
        return (shutterChoices.first { $0.value == v } ?? shutterChoices[1]).sfx
    }

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
