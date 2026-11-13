import Foundation
import UIKit

/// The usage records the app sends for the developer's 分析 (server `logAppEvent`, `metrics.functions.ts`).
///
/// Only a kind and the small, fixed facts the server accepts (`AppEventMeta`): the app's version, the kind of device,
/// the iOS version, the display language, a screen's name, a tutorial step's name, a feature's name. Never a photo, a
/// word, an answer, a place or any text the learner wrote — the privacy policy's 利用状況 (§1) and 画面ごとの利用 (§2)
/// (owner 2026-11-13: 「今のプライバシーポリシーに反さないように設計して」).
///
/// Fire and forget: a failure is dropped (the numbers are for the developer, never worth an error on screen). Not sent
/// from DEBUG builds (simulator, UI tests, CI previews), so test runs never count as people.
enum AppEvents {
    /// The features counted on the person's page (server `APP_FEATURES`).
    enum Feature: String {
        case lasso, selfie, search, pronounce, regenerate
        case wholePhoto = "whole_photo"
    }

    /// The tabs and the word page (server `AppEventMeta.screen`).
    enum Screen: String {
        case home, dex, word, camera, review, memory, settings, onboarding, other

        init(_ tab: AppTab) {
            switch tab {
            case .home: self = .home
            case .dex: self = .dex
            case .camera: self = .camera
            case .review: self = .review
            case .settings: self = .settings
            }
        }
    }

    /// The app came to the front: one open, with the version, device, iOS and display language.
    static func opened() {
        send("app_open", meta: deviceMeta())
        send("session_start")
        // The screen it opens on counts as a view of this visit (the server reads the screen before each leaving).
        let shown = lastScreen
        lastScreen = nil
        if let shown { screen(shown) }
    }

    /// The app went to the back: the screen open last is the one it was left on.
    static func left() {
        send("session_end")
    }

    static func screen(_ s: Screen) {
        // The same screen shown again (a tab tapped twice, a page redrawn) is one view.
        guard s != lastScreen else { return }
        lastScreen = s
        send("screen_view", meta: ["screen": s.rawValue])
    }

    static func feature(_ f: Feature) {
        // A word played again and again within a few seconds is one use.
        let now = Date()
        if let at = lastFeature[f], now.timeIntervalSince(at) < 3 { return }
        lastFeature[f] = now
        send("feature_use", meta: ["feature": f.rawValue])
    }

    /// A step of the first-run tour (`TourStep`'s name in lower case with `_`: tapCamera → tap_camera).
    static func tourStep(_ name: String) {
        guard name != "off" else { return }
        send("tutorial_step", meta: ["step": snake(name)])
    }

    /// The tour ended early (its 「終了」).
    static func tourEnded() {
        send("tutorial_skip")
    }

    // MARK: -

    private static var lastScreen: Screen?
    private static var lastFeature: [Feature: Date] = [:]

    static func snake(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch.isUppercase {
                out += "_" + ch.lowercased()
            } else {
                out.append(ch)
            }
        }
        return out
    }

    static func deviceMeta() -> [String: String] {
        var meta: [String: String] = [:]
        let info = Bundle.main.infoDictionary ?? [:]
        if let v = info["CFBundleShortVersionString"] as? String {
            if let b = info["CFBundleVersion"] as? String, b.allSatisfy(\.isNumber), !b.isEmpty {
                meta["app_version"] = "\(v) (\(b))"
            } else {
                meta["app_version"] = v
            }
        }
        meta["device"] = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let os = UIDevice.current.systemVersion
        if os.range(of: #"^\d{1,3}(\.\d{1,3}){0,2}$"#, options: .regularExpression) != nil { meta["os"] = os }
        meta["lang"] = L10n.lang
        return meta
    }

    private static func send(_ kind: String, meta: [String: String] = [:]) {
        #if DEBUG
        _ = (kind, meta)
        #else
        Task {
            var body: [String: Any] = ["kind": kind]
            if !meta.isEmpty { body["meta"] = meta }
            _ = try? await NativeAPI.call("logAppEvent", body, timeout: 20)
        }
        #endif
    }
}
