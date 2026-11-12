import SwiftUI

@main
struct CatchWordsApp: App {
    /// Upright only, except on iPhone Duo's open inner screen (`ScreenOrientation`).
    @UIApplicationDelegateAdaptor(OrientationDelegate.self) private var orientation
    @State private var auth = AuthStore()
    @State private var dex = DexStore()
    @State private var plan = PlanStore()
    @State private var profile = ProfileStore()
    /// Today's review, read and made ready before the review tab opens (RootView → `ReviewStore.preload`).
    @State private var review = ReviewStore()
    @AppStorage("theme.pref") private var themePref: String = "light"

    /// ライト / ダーク / システム (web settings theme).
    private var scheme: ColorScheme? {
        switch themePref {
        case "dark": .dark
        case "system": nil
        default: .light
        }
    }

    init() {
        // Crashes and failures to Sentry, first, so a crash in the rest of the start is caught (release builds only).
        ErrorReporting.start()
        #if DEBUG
        DemoBackend.install()  // -uiDemo: every request answered offline (UI tests on CI)
        UITestTrace.start()    // -uiDemo: the touches and the catch's steps, for CI (uitest-trace.txt)
        // -uiPreview: the screens are photographed as an account that agreed to the AI consent sees them
        // (the consent screen itself is the "aiconsent" scene).
        if UIPreview.parsed != nil {
            AIConsent.shared.load(userId: nil)
            if !AIConsent.shared.isGranted { AIConsent.shared.grant() }
        }
        #endif
        // Settings values renamed to the web's: sound "soft" → "subtle".
        if UserDefaults.standard.string(forKey: "sound.level") == "soft" {
            UserDefaults.standard.set("subtle", forKey: "sound.level")
        }
        // The developer choices retired in 1.0.1 (the old tab-bar choice, the tick choices): gone, once, before
        // anything is drawn — the camera bar is the original one until B is picked again (owner 2026-10-16).
        DevChoices.migrate()
        ReadingDefault.settle()
        SoundService.shared.configure()
        HapticPatterns.warmUp()   // the haptic engine, made off the main thread before the first tap
        NotificationRouter.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let p = UIPreview.parsed {
                // "<scene>-dark" photographs the same scene in the dark appearance;
                // "-en" / "-zh" in another display language; "-duo" / "-duoland" on iPhone Duo's inner screen, upright / sideways.
                UIPreviewRoot(name: p.scene, duo: p.duo, land: p.land)
                    .environment(\.locale, L10n.locale)
                    .environment(dex)
                    .environment(auth)
                    .environment(plan)
                    .environment(profile)
                    .environment(review)
                    // The status bar's colour as the app sets it (the previews showed the opening's blue under black text).
                    .statusBarRoot()
                    .preferredColorScheme(p.dark ? .dark : .light)
                    .appTypeSizeCap()
                    .appMotionPreference()
            } else {
                app
            }
            #else
            app
            #endif
        }
    }

    private var app: some View {
            RootView()
                .environment(\.locale, L10n.locale)
                .environment(auth)
                .environment(dex)
                .environment(plan)
                .environment(profile)
                .environment(review)
                .statusBarRoot()  // status-bar text colour per screen (inside the theme's colour scheme)
                .preferredColorScheme(scheme)
                .tint(Theme.primary)
                .appTypeSizeCap()  // Dynamic Type up to accessibility 2 (ScaledFont.swift)
                .widgetBridge(dex: dex)  // home/lock-screen widgets: snapshot upkeep + catchwords:// links
                .appMotionPreference()  // 設定 › アニメーション → \.appReduceMotion for every screen (MotionPreference.swift)
                // The Duo folded or opened: the ways the screen may turn are asked again (ScreenOrientation).
                .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in ScreenOrientation.refresh() }
    }
}

/// 設定 › 発音表記 on a phone that has never chosen one (owner 2026-11-12: 「初めてこのアプリを入れたユーザーにはピンインを
/// 表示するようにして」 — a new user's tutorial read in 注音). A new install starts on pinyin; a phone that has used the app
/// before keeps the 注音 it has been reading (it never chose, so it read the old default). Decided once, then stored.
enum ReadingDefault {
    static func settle(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: "reading.pref") == nil else { return }
        #if DEBUG
        // CI and the UI tests keep the readings they were written against (they pass -reading.pref where they need one).
        if defaults.bool(forKey: "uiDemo") || defaults.string(forKey: "uiPreview") != nil { return }
        #endif
        defaults.set(usedBefore(defaults) ? "zhuyin" : "pinyin", forKey: "reading.pref")
    }

    /// Something only a phone that has been through sign-in, onboarding or a catch keeps.
    static func usedBefore(_ defaults: UserDefaults) -> Bool {
        defaults.dictionaryRepresentation().keys.contains { key in
            key.hasPrefix("onboarding.done") || key.hasPrefix("aiConsent") || key == "plan.day" || key == "last.targetLanguage"
        }
    }
}
