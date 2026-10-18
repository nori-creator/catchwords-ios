#if DEBUG
import Foundation

/// The demo backend's in-memory tables (DEBUG only). One lock guards everything; the seed for the
/// learning language given with `-uiDemo` is written on first use. Nothing is kept across launches.
///
/// Tables use the column names the app reads: profiles, stickers, words, reviews, review_history,
/// encounters (photos of re-encounters),
/// dictionary_entries (empty). Dates are ISO 8601 strings in `SupabaseDate.string` form, so a plain
/// string comparison orders them.
nonisolated final class DemoDatabase: @unchecked Sendable {
    static let shared = DemoDatabase()
    static let userId = "00000000-0000-4000-8000-00000000d3e0"

    let lock = NSRecursiveLock()
    var tables: [String: [[String: Any]]] = [:]
    var seeded = false
    /// After deleteMyAccount: stay empty instead of seeding again.
    var accountDeleted = false
    var learning = "zh-TW"
    var pack: [String: Any] = [:]
    /// word id → explain_lang → { explain_lang, meaning, example_translation, extras, source }.
    var explanations: [String: [String: [String: Any]]] = [:]
    /// storage path → uploaded bytes and their content type.
    var uploads: [String: Data] = [:]
    var uploadTypes: [String: String] = [:]
    /// storage path → what its made-up picture shows (emoji, text, kind).
    var imageLabels: [String: [String: String]] = [:]
    var albumHidden: [String] = []
    var scanTapped: [String] = []
    var userMetadata: [String: Any] = [:]
    /// The account's AI consent record (web `ai_consents`): version, agreedAt, revokedAt. Empty: never agreed.
    var aiConsent: [String: Any] = [:]
    var email: String?
    var tokenCounter = 0

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        tables = [:]
        seeded = false
        accountDeleted = false
        pack = [:]
        explanations = [:]
        uploads = [:]
        uploadTypes = [:]
        imageLabels = [:]
        albumHidden = []
        scanTapped = []
        userMetadata = [:]
        aiConsent = [:]
        email = nil
        tokenCounter = 0
    }

    // MARK: - Row helpers (call with the lock held)

    func rows(_ table: String) -> [[String: Any]] {
        tables[table] ?? []
    }

    func insert(_ table: String, _ row: [String: Any]) {
        var list = tables[table] ?? []
        list.append(row)
        tables[table] = list
    }

    func first(_ table: String, id: String) -> [String: Any]? {
        rows(table).first { DJ.str($0["id"]) == id }
    }

    @discardableResult
    func update(_ table: String, where match: ([String: Any]) -> Bool, _ change: (inout [String: Any]) -> Void) -> [[String: Any]] {
        var list = tables[table] ?? []
        var changed: [[String: Any]] = []
        for i in list.indices where match(list[i]) {
            change(&list[i])
            changed.append(list[i])
        }
        tables[table] = list
        return changed
    }

    @discardableResult
    func remove(_ table: String, where match: ([String: Any]) -> Bool) -> [[String: Any]] {
        let list = tables[table] ?? []
        let gone = list.filter { match($0) }
        tables[table] = list.filter { !match($0) }
        return gone
    }

    /// Updates one sticker by id; false when there is none.
    @discardableResult
    func updateSticker(_ id: String, _ change: (inout [String: Any]) -> Void) -> Bool {
        let changed = update("stickers", where: { DJ.str($0["id"]) == id }, change)
        return !changed.isEmpty
    }

    // MARK: - Languages

    /// The language explanations are written in: the requested one (else the display language), never the
    /// learning language itself (the app keeps native != target; a misconfigured launch falls back).
    func reader(_ requested: String?) -> String {
        var r = (requested ?? "").trimmingCharacters(in: .whitespaces)
        if r.isEmpty { r = L10n.lang }
        if r.lowercased().hasPrefix("zh") { r = "zh-TW" }
        if !["ja", "en", "zh-TW"].contains(r) { r = "ja" }
        if r == learning { r = learning == "ja" ? "en" : "ja" }
        return r
    }

    /// `{ "ja": …, "en": …, "zh-TW": … }` → the reader's text ("" when missing).
    func text(_ map: Any?, _ reader: String) -> String {
        let d = DJ.dict(map)
        if let s = DJ.str(d[reader]) { return s }
        return ""
    }

    var fixtureWords: [[String: Any]] { DJ.list(pack["words"]) }
    var variants: [[String: Any]] { DJ.list(pack["variants"]) }

    func fixture(key: String) -> [String: Any]? {
        fixtureWords.first { DJ.str($0["key"]) == key }
    }

    func fixture(headword: String) -> [String: Any]? {
        let h = headword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return fixtureWords.first { (DJ.str($0["headword"]) ?? "").lowercased() == h }
    }

    func variant(headword: String) -> [String: Any]? {
        let h = headword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return variants.first { (DJ.str($0["headword"]) ?? "").lowercased() == h }
    }

    /// The fixture's explanation for a reader (meaning, example_translation, extras).
    func explain(_ fixture: [String: Any], _ reader: String) -> [String: Any] {
        let all = DJ.dict(fixture["explain"])
        if let e = all[reader] as? [String: Any] { return e }
        if let any = all.values.first as? [String: Any] { return any }
        return [:]
    }

    /// A `words` row for a fixture word, written for `reader`.
    func wordRow(_ fixture: [String: Any], id: String, reader: String) -> [String: Any] {
        let e = explain(fixture, reader)
        var row: [String: Any] = [:]
        row["id"] = id
        row["headword"] = DJ.str(fixture["headword"]) ?? ""
        row["reading_zhuyin"] = DJ.orNull(DJ.str(fixture["reading_zhuyin"]))
        row["pinyin"] = DJ.orNull(DJ.str(fixture["pinyin"]))
        row["meaning_ja"] = DJ.str(e["meaning"]) ?? ""
        row["part_of_speech"] = DJ.orNull(DJ.str(fixture["part_of_speech"]))
        row["category_key"] = DJ.orNull(DJ.str(fixture["category_key"]))
        row["example_sentence"] = DJ.orNull(DJ.str(fixture["example_sentence"]))
        row["example_translation"] = DJ.orNull(DJ.str(e["example_translation"]))
        row["extras"] = DJ.dict(e["extras"])
        row["language"] = DJ.str(fixture["language"]) ?? learning
        row["created_at"] = DJ.now()
        return row
    }

    /// Files every reader's explanation of a fixture under a word id (getWordExplanation / getReaderMeanings).
    func registerExplanations(_ fixture: [String: Any], wordId: String) {
        var byLang: [String: [String: Any]] = explanations[wordId] ?? [:]
        for (lang, value) in DJ.dict(fixture["explain"]) {
            let e = DJ.dict(value)
            var row: [String: Any] = [:]
            row["explain_lang"] = lang
            row["meaning"] = DJ.str(e["meaning"]) ?? ""
            row["example_translation"] = DJ.orNull(DJ.str(e["example_translation"]))
            row["extras"] = DJ.dict(e["extras"])
            row["source"] = "demo"
            byLang[lang] = row
        }
        explanations[wordId] = byLang
    }

    // MARK: - Seed

    /// Call with the lock held.
    func ensureSeeded() {
        if seeded { return }
        seeded = true
        learning = DemoBackend.learningLanguage ?? "zh-TW"
        pack = DemoFixtures.pack(for: learning)
        if accountDeleted { return }
        seed()
    }

    private func seed() {
        let r = reader(nil)
        let now = Date()
        let uid = Self.userId
        let defaults = UserDefaults.standard
        let common = DJ.dict(pack["common"])

        var onboarded = true
        if defaults.object(forKey: "uiDemoOnboarded") != nil { onboarded = defaults.bool(forKey: "uiDemoOnboarded") }
        let plan = defaults.string(forKey: "uiDemoPlan") ?? "free"
        insert("profiles", profileRow(onboarded: onboarded, plan: plan, displayName: text(common["display_name"], r),
                                      created: now.addingTimeInterval(-30 * 86_400)))
        if defaults.bool(forKey: "uiDemoEmpty") { return }

        // Words and stickers: 0-5 with photos on three days, 6 without a photo (stand-in picture only).
        let places = DJ.list(pack["places"])
        let dayOffsets: [Double] = [0, 0, 3, 3, 8, 8, 5]
        let words = Array(fixtureWords.prefix(7))
        var stickerIds: [String] = []
        for (i, w) in words.enumerated() {
            let key = DJ.str(w["key"]) ?? "w\(i)"
            let wordId = "demo-word-\(key)"
            insert("words", wordRow(w, id: wordId, reader: r))
            registerExplanations(w, wordId: wordId)

            let stickerId = "demo-sticker-\(key)"
            stickerIds.append(stickerId)
            let taken = now.addingTimeInterval(-dayOffsets[i] * 86_400 - Double(i + 1) * 1_500)
            let place: [String: Any] = places.isEmpty ? [:] : places[i % places.count]
            let emoji = DJ.str(w["emoji"]) ?? ""
            let head = DJ.str(w["headword"]) ?? ""
            var s: [String: Any] = [:]
            s["id"] = stickerId
            s["user_id"] = uid
            s["word_id"] = wordId
            s["caption"] = i == 0 ? (text(common["caption"], r) as Any) : (NSNull() as Any)
            s["location_name"] = text(place["name"], r)
            s["lat"] = (DJ.num(place["lat"]) ?? 0) + Double(i) * 0.0013
            s["lng"] = (DJ.num(place["lng"]) ?? 0) - Double(i) * 0.0011
            s["taken_at"] = DJ.iso(taken)
            s["created_at"] = DJ.iso(taken)
            s["shelf_key"] = NSNull()
            s["hero_role"] = NSNull()
            s["placeholder_credit"] = NSNull()
            s["placeholder_image_url"] = NSNull()
            s["selfie_image_url"] = NSNull()
            s["cutout_image_url"] = NSNull()
            s["object_image_url"] = NSNull()
            if i < 6 {
                let object = "\(uid)/demo-\(key)-object.jpg"
                s["object_image_url"] = object
                s["capture_type"] = "photo"
                imageLabels[object] = ["emoji": emoji, "text": head, "kind": "object"]
                if i % 2 == 0 {
                    let cutout = "\(uid)/demo-\(key)-cutout.png"
                    s["cutout_image_url"] = cutout
                    imageLabels[cutout] = ["emoji": emoji, "text": "", "kind": "cutout"]
                }
                if i == 1 {
                    let selfie = "\(uid)/demo-\(key)-selfie.jpg"
                    s["selfie_image_url"] = selfie
                    imageLabels[selfie] = ["emoji": "🤳", "text": head, "kind": "selfie"]
                }
            } else {
                let stand = "\(uid)/demo-\(key)-placeholder.jpg"
                s["placeholder_image_url"] = stand
                s["placeholder_credit"] = ["name": "Demo Photographer", "link": "https://unsplash.com", "source": "unsplash"] as [String: Any]
                s["capture_type"] = "text"
                imageLabels[stand] = ["emoji": emoji, "text": head, "kind": "placeholder"]
            }
            insert("stickers", s)
        }

        // Reviews: two due now, three later (sticker index, ease, interval, repetitions, last reviewed, due — in days).
        let plans: [(Int, Double, Int, Int, Double?, Double)] = [
            (4, 2.36, 1, 1, -2, -1),
            (5, 2.5, 3, 2, -4, -0.05),
            (2, 2.5, 2, 1, -1, 1),
            (3, 2.6, 3, 2, -1, 2),
            (0, 2.5, 0, 0, nil, 1),
        ]
        for p in plans where p.0 < stickerIds.count {
            let sid = stickerIds[p.0]
            var rv: [String: Any] = [:]
            rv["id"] = "demo-review-\(p.0)"
            rv["user_id"] = uid
            rv["sticker_id"] = sid
            rv["ease"] = p.1
            rv["interval_days"] = p.2
            rv["repetitions"] = p.3
            if let last = p.4 { rv["last_reviewed_at"] = DJ.iso(now.addingTimeInterval(last * 86_400)) } else { rv["last_reviewed_at"] = NSNull() }
            rv["due_at"] = DJ.iso(now.addingTimeInterval(p.5 * 86_400))
            rv["created_at"] = DJ.iso(now.addingTimeInterval(-9 * 86_400))
            insert("reviews", rv)
        }
        // History (sticker index, days ago, score, interval after, ease after).
        let history: [(Int, Double, Int, Int, Double)] = [
            (4, 7, 5, 1, 2.5), (4, 2, 3, 1, 2.36), (5, 7, 5, 1, 2.6), (5, 4, 5, 3, 2.5), (2, 1, 5, 2, 2.5), (3, 1, 4, 3, 2.6),
        ]
        for (n, h) in history.enumerated() where h.0 < stickerIds.count {
            var row: [String: Any] = [:]
            row["id"] = "demo-history-\(n)"
            row["user_id"] = uid
            row["sticker_id"] = stickerIds[h.0]
            row["review_id"] = "demo-review-\(h.0)"
            row["reviewed_at"] = DJ.iso(now.addingTimeInterval(-h.1 * 86_400))
            row["score"] = h.2
            row["interval_days_after"] = h.3
            row["ease_after"] = h.4
            insert("review_history", row)
        }

        // Two earlier encounters (extra photos) of sticker 4.
        if stickerIds.count > 4 && words.count > 4 {
            let w = words[4]
            let key = DJ.str(w["key"]) ?? "w4"
            for (n, daysAgo) in [5.0, 1.0].enumerated() {
                let path = "\(uid)/demo-\(key)-encounter-\(n + 1).jpg"
                imageLabels[path] = ["emoji": DJ.str(w["emoji"]) ?? "", "text": DJ.str(w["headword"]) ?? "", "kind": "encounter\(n + 1)"]
                let place: [String: Any] = places.isEmpty ? [:] : places[(n + 1) % places.count]
                var e: [String: Any] = [:]
                e["id"] = "demo-encounter-\(n + 1)"
                e["user_id"] = uid
                e["sticker_id"] = stickerIds[4]
                e["image_path"] = path
                e["cutout_path"] = NSNull()
                e["location_name"] = text(place["name"], r)
                e["lat"] = DJ.orNull(DJ.num(place["lat"]))
                e["lng"] = DJ.orNull(DJ.num(place["lng"]))
                e["encountered_at"] = DJ.iso(now.addingTimeInterval(-daysAgo * 86_400))
                e["created_at"] = e["encountered_at"]   // the real table's column (the app reads it)
                insert("encounters", e)
            }
        }

        // `-uiDemoMany N`: N more words (the fixture words again, each its own word and photo) — a dex the size of a
        // real learner's (DexOpenTests: the 図鑑 opened with many words).
        let many = defaults.integer(forKey: "uiDemoMany")
        let all = fixtureWords
        if many > 0, !all.isEmpty {
            for n in 0..<many {
                let w = all[n % all.count]
                let key = "many\(n)"
                let wordId = "demo-word-\(key)"
                insert("words", wordRow(w, id: wordId, reader: r))
                registerExplanations(w, wordId: wordId)
                let taken = now.addingTimeInterval(-Double(n + 10) * 3_600)
                let place: [String: Any] = places.isEmpty ? [:] : places[n % places.count]
                let object = "\(uid)/demo-\(key)-object.jpg"
                imageLabels[object] = ["emoji": DJ.str(w["emoji"]) ?? "", "text": DJ.str(w["headword"]) ?? "", "kind": "object"]
                var s: [String: Any] = [:]
                s["id"] = "demo-sticker-\(key)"
                s["user_id"] = uid
                s["word_id"] = wordId
                s["caption"] = NSNull()
                s["location_name"] = text(place["name"], r)
                s["lat"] = (DJ.num(place["lat"]) ?? 0) + Double(n) * 0.0007
                s["lng"] = (DJ.num(place["lng"]) ?? 0) - Double(n) * 0.0005
                s["taken_at"] = DJ.iso(taken)
                s["created_at"] = DJ.iso(taken)
                s["shelf_key"] = NSNull()
                s["hero_role"] = NSNull()
                s["placeholder_credit"] = NSNull()
                s["placeholder_image_url"] = NSNull()
                s["selfie_image_url"] = NSNull()
                s["object_image_url"] = object
                s["capture_type"] = "photo"
                if n % 2 == 0 {
                    let cutout = "\(uid)/demo-\(key)-cutout.png"
                    s["cutout_image_url"] = cutout
                    imageLabels[cutout] = ["emoji": DJ.str(w["emoji"]) ?? "", "text": "", "kind": "cutout"]
                } else {
                    s["cutout_image_url"] = NSNull()
                }
                insert("stickers", s)
            }
        }
    }

    func profileRow(onboarded: Bool, plan: String, displayName: String, created: Date) -> [String: Any] {
        let r = reader(nil)
        var p: [String: Any] = [:]
        p["id"] = Self.userId
        p["display_name"] = displayName
        p["avatar_url"] = NSNull()
        p["native_language"] = r
        p["ui_language"] = r
        p["target_language"] = learning
        let levels: [String: (String, String)] = ["en": ("A2", "B1"), "ja": ("JLPT-N4", "JLPT-N3")]
        let level = levels[learning] ?? ("TOCFL-2", "TOCFL-3")
        p["current_level"] = level.0
        p["level_goal"] = level.1
        p["review_daily_limit"] = 20
        p["onboarded"] = onboarded
        p["plan"] = plan
        p["created_at"] = DJ.iso(created)
        p["updated_at"] = DJ.iso(created)
        return p
    }


    /// A profile for an account made after the seed (or after deleteMyAccount).
    func ensureProfile() {
        if first("profiles", id: Self.userId) != nil { return }
        let common = DJ.dict(pack["common"])
        insert("profiles", profileRow(onboarded: false, plan: "free", displayName: text(common["display_name"], reader(nil)), created: Date()))
    }

    // MARK: - PostgREST subset (rest/v1/<table>?…)

    func rest(method: String, table: String, query: [URLQueryItem], body: Data, prefer: String) -> DemoResponse {
        lock.lock()
        defer { lock.unlock() }
        ensureSeeded()
        var select = "*"
        var order: String?
        var limit: Int?
        var offset = 0
        var onConflict: String?
        var filters: [(String, String)] = []
        for item in query {
            let value = item.value ?? ""
            switch item.name {
            case "select": select = value
            case "order": order = value
            case "limit": limit = Int(value)
            case "offset": offset = Int(value) ?? 0
            case "on_conflict": onConflict = value
            case "columns": break
            default: filters.append((item.name, value))
            }
        }
        let representation = prefer.contains("return=representation")
        switch method {
        case "GET", "HEAD":
            var list = rows(table).filter { DemoQuery.matches($0, filters) }
            list = DemoQuery.sorted(list, order: order)
            if offset > 0 { list = Array(list.dropFirst(offset)) }
            if let limit { list = Array(list.prefix(max(0, limit))) }
            return .json(list.map { present($0, table: table, select: select) })
        case "POST":
            let parsed = DJ.parse(body)
            var items: [[String: Any]] = []
            if let one = parsed as? [String: Any] { items = [one] } else if let many = parsed as? [[String: Any]] { items = many }
            let merge = onConflict != nil || prefer.contains("merge-duplicates")
            let conflictColumns: [String] = (onConflict ?? "id").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            var written: [[String: Any]] = []
            for item in items {
                if merge, let index = conflictIndex(table, item, columns: conflictColumns) {
                    var list = tables[table] ?? []
                    var row = list[index]
                    for (k, v) in item { row[k] = v }
                    row["updated_at"] = DJ.now()
                    list[index] = row
                    tables[table] = list
                    written.append(row)
                } else {
                    let row = withDefaults(table, item)
                    insert(table, row)
                    written.append(row)
                }
            }
            if representation { return .json(written.map { present($0, table: table, select: select) }, status: 201) }
            return .empty(201)
        case "PATCH":
            let patch = DJ.dict(DJ.parse(body))
            let changed = update(table, where: { DemoQuery.matches($0, filters) }) { row in
                for (k, v) in patch { row[k] = v }
            }
            if representation { return .json(changed.map { present($0, table: table, select: select) }) }
            return .empty(204)
        case "DELETE":
            let gone = remove(table) { DemoQuery.matches($0, filters) }
            cascade(table, ids: gone.compactMap { DJ.str($0["id"]) })
            if representation { return .json(gone) }
            return .empty(204)
        default:
            return .error(405, "Method not allowed")
        }
    }

    private func conflictIndex(_ table: String, _ item: [String: Any], columns: [String]) -> Int? {
        let list = tables[table] ?? []
        if columns.contains(where: { DJ.isNull(item[$0]) && $0 != "user_id" }) { return nil }
        return list.firstIndex { row in
            columns.allSatisfy { col in
                var mine: Any? = item[col]
                if col == "user_id" && DJ.isNull(mine) { mine = Self.userId }
                return DemoQuery.same(row[col], mine)
            }
        }
    }

    /// What PostgREST would fill in on insert.
    private func withDefaults(_ table: String, _ item: [String: Any]) -> [String: Any] {
        var row = item
        let now = DJ.now()
        if DJ.isNull(row["id"]) { row["id"] = DJ.uuid() }
        if DJ.isNull(row["created_at"]) { row["created_at"] = now }
        if !["words", "dictionary_entries", "profiles"].contains(table), DJ.isNull(row["user_id"]) { row["user_id"] = Self.userId }
        switch table {
        case "reviews":
            if row["ease"] == nil { row["ease"] = 2.5 }
            if row["interval_days"] == nil { row["interval_days"] = 0 }
            if row["repetitions"] == nil { row["repetitions"] = 0 }
            if row["due_at"] == nil { row["due_at"] = now }
            if row["last_reviewed_at"] == nil { row["last_reviewed_at"] = NSNull() }
        case "stickers":
            if row["taken_at"] == nil { row["taken_at"] = now }
        default:
            break
        }
        return row
    }

    /// Children go with their parent (stickers → reviews, history, encounters).
    func cascade(_ table: String, ids: [String]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        switch table {
        case "stickers":
            for child in ["reviews", "review_history", "encounters"] {
                remove(child) { idSet.contains(DJ.str($0["sticker_id"]) ?? "") }
            }
            albumHidden.removeAll { idSet.contains($0) }
        default:
            break
        }
    }

    /// Every column (the select list only decides the embedded word).
    func present(_ row: [String: Any], table: String, select: String) -> [String: Any] {
        guard table == "stickers", select.contains("word:words(") else { return row }
        var out = row
        if let wid = DJ.str(row["word_id"]), let word = first("words", id: wid) {
            out["word"] = word
        } else {
            out["word"] = NSNull()
        }
        return out
    }

    // MARK: - Auth (auth/v1/…)

    func auth(method: String, path: String, query: [URLQueryItem], body: Data) -> DemoResponse {
        lock.lock()
        defer { lock.unlock() }
        ensureSeeded()
        let json = DJ.dict(DJ.parse(body))
        switch path {
        case "signup":
            let mail = (DJ.str(json["email"]) ?? "").trimmingCharacters(in: .whitespaces)
            if mail.isEmpty {
                accountDeleted = false
                ensureProfile()
                return .json(session(email: nil))
            }
            let password = DJ.str(json["password"]) ?? ""
            if mail.lowercased().hasPrefix("registered@") {
                return .json(["msg": "User already registered", "error_code": "user_already_exists"], status: 422)
            }
            if password.count < 6 {
                return .json(["msg": "Password should be at least 6 characters.", "error_code": "weak_password"], status: 422)
            }
            if mail.lowercased().hasPrefix("confirm@") {
                // Email confirmation on: a user without a session.
                return .json(userJSON(email: mail))
            }
            accountDeleted = false
            ensureProfile()
            return .json(session(email: mail))
        case "token":
            let grant = query.first { $0.name == "grant_type" }?.value ?? ""
            switch grant {
            case "password":
                if (DJ.str(json["password"]) ?? "") == "wrong" {
                    return .json(["error": "invalid_grant", "error_description": "Invalid login credentials"], status: 400)
                }
                ensureProfile()
                return .json(session(email: DJ.str(json["email"])))
            case "refresh_token":
                return .json(session(email: email))
            case "id_token":
                ensureProfile()
                return .json(session(email: "apple-demo@privaterelay.appleid.com"))
            default:
                return .json(["error": "unsupported_grant_type", "error_description": "Unsupported grant type"], status: 400)
            }
        case "recover", "otp", "resend":
            return .json([String: Any]())
        case "logout":
            return .empty(204)
        case "user":
            if method == "PUT" {
                for (k, v) in DJ.dict(json["data"]) { userMetadata[k] = v }
                if let mail = DJ.str(json["email"]) { email = mail }
            }
            return .json(userJSON(email: email))
        default:
            return .notFound()
        }
    }

    private func userJSON(email mail: String?) -> [String: Any] {
        [
            "id": Self.userId,
            "aud": "authenticated",
            "role": "authenticated",
            "email": DJ.orNull(mail),
            "user_metadata": userMetadata,
            "app_metadata": ["provider": mail == nil ? "anonymous" : "email"] as [String: Any],
            "created_at": DJ.now(),
        ]
    }

    /// The session JSON SupabaseClient.storeSession reads.
    private func session(email mail: String?) -> [String: Any] {
        tokenCounter += 1
        if let mail { email = mail }
        let expires = Int(Date().timeIntervalSince1970) + 3_600
        return [
            "access_token": "demo-access-\(tokenCounter)",
            "refresh_token": "demo-refresh-\(tokenCounter)",
            "token_type": "bearer",
            "expires_in": 3_600,
            "expires_at": expires,
            "user": userJSON(email: email),
        ]
    }

    // MARK: - Storage (storage/v1/…)

    func storage(method: String, path: String, body: Data) -> DemoResponse {
        // Find what to answer with under the lock; draw pictures outside it.
        var uploaded: Data?
        var uploadedType = "image/jpeg"
        var label: [String: String] = [:]
        var objectPath = ""
        lock.lock()
        ensureSeeded()
        if path == "object/sign/stickers" || path == "object/sign/stickers/" {
            let json = DJ.dict(DJ.parse(body))
            var out: [[String: Any]] = []
            for p in DJ.strings(json["paths"]) {
                out.append(["path": p, "signedURL": Self.signedPath(p), "error": NSNull()])
            }
            lock.unlock()
            return .json(out)
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        // object/sign/<bucket>/<path> · object/public/<bucket>/<path> · object/authenticated/<bucket>/<path> · object/<bucket>/<path>
        guard parts.count >= 3, parts[0] == "object" else {
            lock.unlock()
            return .notFound()
        }
        var segs = Array(parts.dropFirst())
        if ["sign", "public", "authenticated"].contains(segs[0]) { segs = Array(segs.dropFirst()) }
        guard segs.count >= 2 else {
            lock.unlock()
            return .json([[String: Any]]())
        }
        let bucket = segs[0]
        objectPath = segs.dropFirst().joined(separator: "/")
        if method == "POST" || method == "PUT" {
            uploads[objectPath] = body
            uploads[objectPath + ".thumb.webp"] = nil
            var kind = "image/jpeg"
            if body.count >= 4, body.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) { kind = "image/png" }
            if objectPath.hasSuffix(".m4a") || objectPath.hasSuffix(".mp4") { kind = "audio/mp4" }
            uploadTypes[objectPath] = kind
            lock.unlock()
            return .json(["Key": "\(bucket)/\(objectPath)", "Id": DJ.uuid()])
        }
        if method == "DELETE" {
            uploads[objectPath] = nil
            lock.unlock()
            return .json([[String: Any]]())
        }
        var base = objectPath
        if base.hasSuffix(".thumb.webp") { base = String(base.dropLast(".thumb.webp".count)) }
        uploaded = uploads[base]
        uploadedType = uploadTypes[base] ?? "image/jpeg"
        label = imageLabels[base] ?? [:]
        lock.unlock()

        if let uploaded { return .image(uploaded, contentType: uploadedType) }
        if base.hasSuffix(".m4a") || base.hasSuffix(".mp4") || base.hasSuffix(".mov") { return .notFound() }
        let png = DemoImages.png(seed: base, emoji: label["emoji"] ?? "📷", text: label["text"] ?? "",
                                 transparent: label["kind"] == "cutout")
        return .image(png)
    }

    /// `signedURL` as Supabase returns it (relative to /storage/v1).
    static func signedPath(_ path: String) -> String {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return "/object/sign/stickers/\(encoded)?token=demo"
    }

    /// The full signed URL of a storage path (for function results that carry a URL).
    static func signedURL(_ path: String) -> String {
        AppConfig.supabaseURL + "/storage/v1" + signedPath(path)
    }

    /// A picture for a web image URL (search candidates, Unsplash, Wikimedia…): `/demo/<word key>/<n>.jpg`
    /// shows that word's emoji.
    func webImage(url: URL) -> Data {
        var emoji = "🖼️"
        let comps = url.path.split(separator: "/").map(String.init)
        if comps.count >= 2, comps[0] == "demo" {
            lock.lock()
            ensureSeeded()
            if let f = fixture(key: comps[1]), let e = DJ.str(f["emoji"]) { emoji = e }
            lock.unlock()
        }
        return DemoImages.png(seed: url.absoluteString, emoji: emoji, text: "", transparent: false)
    }
}

/// PostgREST filters and ordering over `[String: Any]` rows.
nonisolated enum DemoQuery {
    static func matches(_ row: [String: Any], _ filters: [(String, String)]) -> Bool {
        for (column, expression) in filters where !passes(row, column, expression) {
            return false
        }
        return true
    }

    /// `eq.` `neq.` `in.(a,b)` `lt.` `lte.` `gt.` `gte.` `is.null` `like.` `ilike.`, optionally after `not.`.
    static func passes(_ row: [String: Any], _ column: String, _ expression: String) -> Bool {
        if column == "or" || column == "and" { return true }
        var expr = expression
        var negate = false
        if expr.hasPrefix("not.") {
            negate = true
            expr = String(expr.dropFirst(4))
        }
        guard let dot = expr.firstIndex(of: ".") else { return true }
        let op = String(expr[..<dot])
        let value = String(expr[expr.index(after: dot)...])
        let cell = row[column]
        var result = true
        switch op {
        case "eq": result = equal(cell, value)
        case "neq": result = !equal(cell, value)
        case "in": result = list(value).contains { equal(cell, $0) }
        case "is":
            if value == "null" { result = DJ.isNull(cell) } else { result = equal(cell, value) }
        case "lt": result = compare(cell, value).map { $0 < 0 } ?? false
        case "lte": result = compare(cell, value).map { $0 <= 0 } ?? false
        case "gt": result = compare(cell, value).map { $0 > 0 } ?? false
        case "gte": result = compare(cell, value).map { $0 >= 0 } ?? false
        case "like", "ilike":
            let needle = value.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "*", with: "").lowercased()
            result = needle.isEmpty || (DJ.str(cell) ?? "").lowercased().contains(needle)
        default: result = true
        }
        return negate ? !result : result
    }

    /// `(a,"b c",d)` → ["a", "b c", "d"].
    static func list(_ raw: String) -> [String] {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("(") { s.removeFirst() }
        if s.hasSuffix(")") { s.removeLast() }
        return s.split(separator: ",").map { item in
            var t = String(item).trimmingCharacters(in: .whitespaces)
            if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") {
                t.removeFirst()
                t.removeLast()
            }
            return t
        }
    }

    static func isBool(_ n: NSNumber) -> Bool {
        CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    static func equal(_ cell: Any?, _ value: String) -> Bool {
        if DJ.isNull(cell) { return value == "null" }
        if let s = cell as? String { return s == value }
        if let n = cell as? NSNumber {
            if isBool(n) { return (n.boolValue ? "true" : "false") == value }
            if let d = Double(value) { return n.doubleValue == d }
        }
        return false
    }

    /// cell compared with a filter value: <0, 0, >0; nil when they cannot be compared.
    static func compare(_ cell: Any?, _ value: String) -> Int? {
        if DJ.isNull(cell) { return nil }
        if let s = cell as? String { return s < value ? -1 : (s > value ? 1 : 0) }
        if let n = cell as? NSNumber, let d = Double(value) {
            return n.doubleValue < d ? -1 : (n.doubleValue > d ? 1 : 0)
        }
        return nil
    }

    /// Two cells hold the same value (upsert conflicts).
    static func same(_ a: Any?, _ b: Any?) -> Bool {
        if DJ.isNull(a) || DJ.isNull(b) { return false }
        if let x = a as? String, let y = b as? String { return x == y }
        if let x = DJ.num(a), let y = DJ.num(b) { return x == y }
        return false
    }

    /// Two cells for sorting; nulls last.
    static func orderCompare(_ a: Any?, _ b: Any?) -> Int {
        let an = DJ.isNull(a)
        let bn = DJ.isNull(b)
        if an && bn { return 0 }
        if an { return 1 }
        if bn { return -1 }
        if let x = a as? String, let y = b as? String { return x < y ? -1 : (x > y ? 1 : 0) }
        if let x = DJ.num(a), let y = DJ.num(b) { return x < y ? -1 : (x > y ? 1 : 0) }
        return 0
    }

    /// `order=col.desc,other.asc` (stable).
    static func sorted(_ rows: [[String: Any]], order: String?) -> [[String: Any]] {
        guard let order, !order.isEmpty else { return rows }
        var keys: [(String, Bool)] = []
        for spec in order.split(separator: ",") {
            let bits = spec.split(separator: ".").map(String.init)
            guard let column = bits.first, !column.isEmpty else { continue }
            keys.append((column, bits.contains("desc")))
        }
        let indexed: [(Int, [String: Any])] = Array(rows.enumerated()).map { ($0.offset, $0.element) }
        let result = indexed.sorted { lhs, rhs in
            for (column, descending) in keys {
                var c = orderCompare(lhs.1[column], rhs.1[column])
                // Nulls stay last either way.
                if descending && !DJ.isNull(lhs.1[column]) && !DJ.isNull(rhs.1[column]) { c = -c }
                if c != 0 { return c < 0 }
            }
            return lhs.0 < rhs.0
        }
        return result.map { $0.1 }
    }
}
#endif
