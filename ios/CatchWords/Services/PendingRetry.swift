import UIKit
import Network
import UserNotifications

/// Photos in 「解析待ち」 are analyzed again on their own — when the connection comes back, when the app
/// comes to the front and after signing in — so the learner no longer has to tap each one to retry.
///
/// - Same server call as the manual retry (`AIService.suggest`, what `CaptureViewModel.restore` runs), and
///   both go through `suggest(for:image:)`: one photo is never analyzed twice at the same time, and the
///   words found here are what the camera shows when the photo is opened (no second call).
/// - One photo at a time, the signed-in account's only, never the one the camera is working on. Each photo
///   gets at most `maxAttempts` automatic tries, spaced out (1, 4, 16, 64 min); a failure keeps the photo
///   and shows its reason, like the manual retry. Tapping the photo retries it by hand at any time.
/// - After a successful analysis the photo stays in the queue (the catch is made when the learner picks the
///   word); a local notification says so — only when notifications are already allowed, never asked here.
/// - A catch whose save failed (「保存待ち」, `PendingCatch.save`) is not analyzed again: its word is saved again as it
///   is (`DexStore.retryUnsaved`, with the same `client_catch_id`), on the same triggers and spacing; no connection
///   is not counted as a try.
final class PendingRetry {
    static let shared = PendingRetry()
    static let maxAttempts = 5
    /// Identifier prefix of the 「解析が終わりました」 notification (NotificationRouter opens the queue).
    static let notificationPrefix = "pending-done-"

    /// Per photo (`PendingCatch.id`), kept across launches so the try limit and the found words survive.
    nonisolated private struct Record: Codable, Sendable {
        var attempts: Int = 0
        var nextAt: Date?
        /// Analyzed automatically: not tried again (the learner picks the word from it).
        var analyzed: Bool = false
        /// The words found, for the learning language they were found in (handed to the camera once).
        var candidates: [Candidate]?
        var language: String?
        /// The display language the words' meanings were written in (nil on records from before 2026-10-20).
        var readerLang: String?
        var updatedAt: Date = Date()
    }

    private static let storeKey = "pending.autoRetry"
    private var records: [String: Record] = [:]
    private var recordsLoaded = false
    /// Analyses running now, per photo: a second request for the same photo waits for this one.
    private var inFlight: [String: Task<[Candidate], any Error>] = [:]
    private var runner: Task<Void, Never>?
    /// Goes up on sign-out, so a pass of the account that left never clears the next account's runner.
    private var generation = 0
    /// A trigger arrived while a pass was running: look at the queue once more when it ends.
    private var rerun = false
    private var wake: Task<Void, Never>?
    /// The server's daily cap was hit: no automatic tries until then (it recovers on its own).
    private var pausedUntil: Date?
    /// Between sign-in (profile and learning language read) and sign-out.
    private var active = false
    private var online: Bool?
    private let monitor = NWPathMonitor()
    private var monitorStarted = false
    private var cameras: [WeakCamera] = []

    private struct WeakCamera { weak var vm: CaptureViewModel? }

    /// The dex that saves 「保存待ち」 catches again (set at sign-in, RootView).
    weak var dex: DexStore?

    // MARK: - Triggers

    /// After sign-in, once the profile (learning language) is read: starts watching and tries now.
    func start() {
        active = true
        if !monitorStarted {
            monitorStarted = true
            monitor.pathUpdateHandler = { path in
                let online = path.status == .satisfied
                Task { @MainActor in PendingRetry.shared.networkChanged(online: online) }
            }
            monitor.start(queue: .main)
        }
        kick()
    }

    /// Signing out: nothing more for that account (a request already sent finishes, its result is dropped).
    func stop() {
        active = false
        rerun = false
        generation += 1
        runner?.cancel()
        runner = nil
        wake?.cancel()
        wake = nil
        pausedUntil = nil
    }

    /// The app came to the front (and the triggers above): try the photos that are due, one by one.
    func kick() {
        guard active, SupabaseClient.shared.userId != nil else { return }
        if runner != nil {
            rerun = true
            return
        }
        let g = generation
        runner = Task { await run(generation: g) }
    }

    private func networkChanged(online now: Bool) {
        let cameBack = online == false && now
        online = now
        if cameBack { kick() }
    }

    // MARK: - The camera

    /// The camera's model: the photo it holds (`pendingId`) is never tried here behind its back.
    func register(_ vm: CaptureViewModel) {
        cameras.removeAll { $0.vm == nil }
        cameras.append(WeakCamera(vm: vm))
    }

    private func isHeld(_ id: String) -> Bool {
        cameras.contains { $0.vm?.pendingId == id }
    }

    /// The manual retry (a photo opened from 「解析待ち」): the words already found automatically, or the
    /// analysis running for this photo now, or a new one — never two at once for the same photo.
    func suggest(for id: String, image: UIImage) async throws -> [Candidate] {
        loadRecords()
        // Only for the same learning language and the same display language (meanings found for a Japanese screen are
        // not shown on a 繁體中文 one — 自転車 reads as both).
        if var r = records[id], let found = r.candidates, !found.isEmpty, r.language == NativeAPI.targetLanguage,
           r.readerLang == L10n.lang {
            r.candidates = nil
            records[id] = r
            saveRecords()
            return found
        }
        return try await analyze(id: id, image: image)
    }

    /// The photo's job is done (saved, or thrown away): its record goes too.
    func forget(_ id: String) {
        loadRecords()
        guard records.removeValue(forKey: id) != nil else { return }
        saveRecords()
    }

    private func analyze(id: String, image: UIImage) async throws -> [Candidate] {
        if let running = inFlight[id] { return try await running.value }
        let task = Task<[Candidate], any Error> { try await AIService.shared.suggest(image: image) }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        return try await task.value
    }

    // MARK: - Passes

    private func run(generation g: Int) async {
        repeat {
            rerun = false
            await pass()
        } while rerun && active && !Task.isCancelled
        guard g == generation else { return }
        runner = nil
        scheduleWake()
    }

    private enum Outcome { case next, stop }

    private func pass() async {
        loadRecords()
        guard online != false, let owner = SupabaseClient.shared.userId else { return }
        let paused = (pausedUntil ?? .distantPast) > Date()
        // No consent to send photos to AI: no photo is analyzed (agreeing kicks a new pass). Saving a word already
        // chosen sends nothing to AI and goes on.
        let mayAnalyze = AIConsent.shared.allowsSending() && !paused
        PendingQueue.shared.reload()
        for item in PendingQueue.shared.items.reversed() {   // oldest first
            guard active, !Task.isCancelled, SupabaseClient.shared.userId == owner else { return }
            guard isDue(item.id), !isHeld(item.id) else { continue }
            if item.isUnsaved {
                if await attemptSave(item) == .stop { return }
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            guard mayAnalyze else { continue }
            // A photo whose file is gone is left as it is (opening it by hand removes it).
            guard let image = PendingQueue.shared.image(for: item) else { continue }
            if await attempt(item.id, image: image) == .stop { return }
            // A short gap between photos, so a long queue never arrives as a burst.
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func isDue(_ id: String) -> Bool {
        guard let r = records[id] else { return true }
        if r.analyzed || r.attempts >= Self.maxAttempts { return false }
        return (r.nextAt ?? .distantPast) <= Date()
    }

    private func isQueued(_ id: String) -> Bool {
        PendingQueue.shared.items.contains { $0.id == id }
    }

    private func attempt(_ id: String, image: UIImage) async -> Outcome {
        let language = NativeAPI.targetLanguage
        var r = records[id] ?? Record()
        r.attempts += 1
        r.updatedAt = Date()
        records[id] = r
        saveRecords()
        do {
            let found = try await analyze(id: id, image: image)
            // Opened by hand meanwhile (the camera shows these words itself), or no longer in the queue.
            guard active, isQueued(id), !isHeld(id) else { return .next }
            var done = records[id] ?? r
            done.analyzed = true
            done.candidates = found
            done.language = language
            done.readerLang = L10n.lang
            done.nextAt = nil
            records[id] = done
            saveRecords()
            PendingQueue.shared.updateReason(id: id, reason: L("解析が終わりました。タップして単語を選べます"))
            await notifyDone(id: id, word: found.first?.headword)
            return .next
        } catch {
            guard isQueued(id) else { return .next }
            var failed = records[id] ?? r
            // The photo is kept, with why it failed (the same words as the manual retry).
            if !isHeld(id) { PendingQueue.shared.updateReason(id: id, reason: CaptureViewModel.reason(error)) }
            let outcome: Outcome
            switch error as? APIError {
            case .offline?:
                // No connection: not counted; the connection coming back tries again.
                failed.attempts -= 1
                failed.nextAt = nil
                outcome = .stop
            case .unauthorized?, .notConfigured?, .aiConsentRequired?:
                // The login is handled elsewhere (sessionExpired), the consent on its screen; not this photo's fault.
                failed.attempts -= 1
                outcome = .stop
            case .limit?:
                pausedUntil = Date().addingTimeInterval(60 * 60)
                failed.nextAt = pausedUntil
                outcome = .stop
            default:
                failed.nextAt = Date().addingTimeInterval(Self.backoff(after: failed.attempts))
                outcome = .next
            }
            failed.attempts = max(0, failed.attempts)
            records[id] = failed
            saveRecords()
            return outcome
        }
    }

    /// A 「保存待ち」 catch: its word saved again (`DexStore.retryUnsaved`). Only for the learning language shown now (its
    /// word then takes its place in this dex); another language's waits until that language is studied again.
    private func attemptSave(_ item: PendingCatch) async -> Outcome {
        guard let dex, item.save?.language == NativeAPI.targetLanguage else { return .next }
        var r = records[item.id] ?? Record()
        r.attempts += 1
        r.updatedAt = Date()
        records[item.id] = r
        saveRecords()
        do {
            try await dex.retryUnsaved(pendingId: item.id)
            dex.refreshPending()
            return .next
        } catch {
            var failed = records[item.id] ?? r
            let outcome: Outcome
            if error is CancellationError {
                // Being saved by hand right now: not a try.
                failed.attempts -= 1
                outcome = .next
            } else {
                switch SaveFailure.classify(error) {
                case .offline:
                    // No connection: not counted; the connection coming back tries again.
                    failed.attempts -= 1
                    failed.nextAt = nil
                    outcome = .stop
                case .signedOut:
                    failed.attempts -= 1
                    outcome = .stop
                default:
                    failed.nextAt = Date().addingTimeInterval(Self.backoff(after: failed.attempts))
                    outcome = .next
                }
            }
            failed.attempts = max(0, failed.attempts)
            records[item.id] = failed
            saveRecords()
            return outcome
        }
    }

    /// A catch's first save failed just now (`CaptureView.finishSave`): its first automatic retry comes a minute later
    /// (at once when the connection comes back, if there was none), not in the same breath.
    func noteFailedSave(_ id: String, error: Error) {
        loadRecords()
        var r = records[id] ?? Record()
        if SaveFailure.classify(error) == .offline {
            r.nextAt = nil
        } else {
            r.attempts += 1
            r.nextAt = Date().addingTimeInterval(Self.backoff(after: r.attempts))
        }
        r.updatedAt = Date()
        records[id] = r
        saveRecords()
        if runner == nil { scheduleWake() }
    }

    /// 1, 4, 16, 64 minutes after the 1st, 2nd, 3rd, 4th failed try.
    private static func backoff(after attempts: Int) -> TimeInterval {
        min(2 * 60 * 60, 60 * pow(4, Double(max(0, attempts - 1))))
    }

    /// While the app runs, the next try that falls due within half an hour is not left waiting for a trigger.
    private func scheduleWake() {
        wake?.cancel()
        wake = nil
        guard active else { return }
        let now = Date()
        let next = PendingQueue.shared.items.compactMap { item -> Date? in
            guard let r = records[item.id], !r.analyzed, r.attempts < Self.maxAttempts, let at = r.nextAt, at > now else { return nil }
            return at
        }.min()
        guard let next, next.timeIntervalSince(now) <= 30 * 60 else { return }
        let delay = next.timeIntervalSince(now) + 1
        wake = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            kick()
        }
    }

    // MARK: - Notification

    /// 「解析が終わりました：◯◯」 — only when the learner already allowed notifications (never asks here).
    /// In the foreground it shows as a banner too (NotificationRouter `willPresent`).
    private func notifyDone(id: String, word: String?) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }
        let content = UNMutableNotificationContent()
        content.title = "CatchWords"
        if let word, !word.isEmpty {
            content.body = L("解析が終わりました：\(word)")
        } else {
            content.body = L("解析が終わりました。写真から単語を選べます")
        }
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: Self.notificationPrefix + id, content: content, trigger: nil))
    }

    // MARK: - Storage

    private func loadRecords() {
        guard !recordsLoaded else { return }
        recordsLoaded = true
        guard let data = UserDefaults.standard.data(forKey: Self.storeKey),
              let saved = try? JSONDecoder().decode([String: Record].self, from: data) else { return }
        // Photos of another account stay listed; anything untouched for 30 days is dropped (its photo was
        // saved or deleted long ago, or it simply starts over).
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        records = saved.filter { $0.value.updatedAt > cutoff }
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.storeKey)
    }
}
