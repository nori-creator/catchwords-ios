import Foundation

/// 設定 › 開発者 › 開発者の試し was where a developer compared an alternative look on the device before it shipped. Every
/// trial is decided now (the sounds 2026-10-16/20, the shutter 2026-10-21, the camera disc 2026-10-25: 「開発者の試しの
/// 下のバーのカメラを浮いた丸に変更して」), so the trials section is gone and only the clean-up of their stored keys is left.
nonisolated enum DevChoices {
    /// The keys of the earlier trials (the tab-bar choices, the sound choices, the 設定 wheel and the shutter), removed
    /// at launch.
    static let retiredKeys = ["dev.tabbar.variant", "dev.tabbar.choice.v2", "dev.sfx.timeline", "dev.sfx.picker",
                              "dev.sfx.settings", "dev.settings.wheel", "dev.sfx.shutter"]

    /// Once per launch, before anything is drawn: the retired trial keys go.
    static func migrate() {
        for key in retiredKeys where UserDefaults.standard.object(forKey: key) != nil {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
