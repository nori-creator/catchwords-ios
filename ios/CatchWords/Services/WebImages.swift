import Foundation
import UIKit

/// One picture the web's image search offers for a word (images.functions.ts `ImageCandidate`):
/// an Unsplash / Wikimedia photo, or an AI illustration sent inline as a `data:` URL.
nonisolated struct WebImageCandidate: Decodable, Sendable, Hashable, Identifiable {
    struct Credit: Decodable, Sendable, Hashable {
        let name: String?
        let link: String?
    }

    let url: String
    let thumb: String?
    let source: String
    let credit: Credit?

    var id: String { url }
    /// The small version for tiles (AI pictures have only the one).
    var previewURL: URL? { URL(string: thumb ?? url) }
    /// What is saved with the word (`stickers.placeholder_credit`).
    var creditPayload: [String: Any] {
        var out: [String: Any] = ["source": source]
        if let n = credit?.name { out["name"] = n }
        if let l = credit?.link { out["link"] = l }
        return out
    }
}

/// Pictures from the internet for a word (web use-web-images.ts / use-auto-hero.ts). The search words
/// come from `LanguageRules.heroSearchQuery` only, the same rule the web uses, so the picture a word
/// gets on the iPhone is the one it gets on the web.
@MainActor
enum WebImages {
    private static var cache: [String: [WebImageCandidate]] = [:]

    /// The same hosts the web's `fetchImageAsDataUrl` accepts (image-proxy.ts ALLOWED_IMAGE_HOSTS, Openverse and Flickr
    /// added there 2026-10-09); anything else is never downloaded.
    private static let allowedHosts: Set<String> = Set(["images.unsplash.com", "plus.unsplash.com", "upload.wikimedia.org",
                                                        "api.openverse.org", "live.staticflickr.com"]
                                                       + (1...9).map { "farm\($0).staticflickr.com" })

    /// Search candidates. `round` > 0 is 「別の画像」: the web searches again with the headword added.
    static func search(headword: String, meaning: String?, round: Int = 0) async throws -> [WebImageCandidate] {
        try await search(headword: headword, meaning: meaning, imageQuery: nil, avoid: nil, category: nil, language: nil, round: round)
    }

    /// A saved word's pictures: its own English search words, the words that mean a wrong picture, its shelf
    /// and language go with the search, so the server looks for the thing itself (web use-web-images.ts).
    static func search(word: Word, round: Int = 0) async throws -> [WebImageCandidate] {
        try await search(headword: word.headword, meaning: word.meaningJa, imageQuery: word.extras?.imageQuery,
                         avoid: word.extras?.imageAvoid, category: word.categoryKey,
                         language: LanguageRules.resolveWordLanguage(stored: word.language, headword: word.headword), round: round)
    }

    /// The headword and the reader's meaning are sent too: when the query is not English, the server decides the
    /// English search words and what to avoid from them, and checks the pictures against them (image-sense.ts).
    static func search(headword: String, meaning: String?, imageQuery: String?, avoid: [String]?, category: String?,
                       language: String?, round: Int = 0) async throws -> [WebImageCandidate] {
        let base = LanguageRules.heroSearchQuery(headword: headword, meaning: meaning, imageQuery: imageQuery)
        // Never send an empty search (a word with no headword and no meaning simply has no picture).
        guard !base.isEmpty else { return [] }
        // An English query with the Mandarin headword added finds nothing anywhere: only the meaning-based
        // query gets the headword on 「別の画像」.
        let english = !LanguageRules.cleanImageQuery(imageQuery).isEmpty
        let query = round == 0 || english ? base : "\(base) \(headword)"
        let avoidList = (avoid ?? []).filter { !$0.isEmpty }.prefix(12).map { String($0.prefix(40)) }
        let key = [query, avoidList.joined(separator: "|"), category ?? "", language ?? "", String(round)].joined(separator: "\u{1F}")
        if let hit = seeded[headword] ?? cache[key] { return hit }
        var body: [String: Any] = ["query": String(query.prefix(120)), "headword": String(headword.prefix(80))]
        let m = (meaning ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { body["meaning"] = String(m.prefix(200)) }
        if !avoidList.isEmpty { body["avoid"] = Array(avoidList) }
        if let category, !category.isEmpty { body["category"] = String(category.prefix(40)) }
        if let language, !language.isEmpty { body["language"] = language }
        struct Res: Decodable { let candidates: [WebImageCandidate] }
        let r = try await NativeAPI.call("searchImageCandidates", body, as: Res.self, timeout: 60)
        cache[key] = r.candidates
        return r.candidates
    }

    /// Previews only: what a search for this word returns, without the network.
    static func seed(headword: String, meaning: String?, candidates: [WebImageCandidate]) {
        seeded[headword] = candidates
    }

    private static var seeded: [String: [WebImageCandidate]] = [:]

    private static var inline: [String: UIImage] = [:]

    /// An AI picture sent inline (`data:` URL), decoded once; nil for pictures on the web.
    static func inlineImage(_ candidate: WebImageCandidate) -> UIImage? {
        guard candidate.url.hasPrefix("data:") else { return nil }
        if let hit = inline[candidate.url] { return hit }
        guard let comma = candidate.url.firstIndex(of: ","),
              let data = Data(base64Encoded: String(candidate.url[candidate.url.index(after: comma)...])),
              let img = UIImage(data: data) else { return nil }
        inline[candidate.url] = img
        return img
    }

    /// The candidate's full picture: decoded from a `data:` URL, or downloaded from an allowed https host.
    static func image(for candidate: WebImageCandidate) async throws -> UIImage {
        if candidate.url.hasPrefix("data:") {
            guard let img = inlineImage(candidate) else { throw APIError.decoding }
            return img
        }
        guard let url = URL(string: candidate.url), url.scheme == "https",
              let host = url.host?.lowercased(), allowedHosts.contains(host) else { throw APIError.decoding }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: data) else { throw APIError.decoding }
        return img
    }
}
