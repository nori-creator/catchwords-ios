import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform

/// Rewarded ads, the app's only ad format (owner decision 2026-10-21, docs/monetization.md): at the end of the day's
/// free catches the learner may choose to watch one and gets one more catch (`PlanStore.grantBonusCatch`, at most
/// `PlanStore.maxBonusPerDay` a day). Never shown on its own, never at launch, never during a catch.
///
/// Order (Google's sample, googleads-mobile-ios-examples SwiftUIDemo): the consent form of Google's User Messaging
/// Platform first (shown only where the law asks, e.g. the EEA/UK), then the SDK starts, then one ad is loaded ahead.
/// No App Tracking Transparency prompt: the app does not ask to track (owner 2026-10-21), so ads use no IDFA.
@MainActor
@Observable
final class RewardedAds: NSObject {
    static let shared = RewardedAds()

    #if DEBUG
    /// Google's test unit for rewarded ads: DEBUG builds never request real ads (clicking your own is a policy breach).
    static let unitID = "ca-app-pub-3940256099942544/1712485313"
    #else
    static let unitID = "ca-app-pub-5322226492885516/5831285799"
    #endif

    /// Off under `-uiDemo` (DEBUG: the UI tests run offline).
    static var enabled: Bool {
        #if DEBUG
        return !DemoBackend.isOn
        #else
        return true
        #endif
    }

    private(set) var ad: RewardedAd?
    private(set) var isLoading = false
    /// The ad could not be loaded (no fill, no network, no consent): the sheet says so instead of waiting.
    private(set) var unavailable = false
    var isReady: Bool { ad != nil }

    private var started = false
    private var preparing = false
    private var earned = false
    private var onFinish: ((Bool) -> Void)?

    /// Consent, SDK start and one ad loaded ahead. Called when the day's catches are nearly used up and when the
    /// limit sheet opens; cheap to call again.
    func prepare() {
        guard Self.enabled, !preparing else { return }
        if started {
            load()
            return
        }
        preparing = true
        ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if error == nil {
                    try? await ConsentForm.loadAndPresentIfRequired(from: nil)
                }
                self.preparing = false
                guard ConsentInformation.shared.canRequestAds else {
                    self.unavailable = true
                    return
                }
                if !self.started {
                    self.started = true
                    _ = await MobileAds.shared.start()
                }
                self.load()
            }
        }
    }

    private func load() {
        guard ad == nil, !isLoading else { return }
        isLoading = true
        unavailable = false
        Task {
            do {
                let loaded = try await RewardedAd.load(with: Self.unitID, request: Request())
                loaded.fullScreenContentDelegate = self
                ad = loaded
            } catch {
                unavailable = true
            }
            isLoading = false
        }
    }

    /// Shows the loaded ad over whatever is on screen. `done(true)` only when it was watched to the reward.
    func show(_ done: @escaping (Bool) -> Void) {
        guard let ad else {
            done(false)
            return
        }
        earned = false
        onFinish = done
        ad.present(from: Self.topController()) { [weak self] in
            self?.earned = true
        }
    }

    /// Privacy options form (Google's consent): offered in Settings when the learner's region needs one.
    var privacyOptionsRequired: Bool {
        Self.enabled && ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    func presentPrivacyOptions() {
        Task { try? await ConsentForm.presentPrivacyOptionsForm(from: Self.topController()) }
    }

    private func finish() {
        let done = onFinish
        onFinish = nil
        ad = nil
        done?(earned)
        earned = false
        load()   // the next one ready for the second extra catch
    }

    /// The front-most screen (the limit sheet is itself presented over the tabs).
    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var vc = scene?.keyWindow?.rootViewController
        while let next = vc?.presentedViewController { vc = next }
        return vc
    }
}

extension RewardedAds: FullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.finish() }
    }
}
