import SwiftUI
import StoreKit

/// Freemium: a daily number of catches on the app's Taipei calendar day (`SRS.taipeiDay`, like the web).
/// Pro = StoreKit subscription OR `profiles.plan == "pro"` (so web Stripe subscribers stay Pro on iPhone),
/// but only once in-app purchase is offered too (`inAppPurchaseAvailable`, App Review Guideline 3.1.3(b)).
@Observable
final class PlanStore {
    /// Owner decision 2026-10-21 (free with ads, no subscription yet): 10 catches a day for the first 7 days
    /// (the collection grows while the app is new — endowment), then 3 a day. Observed beta use (13 learners,
    /// 2026-08/10): median 1 catch a day, 9 days in 10 at 3 or fewer, so 3 binds only on heavy days. Reviews and
    /// the dex are never limited. A catch counts when it is saved (`recordCatch`); the shutter needs one left.
    static let freeCatchesPerDay = 3
    static let welcomeCatchesPerDay = 10
    static let welcomeDays = 7
    /// Extra catches a learner can earn in a day (a rewarded ad: `grantBonusCatch`).
    static let maxBonusPerDay = 2
    /// On since 2026-10-21 (owner decision above). Off under `-uiDemo` (DEBUG only: the UI tests catch many times a day).
    static var catchLimitEnabled: Bool {
        #if DEBUG
        return !DemoBackend.isOn
        #else
        return true
        #endif
    }
    /// The first App Store version is free only: no "Upgrade to Pro", no purchase / restore buttons
    /// (the products are not set up in App Store Connect and the server does not check Apple purchases
    /// yet). Flip together with `catchLimitEnabled` when Pro launches; the StoreKit code stays as is.
    static let paywallEnabled = false
    /// The web server verifies App Store purchases and writes `profiles.plan` for them (needed for the
    /// server-decided Pro features such as 「作り直す」). Not built yet: see docs/self-managing-ios.md §7.
    /// Until then the paywall does not promise those features.
    static let serverVerifiesAppStore = false
    /// App Review Guideline 3.1.3(b) (multiplatform services): a subscription bought outside the app (web
    /// Stripe) may unlock features in the iOS app only if those same features can also be bought here with
    /// in-app purchase. While IAP is not offered (`paywallEnabled` off), the app treats every account as
    /// free for Pro-only features — web Pro included — and never shows a paywall or points to buying on the
    /// web. This is the one switch for that: it turns on with the paywall, once the server verifies App
    /// Store purchases (docs/self-managing-ios.md §7-2) so the in-app Pro unlocks the same features.
    /// Server calls are unchanged; only what the app offers follows this.
    static let inAppPurchaseAvailable = paywallEnabled
    static let productIDs = ["catchwords.pro.yearly", "catchwords.pro.monthly"]

    var products: [Product] = []
    var isStorePro: Bool = false
    var isServerPro: Bool = false
    var usedToday: Int = 0
    /// Catches earned today (rewarded ads), at most `maxBonusPerDay`.
    var bonusToday: Int = 0
    var isPurchasing: Bool = false
    var message: String?

    /// Pro for what the APP gates on the device (catch limit, paywall): an active App Store subscription is
    /// trusted locally, so a paying user is never locked out while the server does not know the purchase yet.
    /// Off entirely while in-app purchase is unavailable (`inAppPurchaseAvailable`, Guideline 3.1.3(b)).
    var isPro: Bool { Self.inAppPurchaseAvailable && (isStorePro || isServerPro) }
    /// Pro for features the SERVER decides (`isProUser`: `profiles.plan == "pro"` or admin), e.g. section
    /// 「作り直す」. The server does not verify App Store purchases yet (only web Stripe writes
    /// `profiles.plan`), so a StoreKit-only Pro does NOT count here — offering those buttons would only fail.
    /// Also off while in-app purchase is unavailable: web Pro alone must not unlock them here (3.1.3(b)).
    var serverGrantsPro: Bool { Self.inAppPurchaseAvailable && isServerPro }
    /// Today's free catches: `welcomeCatchesPerDay` during the first `welcomeDays` days, then `freeCatchesPerDay`.
    var dailyLimit: Int { Self.limit(onDay: Self.dayKey()) }
    /// Tomorrow's free catches (what the limit sheet promises).
    var tomorrowLimit: Int { Self.limit(onDay: SRS.taipeiDay(Date().addingTimeInterval(86_400))) }
    var remainingToday: Int { max(0, dailyLimit + bonusToday - usedToday) }
    var canEarnBonus: Bool { bonusToday < Self.maxBonusPerDay }
    var canCatch: Bool { !Self.catchLimitEnabled || isPro || remainingToday > 0 }

    private var updatesTask: Task<Void, Never>?

    init() {
        _ = Self.firstDay   // the welcome week starts on the first launch
        loadUsage()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update { await t.finish() }
                await self?.refreshEntitlements()
            }
        }
    }

    func bootstrap() async {
        loadUsage()
        await refreshEntitlements()
        if Self.paywallEnabled { await loadProducts() }
        await refreshServerPlan()
    }

    /// True while the App Store prices are being fetched; false with no products = they could not be read.
    var isLoadingProducts: Bool = false

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        let loaded = (try? await Product.products(for: Self.productIDs)) ?? []
        products = loaded.sorted { ($0.subscription?.subscriptionPeriod.unit == .year ? 0 : 1) < ($1.subscription?.subscriptionPeriod.unit == .year ? 0 : 1) }
    }

    func refreshEntitlements() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, Self.productIDs.contains(t.productID), t.revocationDate == nil { pro = true }
        }
        isStorePro = pro
    }

    func refreshServerPlan() async {
        guard let uid = SupabaseClient.shared.userId else { isServerPro = false; return }
        // `plan` is a private column: read through `get_my_profile()` (a plain select of it is refused, which left
        // a web Pro subscription unseen here). A row without it (the public columns only) changes nothing.
        guard let row = await SupabaseClient.shared.myProfileRow(uid: uid), row.keys.contains("plan"),
              SupabaseClient.shared.userId == uid else { return }
        let plan = (row["plan"] as? String) ?? "free"
        isServerPro = plan == "pro" || plan == "premium"
    }

    /// Signing out: the web plan belonged to that account (App Store entitlements follow the Apple ID).

    func purchase(_ product: Product) async {
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }
        do {
            // The account's id travels with the purchase (`appAccountToken`): Apple puts it in the signed
            // transaction and in App Store Server Notifications, so the server can tell whose Pro it is
            // without trusting anything the app says. Supabase user ids are UUIDs.
            var options: Set<Product.PurchaseOption> = []
            if let uid = SupabaseClient.shared.userId, let token = UUID(uuidString: uid) {
                options.insert(.appAccountToken(token))
            }
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let t):
                    await t.finish()
                    await refreshEntitlements()
                    Haptics.success()
                case .unverified:
                    message = L("購入を確認できませんでした。しばらくしてから「購入を復元」をお試しください。")
                }
            case .pending:
                message = L("購入の承認待ちです。")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = L("購入を完了できませんでした。")
        }
    }

    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        try? await AppStore.sync()
        await refreshEntitlements()
        await refreshServerPlan()
        message = isPro ? L("Proを復元しました。") : L("復元できる購入が見つかりませんでした。")
    }

    /// Signing out / account deleted: the next account starts from its own plan, never the previous one's
    /// web Pro (StoreKit entitlements belong to the Apple ID and are read again).
    func reset() {
        isServerPro = false
        message = nil
    }

    func recordCatch() {
        loadUsage()
        usedToday += 1
        saveUsage()
    }

    /// A catch counted at the flick whose background save then failed: it does not use up a catch.
    func undoCatch() {
        loadUsage()
        usedToday = max(0, usedToday - 1)
        saveUsage()
    }

    /// One more catch today (a rewarded ad watched to the end). False when today's extras are used up.
    @discardableResult
    func grantBonusCatch() -> Bool {
        loadUsage()
        guard canEarnBonus else { return false }
        bonusToday += 1
        saveUsage()
        return true
    }

    private func loadUsage() {
        let d = UserDefaults.standard
        let today = d.string(forKey: "plan.day") == Self.dayKey()
        usedToday = today ? d.integer(forKey: "plan.used") : 0
        bonusToday = today ? d.integer(forKey: "plan.bonus") : 0
    }

    private func saveUsage() {
        let d = UserDefaults.standard
        d.set(usedToday, forKey: "plan.used")
        d.set(bonusToday, forKey: "plan.bonus")
        d.set(Self.dayKey(), forKey: "plan.day")
    }

    /// The day of the first launch (Taipei calendar). Kept in the Keychain so deleting and reinstalling the app
    /// does not start a new welcome week.
    static let firstDay: String = {
        let account = "plan.firstDay"
        if let data = KeychainStore.load(account: account), let day = String(data: data, encoding: .utf8),
           day.count == 10 {
            return day
        }
        let today = SRS.taipeiDay(Date())
        KeychainStore.save(Data(today.utf8), account: account)
        return today
    }()

    /// The free catches on a Taipei day (`yyyy-MM-dd`): the welcome amount for the first `welcomeDays` days.
    static func limit(onDay day: String, firstDay: String = PlanStore.firstDay) -> Int {
        guard let n = daysBetween(firstDay, day) else { return freeCatchesPerDay }
        return n < welcomeDays ? welcomeCatchesPerDay : freeCatchesPerDay
    }

    /// Whole days from `a` to `b` (both `yyyy-MM-dd`); nil when either does not parse.
    static func daysBetween(_ a: String, _ b: String) -> Int? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let da = f.date(from: a), let db = f.date(from: b) else { return nil }
        return Int((db.timeIntervalSince(da) / 86_400).rounded())
    }

    /// The app's "today" is one calendar everywhere: Taiwan midnight, like the web (`SRS.taipeiDay`).
    private static func dayKey() -> String { SRS.taipeiDay(Date()) }
}
