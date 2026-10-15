import Foundation

/// Why a catch could not be saved and how far it got (`DexStore.save`): the photos went up or not, then the row
/// (`saveSticker`). The developer log names the step; a retry saves the row with the photos already in storage
/// (`uploads`) instead of sending them again.
nonisolated struct CatchSaveError: Error, LocalizedError {
    nonisolated enum Stage: String, Sendable {
        /// Sending the photos to storage.
        case upload
        /// Writing the word and its sticker (`saveSticker`).
        case save
    }

    let stage: Stage
    let underlying: Error
    /// The photos already in storage when it stopped (nil: none went up).
    let uploads: CatchUploads?

    var errorDescription: String? { SaveFailure.message(for: self) }
}

/// The kind of failure that stopped a save, told apart (owner 2026-10-15: 花束 and 草莓蛋糕 were reported as
/// 「保存に失敗しました。ネットワークに接続できませんでした」 whatever had happened, and the words disappeared):
/// no network on the phone, a connection that dropped while online, a server that took too long, a server that answered
/// with an error, an answer the app could not read.
nonisolated enum SaveFailure: String, Equatable, Sendable {
    /// No network at all on this phone.
    case offline
    /// Online, but the connection to the server could not be made or dropped mid-request.
    case connectionLost
    /// The server did not answer in time.
    case timeout
    /// The server answered with an error (4xx: it refused what was sent; 5xx: it failed).
    case rejected
    /// The server answered, but not in a shape this build reads.
    case decoding
    /// The login is over.
    case signedOut
    case other

    /// The error under a `CatchSaveError`.
    static func root(_ error: Error) -> Error {
        (error as? CatchSaveError)?.underlying ?? error
    }

    static func classify(_ error: Error) -> SaveFailure {
        let e = root(error)
        if let u = e as? URLError, let mapped = APIError.from(u) as? APIError { return classify(mapped) }
        if e is DecodingError { return .decoding }
        guard let api = e as? APIError else { return .other }
        switch api {
        case .offline: return .offline
        case .connectionLost: return .connectionLost
        case .timeout: return .timeout
        case .server, .limit: return .rejected
        case .decoding: return .decoding
        case .unauthorized: return .signedOut
        case .notConfigured, .message, .aiConsentRequired: return .other
        }
    }

    /// A save that may well work later (the word waits in 「保存待ち」 and is tried again on its own).
    static func isRetryable(_ error: Error) -> Bool {
        switch classify(error) {
        case .offline, .connectionLost, .timeout, .decoding: return true
        case .rejected:
            if case .server(let code, _)? = root(error) as? APIError { return code >= 500 || code == 429 || code == 408 }
            return false
        case .signedOut, .other: return false
        }
    }

    /// What the learner reads: what happened, in a few words, in the display language. A connection that dropped is
    /// never called being offline (owner 2026-10-15: the Wi-Fi was on — it dropped connections during the larger
    /// uploads, and the same photo went up at once over the iPhone's tethering): it says the connection dropped while
    /// sending, and that another network or a little later may work.
    static func message(for error: Error) -> String {
        let e = root(error)
        let upload = (error as? CatchSaveError)?.stage == .upload
        let reason: String
        switch classify(error) {
        case .offline:
            reason = L("インターネットに接続できません。")
        case .connectionLost:
            let code: Int? = { if case .connectionLost(let c)? = e as? APIError { return c }; return nil }()
            if upload {
                // Said in full here: "写真を送れませんでした" in front would only repeat it.
                return (code.map { L("写真を送っている途中で接続が切れました（\($0)）。") } ?? L("写真を送っている途中で接続が切れました。"))
                    + "\n" + L("別のネットワークに切り替えるか、少し時間をおいてお試しください。")
            }
            reason = (code.map { L("サーバーとの通信が途中で切れました（\($0)）。") } ?? L("サーバーとの通信が途中で切れました。"))
                + "\n" + L("別のネットワークに切り替えるか、少し時間をおいてお試しください。")
        case .timeout:
            reason = L("サーバーの応答が時間切れになりました。")
        case .rejected:
            if case .server(let code, _)? = e as? APIError {
                reason = code >= 500 ? L("サーバーで問題が起きました（\(code)）。") : L("サーバーが保存を受け付けませんでした（\(code)）。")
            } else {
                reason = (e as? LocalizedError)?.errorDescription ?? L("サーバーが保存を受け付けませんでした。")
            }
        case .decoding:
            reason = L("サーバーの返事を読み取れませんでした。")
        case .signedOut:
            reason = L("ログインの有効期限が切れました。もう一度ログインしてください。")
        case .other:
            reason = (e as? LocalizedError)?.errorDescription ?? L("保存できませんでした。")
        }
        if upload { return L("写真を送れませんでした：\(reason)") }
        return reason
    }

    /// What the developer log keeps: the step, the kind, and the real error with every detail.
    static func log(_ error: Error, headword: String) -> String {
        let stage = (error as? CatchSaveError)?.stage.rawValue ?? "save"
        let uploads = (error as? CatchSaveError)?.uploads.map { u in
            "uploaded object=\(u.object ?? "-") cutout=\(u.cutout ?? "-") selfie=\(u.selfie ?? "-")"
        } ?? "nothing uploaded"
        return "\(headword): \(stage) failed (\(classify(error).rawValue)) — \(APIError.describe(root(error))); \(uploads)"
    }
}

/// Storage paths already written for a catch waiting in 「保存待ち」 (`CatchUploads`, kept on the phone).
nonisolated struct SavedUploads: Codable, Sendable, Hashable {
    var object: String?
    var cutout: String?
    var selfie: String?

    init(_ u: CatchUploads) {
        object = u.object
        cutout = u.cutout
        selfie = u.selfie
    }

    var uploads: CatchUploads { CatchUploads(object: object, cutout: cutout, selfie: selfie) }
}

/// Everything needed to save again a catch whose save failed (「保存待ち」, owner 2026-10-15: a failed save must never
/// make the word disappear): the word chosen and its card, where and when, the photos already in storage, and the catch's
/// own id (`client_catch_id`: the server answers with the sticker it already made for this id, so trying again never
/// makes a second one). Kept with its photo in 「解析待ち」 (`PendingQueue`), so it survives an app kill; its cut-out and
/// selfie are files next to the photo.
nonisolated struct PendingSave: Codable, Sendable, Hashable {
    /// `client_catch_id` (lowercase UUID): the same on every try.
    var catchId: String
    /// The provisional dex entry standing for it (`DexStore.provisionalPrefix`).
    var provisionalId: String
    /// The stamp the provisional entry's pictures are cached under (`uid/<ts>-object.jpg` …).
    var ts: Int
    /// The learning language it was caught in.
    var language: String
    var candidate: Candidate
    /// The card as `generateCard` returned it (nil: saved from the word's own fields; the page writes the notes).
    var card: JSONValue?
    var categoryKey: String
    var exampleSentence: String
    var exampleTranslation: String
    var caption: String
    var placeName: String?
    var lat: Double?
    var lng: Double?
    var captureType: String
    var takenAt: Date
    var hasCutout: Bool
    var hasSelfie: Bool
    /// The photos already in storage (nil: send them again).
    var uploads: SavedUploads?

    /// The card to save it with: the real one when it came, else the word's own fields.
    var details: CardDetails {
        if let card, let data = try? JSONEncoder().encode(card), let d = try? JSONDecoder().decode(CardDetails.self, from: data) {
            return d
        }
        return CardDetails(categoryKey: categoryKey, exampleSentence: exampleSentence, exampleTranslation: exampleTranslation,
                           extras: WordExtras())
    }
}

/// How a picture's upload is tried again (owner 2026-10-15). The connection dropped now and then while a larger file was
/// going up — 花束 (a 2.15 MB cut-out) failed about ten times before it saved, the strawberry cake five times out of
/// five — and every try was the learner's own. Now each upload is tried again on its own, after 1, 2 and 4 seconds,
/// when the failure is one another try can get past.
enum UploadRetry {
    /// The waits before the 2nd, 3rd and 4th tries.
    static let delays: [TimeInterval] = [1, 2, 4]

    /// The connection dropped (-1005) or could not be made (-1004), it took too long, or there was no network for a
    /// moment. A server's answer (the file refused, a full disk) is not tried again.
    static func isRetryable(_ error: Error) -> Bool {
        switch SaveFailure.root(error) as? APIError {
        case .connectionLost(let code)?:
            return code == URLError.Code.networkConnectionLost.rawValue || code == URLError.Code.cannotConnectToHost.rawValue
        case .timeout?, .offline?:
            return true
        default:
            return false
        }
    }

    /// Runs `send` (given the try's number, from 1) until it succeeds, fails in a way another try cannot get past, or the
    /// last try has failed (that failure is thrown).
    static func run(sleep: ((TimeInterval) async -> Void)? = nil, _ send: (Int) async throws -> Void) async throws {
        var attempt = 1
        while true {
            do {
                try await send(attempt)
                return
            } catch {
                guard attempt <= delays.count, isRetryable(error) else { throw error }
                let wait = delays[attempt - 1]
                if let sleep { await sleep(wait) } else { try? await Task.sleep(for: .seconds(wait)) }
                attempt += 1
            }
        }
    }
}
