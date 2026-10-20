import SwiftUI

/// The shared `profiles` row (same columns the web settings screen edits).
@Observable
final class ProfileStore {
    var displayName: String = ""
    var avatarURL: String?
    var nativeLanguage: String = "ja"
    var targetLanguage: String = "zh-TW" {
        didSet { NativeAPI.targetLanguage = ["en", "ja"].contains(targetLanguage) ? targetLanguage : "zh-TW" }
    }
    var currentLevel: String = "TOCFL-1"
    var levelGoal: String = "TOCFL-2"
    /// 0 = 無制限 (review-batch.ts).
    var reviewDailyLimit: Int = 20
    /// 無制限 = every due card (1000 is the most one REST read returns).
    var effectiveReviewLimit: Int { reviewDailyLimit == 0 ? 1000 : reviewDailyLimit }
    var isSavingAvatar: Bool = false
    /// `profiles.onboarded` — true once the first-run setup has been finished (on any device).
    var onboarded: Bool = false
    /// When the account was made (`profiles.created_at`) — day 1 for the milestone albums.
    var createdAt: Date?
    var isLoaded: Bool = false
    /// The profile could not be read (offline / server down): nothing is known about onboarding, so
    /// the welcome screens are not shown again; `load()` runs again when the app becomes active.
    var loadFailed: Bool = false
    var message: String?

    private let client = SupabaseClient.shared

    static let levelOptions: [(value: String, label: String)] = (1...6).map { ("TOCFL-\($0)", "TOCFL Level \($0)") }
    static let cefrOptions: [(value: String, label: String)] = ["A1", "A2", "B1", "B2", "C1", "C2"].map { ($0, "CEFR \($0)") }
    // Language names in their own language (an autonym never changes with the display language): every display
    // language in languages.json, in its order.
    static let nativeOptions: [(value: String, label: String)] = DisplayLanguages.all.map { ($0.code, $0.autonym) }
    /// Every learning language the app can teach. Only 繁體字（台灣） is offered for now (owner 2026-10-11: 「学習言語は
    /// とりあえず英語はコードを隠して、繁體字(台灣)に絞って。名前も変更して」): English and Japanese stay in the code,
    /// hidden (`offeredTargets`). The name is the web's (`settings.langZhTw`).
    static var allTargetOptions: [(value: String, label: String)] {
        [("zh-TW", L("繁體字（台灣）")), ("en", "English"), ("ja", "日本語")]  // l10n-ignore (autonyms)
    }
    /// The learning languages offered on screen (onboarding, 設定).
    static let offeredTargets: Set<String> = ["zh-TW"]
    static var targetOptions: [(value: String, label: String)] {
        allTargetOptions.filter { offeredTargets.contains($0.value) }
    }
    /// The choices for someone learning `current`: the offered ones, plus `current` itself when it is a hidden one
    /// (an account that already learns English keeps seeing — and can keep — its own language). The display language
    /// may be one of them (owner 2026-10-20: 繁體字（台灣） as the display language while learning it), so the 設定 row
    /// and its wheel agree on the count.
    static func targetChoices(current: String) -> [(value: String, label: String)] {
        allTargetOptions.filter { offeredTargets.contains($0.value) || $0.value == current }
    }
    /// The learning language's name as the 設定 row shows it.
    static func targetLabel(_ code: String) -> String {
        allTargetOptions.first { $0.value == code }?.label ?? L("繁體字（台灣）")
    }
    /// level-scale.ts JLPT_SCALE: six steps like TOCFL and CEFR; step 6 is "beyond N1".
    static let jlptOptions: [(value: String, label: String)] = ["N5", "N4", "N3", "N2", "N1", "N1+"].map { ("JLPT-\($0)", "JLPT \($0)") }

    /// TOCFL for 台湾華語, CEFR for English, JLPT for Japanese (level-scale.ts).
    static func levels(for target: String) -> [(value: String, label: String)] {
        switch target {
        case "en": cefrOptions
        case "ja": jlptOptions
        default: levelOptions
        }
    }

    /// Re-maps a stored level onto the other scale by step (TOCFL-4 ⇄ B2 ⇄ JLPT-N2).
    static func remap(_ value: String, to target: String) -> String {
        let all = levels(for: target)
        if all.contains(where: { $0.value == value }) { return value }
        let step = [levelOptions, cefrOptions, jlptOptions].lazy.compactMap { list in list.firstIndex { $0.value == value } }.first ?? 0
        return all[min(step, all.count - 1)].value
    }

    func load() async {
        guard let uid = client.userId else { isLoaded = true; return }
        let row = await client.myProfileRow(uid: uid)
        // Signed out (or into another account), or cancelled, while reading: this answer is not for the
        // account on screen now — touch nothing (isLoaded / loadFailed included); its own load fills them.
        guard !Task.isCancelled, client.userId == uid else { return }
        defer { isLoaded = true }
        guard let row else {
            loadFailed = true
            return
        }
        loadFailed = false
        displayName = row["display_name"] as? String ?? ""
        avatarURL = row["avatar_url"] as? String
        onboarded = row["onboarded"] as? Bool ?? false
        if let s = row["created_at"] as? String { createdAt = SupabaseDate.parse(s) }
        // The private settings come only with the full row (`get_my_profile`); the public columns alone must not
        // reset them to defaults.
        guard row.keys.contains("target_language") else { return }
        nativeLanguage = row["native_language"] as? String ?? "ja"
        ReaderLanguage.native = (row["native_language"] as? String).map { L10n.normalize($0) }
        // The display language follows the account (set on the web or another device too).
        if let ui = row["ui_language"] as? String, !ui.isEmpty {
            L10n.set(ui)
            nativeLanguage = L10n.lang
        }
        targetLanguage = row["target_language"] as? String ?? "zh-TW"
        if let v = row["current_level"] as? String, !v.isEmpty { currentLevel = v }
        if let v = row["level_goal"] as? String, !v.isEmpty { levelGoal = v }
        if let v = row["review_daily_limit"] as? Int, v >= 0 { reviewDailyLimit = v }
    }

    /// Signing out: the next account starts from a blank profile (its own is read on sign-in). The
    /// learning language is kept: it is only this device's first guess until the profile arrives.
    func reset() {
        displayName = ""
        avatarURL = nil
        currentLevel = "TOCFL-1"
        levelGoal = "TOCFL-2"
        reviewDailyLimit = 20
        onboarded = false
        createdAt = nil
        isLoaded = false
        loadFailed = false
        isSavingAvatar = false
        message = nil
    }

    /// Saves profile columns. True when the server kept them (設定 then says 「保存しました」).
    @discardableResult
    func update(_ fields: [String: Any]) async -> Bool {
        guard let uid = client.userId else { return false }
        var body = fields
        body["updated_at"] = SupabaseDate.string(Date())
        do {
            _ = try await client.rest("PATCH", "profiles?id=eq.\(uid)", body: body)
            message = nil
            return true
        } catch {
            message = L("保存できませんでした。通信を確かめてください。")
            return false
        }
    }

    func uploadAvatar(_ image: UIImage) async {
        guard let uid = client.userId,
              let jpeg = ImageTools.jpegForUpload(ImageTools.resized(image, maxSide: 512), quality: 0.85) else { return }
        isSavingAvatar = true
        defer { isSavingAvatar = false }
        let path = "\(uid)/avatar-\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        do {
            try await client.upload(jpeg, path: path, bucket: "avatars")
            guard let url = client.publicURL(bucket: "avatars", path: path) else { return }
            let previous = avatarURL
            // Shown only once the profile points at it: a photo the profile does not keep would be gone on the
            // next launch.
            guard await update(["avatar_url": url]) else { return }
            avatarURL = url
            // The photo it replaced leaves the public bucket too (once the profile points at the new one).
            await removeAvatarFile(previous)
        } catch {
            message = L("写真を保存できませんでした。")
        }
    }

    /// 退会: removes the user's photos and every personal row RLS lets the owner delete
    /// (stickers cascade encounters / reviews / review_history). Shared `words` stay.
    /// Deletes the whole account through the web's `deleteMyAccount`: photos, every row
    /// (children first), and the **login itself** (`auth.admin.deleteUser`, service role).
    /// Deleting only the rows left a live login behind (App Store Review Guideline 5.1.1(v)).
    /// The user has typed 「削除」 on the settings screen; that is the confirmation the server requires.
    /// The server's answer alone is not taken as proof: Supabase Auth is then asked directly whether the
    /// login still exists (`verifyLoginDeleted`). If Auth still knows this user, the deletion is reported as
    /// failed and the user stays signed in to retry (the server's steps are safe to run again).
    func deleteAccount() async throws {
        _ = try await NativeAPI.call("deleteMyAccount", ["confirm": "削除"], timeout: 60)  // l10n-ignore (server keyword)
        if await client.verifyLoginDeleted() == false {
            throw APIError.message(L("アカウントのログイン情報を削除できませんでした。もう一度お試しください。"))
        }
    }

    /// 「外す」: the profile goes back to the default mark, and the photo is deleted from the public
    /// `avatars` bucket (R6-08) — it could otherwise still be opened by anyone with its URL. The field is
    /// cleared first; a deletion that fails leaves only the file. When the field could not be saved the
    /// file stays, since the profile still points at it.
    func clearAvatar() async {
        let previous = avatarURL
        await update(["avatar_url": NSNull()])
        let saved = message == nil
        avatarURL = nil
        if saved { await removeAvatarFile(previous) }
    }

    /// Best effort: deletes a photo this account put in `avatars` (`<uid>/avatar-….jpg`, from its public URL).
    private func removeAvatarFile(_ url: String?) async {
        guard let path = ownAvatarPath(url) else { return }
        try? await client.removeObject(path: path, bucket: "avatars")
    }

    /// The storage path inside `avatars` of a public URL in this account's own folder; nil for anything else
    /// (a URL from elsewhere, another folder), which is never touched.
    private func ownAvatarPath(_ url: String?) -> String? {
        guard let url, let uid = client.userId, let path = URL(string: url)?.path else { return nil }
        guard let r = path.range(of: "/storage/v1/object/public/avatars/") else { return nil }
        let object = String(path[r.upperBound...])
        guard object.hasPrefix(uid + "/"), object.count > uid.count + 1, !object.contains("..") else { return nil }
        return object
    }
}

/// Round profile photo (falls back to a person glyph).
struct AvatarView: View {
    let url: String?
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(Theme.secondary)
            .frame(width: size, height: size)
            .overlay {
                if let url, let u = URL(string: url) {
                    AsyncImage(url: u) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    .allowsHitTesting(false)
                } else {
                    Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundStyle(Theme.muted)
                }
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

extension SupabaseClient {
    /// This account's own `profiles` row, or nil when it could not be read.
    ///
    /// Read through `get_my_profile()` (SECURITY DEFINER, only `auth.uid()`'s row), as the web's `getMyProfile` does:
    /// the private columns (languages, levels, review settings, plan) are not granted to signed-in users, so a plain
    /// select that names any of them fails as a whole (403 "permission denied for table profiles"). That failure
    /// used to leave the name and the photo blank on every launch even though they were saved (owner 2026-10-11:
    /// 「プロフィールの名前と画像が保存されない…アプリを閉じると白紙になる」). Without the function, only the columns
    /// every account may read come back (no language keys).
    func myProfileRow(uid: String) async -> [String: Any]? {
        if let data = try? await rest("POST", "rpc/get_my_profile", body: [String: Any]()),
           let row = Self.firstObject(data), row["id"] is String {
            return row
        }
        guard !Task.isCancelled, userId == uid,
              let data = try? await rest("GET", "profiles?id=eq.\(uid)&select=display_name,avatar_url,onboarded,created_at")
        else { return nil }
        return Self.firstObject(data)
    }

    /// A function returning one row answers with an object; a table read with an array.
    nonisolated static func firstObject(_ data: Data) -> [String: Any]? {
        let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if let row = json as? [String: Any] { return row }
        return (json as? [[String: Any]])?.first
    }
}
