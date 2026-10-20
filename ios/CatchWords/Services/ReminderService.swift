import Foundation
import UserNotifications
import CoreLocation

/// Local notifications for 「復習の通知」 (off / auto / custom times) and 「場所でリマインド」.
enum ReminderService {
    static let modeKey = "reminder.mode"
    static let timesKey = "reminder.times"
    static let placeKey = "place.remind"
    private static let reviewPrefix = "review-"
    private static let placePrefix = "place-"
    /// Read by NotificationRouter to know where a tapped notification leads.
    static var reviewIdentifierPrefix: String { reviewPrefix }
    static var placeIdentifierPrefix: String { placePrefix }

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    static let defaultTime = "09:00"   // web DEFAULT_REMINDER_PREFS
    private static let opensKey = "app.opens"
    private static let quietStart = 22 * 60, quietEnd = 8 * 60
    private static let minBatch = 5
    private static let mergeWindow: TimeInterval = 90 * 60

    static func parseTimes(_ raw: String) -> [String] {
        let list = raw.split(separator: ",").map(String.init).filter { isValidTime($0) }
        return list.isEmpty ? [defaultTime] : Array(Set(list)).sorted().prefix(3).map { $0 }
    }

    static func isValidTime(_ s: String) -> Bool {
        let p = s.split(separator: ":").compactMap { Int($0) }
        return s.count == 5 && p.count == 2 && (0...23).contains(p[0]) && (0...59).contains(p[1])
    }

    // MARK: おまかせ (web review-reminder.ts planReminders)

    enum Reason { case custom, srs, habit }

    /// Remembers when the app was opened (at most every 30 min, 14 days) — for the habit reminder.
    static func recordAppOpen(now: Date = Date()) {
        var list = opens()
        if let last = list.last, now.timeIntervalSince(last) < 30 * 60 { return }
        list = list.filter { now.timeIntervalSince($0) < 14 * 86_400 } + [now]
        UserDefaults.standard.set(list.map { $0.timeIntervalSince1970 }, forKey: opensKey)
    }

    private static func opens() -> [Date] {
        (UserDefaults.standard.array(forKey: opensKey) as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) }
    }

    /// Never between 22:00 and 08:00: moved to 08:00.
    static func outsideQuietHours(_ d: Date) -> Date {
        let cal = Calendar.current
        let m = cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d)
        if m >= quietEnd && m < quietStart { return d }
        var day = cal.startOfDay(for: d)
        if m >= quietStart { day = cal.date(byAdding: .day, value: 1, to: day) ?? day }
        return cal.date(bySettingHour: quietEnd / 60, minute: 0, second: 0, of: day) ?? d
    }

    static func nextOccurrence(_ hhmm: String, now: Date) -> Date {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        let cal = Calendar.current
        var d = cal.date(bySettingHour: p.first ?? 9, minute: p.last ?? 0, second: 0, of: now) ?? now
        if d <= now { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        return d
    }

    /// When enough cards (5, or all of them) come due within a day — never sooner than 30 minutes.
    static func srsBestTime(_ due: [Date], now: Date) -> Date? {
        let horizon = now.addingTimeInterval(86_400)
        let soon = due.filter { $0 <= horizon }.sorted()
        guard !soon.isEmpty else { return nil }
        let pick = soon[min(minBatch, soon.count) - 1]
        return outsideQuietHours(max(pick, now.addingTimeInterval(30 * 60)))
    }

    /// The time you first opened the app yesterday.
    static func habitTime(_ opens: [Date], now: Date) -> Date? {
        let cal = Calendar.current
        guard let y = cal.date(byAdding: .day, value: -1, to: now),
              let first = opens.filter({ cal.isDate($0, inSameDayAs: y) }).min() else { return nil }
        let hhmm = String(format: "%02d:%02d", cal.component(.hour, from: first), cal.component(.minute, from: first))
        return outsideQuietHours(nextOccurrence(hhmm, now: now))
    }

    static func plan(mode: String, times: [String], due: [Date], opens: [Date], now: Date) -> [(at: Date, reason: Reason)] {
        var out: [(at: Date, reason: Reason)] = []
        switch mode {
        case "custom":
            out = parseTimes(times.joined(separator: ",")).map { (nextOccurrence($0, now: now), .custom) }
        case "ai":
            let srs = srsBestTime(due, now: now)
            if let srs { out.append((srs, .srs)) }
            if let habit = habitTime(opens, now: now) {
                if srs.map({ abs(habit.timeIntervalSince($0)) < mergeWindow }) != true { out.append((habit, .habit)) }
            }
        default: break
        }
        return out.filter { $0.at > now }.sorted { $0.at < $1.at }
    }

    /// Replaces every pending review reminder. Custom times repeat daily; おまかせ plans the next
    /// ones from the cards coming due and yesterday's first open (re-planned each time the app opens).
    static func applyReview(mode: String, times: [String], due: [Date] = []) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(reviewPrefix) })
        guard mode == "custom" || mode == "ai" else { return }
        let cal = Calendar.current
        for (i, p) in plan(mode: mode, times: times, due: due, opens: opens(), now: Date()).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "CatchWords"
            content.body = switch p.reason {  // lang-ok: the app's own enum, each case an L() string
            case .srs: L("思い出しどきの単語がたまっています。今なら記憶に残りやすい時間です")
            case .habit: L("いつもの時間です。1枚だけでも思い出してみよう")
            case .custom: L("今日の復習が待っています。1枚だけでも思い出してみよう")
            }
            content.sound = .default
            let trigger: UNCalendarNotificationTrigger
            if p.reason == .custom {
                trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.hour, .minute], from: p.at), repeats: true)
            } else {
                trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: p.at), repeats: false)
            }
            try? await center.add(UNNotificationRequest(identifier: "\(reviewPrefix)\(i)", content: content, trigger: trigger))
        }
    }

    /// Re-plans with the current setting (app opened, reviews graded).
    static func refresh(due: [Date]) async {
        let d = UserDefaults.standard
        await applyReview(mode: d.string(forKey: modeKey) ?? "off", times: parseTimes(d.string(forKey: timesKey) ?? defaultTime), due: due)
    }

    // MARK: Account sync (web user_metadata.notification_preferences)

    static func saveToAccount(mode: String, times: [String]) async {
        try? await SupabaseClient.shared.updateUserMetadata([
            "notification_preferences": ["mode": mode, "times": parseTimes(times.joined(separator: ",")), "ai": ["srs": true, "habit": true]],
        ])
    }

    /// Takes the setting made on the web (or at onboarding) when this device has none yet.
    static func loadFromAccount() async {
        guard let meta = try? await SupabaseClient.shared.userMetadata(),
              let prefs = meta["notification_preferences"] as? [String: Any],
              let mode = prefs["mode"] as? String, ["off", "custom", "ai"].contains(mode) else { return }
        let d = UserDefaults.standard
        d.set(mode, forKey: modeKey)
        let times = (prefs["times"] as? [String] ?? []).filter(isValidTime)
        d.set((times.isEmpty ? [defaultTime] : times).joined(separator: ","), forKey: timesKey)
    }

    /// One arrival notification per recent catch location (max 20, 150 m radius).
    static func applyPlaces(enabled: Bool, stickers: [Sticker]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(placePrefix) })
        guard enabled else { return }
        LocationService.shared.requestPermissionIfNeeded()
        var used: [CLLocation] = []
        for s in stickers {
            guard used.count < 20, let la = s.lat, let lo = s.lng, let head = s.word?.headword else { continue }
            let here = CLLocation(latitude: la, longitude: lo)
            if used.contains(where: { $0.distance(from: here) < 200 }) { continue }
            used.append(here)
            let region = CLCircularRegion(center: here.coordinate, radius: 150, identifier: "\(placePrefix)\(s.id)")
            region.notifyOnEntry = true
            region.notifyOnExit = false
            let content = UNMutableNotificationContent()
            content.title = L("ここで覚えた単語")
            content.body = L("\(LocationService.shownPlace(s.locationName) ?? L("この場所"))で「\(head)」をキャッチしました。覚えていますか？")
            content.sound = .default
            let trigger = UNLocationNotificationTrigger(region: region, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: region.identifier, content: content, trigger: trigger))
        }
    }
}
