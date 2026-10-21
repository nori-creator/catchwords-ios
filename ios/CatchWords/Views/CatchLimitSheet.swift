import SwiftUI

/// Today's free catches (`PlanStore`): shown when they run out (the shutter, a photo, 「解析待ち」) and from the
/// camera's counter. Owner rule (docs/monetization.md §2-1): at the limit, say first that it comes back tomorrow
/// and that reviewing is never limited — no sales pitch while Pro is not sold (`PlanStore.paywallEnabled`).
struct CatchLimitSheet: View {
    @Environment(PlanStore.self) private var plan
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
            PrimaryButton(title: L("復習する"), icon: "rectangle.stack.fill") {
                dismiss()
                router.tab = .review
            }
            Button(L("閉じる")) { dismiss() }
                .scaledFont(size: 15, weight: .medium)
                .foregroundStyle(Theme.muted)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    /// How many catches a day: the welcome week first, then the everyday amount.
    private var rule: String {
        plan.dailyLimit > PlanStore.freeCatchesPerDay
            ? L("はじめの\(PlanStore.welcomeDays)日間は1日\(PlanStore.welcomeCatchesPerDay)回、そのあとは1日\(PlanStore.freeCatchesPerDay)回撮れます。")
            : L("1日\(PlanStore.freeCatchesPerDay)回撮れます。")
    }
}
