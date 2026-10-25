import SwiftUI
import UserNotifications

/// Milestone albums (web lib/milestone-album.ts + milestone-schedule.ts + MemorialReveal):
/// on day 7, 30, 100, 200, 365 (and every year after) counted from the day the account was made,
/// Home offers an album of the best photos so far, opened with a celebration.
enum Milestone {
    static let days = [7, 30, 100, 200, 365]
    static let maxPhotos = 8
    static let hour = 19
    static let minute = 30
    /// The milestone albums closed on this device, per account (`memorial-seen-v1.<userId>`, R6-05), like
    /// `OnboardingState`. The bare key is the old device-wide list: the first account to ask adopts it.
    private static let legacySeenKey = "memorial-seen-v1"
    static let notificationId = "milestone-album"

    /// Day 1 is the day the account was made (local calendar days, no clock time).
    static func dayNumber(start: Date, now: Date = Date()) -> Int {
        let cal = Calendar.current
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: now)).day ?? 0
        return d + 1
    }

    static func isMilestone(_ n: Int) -> Bool { days.contains(n) || (n > 365 && n % 365 == 0) }

    static func today(start: Date, now: Date = Date()) -> Int? {
        let n = dayNumber(start: start, now: now)
        return n >= 1 && isMilestone(n) ? n : nil
    }

    static func next(start: Date, now: Date = Date()) -> (n: Int, date: Date)? {
        let today = dayNumber(start: start, now: now)
        for n in max(1, today + 1)..<(today + 800) where isMilestone(n) {
            let d = Calendar.current.date(byAdding: .day, value: n - 1, to: Calendar.current.startOfDay(for: start))
            if let d { return (n, d) }
        }
        return nil
    }

    /// Up to 8 photos spread across the whole time: one per day at even steps, preferring a photo
    /// with a one-liner, then the newest; filled up if there were fewer days (web pickHighlights).
    static func highlights(_ items: [Sticker]) -> [Sticker] {
        let withPhoto = items.filter { $0.heroPath != nil }
        if withPhoto.count <= maxPhotos { return withPhoto.sorted { $0.takenAt < $1.takenAt } }
        let cal = Calendar.current
        let byDay = Dictionary(grouping: withPhoto) { cal.startOfDay(for: $0.takenAt) }
        let rank: (Sticker, Sticker) -> Bool = { a, b in
            let ca = !(a.caption ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            let cb = !(b.caption ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            if ca != cb { return ca }
            return a.takenAt > b.takenAt
        }
        let dayKeys = byDay.keys.sorted()
        let take = min(maxPhotos, dayKeys.count)
        var picked: [Sticker] = []
        for i in 0..<take {
            let idx = take == 1 ? 0 : Int((Double(i * (dayKeys.count - 1)) / Double(take - 1)).rounded())
            if let best = byDay[dayKeys[idx]]?.sorted(by: rank).first, !picked.contains(where: { $0.id == best.id }) {
                picked.append(best)
            }
        }
        if picked.count < maxPhotos {
            let rest = withPhoto.filter { s in !picked.contains { $0.id == s.id } }.sorted(by: rank)
            picked += rest.prefix(maxPhotos - picked.count)
        }
        return picked.sorted { $0.takenAt < $1.takenAt }
    }

    private static func seenStorageKey(for userId: String?) -> String {
        guard let userId else { return legacySeenKey }   // a local guest (no account) keeps the device-wide list
        return legacySeenKey + "." + userId
    }

    /// This account's closed albums. The first time an account asks, it takes over the old device-wide
    /// list (closed before it was kept per account) and clears it, so the next account starts with its own.
    private static func seenList(userId: String?) -> [Int] {
        let defaults = UserDefaults.standard
        let key = seenStorageKey(for: userId)
        if let list = defaults.array(forKey: key) as? [Int] { return list }
        guard userId != nil, let legacy = defaults.array(forKey: legacySeenKey) as? [Int] else { return [] }
        defaults.set(legacy, forKey: key)
        defaults.removeObject(forKey: legacySeenKey)
        return legacy
    }

    static func wasDismissed(_ n: Int) -> Bool {
        seenList(userId: SupabaseClient.shared.userId).contains(n)
    }

    static func dismiss(_ n: Int) {
        let userId = SupabaseClient.shared.userId
        var list = seenList(userId: userId)
        if !list.contains(n) { list.append(n) }
        UserDefaults.standard.set(Array(list.suffix(20)), forKey: seenStorageKey(for: userId))
    }

    /// Account deletion: that account's closed albums.
    static func removeRecord(userId: String?) {
        guard let userId else { return }
        UserDefaults.standard.removeObject(forKey: seenStorageKey(for: userId))
    }

    /// One local notification at 19:30 on today's milestone (if still ahead) or the next one.
    static func scheduleNotification(start: Date, now: Date = Date()) async {
        let cal = Calendar.current
        func at(_ d: Date) -> Date { cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d }
        var target: (n: Int, at: Date)?
        if let n = today(start: start, now: now), at(now) > now {
            target = (n, at(now))
        } else if let nx = next(start: start, now: now) {
            target = (nx.n, at(nx.date))
        }
        guard let target else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        center.removePendingNotificationRequests(withIdentifiers: [notificationId])
        let content = UNMutableNotificationContent()
        content.title = L("\(target.n)日目の記念アルバムができました")
        content.body = L("使い始めて\(target.n)日。これまでの思い出を1冊にまとめました")
        content.sound = .default
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: target.at)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger))
    }
}

/// The entry above today's page on a milestone day.
struct MemorialBanner: View {
    let n: Int
    let words: Int
    let photos: Int
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @State private var shimmer = false
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [Color(hex: 0xFFD97A), Theme.gold], startPoint: .top, endPoint: .bottom))
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, options: .repeat(2), value: shimmer)
                    }
                    .frame(width: 46, height: 46)
                    .shadow(color: Theme.gold.opacity(0.45), radius: 8, y: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("使い始めて\(n)日の記念アルバム"))
                            .scaledFont(size: 15, weight: .bold)
                            .foregroundStyle(Color(hex: 0x33291F))
                        Text(L("\(n)日間で\(words)語。思い出の\(photos)枚をまとめました"))
                            .scaledFont(size: 12)
                            .foregroundStyle(Color(hex: 0x33291F, opacity: 0.6))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("閉じる"))
        }
        .padding(.leading, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFFF7E3), .white], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.gold.opacity(0.45), lineWidth: 1))
                .shadow(color: Theme.gold.opacity(0.18), radius: 12, y: 5)
        }
        .onAppear { if !reduceMotion { shimmer.toggle() } }
    }
}

/// Full-screen album: first the celebration (MemorialReveal), then the page of photos.
struct MemorialAlbumView: View {
    let n: Int
    let words: Int
    let picks: [Sticker]
    let onOpen: (Sticker) -> Void
    let onClose: () -> Void

    @Environment(DexStore.self) private var dex
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            HomeBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 6) {
                    Text(L("使い始めて\(n)日の記念アルバム"))
                        .scaledFont(size: 24, weight: .heavy)
                        .foregroundStyle(Color(hex: 0x33291F))
                        .multilineTextAlignment(.center)
                    Text(L("\(n)日間で\(words)語。思い出の\(picks.count)枚をまとめました"))
                        .scaledFont(size: 13)
                        .foregroundStyle(Color(hex: 0x33291F, opacity: 0.6))
                    CollageBoard(items: picks, editable: false, onOpen: onOpen, autoOnly: true)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 70)
                .padding(.bottom, 60)
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 30)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.trailing, 16).padding(.top, 8)
                .accessibilityLabel(L("閉じる"))
            }
            if !revealed {
                MemorialReveal(n: n, words: words, photos: picks.compactMap(\.heroPath)) {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.86)) { revealed = true }
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .statusBarTone(revealed ? .dark : .light)  // the night-sky reveal, then the paper album
    }
}

/// The celebration: the day count rolls up, confetti bursts, the words count up, and the chosen
/// photos fan out one by one with a tick each. Tap skips to the end; tap again opens the album.
struct MemorialReveal: View {
    let n: Int
    let words: Int
    let photos: [String]
    let onDone: () -> Void

    @Environment(DexStore.self) private var dex
    @Environment(\.appReduceMotion) private var reduceMotion
    private enum Phase { case count, burst, fan, ready, leaving }
    @State private var phase: Phase = .count
    @State private var day = 1
    @State private var count = 0
    @State private var fanned = 0
    @State private var task: Task<Void, Never>?

    private var fan: [String] { Array(photos.prefix(7)) }

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x1E2B55), Color(hex: 0x070B18)], center: .center, startRadius: 20, endRadius: 520)
                .ignoresSafeArea()
            Rays(turning: phase != .count && !reduceMotion)
                .opacity(phase == .count ? 0 : 0.55)
                .scaleEffect(phase == .count ? 0.6 : 1)
                .animation(.easeOut(duration: 0.9), value: phase)
                .ignoresSafeArea()
            Confetti(active: phase != .count)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                Text(L("おめでとう"))
                    .font(.system(size: 15, weight: .bold))
                    .tracking(4)
                    .foregroundStyle(Theme.gold)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(day)")
                        .font(.system(size: 110, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(LinearGradient(colors: [.white, Color(hex: 0xFFE7A8)], startPoint: .top, endPoint: .bottom))
                        .contentTransition(.numericText(value: Double(day)))
                        .shadow(color: Theme.gold.opacity(0.5), radius: phase == .count ? 0 : 24)
                    Text(L10n.unit(L("日"), count: day)).font(.system(size: 30, weight: .heavy)).foregroundStyle(.white.opacity(0.9))
                }
                Text(L("\(count)語を集めました"))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .contentTransition(.numericText(value: Double(count)))
                    .opacity(phase == .count ? 0 : 1)
                ZStack {
                    ForEach(Array(fan.enumerated()), id: \.offset) { i, path in
                        let mid = Double(fan.count - 1) / 2
                        let k = Double(i) - mid
                        let on = i < fanned
                        Color.white
                            .frame(width: 96, height: 120)
                            .overlay {
                                StickerImage(path: path, url: dex.url(for: path), contentMode: .fill)
                                    .padding(5)
                                    .padding(.bottom, 14)
                                    .allowsHitTesting(false)
                            }
                            .clipped()
                            .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
                            .rotationEffect(.degrees(on ? k * 7 : 0))
                            .offset(x: on ? k * 44 : 0, y: on ? abs(k) * 9 : 80)
                            .scaleEffect(on ? 1 : 0.6)
                            .opacity(on ? 1 : 0)
                            .zIndex(10 - abs(k))
                    }
                }
                .frame(height: 170)
                .padding(.top, 22)
                Text(L("アルバムを開く"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x33291F))
                    .padding(.horizontal, 28)
                    .frame(minHeight: 50)
                    .background(LinearGradient(colors: [Color(hex: 0xFFE7A8), Theme.gold], startPoint: .top, endPoint: .bottom), in: Capsule())
                    .shadow(color: Theme.gold.opacity(0.5), radius: 14, y: 5)
                    .opacity(phase == .ready ? 1 : 0)
                    .scaleEffect(phase == .ready ? 1 : 0.85)
                    .padding(.top, 18)
            }
            .scaleEffect(phase == .leaving ? 1.08 : 1)
            .opacity(phase == .leaving ? 0 : 1)
        }
        .contentShape(.rect)
        .onTapGesture { finish() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("使い始めて\(n)日の記念アルバム。\(words)語を集めました"))
        .accessibilityAddTraits(.isButton)
        .onAppear(perform: run)
        .onDisappear { task?.cancel() }
    }

    private func run() {
        if reduceMotion {
            day = n; count = words; fanned = fan.count; phase = .ready
            return
        }
        task = Task { @MainActor in
            // 1) The day number rolls up (ease-out, ~1.15 s).
            let steps = min(n, 40)
            for i in 1...max(1, steps) {
                let p = Double(i) / Double(max(1, steps))
                let e = 1 - pow(1 - p, 3)
                withAnimation(.snappy(duration: 0.08)) { day = max(1, Int((e * Double(n)).rounded())) }
                try? await Task.sleep(for: .milliseconds(Int(1150.0 / Double(max(1, steps)))))
                if Task.isCancelled { return }
            }
            // 2) Burst: confetti, fanfare, the words count up.
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { phase = .burst }
            Haptics.success()
            HapticPatterns.shared.bloom()
            SoundService.shared.play(.sting)
            Task { @MainActor in
                for i in 1...20 {
                    let p = Double(i) / 20
                    withAnimation(.snappy(duration: 0.06)) { count = Int(((1 - pow(1 - p, 2)) * Double(words)).rounded()) }
                    try? await Task.sleep(for: .milliseconds(45))
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            // 3) The photos fan out one by one.
            phase = .fan
            for i in 0..<fan.count {
                try? await Task.sleep(for: .milliseconds(110))
                if Task.isCancelled { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) { fanned = i + 1 }
                Haptics.impact(.light)
            }
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { phase = .ready }
        }
    }

    private func finish() {
        guard phase != .leaving else { return }
        if phase != .ready {
            task?.cancel()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                day = n; count = words; fanned = fan.count; phase = .ready
            }
            return
        }
        Haptics.impact(.medium)
        SoundService.shared.play(.bookOpen)
        withAnimation(.easeIn(duration: 0.45)) { phase = .leaving }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 480))
            onDone()
        }
    }
}

/// Slowly turning light rays behind the number.
struct Rays: View {
    /// False while the rays are hidden or Reduce Motion is on: the timeline stops redrawing every frame.
    var turning: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !turning)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height * 0.38)
                let r = max(size.width, size.height)
                let count = 14
                for i in 0..<count {
                    let a = Double(i) / Double(count) * 2 * .pi + t * 0.08
                    var p = Path()
                    p.move(to: c)
                    p.addLine(to: CGPoint(x: c.x + cos(a - 0.09) * r, y: c.y + sin(a - 0.09) * r))
                    p.addLine(to: CGPoint(x: c.x + cos(a + 0.09) * r, y: c.y + sin(a + 0.09) * r))
                    p.closeSubpath()
                    ctx.fill(p, with: .radialGradient(Gradient(colors: [Color(hex: 0xFFD97A).opacity(0.35), .clear]),
                                                       center: c, startRadius: 0, endRadius: r * 0.8))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
