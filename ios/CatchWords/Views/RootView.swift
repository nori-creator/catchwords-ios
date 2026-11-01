import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(DexStore.self) private var dex
    @Environment(PlanStore.self) private var plan
    @Environment(ProfileStore.self) private var profile
    @Environment(ReviewStore.self) private var review
    @Environment(\.scenePhase) private var scenePhase
    /// This account's onboarding flag on this device (`OnboardingState`), read again on every sign-in.
    @State private var onboardingDone: Bool = false
    /// The opening (`LaunchIntro`), once per launch, over whatever screen the launch opens on.
    @State private var showIntro: Bool = LaunchIntro.shouldPlay

    private var needsOnboarding: Bool {
        !onboardingDone && profile.isLoaded && !profile.loadFailed && !profile.onboarded && dex.stickers.isEmpty
    }

    /// The AI consent, once per account: after onboarding (or right after sign-in for an account that has
    /// done it), before the camera or any AI feature. Waits for the profile, so it never flashes in front of
    /// the onboarding that is about to open.
    private var needsAIConsent: Bool {
        #if DEBUG
        if StoreShot.isOn { return false }   // the App Store shots show the app as an account that agreed sees it
        #endif
        let consent = AIConsent.shared
        return consent.isLoaded && consent.isUndecided && !needsOnboarding && (profile.isLoaded || profile.loadFailed)
    }

    var body: some View {
        ZStack {
            AppBackground()
            switch auth.phase {
            case .checking:
                SplashView()
                    .transition(.opacity)
            case .signedOut:
                AuthView()
                    .uiReady("root")  // CI's launch pictures wait for the first real screen (DEBUG only)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .signedIn:
                ZStack {
                    MainTabView()
                        .accessibilityHidden(needsAIConsent)
                        .uiReady("root")
                    if needsAIConsent {
                        AIConsentView()
                            // Over the home screen (dark status-bar text): follow this screen's own background.
                            .statusBarTone(.automatic)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .zIndex(1)
                    }
                    if needsOnboarding {
                        OnboardingView {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { onboardingDone = true }
                            // The sample word, in the album, the dex and the review before the first photo.
                            dex.installSample()
                        }
                            .environment(\.colorScheme, .light)
                            .statusBarTone(.dark)
                            .transition(.opacity.combined(with: .scale(scale: 1.02)))
                            .zIndex(1)
                    }
                }
                    .transition(.opacity)
                    .task {
                        // The 図鑑's shadows read once off the main thread (`DexSilhouette.warmUp`), then Japanese line
                        // breaking's dictionary and language detection, read on their first use: the 図鑑's first open
                        // spent 6 s in them on the iPhone simulator (DexOpenTests 2026-10-20).
                        Task.detached(priority: .utility) {
                            DexSilhouette.warmUp()
                            let sample = "見つけた言葉を毎日の暮らしで覚えよう。今日の復習はここから始めます。"  // l10n-ignore (text system warm-up)
                            _ = NSAttributedString(string: sample, attributes: [.font: UIFont.systemFont(ofSize: 15)])
                                .boundingRect(with: CGSize(width: 120, height: CGFloat.greatestFiniteMagnitude),
                                              options: [.usesLineFragmentOrigin], context: nil)
                        }
                        // Before the profile arrives (`needsOnboarding` waits for it): the account that just
                        // signed in, not the previous one.
                        onboardingDone = OnboardingState.isDone(userId: SupabaseClient.shared.userId)
                        TourStep.adoptDevicePending(userId: SupabaseClient.shared.userId)
                        AIConsent.shared.load(userId: SupabaseClient.shared.userId)
                        #if DEBUG
                        // The App Store shots: the camera as an account that agreed sees it.
                        if StoreShot.isOn, !AIConsent.shared.isGranted { AIConsent.shared.grant() }
                        #endif
                        let guessed = NativeAPI.targetLanguage
                        // The dex as it was last read on this phone, at once (its pictures are on disk too); the
                        // server's read below replaces it. Read off the main thread, while the server is asked.
                        async let snapshot: Void = dex.restoreSnapshot()
                        async let p: Void = profile.load()
                        await dex.load()
                        await snapshot
                        await p
                        // First uses that used to land on the first 図鑑's opening (DexOpenTests, 2026-10-20: a 12 s
                        // first open): the location service (its CLLocationManager, made on the main thread, for the
                        // cards' place names), the text system and the tick engine's sounds (read off the main thread).
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            _ = LocationService.shared
                            // The text system's first field (the 図鑑's search field was the first one made): its
                            // settings are read from disk once, here instead.
                            _ = UITextField()
                            await SoundService.shared.prepareTicks()
                        }
                        // Today's review is read and its first cards made ready now, not when the tab is opened.
                        Task { await review.preload(dex: dex, limit: profile.effectiveReviewLimit) }
                        // This device's answer and the server's record are made to agree (an unsent answer is
                        // sent, an agreement or withdrawal made elsewhere is taken). Never awaited: a server
                        // without these functions yet, or no network, changes nothing and blocks nothing.
                        Task { await AIConsent.shared.syncWithServer() }
                        // The album was read for the language remembered on this device; another account
                        // (or a change made on the web) can have a different one.
                        if NativeAPI.targetLanguage != guessed { await dex.load() }
                        // Photos left in 「解析待ち」 are analyzed again on their own (in this account's
                        // learning language, now known); also when the connection comes back.
                        // 「保存待ち」 words (a save that failed) are saved again by the same runner.
                        PendingRetry.shared.dex = dex
                        PendingRetry.shared.start()
                        await plan.bootstrap()
                        await ReminderService.loadFromAccount()
                        // A setting taken from the account (web / another device) may be on while this iPhone
                        // was never asked: ask now (the system sheet only appears while undecided).
                        if (UserDefaults.standard.string(forKey: ReminderService.modeKey) ?? "off") != "off" {
                            _ = await ReminderService.requestPermission()
                        }
                        await ReminderService.refresh(due: dex.upcomingDueTimes)
                        // Place reminders are this account's (cleared on sign-out): set them again from its
                        // own catches when the setting is on.
                        if UserDefaults.standard.bool(forKey: ReminderService.placeKey), dex.hasLoaded {
                            await ReminderService.applyPlaces(enabled: true, stickers: dex.stickers)
                        }
                    }
            case .failed(let reason):
                ConnectionFailedView(reason: reason) {
                    Task { await auth.bootstrap() }
                }
            }
            if showIntro {
                LaunchIntro { showIntro = false }
                    .zIndex(100)
                    .transition(.identity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: auth.phase)
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: AIConsent.shared.status)
        // Dates, numbers and the time pickers in the display language, redrawn when it changes (this body reads it; the
        // App's own `.environment` may not be read again after a switch in the app).
        .environment(\.locale, L10n.locale)
        .task {
            // A review Live Activity left from a previous run (the app was closed mid-round) shows a round
            // that no longer exists: end it; a new round starts its own.
            ReviewActivityController.end()
            await auth.bootstrap()
        }
        .onChange(of: auth.phase) { _, phase in
            if phase == .signedOut {
                // Nothing of the account that just left may stay for the next one: the stores, the
                // pictures in memory, the widgets' snapshot, the review Live Activity and the reminders
                // (place reminders name its words and places).
                dex.reset()
                review.reset()
                profile.reset()
                plan.reset()
                CutoutBackfill.shared.stop()
                SelfieCutouts.shared.reset()
                DexSnapshot.removeAll()
                AIConsent.shared.reset()
                AdminAccess.shared.clear()
                PendingRetry.shared.stop()
                ImageCache.shared.removeAll()
                StickerPhoto.invalidateAll()
                ReviewActivityController.end()
                WidgetBridge.clear()
                // Every notification planned for it (reminders, the milestone album) goes in AccountCleanup.
                Task { await AccountCleanup.signedOut() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionExpired)) { _ in auth.sessionExpired() }
        // Meanings and notes follow the display language too (read again in the new one).
        .onChange(of: LanguageState.shared.lang) { _, _ in
            dex.readerLanguageChanged()
            // Scheduled reminders were written in the old language: write them again (N1). Not after a
            // sign-out (the language goes back to the iPhone's): that account's reminders were just cleared.
            guard auth.phase == .signedIn else { return }
            Task {
                await ReminderService.refresh(due: dex.upcomingDueTimes)
                // Place reminders carry their text too (only from a loaded dex: an empty one would clear them).
                if UserDefaults.standard.bool(forKey: ReminderService.placeKey), dex.hasLoaded {
                    await ReminderService.applyPlaces(enabled: true, stickers: dex.stickers)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // おまかせ reminders follow yesterday's first open and the cards coming due.
            guard phase == .active, auth.phase == .signedIn else { return }
            if profile.loadFailed { Task { await profile.load() } }
            ReminderService.recordAppOpen()
            PendingRetry.shared.kick()   // waiting photos that are due (a no-op until sign-in has finished)
            Task { await ReminderService.refresh(due: dex.upcomingDueTimes) }
            // Back after a while: picture links older than 5 hours are made again, and the review is made ready.
            dex.refreshStaleLinks()
            if dex.hasLoaded { Task { await review.preload(dex: dex, limit: profile.effectiveReviewLimit) } }
        }
    }
}

struct SplashView: View {
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var breathe: Bool = false

    var body: some View {
        VStack(spacing: 18) {
            LogoMark(size: 88)
                .scaleEffect(breathe ? 1.04 : 0.98)
            ProgressView().tint(Theme.muted)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

struct ConnectionFailedView: View {
    let reason: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Text(reason)
                .scaledFont(size: 15)
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)
            PrimaryButton(title: L("もう一度試す"), icon: "arrow.clockwise", action: retry)
                .frame(maxWidth: 260)
        }
        .padding(32)
    }
}

/// The app's mark: the App Store icon itself (`AppLogo`, a copy of `AppIcon`), in the icon's rounded square. Owner
/// 2026-10-28: the mark drawn here before (two plain rings) was not the real icon.
struct LogoMark: View {
    var size: CGFloat

    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.2237, style: .continuous))
            .shadow(color: Theme.primary.opacity(0.5), radius: size * 0.25, y: size * 0.08)
            .accessibilityHidden(true)
    }
}
