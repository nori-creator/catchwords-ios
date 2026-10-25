import Foundation
import Observation

/// Consent to send the learner's photos, words and text to third-party AI (App Store Review Guideline
/// 5.1.2(i): "clearly disclose where personal data will be shared with third parties, including with
/// third-party AI, and obtain explicit permission before doing so"; privacy policy chapter 4).
///
/// - Asked once per account (`AIConsentView`, over the app right after sign-in / onboarding), before the
///   first AI feature and before the camera opens.
/// - The one gate: `NativeAPI.call` refuses every function in `aiFunctions` with
///   `APIError.aiConsentRequired` until this account has agreed, before anything leaves the phone. The
///   screens only decide what to show instead (the camera tab's `AIConsentGateView`, the consent sheet).
/// - Kept on this device per account (`aiConsent.<userId>`: status, version, date). Withdrawn in 設定.
/// - The server keeps its own record (web `ai_consents`, docs/ios-spec/23-ai-consent.md in the web repo;
///   the web patch is docs/web-changes/ here). Every answer is sent with `recordAiConsent`; after sign-in
///   `syncWithServer` reads `getAiConsent` and makes the two agree. A server without these functions yet
///   (production until the web patch is deployed), or any failure, changes nothing here: the answer on
///   this device stays the one that counts, and an unsent answer is marked (`pending`) and sent again on
///   the next launch. None of this ever waits in front of a screen.
/// - An AI function the server refuses (403 `AI_CONSENT_REQUIRED`) arrives as `APIError.aiConsentRequired`
///   too (`NativeAPI.call` → `serverRefused`).
@Observable
final class AIConsent {
    static let shared = AIConsent()

    /// Raise when what is sent, or to whom, changes: a consent given to an older version is asked again
    /// (privacy policy 14: a new third party needs a new consent).
    static let currentVersion = 1

    /// Server functions that send the learner's photos, words or text on to an AI provider.
    /// Reads of what was already written (meanings, explanations), saving, review grading and speech are
    /// not here: they do not hand personal data to an AI.
    static let aiFunctions: Set<String> = [
        "suggestWords",           // photo → candidates
        "detectScan",             // scan frame → words
        "rankScanCandidates",     // the words a scan found
        "suggestWordCandidates",  // typed or spoken word → names
        "generateCard",           // word → card, notes, example sentences
        "regenerateCardSection",  // word → one section written again
        "reportAndFixSection",    // the learner's note on a wrong item
        "correctMyJournal",       // the finished diary → its correction (2026-10-25)
        "checkDiarySentence",     // each finished sentence of the diary → its check (2026-10-25)
    ]

    enum Status: Equatable {
        case undecided
        case granted(Date)
        case declined(Date)
    }

    private(set) var status: Status = .undecided
    /// Read for the signed-in account (false while signed out).
    private(set) var isLoaded = false
    /// The account `status` belongs to.
    private var userId: String?

    var isGranted: Bool {
        if case .granted = status { return true }
        return false
    }

    var isUndecided: Bool { status == .undecided }

    // MARK: - Reading and saving

    private static let keyPrefix = "aiConsent"

    private static func key(for userId: String?) -> String {
        guard let userId else { return keyPrefix }   // no account: the device's own answer
        return keyPrefix + "." + userId
    }

    /// After sign-in: this account's answer on this device.
    func load(userId: String?) {
        self.userId = userId
        isLoaded = true
        guard let record = UserDefaults.standard.dictionary(forKey: Self.key(for: userId)),
              let state = record["status"] as? String else {
            status = .undecided
            return
        }
        let version = record["version"] as? Int ?? 0
        let date = Date(timeIntervalSince1970: record["date"] as? Double ?? 0)
        switch state {
        case "granted" where version >= Self.currentVersion: status = .granted(date)
        case "declined": status = .declined(date)
        default: status = .undecided   // agreed to an older version: asked again
        }
    }

    /// Signed out: nothing is known until the next account's answer is read.
    func reset() {
        userId = nil
        isLoaded = false
        status = .undecided
        syncTask = nil
        syncUser = nil
    }

    /// 「同意して始める」.
    func grant() {
        save("granted")
        sendAnswer()
        // Photos left in 「解析待ち」 can be analyzed now.
        PendingRetry.shared.kick()
    }

    /// 「同意しない」, or withdrawing it in 設定: the AI features are blocked again.
    func decline() {
        save("declined")
        sendAnswer()
    }

    private func save(_ state: String) {
        let now = Date()
        var record: [String: Any] = [
            "status": state,
            "version": Self.currentVersion,
            "date": now.timeIntervalSince1970,
        ]
        // Not on the server yet: sent right after this, and again on every launch until it arrives.
        if userId != nil { record["pending"] = true }
        UserDefaults.standard.set(record, forKey: Self.key(for: userId))
        status = state == "granted" ? .granted(now) : .declined(now)
    }

    /// The gate (`NativeAPI.call`): whether an AI request may go out now, for the account signed in now.
    func allowsSending() -> Bool {
        let current = SupabaseClient.shared.userId
        if !isLoaded || current != userId { load(userId: current) }
        return isGranted
    }

    /// Account deleted: its answer goes with it.
    static func removeRecord(userId: String?) {
        UserDefaults.standard.removeObject(forKey: key(for: userId))
    }

    // MARK: - The server's record (docs/ios-spec/23-ai-consent.md in the web repo)

    /// The functions that read and write the consent itself: never refused for want of consent, and a
    /// refusal of theirs (an outdated version) is not answered by syncing again.
    static let recordFunctions: Set<String> = ["recordAiConsent", "getAiConsent"]

    /// `recordAiConsent` / `getAiConsent` → `result`. `agreed` is true only for the server's current version.
    private struct ServerRecord: Decodable {
        let agreed: Bool
        let version: Int?
        let agreedAt: String?
        let revokedAt: String?
        /// `getAiConsent` only: false while the server has no table yet (it checks nothing then).
        let recorded: Bool?
    }

    /// The sync running now and its account: callers arriving meanwhile wait for it instead of starting another.
    @ObservationIgnored private var syncTask: Task<SyncOutcome, Never>?
    @ObservationIgnored private var syncUser: String?
    @ObservationIgnored private var syncGeneration = 0

    private static func storedRecord(for userId: String) -> [String: Any]? {
        UserDefaults.standard.dictionary(forKey: key(for: userId))
    }

    private static func isPending(_ userId: String) -> Bool {
        storedRecord(for: userId)?["pending"] as? Bool == true
    }

    /// After sign-in (`RootView`, not awaited) and when the server refuses an AI function: makes this device
    /// and the server agree (spec 「iOS 側でやること」 3). Returns true when the server is known to hold this
    /// account's agreement to the current version. Every failure leaves the answer on this device as it is.
    @discardableResult
    func syncWithServer() async -> Bool {
        await sync() == .agreed
    }

    /// What a sync learned: the server holds the agreement, the server answered without one, or no answer.
    private enum SyncOutcome { case agreed, notAgreed, unknown }

    private func sync() async -> SyncOutcome {
        guard let uid = SupabaseClient.shared.userId else { return .unknown }
        if !isLoaded || userId != uid { load(userId: uid) }
        if let running = syncTask, syncUser == uid { return await running.value }
        syncGeneration += 1
        let generation = syncGeneration
        let task = Task { () -> SyncOutcome in
            let outcome = await self.reconcile(uid)
            // Cleared before anyone waiting on it resumes: the next call starts a fresh sync.
            if self.syncGeneration == generation {
                self.syncTask = nil
                self.syncUser = nil
            }
            return outcome
        }
        syncTask = task
        syncUser = uid
        return await task.value
    }

    /// The server refused an AI function (403 `AI_CONSENT_REQUIRED`): it has no agreement for this account.
    /// True when the agreement kept on this device has reached it now (the caller tries once more). When the
    /// server answers that it has none, an agreement still shown here is dropped, so the consent screen asks
    /// again; when it cannot be reached, nothing changes.
    func serverRefused() async -> Bool {
        guard let uid = SupabaseClient.shared.userId else { return false }
        var outcome = await sync()
        // A sync already running when the answer was given here (sign-in) may have passed it by: once more.
        if outcome != .agreed, Self.isPending(uid) { outcome = await sync() }
        if outcome == .agreed { return true }
        if outcome == .notAgreed, userId == uid, isGranted {
            UserDefaults.standard.removeObject(forKey: Self.key(for: uid))
            load(userId: uid)
        }
        return false
    }

    /// Every `recordAiConsent` — answers given on screen and the sends a sync makes — goes to the server one at
    /// a time, in the order queued. Each job re-reads the answer kept on this device when its turn comes, so
    /// nothing older can overtake a withdrawal (or an agreement) made after it was queued.
    @ObservationIgnored private var sendChain: Task<Void, Never>?

    /// Queues `work` behind every send already queued; await `.value` for its result.
    @discardableResult
    private func enqueue<T: Sendable>(_ work: @escaping () async -> T) -> Task<T, Never> {
        let previous = sendChain
        let job = Task { () -> T in
            await previous?.value
            return await work()
        }
        sendChain = Task { _ = await job.value }
        return job
    }

    /// Right after 「同意して始める」 / 「同意しない」 / withdrawing: the answer goes to the server in the background.
    private func sendAnswer() {
        guard let uid = userId else { return }
        enqueue { await self.sendPending(for: uid) }
    }

    private static func outcome(of sent: ServerRecord?) -> SyncOutcome {
        guard let sent else { return .unknown }
        return sent.agreed && (sent.version ?? 0) >= currentVersion ? .agreed : .notAgreed
    }

    private func reconcile(_ uid: String) async -> SyncOutcome {
        // 1. An answer given on this device that has not reached the server goes first; while it cannot be
        //    sent, it is the one that counts (the server's record is older than it). Queued like every send,
        //    so an answer given on screen meanwhile goes after it and wins.
        if let sent = await enqueue({ await self.sendPending(for: uid) }).value { return Self.outcome(of: sent) }
        if Self.isPending(uid) { return .unknown }

        // 2. The server's record. No such function yet (the production server before the web patch), no
        //    table yet, no network: nothing changes here.
        guard SupabaseClient.shared.userId == uid,
              let server = try? await NativeAPI.call("getAiConsent", [:], as: ServerRecord.self, timeout: 15),
              server.recorded != false,
              userId == uid, !Self.isPending(uid) else { return .unknown }
        let local = Self.storedRecord(for: uid)
        let localDate = (local?["date"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? .distantPast
        let agreedAt = server.agreedAt.flatMap(SupabaseDate.parse)
        let revokedAt = server.revokedAt.flatMap(SupabaseDate.parse)

        if server.agreed, (server.version ?? 0) >= Self.currentVersion {
            switch status {
            case .granted:
                return .agreed
            case .declined where localDate > (agreedAt ?? .distantPast):
                // Declined on this device after the server's agreement (with a build that did not send answers).
                // Sent only if it is still the answer here when its turn comes.
                _ = await enqueue { () -> ServerRecord? in
                    guard self.userId == uid, !self.isGranted, !Self.isPending(uid) else { return nil }
                    return await self.send(agreed: false, version: Self.currentVersion, for: uid)
                }.value
                return .notAgreed
            case .declined, .undecided:
                // Agreed on another device or on the web: not asked again here.
                adopt("granted", version: server.version ?? Self.currentVersion, date: agreedAt ?? Date(), for: uid)
                return .agreed
            }
        }

        guard isGranted else { return .notAgreed }
        if let revokedAt, revokedAt >= localDate {
            // Withdrawn on the web or another device after agreeing here: withdrawn here too.
            adopt("declined", version: Self.currentVersion, date: revokedAt, for: uid)
            return .notAgreed
        }
        // Agreed here before the server kept a record (an earlier build): send that agreement, a copy of what
        // this person explicitly chose. A failure is tried again on the next sync.
        // Sent only if it is still the answer here when its turn comes (a withdrawal queued meanwhile wins).
        let version = local?["version"] as? Int ?? Self.currentVersion
        let sent = await enqueue { () -> ServerRecord? in
            guard self.userId == uid, self.isGranted, !Self.isPending(uid) else { return nil }
            return await self.send(agreed: true, version: version, for: uid)
        }.value
        return Self.outcome(of: sent)
    }

    /// Sends this account's unsent answer. The server's record after it, or nil when there was nothing to send
    /// or sending failed (kept unsent: sent again on the next launch).
    private func sendPending(for uid: String) async -> ServerRecord? {
        guard let record = Self.storedRecord(for: uid), record["pending"] as? Bool == true,
              let state = record["status"] as? String else { return nil }
        let version = record["version"] as? Int ?? Self.currentVersion
        let date = record["date"] as? Double
        if state == "granted", version < Self.currentVersion {
            // Agreed to an older version: asked again (`load`), nothing to send.
            markSent(uid, state: state, date: date)
            return nil
        }
        guard let sent = await send(agreed: state == "granted", version: version, for: uid) else { return nil }
        markSent(uid, state: state, date: date, server: sent)
        return sent
    }

    /// The unsent mark comes off, unless the answer changed meanwhile (that one is sent by its own call).
    /// The date kept becomes the server's own time for this answer, so later syncs compare the server's
    /// clock with the server's clock, never with this phone's.
    private func markSent(_ uid: String, state: String, date: Double?, server: ServerRecord? = nil) {
        guard var record = Self.storedRecord(for: uid),
              record["status"] as? String == state, record["date"] as? Double == date else { return }
        record.removeValue(forKey: "pending")
        let serverTime = (state == "granted" ? server?.agreedAt : server?.revokedAt).flatMap(SupabaseDate.parse)
        if let serverTime { record["date"] = serverTime.timeIntervalSince1970 }
        UserDefaults.standard.set(record, forKey: Self.key(for: uid))
    }

    /// `recordAiConsent`. Any failure (an unknown function on a server without the web patch, 400, 404, 503,
    /// no network, signed out meanwhile) is nil and is never shown.
    private func send(agreed: Bool, version: Int, for uid: String) async -> ServerRecord? {
        guard SupabaseClient.shared.userId == uid else { return nil }
        do {
            return try await NativeAPI.call("recordAiConsent", ["version": version, "agreed": agreed],
                                            as: ServerRecord.self, timeout: 15, asUser: uid)
        } catch {
            return nil
        }
    }

    /// The server's answer, kept on this device as already sent.
    private func adopt(_ state: String, version: Int, date: Date, for uid: String) {
        guard userId == uid, SupabaseClient.shared.userId == uid else { return }
        UserDefaults.standard.set([
            "status": state,
            "version": version,
            "date": date.timeIntervalSince1970,
        ] as [String: Any], forKey: Self.key(for: uid))
        load(userId: uid)
    }
}
