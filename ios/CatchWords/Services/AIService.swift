import Foundation
import UIKit

/// Detection, candidates and cards through the web app's server functions (`/api/native-fn`).
/// The server holds the AI keys and every prompt, and writes meanings and notes in the learner's
/// display language and learning language — so the app never sends a prompt of its own, and no
/// AI text on screen can come back in a different language from the rest of the app.
final class AIService {
    static let shared = AIService()

    // MARK: - Web server functions (the Lovable-decided behaviour)

    private struct Suggestions: Decodable { let suggestions: [Candidate] }
    private struct WordCandidates: Decodable { let candidates: [Candidate] }

    /// Photo → candidates, exactly like the web capture (`suggestWords`, capture.tsx runAi):
    /// 768px / q0.8, one entry per object (`group`) plus its other names (`register`),
    /// in the server's order (most likely first, everyday name first). Never re-sorted here.
    func suggest(image: UIImage) async throws -> [Candidate] {
        guard let jpeg = await ImageTools.jpegForUploadInBackground(image, maxSide: 768, quality: 0.8) else {
            throw APIError.message(L("写真を読み込めませんでした。"))
        }
        let res = try await NativeAPI.call("suggestWords", [
            "imageBase64": "data:image/jpeg;base64,\(jpeg.base64EncodedString())",
            "targetLanguage": NativeAPI.targetLanguage,
        ], as: Suggestions.self, timeout: 25)
        // A repeated name is dropped only within one object: two different objects with the same name (two cups
        // in one photo) stay two objects, each with its own point (card catch groups by `group`).
        // A name not written in the learning language alone (kana or English in a Mandarin word) is never offered.
        var out: [Candidate] = []
        for c in res.suggestions where !out.contains(where: { Self.sameSuggestion($0, c) })
            && LanguageRules.headwordSaveable(c.headword, target: NativeAPI.targetLanguage) { out.append(c) }
        guard !out.isEmpty else { throw APIError.message(L("AIから候補が返りませんでした。もう一度お試しください。")) }
        return out
    }

    /// The same name for the same object: the same group, or (no group) the same point.
    nonisolated static func sameSuggestion(_ a: Candidate, _ b: Candidate) -> Bool {
        guard a.headword == b.headword else { return false }
        if let ga = a.group, let gb = b.group { return ga == gb }
        if a.group != nil || b.group != nil { return false }
        return a.point == b.point
    }

    /// The scan screen (web `detectScan`): nouns only, the learner's level, dictionary learning and
    /// the scan_events funnel log — all on the server, same as the web.
    func detectScan(image: UIImage, lat: Double? = nil, lng: Double? = nil) async throws -> [Candidate] {
        struct Res: Decodable { let items: [Candidate] }
        guard let jpeg = await ImageTools.jpegForUploadInBackground(image) else { throw APIError.message(L("写真を読み込めませんでした。")) }
        var data: [String: Any] = ["imageBase64": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]
        if let lat, let lng { data["lat"] = lat; data["lng"] = lng }
        let res = try await NativeAPI.call("detectScan", data, as: Res.self, timeout: 40)
        var out: [Candidate] = []
        for c in res.items where !out.contains(where: { $0.headword == c.headword }) { out.append(c) }
        guard !out.isEmpty else { throw APIError.message(L("写真から言葉を見つけられませんでした。明るい所で、撮りたい物に近づいて撮り直してください。")) }
        return out
    }

    /// Typed word (any language) → 1–5 names, each with how it differs and what kind of name it is
    /// (`suggestWordCandidates`). The camera always lists them on the choose screen, even one (owner 2026-10-15).
    func candidates(for query: String, scene: String? = nil) async throws -> [Candidate] {
        var data: [String: Any] = ["query": String(query.prefix(60)), "targetLanguage": NativeAPI.targetLanguage]
        if let scene, !scene.isEmpty { data["scene"] = String(scene.prefix(200)) }
        let res = try await NativeAPI.call("suggestWordCandidates", data, as: WordCandidates.self, timeout: 30)
        return res.candidates
    }

    /// Voice search: the spoken word (any language) → the best name (`suggestWordCandidates`, first),
    /// written in the reader's language by the server.
    func lookup(text query: String) async throws -> Candidate {
        guard let first = try await candidates(for: query).first else { throw APIError.message(L("その言葉が見つかりませんでした。")) }
        return first
    }

    /// The web's card (`generateCard`): the example sentence and chunks are written at the learner's level
    /// (the server reads `profiles.current_level` / `level_goal`, set in 設定), in the explanation language,
    /// with retries on bad shape and every extras section. The card's own `level` field is not used on iOS.
    func cardDetails(for candidate: Candidate) async throws -> CardDetails {
        var data: [String: Any] = ["headword": candidate.headword, "targetLanguage": NativeAPI.targetLanguage]
        if let hint = candidate.categoryKey, !hint.isEmpty { data["hintCategory"] = hint }
        return try await NativeAPI.call("generateCard", data, as: CardDetails.self, timeout: 60)
    }
}
