import SwiftUI

/// Today's free catches (`PlanStore`): shown when they run out (the shutter, a photo, 「解析待ち」) and from the
/// camera's counter. Owner rule (docs/monetization.md §2-1): at the limit, say first that it comes back tomorrow
/// and that reviewing is never limited — no sales pitch while Pro is not sold (`PlanStore.paywallEnabled`).
/// The learner may choose to watch a rewarded ad for one more catch (`RewardedAds`, at most 2 a day).
struct CatchLimitSheet: View {
    @Environment(PlanStore.self) private var plan
    private let ads = RewardedAds.shared
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: plan.remainingToday == 0 ? "moon.stars.fill" : "camera.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 72, height: 72)
                .background(Theme.accent, in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(plan.remainingToday == 0 ? L("今日のキャッチはここまでです") : L("今日あと\(plan.remainingToday)回撮れます"))
                    .scaledFont(size: 20, weight: .bold)
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)
                Text(plan.remainingToday == 0 ? L("明日はまた\(plan.tomorrowLimit)回撮れます。") : rule)
                    .scaledFont(size: 15)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Text(L("図鑑の単語の復習は、いつでも何回でもできます。"))
                    .scaledFont(size: 15)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)
            if offersAd {
                adButton
                Button {
                    dismiss()
                    router.tab = .review
                } label: {
                    Text(L("復習する"))
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(Theme.primaryInk)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .overlay(Capsule().stroke(Theme.primaryInk.opacity(0.35), lineWidth: 1.5))
                }
                .buttonStyle(PressableStyle())
            } else {
                PrimaryButton(title: L("復習する"), icon: "rectangle.stack.fill") {
                    dismiss()
                    router.tab = .review
                }
            }
            Button(L("閉じる")) { dismiss() }
                .scaledFont(size: 15, weight: .medium)
                .foregroundStyle(Theme.muted)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .task { if offersAd { ads.prepare() } }
    }

    /// No catch left, an extra one still allowed today, and ads on.
    private var offersAd: Bool {
        RewardedAds.enabled && !plan.isPro && plan.remainingToday == 0 && plan.canEarnBonus
    }

    @ViewBuilder
    private var adButton: some View {
        VStack(spacing: 6) {
            PrimaryButton(title: ads.isReady || ads.unavailable ? L("広告を見て1回ふやす") : L("広告を読み込んでいます…"),
                          icon: "play.rectangle.fill", isLoading: ads.isLoading && !ads.isReady) {
                ads.show { earned in
                    guard earned, plan.grantBonusCatch() else { return }
                    Haptics.success()
                    dismiss()
                    router.showNotice(L("1回ふえました"))
                }
            }
            .disabled(!ads.isReady)
            Text(ads.unavailable && !ads.isReady
                 ? L("今は広告がありません。しばらくしてからお試しください。")
                 : L("今日はあと\(PlanStore.maxBonusPerDay - plan.bonusToday)回ふやせます"))
                .scaledFont(size: 12)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
    }

    /// How many catches a day: the welcome week first, then the everyday amount.
    private var rule: String {
        plan.dailyLimit > PlanStore.freeCatchesPerDay
            ? L("はじめの\(PlanStore.welcomeDays)日間は1日\(PlanStore.welcomeCatchesPerDay)回、そのあとは1日\(PlanStore.freeCatchesPerDay)回撮れます。")
            : L("1日\(PlanStore.freeCatchesPerDay)回撮れます。")
    }
}
