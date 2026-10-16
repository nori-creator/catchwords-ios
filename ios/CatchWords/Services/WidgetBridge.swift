import SwiftUI
import UIKit
import WidgetKit
import ActivityKit

/// Hands the widgets (CatchWordsWidgets extension) what they show: word of the day, cards due,
/// words caught and the streak — written to the App Group as a `WidgetSnapshot` (Shared/WidgetShared.swift),
/// with small JPEG thumbnails in the App Group container. Everything here is best effort: a missing
/// App Group (unsigned / not provisioned build) just leaves the widgets on their empty state.
enum WidgetBridge {
    /// How many days of "word of the day" are written ahead.
    private static let daysAhead = 7
    private static let thumbSide: CGFloat = 300
    @MainActor private static var pendingTask: Task<Void, Never>?
    /// Last streak the review screen reported (the dex alone does not know it).
    @MainActor private static var lastStreak: Int?

    /// Rewrites the snapshot shortly (several triggers in a row collapse into one write).
    @MainActor
    static func refresh(dex: DexStore, streak: Int? = nil) {
        if let streak { lastStreak = streak }
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await write(dex: dex)
        }
    }

    /// Signing out: the widgets go back to their empty state, so the next person to pick up the phone
    /// (or the next account) never sees this account's words, pictures or streak.
    @MainActor
    static func clear() {
        pendingTask?.cancel()
        pendingTask = nil
        lastStreak = nil
        WidgetShared.defaults?.removeObject(forKey: WidgetShared.snapshotKey)
        removeStaleThumbs(keeping: [])
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor
    private static func write(dex: DexStore) async {
        let now = Date()
        let mine = Set(dex.stickers.map(\.id))
        let dues = dex.reviews.filter { mine.contains($0.key) }.values.compactMap(\.dueAt)
        let dueNow = dues.filter { $0 <= now }.count
        let upcoming = Array(dues.filter { $0 > now }.sorted().prefix(300))

        // Word of the day: a stable pick per local day from this learning language's words.
        let pool = dex.stickers.filter { $0.word != nil && !DexStore.isProvisional($0.id) }.sorted { $0.id < $1.id }
        var words: [WidgetWord] = []
        var keep: Set<String> = []
        if !pool.isEmpty {
            let cal = Calendar.current
            for d in 0..<min(daysAhead, pool.count) {
                guard let date = cal.date(byAdding: .day, value: d, to: now) else { continue }
                let ordinal = cal.ordinality(of: .day, in: .era, for: date) ?? d
                let s = pool[(ordinal &* 7919 % pool.count + pool.count) % pool.count]
                guard let w = s.word, !words.contains(where: { $0.stickerId == s.id }) else { continue }
                let path = s.heroPath ?? s.placeholderImageUrl
                var file: String?
                if let path, let jpeg = await thumbnail(path: path, dex: dex) {
                    if Task.isCancelled { return }
                    let name = "\(s.id).jpg"
                    if let url = WidgetShared.thumbURL(name) {
                        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        if (try? jpeg.write(to: url, options: .atomic)) != nil {
                            file = name
                            keep.insert(name)
                        }
                    }
                }
                words.append(WidgetWord(day: WidgetShared.dayKey(date), stickerId: s.id, headword: w.headword,
                                        reading: w.readingZhuyin?.isEmpty == false ? w.readingZhuyin : nil,
                                        meaning: w.meaningJa, thumbFile: file,
                                        isCutout: path != nil && path == s.cutoutImageUrl))
            }
        }
        // Signed out (`clear()`) or superseded while the pictures were loading: write nothing stale.
        guard !Task.isCancelled else { return }
        removeStaleThumbs(keeping: keep)

        let snapshot = WidgetSnapshot(lang: L10n.lang, words: words, dueNow: dueNow, upcomingDue: upcoming,
                                      totalWords: dex.stickers.count,
                                      streak: lastStreak ?? WidgetShared.load()?.streak,
                                      updatedAt: now)
        WidgetShared.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The word's picture, ≤ 300 px, flattened on white (cut-outs are transparent PNGs).
    @MainActor
    private static func thumbnail(path: String, dex: DexStore) async -> Data? {
        if WidgetShared.containerURL == nil { return nil }
        var image = ImageCache.shared.image(for: path)
        if image == nil, let url = dex.url(for: path, preferThumb: true) {
            image = await ImageCache.shared.load(url: url, key: "widget:" + path)
        }
        guard let image else { return nil }
        let side = thumbSide
        // Drawn and encoded off the main thread (it ran there for every word of the next days at launch).
        return await Task.detached(priority: .utility) { () -> Data? in
            let size = image.size
            guard size.width > 0, size.height > 0 else { return nil }
            let scale = min(1, side / max(size.width, size.height))
            let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true
            let flat = UIGraphicsImageRenderer(size: target, format: format).image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: target))
                image.draw(in: CGRect(origin: .zero, size: target))
            }
            return flat.jpegData(compressionQuality: 0.8)
        }.value
    }

    private static func removeStaleThumbs(keeping keep: Set<String>) {
        guard let dir = WidgetShared.thumbsURL,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for f in files where !keep.contains(f) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }

    /// Links from the widgets: `catchwords://review` and `catchwords://word/<sticker id>`.
    /// Handed to the tab shell the same way a tapped notification is.
    @MainActor
    static func open(_ url: URL) {
        guard url.scheme == "catchwords" else { return }
        switch url.host {
        case "review":
            NotificationRouter.shared.pending = .review
        case "word":
            let id = url.pathComponents.filter { $0 != "/" }.first ?? ""
            if !id.isEmpty { NotificationRouter.shared.pending = .sticker(id) }
        default:
            break
        }
    }
}

/// Keeps the widgets current: after the dex loads, after a catch (word count changes), when the
/// display language changes and whenever the app comes to the foreground. Also takes widget links.
private struct WidgetBridgeModifier: ViewModifier {
    let dex: DexStore
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onOpenURL { WidgetBridge.open($0) }
            .onChange(of: dex.hasLoaded) { _, loaded in if loaded { WidgetBridge.refresh(dex: dex) } }
            .onChange(of: dex.stickers.count) { _, _ in WidgetBridge.refresh(dex: dex) }
            .onChange(of: L10n.lang) { _, _ in WidgetBridge.refresh(dex: dex) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { WidgetBridge.refresh(dex: dex) } }
    }
}

extension View {
    /// Widget snapshot upkeep + widget deep links (applied once, on the app's root view).
    func widgetBridge(dex: DexStore) -> some View { modifier(WidgetBridgeModifier(dex: dex)) }

    /// Mirrors the review round on the Lock Screen / Dynamic Island (Live Activity) and refreshes the
    /// widgets when the round ends. `enabled` is false for the practice tour (nothing is graded there).
    func reviewLiveActivity(store: ReviewStore, dex: DexStore, answered: Bool, enabled: Bool) -> some View {
        modifier(ReviewActivityModifier(store: store, dex: dex, answered: answered, enabled: enabled))
    }
}

/// Starts / updates / ends the review Live Activity. All failures are ignored.
@MainActor
enum ReviewActivityController {
    private static var activity: Activity<ReviewActivityAttributes>?

    static func sync(done: Int, total: Int, correct: Int) {
        guard total > 0 else { return }
        let state = ReviewActivityAttributes.ContentState(done: min(done, total), total: total, correct: correct)
        let content = ActivityContent(state: state, staleDate: nil)
        if let a = activity ?? Activity<ReviewActivityAttributes>.activities.first {
            activity = a
            Task { await a.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(attributes: ReviewActivityAttributes(lang: L10n.lang), content: content, pushType: nil)
    }

    /// Ends every review activity. With a final state it stays briefly on the Lock Screen; without, it goes now.
    static func end(final state: ReviewActivityAttributes.ContentState? = nil) {
        activity = nil
        let all = Activity<ReviewActivityAttributes>.activities
        guard !all.isEmpty else { return }
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = state == nil ? .immediate : .after(Date().addingTimeInterval(5 * 60))
        for a in all {
            Task { await a.end(content, dismissalPolicy: policy) }
        }
    }
}

private struct ReviewActivityModifier: ViewModifier {
    let store: ReviewStore
    let dex: DexStore
    let answered: Bool
    let enabled: Bool

    private var done: Int { min(store.queue.count, store.index + (answered ? 1 : 0)) }
    private var key: [Int] { [store.index, store.queue.count, store.correctCount, answered ? 1 : 0, store.isRetry ? 1 : 0, store.hasLoaded ? 1 : 0] }

    func body(content: Content) -> some View {
        content
            .onAppear { update() }
            .onChange(of: key) { _, _ in update() }
            .onDisappear {
                ReviewActivityController.end()
                if enabled { WidgetBridge.refresh(dex: dex, streak: store.streak) }
            }
    }

    private func update() {
        guard enabled, store.hasLoaded, !store.queue.isEmpty else { return }
        let total = store.queue.count
        if store.current == nil {
            // Round finished: show the result for a moment, then let it go; widgets get the new due count.
            ReviewActivityController.end(final: .init(done: total, total: total, correct: store.correctCount))
            WidgetBridge.refresh(dex: dex, streak: store.streak)
        } else {
            ReviewActivityController.sync(done: done, total: total, correct: store.correctCount)
        }
    }
}
