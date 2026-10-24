import SwiftUI
import StoreKit

/// Monthly vs yearly (yearly highlighted, shown per-month) per docs/monetization.md.
struct PaywallView: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion

    @State private var selectedID: String = PlanStore.productIDs[0]
    @State private var appeared: Bool = false
    @State private var float: Bool = false

    /// Only what Pro really changes (App Store Review 2.3.1 / 3.1.2: no promise the app does not keep).
    /// - The daily limit exists only while `catchLimitEnabled` is on.
    /// - Cut-outs are free and unlimited for everyone, so they are not a Pro benefit.
    /// - 「作り直す」 is decided by the server, which does not know App Store purchases yet
    ///   (`PlanStore.serverVerifiesAppStore`).
    private var benefits: [(String, String, String)] {
        var list: [(String, String, String)] = []
        if PlanStore.catchLimitEnabled {
            list.append(("infinity", L("撮影・キャッチが無制限"), L("1日5回の上限がなくなります")))
        }
        if PlanStore.serverVerifiesAppStore {
            list.append(("wand.and.stars", L("解説の作り直し"), L("気になるカードをいつでも作り直せます")))
        }
        list.append(("heart.fill", L("開発を応援"), L("これからの機能づくりを支えます")))
        return list
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 26) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.muted)
                                .frame(width: 44, height: 44)
                                .background(Theme.card, in: Circle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.9))
                        .accessibilityLabel(L("閉じる"))
                    }
                    ZStack {
                        Circle().fill(Theme.primary.opacity(0.25)).frame(width: 180).blur(radius: 40)
                        LogoMark(size: 104)
                            .offset(y: float ? -6 : 4)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.gold)
                            .shadow(color: Theme.gold.opacity(0.7), radius: 10)
                            .offset(x: 48, y: -54 + (float ? -6 : 4))
                    }
                    .frame(height: 150)
                    VStack(spacing: 8) {
                        Text(L("街じゅうを、図鑑にしよう。"))
                            .scaledFont(size: 26, weight: .bold)
                            .foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.center)
                        Text(PlanStore.catchLimitEnabled && plan.remainingToday == 0 ? L("今日の無料キャッチ（3回）を使い切りました。") : L("Proなら、見つけた瞬間に何度でも。"))
                            .scaledFont(size: 17)
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    VStack(spacing: 12) {
                        ForEach(Array(benefits.enumerated()), id: \.offset) { idx, b in
                            HStack(spacing: 14) {
                                Image(systemName: b.0).font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.primary)
                                    .frame(width: 40, height: 40)
                                    .background(Theme.accent, in: .rect(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.1).scaledFont(size: 15, weight: .semibold).foregroundStyle(Theme.foreground)
                                    Text(b.2).scaledFont(size: 12).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                            }
                            .opacity(appeared ? 1 : 0)
                            .offset(x: appeared ? 0 : -20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.1 + Double(idx) * 0.06), value: appeared)
                        }
                    }
                    plans
                    PrimaryButton(title: buyTitle, icon: plan.products.isEmpty && !plan.isLoadingProducts ? "arrow.clockwise" : "sparkles",
                                  isLoading: plan.isPurchasing, sheen: true) {
                        guard let product = plan.products.first(where: { $0.id == selectedID }) ?? plan.products.first else {
                            Task { await plan.loadProducts() }   // the prices could not be read: try again
                            return
                        }
                        Task {
                            await plan.purchase(product)
                            if plan.isPro { dismiss() }
                        }
                    }
                    .disabled(plan.isLoadingProducts)
                    if let msg = plan.message {
                        Text(msg).scaledFont(size: 13).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    HStack(spacing: 18) {
                        Button(L("購入を復元")) { Task { await plan.restore(); if plan.isPro { dismiss() } } }
                            .buttonStyle(PressableStyle(scale: 0.97))
                        Link(L("利用規約"), destination: AppConfig.termsURL)
                        Link(L("プライバシー"), destination: AppConfig.privacyURL)
                    }
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    Link(L("特定商取引法に基づく表記"), destination: AppConfig.tokushohoURL)
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundStyle(Theme.muted)
                    // Auto-renewal terms (Guideline 3.1.2): readable size and full contrast, not fine print.
                    Text(L("お支払いは購入の確定時にApple IDに請求されます。サブスクリプションは期間終了の24時間前までに解約しない限り、同じ期間・同じ価格で自動更新されます。解約はApp Storeのアカウント設定からいつでも行えます。"))
                        .scaledFont(size: 12)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
        .task { await plan.loadProducts() }
        .onAppear {
            appeared = true
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { float = true }
        }
    }

    private var buyTitle: String {
        if !plan.products.isEmpty { return L("Proをはじめる") }
        return plan.isLoadingProducts ? L("読み込み中…") : L("もう一度読み込む")
    }

    /// How much cheaper the yearly plan is than 12 months of the monthly one, from the real store prices.
    private var yearlySaving: Int? {
        guard let y = plan.products.first(where: { $0.subscription?.subscriptionPeriod.unit == .year }),
              let m = plan.products.first(where: { $0.subscription?.subscriptionPeriod.unit == .month }) else { return nil }
        let full = m.price * 12
        guard full > 0, y.price < full else { return nil }
        let pct = NSDecimalNumber(decimal: (full - y.price) / full * 100).intValue
        return pct >= 5 ? pct : nil
    }

    @ViewBuilder
    private var plans: some View {
        if plan.products.isEmpty {
            VStack(spacing: 6) {
                if plan.isLoadingProducts {
                    ProgressView().tint(Theme.muted)
                } else {
                    Text(L("App Store の価格を読み込めませんでした。通信を確かめて、もう一度お試しください。"))
                        .scaledFont(size: 13).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(minHeight: 80)
        } else {
            VStack(spacing: 10) {
                ForEach(plan.products, id: \.id) { product in
                    let isYearly = product.subscription?.subscriptionPeriod.unit == .year
                    let selected = selectedID == product.id
                    Button {
                        Haptics.selection()
                        withAnimation(.snappy) { selectedID = product.id }
                    } label: {
                        HStack {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected ? Theme.primary : Theme.muted)
                                .contentTransition(.symbolEffect(.replace))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(isYearly ? L("年額プラン") : L("月額プラン")).scaledFont(size: 16, weight: .bold)
                                    if isYearly, let off = yearlySaving {
                                        Text(L("\(off)%おトク"))
                                            .scaledFont(size: 10, weight: .bold)
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Theme.gold, in: Capsule())
                                    }
                                }
                                // Schedule 2 / 3.1.2: the length of the subscription next to its price.
                                Text(isYearly ? L("1年ごとに自動更新") : L("1か月ごとに自動更新"))
                                    .scaledFont(size: 12).foregroundStyle(Theme.muted)
                                if isYearly {
                                    Text(L("月あたり \((product.price / 12).formatted(product.priceFormatStyle))"))
                                        .scaledFont(size: 12).foregroundStyle(Theme.muted)
                                }
                            }
                            .foregroundStyle(Theme.foreground)
                            Spacer()
                            Text(isYearly ? L("\(product.displayPrice)／年") : L("\(product.displayPrice)／月"))
                                .scaledFont(size: 17, weight: .bold).foregroundStyle(Theme.foreground)
                        }
                        .padding(16)
                        .background(selected ? Theme.primary.opacity(0.06) : Theme.card, in: .rect(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(selected ? Theme.primary : Theme.border, lineWidth: selected ? 2 : 1))
                        .scaleEffect(selected ? 1 : 0.985)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            }
        }
    }
}
