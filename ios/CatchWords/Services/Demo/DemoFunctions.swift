#if DEBUG
import Foundation

/// The web's `/api/native-fn` functions, answered from the demo tables. Each answer is `{"result": …}`
/// in the shape the app decodes. Mutations change the tables so the screens show them.
nonisolated extension DemoDatabase {
    func callFunction(_ fn: String, _ data: [String: Any]) -> DemoResponse {
        lock.lock()
        defer { lock.unlock() }
        ensureSeeded()
        if let status = Self.failureStatus(in: data) {
            return status == 429 ? .error(429, "") : .error(500, "demo failure")
        }
        let r = reader(DJ.str(data["explain_lang"]))
        let result: Any
        switch fn {
        // AI: candidates, cards, scans
        case "suggestWords": result = ["suggestions": suggestions(r)]
        case "suggestWordCandidates": result = ["candidates": wordCandidates(query: DJ.str(data["query"]) ?? "", reader: r)]
        case "detectScan": result = ["items": scanItems(r)]
        case "generateCard": result = generateCard(headword: DJ.str(data["headword"]) ?? "", hint: DJ.str(data["hintCategory"]), reader: r)
        case "rankScanCandidates": result = rankScan(DJ.list(data["items"]))
        case "markScanTap":
            if let h = DJ.str(data["headword"]), !scanTapped.contains(h) { scanTapped.append(h) }
            result = ["ok": true]
        case "markScanCaught": result = ["ok": true]
        case "getScanContext": result = scanContext()
        case "searchImageCandidates": result = ["candidates": imageCandidates(query: DJ.str(data["query"]) ?? "")]
        case "regenerateCardSection": result = ["ok": false, "filled": false]
        // The web's dictionary is not in the demo: only the 版25 preview's sentences are read (`Word25Preview`), the
        // others stay as they are.
        case "readSentences": result = ["readings": Word25Preview.demoReadings(DJ.strings(data["sentences"]))]
        case "reportAndFixSection":
            let item = DJ.str(data["item"]) ?? "auto"
            if item == "auto" {
                result = ["fixed": false, "by": "none", "item": NSNull()] as [String: Any]
            } else {
                result = ["fixed": true, "by": "ai", "item": item] as [String: Any]
            }
        case "synthesizeSpeech":
            // Locked: the app speaks with the device voice instead.
            result = ["locked": true, "audio_url": NSNull()] as [String: Any]

        // Words and explanations
        case "saveSticker": return saveSticker(data, reader: r)
        case "checkOwnedWord": result = ["owned": ownedWord(headword: DJ.str(data["headword"]) ?? "", reader: r)]
        case "getReaderMeanings": result = readerMeanings(DJ.strings(data["word_ids"]), reader: r)
        case "getWordExplanation": result = wordExplanation(data)
        case "updateWordExtras": result = updateWordExtras(data)
        case "setStickerHeadword": return setHeadword(data, reader: r)

        // Stickers
        case "recordEncounter": result = recordEncounter(data)
        case "replaceStickerPhoto":
            let sid = DJ.str(data["sticker_id"]) ?? ""
            let path = DJ.orNull(DJ.str(data["object_path"]))
            guard updateSticker(sid, { s in s["object_image_url"] = path; s["cutout_image_url"] = NSNull() }) else { return notFound() }
            result = ["ok": true]
        case "setStickerPlaceholder":
            let sid = DJ.str(data["sticker_id"]) ?? ""
            let path = DJ.orNull(DJ.str(data["placeholder_path"]))
            let credit = DJ.orNull(data["placeholder_credit"])
            guard updateSticker(sid, { s in s["placeholder_image_url"] = path; s["placeholder_credit"] = credit }) else { return notFound() }
            result = ["ok": true]
        case "attachStickerCutout":
            let sid = DJ.str(data["sticker_id"]) ?? ""
            let path = DJ.orNull(DJ.str(data["cutout_path"]))
            guard updateSticker(sid, { s in s["cutout_image_url"] = path }) else { return notFound() }
            result = ["ok": true, "saved": true]
        case "attachStickerSelfie":
            let sid = DJ.str(data["sticker_id"]) ?? ""
            let path = DJ.orNull(DJ.str(data["selfie_path"]))
            guard updateSticker(sid, { s in s["selfie_image_url"] = path }) else { return notFound() }
            result = ["saved": true]
        case "updateStickerCaption":
            let sid = DJ.str(data["sticker_id"]) ?? ""
            let caption = (DJ.str(data["caption"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let value: Any = caption.isEmpty ? (NSNull() as Any) : (String(caption.prefix(500)) as Any)
            guard updateSticker(sid, { s in s["caption"] = value }) else { return notFound() }
            result = ["ok": true]
        case "setStickerHeroRole":
            let sid = DJ.str(data["sticker_id"]) ?? ""
            let role = DJ.orNull(DJ.str(data["hero_role"]))
            guard updateSticker(sid, { s in s["hero_role"] = role }) else { return notFound() }
            result = ["saved": true]
        case "deleteSticker":
            let sid = DJ.str(data["sticker_id"]) ?? ""
            let gone = remove("stickers") { DJ.str($0["id"]) == sid }
            cascade("stickers", ids: gone.compactMap { DJ.str($0["id"]) })
            result = ["ok": true]
        case "listStickerPhotos": result = ["photos": stickerPhotos(DJ.str(data["sticker_id"]) ?? "")]
        case "listAlbumHidden": result = ["ids": albumHidden]
        case "setAlbumHidden":
            let sid = DJ.str(data["sticker_id"]) ?? ""
            let hidden = DJ.bool(data["hidden"]) ?? false
            albumHidden.removeAll { $0 == sid }
            if hidden { albumHidden.append(sid) }
            result = ["saved": true]
        case "saveAlbumLayout": result = saveAlbumLayout(DJ.list(data["items"]))

        // Review, stats, account
        case "gradeReview": return gradeReview(data)
        case "getMyStats": result = myStats()
        case "recordAiConsent": return recordAiConsent(data)
        case "getAiConsent": result = aiConsentResult(recorded: true)
        case "deleteMyAccount":
            aiConsent = [:]
            tables = [:]
            explanations = [:]
            albumHidden = []
            scanTapped = []
            userMetadata = [:]
            accountDeleted = true
            result = ["ok": true]
        default:
            result = NSNull()
        }
        return .json(["result": result])
    }

    private func notFound() -> DemoResponse {
        .error(404, "not found")
    }

    // MARK: - AI consent (web patch docs/web-changes/, docs/ios-spec/23-ai-consent.md)

    /// The server's current consent version (web `AI_CONSENT_VERSION`).
    private static let aiConsentVersion = 1

    /// `recordAiConsent` {version, agreed}: the same answers and refusals as the web server.
    private func recordAiConsent(_ data: [String: Any]) -> DemoResponse {
        guard let version = DJ.int(data["version"]), (1...1000).contains(version),
              let agreed = data["agreed"] as? Bool else {
            return .error(400, "送った内容の形が違います。アプリを最新にしてください。")  // l10n-ignore (server text)
        }
        let now = DJ.now()
        if agreed {
            guard version >= Self.aiConsentVersion else {
                return .error(403, "AI_CONSENT_REQUIRED: 同意の内容が新しくなりました。")  // l10n-ignore (server text)
            }
            aiConsent = ["version": version, "agreedAt": now, "revokedAt": NSNull()]
        } else if !aiConsent.isEmpty {
            // Withdrawn: the agreement stays on record with the time it was withdrawn.
            aiConsent["revokedAt"] = now
        }
        // Never agreed and declining: nothing is written.
        return .json(["result": aiConsentResult(recorded: nil)])
    }

    /// `getAiConsent` (and what `recordAiConsent` answers, without `recorded`).
    private func aiConsentResult(recorded: Bool?) -> [String: Any] {
        let version = DJ.int(aiConsent["version"])
        let revoked = !DJ.isNull(aiConsent["revokedAt"])
        let agreed = !revoked && (version ?? 0) >= Self.aiConsentVersion
        var result: [String: Any] = [
            "agreed": agreed,
            "version": DJ.orNull(version),
            "agreedAt": DJ.orNull(aiConsent["agreedAt"]),
            "revokedAt": revoked ? DJ.orNull(aiConsent["revokedAt"]) : NSNull(),
            "currentVersion": Self.aiConsentVersion,
        ]
        if let recorded { result["recorded"] = recorded }
        return result
    }

    /// `__fail__` → 500, `__limit__` → 429, in any text value (also one level down, e.g. word.headword).
    static func failureStatus(in data: [String: Any]) -> Int? {
        var texts: [String] = []
        for value in data.values {
            if let s = value as? String { texts.append(s) }
            if let d = value as? [String: Any] {
                for inner in d.values { if let s = inner as? String { texts.append(s) } }
            }
        }
        for t in texts {
            let v = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if v == "__fail__" { return 500 }
            if v == "__limit__" { return 429 }
        }
        return nil
    }

    // MARK: - Candidates

    /// Candidate JSON (Candidate's CodingKeys) for a fixture word.
    private func candidate(_ w: [String: Any], reader r: String, group: Int, register: String?, distinction: String,
                           point: [Double], confidence: Double) -> [String: Any] {
        var c: [String: Any] = [:]
        c["kind"] = "object"
        c["headword"] = DJ.str(w["headword"]) ?? ""
        c["zhuyin"] = DJ.str(w["reading_zhuyin"]) ?? ""
        c["pinyin"] = DJ.str(w["pinyin"]) ?? ""
        let e = explain(w, r)
        c["meaning_ja"] = DJ.str(e["meaning"]) ?? text(w["meaning"], r)
        c["pos"] = DJ.str(w["part_of_speech"]) ?? DJ.str(DJ.dict(pack["synth"])["pos"]) ?? ""
        c["point"] = point
        c["confidence"] = confidence
        c["alternatives"] = [String]()
        c["distinction"] = distinction
        c["register"] = DJ.orNull(register)
        c["group"] = group
        c["category_key"] = DJ.orNull(DJ.str(w["category_key"]))
        return c
    }

    private func distinction(_ key: String, _ r: String) -> String {
        text(DJ.dict(pack["distinctions"])[key], r)
    }

    /// The other name of a fixture word (variant), as a candidate in the same group.
    private func variantCandidate(of key: String, reader r: String, group: Int) -> [String: Any]? {
        guard let v = variants.first(where: { DJ.str($0["of"]) == key }) else { return nil }
        var c = candidate(v, reader: r, group: group, register: DJ.str(v["register"]) ?? "specific",
                          distinction: text(v["distinction"], r), point: [500, 480], confidence: 0.7)
        c["meaning_ja"] = text(v["meaning"], r)
        return c
    }

    /// Photo → one new object with its other name, plus a word already in the dex (re-encounter).
    private func suggestions(_ r: String) -> [[String: Any]] {
        var out: [[String: Any]] = []
        if let scooter = fixture(key: "scooter") {
            out.append(candidate(scooter, reader: r, group: 0, register: "common", distinction: distinction("scooter", r),
                                 point: [480, 520], confidence: 0.93))
            if let v = variantCandidate(of: "scooter", reader: r, group: 0) { out.append(v) }
        }
        if let owned = fixtureWords.first {
            out.append(candidate(owned, reader: r, group: 1, register: nil, distinction: "", point: [760, 300], confidence: 0.71))
        }
        // `object_label` (server #184): each object's everyday name in the reader's language, the same on all its names.
        for i in out.indices {
            let group = out[i]["group"] as? Int
            let first = out.first { ($0["group"] as? Int) == group }
            out[i]["object_label"] = DJ.str(first?["meaning_ja"]) ?? ""
        }
        return out
    }

    /// Typed or spoken word → up to three names.
    private func wordCandidates(query: String, reader r: String) -> [[String: Any]] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = q.lowercased()
        var match: [String: Any]?
        if !q.isEmpty {
            match = fixture(headword: q)
            if match == nil, let v = variant(headword: q), let base = fixture(key: DJ.str(v["of"]) ?? "") {
                match = base
            }
            if match == nil {
                // A meaning in any reader's language ("マンゴー", "mango", "芒果").
                match = fixtureWords.first { w in
                    DJ.dict(w["explain"]).values.contains { e in
                        let m = (DJ.str(DJ.dict(e)["meaning"]) ?? "").lowercased()
                        return !m.isEmpty && (m == lower || m.components(separatedBy: CharacterSet(charactersIn: "、,，（）() ")).contains(lower))
                    }
                }
            }
        }
        var out: [[String: Any]] = []
        if let m = match {
            let key = DJ.str(m["key"]) ?? ""
            out.append(candidate(m, reader: r, group: 0, register: "common", distinction: distinction(key, r), point: [500, 500], confidence: 0.95))
            if let v = variantCandidate(of: key, reader: r, group: 0) { out.append(v) }
            for w in fixtureWords where out.count < 3 && DJ.str(w["key"]) != key {
                if ["pineapple", "scooter"].contains(DJ.str(w["key"]) ?? "") {
                    out.append(candidate(w, reader: r, group: out.count, register: nil, distinction: "", point: [500, 500], confidence: 0.4))
                }
            }
            return Array(out.prefix(3))
        }
        if !q.isEmpty && LanguageRules.headwordOk(q, target: learning) {
            // Unknown word in the learning language: offer it as typed (its meaning comes with the card).
            var c: [String: Any] = [:]
            c["kind"] = "object"
            c["headword"] = q
            c["zhuyin"] = ""
            c["pinyin"] = ""
            c["meaning_ja"] = ""
            c["pos"] = DJ.str(DJ.dict(pack["synth"])["pos"]) ?? ""
            c["point"] = [500.0, 500.0]
            c["confidence"] = 0.8
            c["alternatives"] = [String]()
            c["distinction"] = ""
            c["group"] = 0
            out.append(c)
        }
        for key in ["pineapple", "scooter", "mango", "cat", "umbrella"] where out.count < 3 {
            if let w = fixture(key: key) {
                out.append(candidate(w, reader: r, group: out.count, register: nil, distinction: "", point: [500, 500], confidence: 0.5))
            }
        }
        return Array(out.prefix(3))
    }

    /// Scan → two new words and one already in the dex, with positions.
    private func scanItems(_ r: String) -> [[String: Any]] {
        var out: [[String: Any]] = []
        if let w = fixture(key: "pineapple") {
            out.append(candidate(w, reader: r, group: 0, register: nil, distinction: "", point: [320, 420], confidence: 0.92))
        }
        if let w = fixture(key: "scooter") {
            out.append(candidate(w, reader: r, group: 1, register: nil, distinction: "", point: [690, 300], confidence: 0.85))
        }
        if fixtureWords.count > 1 {
            out.append(candidate(fixtureWords[1], reader: r, group: 2, register: nil, distinction: "", point: [500, 760], confidence: 0.78))
        }
        return out
    }

    private func rankScan(_ items: [[String: Any]]) -> [String: Any] {
        let indexed: [(Int, Bool, Double)] = items.enumerated().map { pair in
            (pair.offset, DJ.bool(pair.element["owned"]) ?? false, DJ.num(pair.element["confidence"]) ?? 0)
        }
        let ordered = indexed.sorted { a, b in
            if a.1 != b.1 { return !a.1 }
            if a.2 != b.2 { return a.2 > b.2 }
            return a.0 < b.0
        }
        return ["order": ordered.map { $0.0 }, "doubtful": [Int]()]
    }

    private func scanContext() -> [String: Any] {
        var owned: [String: Any] = [:]
        for s in rows("stickers") {
            guard let wid = DJ.str(s["word_id"]), let w = first("words", id: wid), let head = DJ.str(w["headword"]) else { continue }
            let hasPhoto = !DJ.isNull(s["object_image_url"]) || !DJ.isNull(s["cutout_image_url"])
            owned[head] = ["sticker_id": DJ.str(s["id"]) ?? "", "has_photo": hasPhoto, "found_at": DJ.str(s["taken_at"]) ?? DJ.now()] as [String: Any]
        }
        return ["owned": owned, "tapped": scanTapped]
    }

    // MARK: - Cards

    /// The card for a headword: the fixture's when known, else a small one from the templates.
    private func generateCard(headword: String, hint: String?, reader r: String) -> [String: Any] {
        if let f = fixture(headword: headword) {
            let e = explain(f, r)
            var card: [String: Any] = [:]
            card["headword"] = DJ.str(f["headword"]) ?? headword
            card["reading_zhuyin"] = DJ.orNull(DJ.str(f["reading_zhuyin"]))
            card["pinyin"] = DJ.orNull(DJ.str(f["pinyin"]))
            card["meaning_ja"] = DJ.str(e["meaning"]) ?? ""
            card["part_of_speech"] = DJ.str(f["part_of_speech"]) ?? ""
            card["category_key"] = DJ.str(f["category_key"]) ?? (hint ?? "other")
            card["example_sentence"] = DJ.str(f["example_sentence"]) ?? ""
            card["example_translation"] = DJ.str(e["example_translation"]) ?? ""
            card["extras"] = DJ.dict(e["extras"])
            card["explain_lang"] = r
            return card
        }
        if let v = variant(headword: headword) {
            return synthCard(headword: DJ.str(v["headword"]) ?? headword, reading: DJ.str(v["reading_zhuyin"]), pinyin: DJ.str(v["pinyin"]),
                             meaning: text(v["meaning"], r), category: DJ.str(v["category_key"]) ?? hint, reader: r)
        }
        return synthCard(headword: headword, reading: nil, pinyin: nil, meaning: "", category: hint, reader: r)
    }

    func synthCard(headword h: String, reading: String?, pinyin: String?, meaning: String, category: String?, reader r: String) -> [String: Any] {
        let s = DJ.dict(pack["synth"])
        let fill: (String) -> String = { $0.replacingOccurrences(of: "{h}", with: h) }
        var parts: [[String: Any]] = []
        if let raw = s["chunk_parts"] as? [[String]] {
            for p in raw where p.count >= 2 {
                parts.append(["text": fill(p[0]), "pos": p[1]])
            }
        }
        let chunk: [String: Any] = ["parts": parts, "ja": fill(text(s["chunk_tr"], r))]
        var extras: [String: Any] = ["explain_lang": r, "register_scale": 0]
        if parts.count >= 2 { extras["usage_chunks"] = [chunk] }
        var card: [String: Any] = [:]
        card["headword"] = h
        card["reading_zhuyin"] = DJ.orNull(reading)
        card["pinyin"] = DJ.orNull(pinyin)
        card["meaning_ja"] = meaning
        card["part_of_speech"] = DJ.str(s["pos"]) ?? ""
        card["category_key"] = category ?? "other"
        card["example_sentence"] = fill(DJ.str(s["example"]) ?? h)
        card["example_translation"] = fill(text(s["ex_tr"], r))
        card["extras"] = extras
        card["explain_lang"] = r
        return card
    }

    private func imageCandidates(query: String) -> [[String: Any]] {
        // Which word the search is for (its meaning or headword is in the query), for the picture's emoji.
        let lower = query.lowercased()
        var key = "img"
        for w in fixtureWords {
            var names: [String] = [(DJ.str(w["headword"]) ?? "").lowercased()]
            for value in DJ.dict(w["explain"]).values {
                let m = (DJ.str(DJ.dict(value)["meaning"]) ?? "").lowercased()
                if let firstSense = m.components(separatedBy: CharacterSet(charactersIn: "、,，（(")).first { names.append(firstSense.trimmingCharacters(in: .whitespaces)) }
            }
            if names.contains(where: { !$0.isEmpty && lower.contains($0) }) {
                key = DJ.str(w["key"]) ?? "img"
                break
            }
        }
        let credits = ["Aiko Tanaka", "Ben Carter", "Lin Wei-ting"]
        var out: [[String: Any]] = []
        for (i, name) in credits.enumerated() {
            let url = "https://images.unsplash.com/demo/\(key)/\(i + 1).jpg"
            let credit: [String: Any] = ["name": name, "link": "https://unsplash.com/@demo"]
            out.append(["url": url, "thumb": url + "?w=400", "source": "unsplash", "credit": credit])
        }
        return out
    }

    // MARK: - Words

    private func saveSticker(_ data: [String: Any], reader r: String) -> DemoResponse {
        var word = DJ.dict(data["word"])
        let head = (DJ.str(word["headword"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty else { return .error(400, "headword required") }
        let lang = DJ.str(data["language"]) ?? learning
        let wordId: String
        if let existing = rows("words").first(where: { DJ.str($0["headword"]) == head && (DJ.str($0["language"]) ?? learning) == lang }) {
            wordId = DJ.str(existing["id"]) ?? DJ.uuid()
        } else {
            wordId = "demo-word-" + String(DJ.uuid().prefix(8))
            word["id"] = wordId
            word["headword"] = head
            word["language"] = lang
            word["created_at"] = DJ.now()
            if !(word["extras"] is [String: Any]) { word["extras"] = [String: Any]() }
            insert("words", word)
            if let f = fixture(headword: head) {
                registerExplanations(f, wordId: wordId)
            } else {
                let extras = DJ.dict(word["extras"])
                let mark = DJ.str(extras["explain_lang"]) ?? r
                var row: [String: Any] = [:]
                row["explain_lang"] = mark
                row["meaning"] = DJ.str(word["meaning_ja"]) ?? ""
                row["example_translation"] = DJ.orNull(DJ.str(word["example_translation"]))
                row["extras"] = extras
                row["source"] = "demo"
                var byLang = explanations[wordId] ?? [:]
                byLang[mark] = row
                explanations[wordId] = byLang
            }
        }
        // The catch's own id (`client_catch_id`, as the server): a save tried again gets the sticker already made for it.
        let catchId = DJ.str(data["client_catch_id"])
        if let catchId, let made = rows("stickers").first(where: { DJ.str($0["id"]) == catchId }) {
            return .json(["result": ["id": catchId, "word_id": DJ.str(made["word_id"]) ?? wordId]])
        }
        // One sticker per word (the server's duplicate guard).
        if let owned = rows("stickers").first(where: { DJ.str($0["word_id"]) == wordId }), let sid = DJ.str(owned["id"]) {
            return .json(["result": ["id": sid]])
        }
        let sid = catchId ?? ("demo-sticker-" + String(DJ.uuid().prefix(8)))
        let objectPath = DJ.str(data["object_path"])
        let caption = (DJ.str(data["caption"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var s: [String: Any] = [:]
        s["id"] = sid
        s["user_id"] = Self.userId
        s["word_id"] = wordId
        s["object_image_url"] = DJ.orNull(objectPath)
        s["cutout_image_url"] = DJ.orNull(DJ.str(data["cutout_path"]))
        s["selfie_image_url"] = DJ.orNull(DJ.str(data["selfie_path"]))
        s["caption"] = caption.isEmpty ? (NSNull() as Any) : (caption as Any)
        s["location_name"] = DJ.orNull(DJ.str(data["location_name"]))
        s["lat"] = DJ.orNull(DJ.num(data["lat"]))
        s["lng"] = DJ.orNull(DJ.num(data["lng"]))
        s["taken_at"] = DJ.now()
        s["created_at"] = DJ.now()
        s["capture_type"] = objectPath == nil ? "text" : "photo"
        s["shelf_key"] = NSNull()
        s["hero_role"] = NSNull()
        s["placeholder_image_url"] = NSNull()
        s["placeholder_credit"] = NSNull()
        insert("stickers", s)
        var review: [String: Any] = [:]
        review["id"] = "demo-review-" + String(DJ.uuid().prefix(8))
        review["user_id"] = Self.userId
        review["sticker_id"] = sid
        review["ease"] = 2.5
        review["interval_days"] = 0
        review["repetitions"] = 0
        review["last_reviewed_at"] = NSNull()
        review["due_at"] = DJ.iso(Date().addingTimeInterval(86_400))
        review["created_at"] = DJ.now()
        insert("reviews", review)
        return .json(["result": ["id": sid]])
    }

    /// The meaning this reader sees for a word ("" when there is none in their language).
    private func meaning(wordId: String, reader r: String) -> String {
        if let m = DJ.str(explanations[wordId]?[r]?["meaning"]), !m.isEmpty { return m }
        if let w = first("words", id: wordId), DJ.str(DJ.dict(w["extras"])["explain_lang"]) == r {
            return DJ.str(w["meaning_ja"]) ?? ""
        }
        return ""
    }

    private func ownedWord(headword: String, reader r: String) -> Any {
        let h = headword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let w = rows("words").first(where: { DJ.str($0["headword"]) == h }),
              let wid = DJ.str(w["id"]),
              let s = rows("stickers").first(where: { DJ.str($0["word_id"]) == wid }),
              let sid = DJ.str(s["id"]) else { return NSNull() }
        let encounters = rows("encounters").filter { DJ.str($0["sticker_id"]) == sid }.count
        var o: [String: Any] = [:]
        o["sticker_id"] = sid
        o["word_id"] = wid
        o["headword"] = h
        o["meaning_ja"] = meaning(wordId: wid, reader: r)
        o["reading_zhuyin"] = DJ.orNull(DJ.str(w["reading_zhuyin"]))
        o["pinyin"] = DJ.orNull(DJ.str(w["pinyin"]))
        if let path = DJ.str(s["cutout_image_url"]) ?? DJ.str(s["object_image_url"]) ?? DJ.str(s["placeholder_image_url"]) {
            o["cutout_url"] = Self.signedURL(path)
        } else {
            o["cutout_url"] = NSNull()
        }
        o["encounter_count"] = 1 + encounters
        o["taken_at"] = DJ.str(s["taken_at"]) ?? DJ.now()
        o["location_name"] = DJ.orNull(DJ.str(s["location_name"]))
        return o
    }

    private func readerMeanings(_ ids: [String], reader r: String) -> [String: Any] {
        var out: [String: Any] = [:]
        for id in ids {
            let m = meaning(wordId: id, reader: r)
            out[id] = m.isEmpty ? (NSNull() as Any) : (m as Any)
        }
        return out
    }

    /// web getWordExplanation: this reader's explanation, filed under exactly the language and l1 asked for.
    private func wordExplanation(_ data: [String: Any]) -> [String: Any] {
        let wid = DJ.str(data["word_id"]) ?? ""
        let asked = DJ.str(data["explain_lang"]) ?? L10n.lang
        let r = reader(asked)
        let l1 = DJ.str(data["l1"]) ?? r
        var picked: [String: Any]?
        if let e = explanations[wid]?[r] {
            picked = e
        } else if let w = first("words", id: wid), DJ.str(DJ.dict(w["extras"])["explain_lang"]) == r {
            picked = ["meaning": DJ.str(w["meaning_ja"]) ?? "", "example_translation": DJ.orNull(DJ.str(w["example_translation"])),
                      "extras": DJ.dict(w["extras"]), "source": "demo"]
        }
        guard var p = picked else { return ["picked": NSNull(), "unavailable": true] }
        p["explain_lang"] = asked
        p["l1"] = l1
        var extras = DJ.dict(p["extras"])
        extras["explain_lang"] = asked
        p["extras"] = extras
        return ["picked": p, "unavailable": false]
    }

    private func updateWordExtras(_ data: [String: Any]) -> [String: Any] {
        let wid = DJ.str(data["word_id"]) ?? ""
        let extras = DJ.dict(data["extras"])
        let patch = DJ.dict(data["patch"])
        let lang = reader(DJ.str(extras["explain_lang"]))
        if !patch.isEmpty {
            update("words", where: { DJ.str($0["id"]) == wid }) { w in
                for (k, v) in patch { w[k] = v }
            }
        }
        var row = explanations[wid]?[lang] ?? [:]
        row["explain_lang"] = lang
        row["extras"] = extras
        if let m = DJ.str(patch["meaning_ja"]) { row["meaning"] = m }
        if row["meaning"] == nil { row["meaning"] = meaning(wordId: wid, reader: lang) }
        row["source"] = "demo"
        var byLang = explanations[wid] ?? [:]
        byLang[lang] = row
        explanations[wid] = byLang
        return ["ok": true]
    }

    private func setHeadword(_ data: [String: Any], reader r: String) -> DemoResponse {
        let sid = DJ.str(data["sticker_id"]) ?? ""
        let head = (DJ.str(data["headword"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty else { return .error(400, "headword required") }
        guard LanguageRules.headwordOk(head, target: learning) else { return .error(400, "NOT_TARGET_LANGUAGE") }
        guard first("stickers", id: sid) != nil else { return notFound() }
        let wordId: String
        if let existing = rows("words").first(where: { DJ.str($0["headword"]) == head }) {
            wordId = DJ.str(existing["id"]) ?? DJ.uuid()
        } else if let f = fixture(headword: head) {
            wordId = "demo-word-" + String(DJ.uuid().prefix(8))
            insert("words", wordRow(f, id: wordId, reader: r))
            registerExplanations(f, wordId: wordId)
        } else {
            wordId = "demo-word-" + String(DJ.uuid().prefix(8))
            let card = synthCard(headword: head, reading: nil, pinyin: nil, meaning: "", category: nil, reader: r)
            var row = card
            row["id"] = wordId
            row["language"] = learning
            row["created_at"] = DJ.now()
            row["explain_lang"] = nil
            insert("words", row)
        }
        updateSticker(sid) { s in s["word_id"] = wordId }
        return .json(["result": ["ok": true]])
    }

    // MARK: - Stickers

    private func recordEncounter(_ data: [String: Any]) -> [String: Any] {
        let sid = DJ.str(data["sticker_id"]) ?? ""
        var e: [String: Any] = [:]
        e["id"] = DJ.uuid()
        e["user_id"] = Self.userId
        e["sticker_id"] = sid
        e["image_path"] = DJ.orNull(DJ.str(data["image_path"]))
        e["cutout_path"] = DJ.orNull(DJ.str(data["cutout_path"]))
        e["location_name"] = DJ.orNull(DJ.str(data["location_name"]))
        e["lat"] = DJ.orNull(DJ.num(data["lat"]))
        e["lng"] = DJ.orNull(DJ.num(data["lng"]))
        e["encountered_at"] = DJ.now()
        e["created_at"] = e["encountered_at"]   // the real table's column (the app reads it)
        insert("encounters", e)
        let count = 1 + rows("encounters").filter { DJ.str($0["sticker_id"]) == sid }.count
        return ["encounter_count": count]
    }

    private func stickerPhotos(_ sid: String) -> [[String: Any]] {
        guard let s = first("stickers", id: sid) else { return [] }
        var out: [[String: Any]] = []
        if let path = DJ.str(s["object_image_url"]) ?? DJ.str(s["cutout_image_url"]) ?? DJ.str(s["placeholder_image_url"]) {
            out.append(["url": Self.signedURL(path), "taken_at": DJ.str(s["taken_at"]) ?? DJ.now(),
                        "place": DJ.orNull(DJ.str(s["location_name"])), "first": true])
        }
        let encounters = rows("encounters").filter { DJ.str($0["sticker_id"]) == sid }
            .sorted { (DJ.str($0["encountered_at"]) ?? "") < (DJ.str($1["encountered_at"]) ?? "") }
        for e in encounters {
            guard let path = DJ.str(e["image_path"]) ?? DJ.str(e["cutout_path"]) else { continue }
            out.append(["url": Self.signedURL(path), "taken_at": DJ.str(e["encountered_at"]) ?? DJ.now(),
                        "place": DJ.orNull(DJ.str(e["location_name"])), "first": false])
        }
        return out
    }

    private func saveAlbumLayout(_ items: [[String: Any]]) -> [String: Any] {
        var saved = 0
        for item in items {
            guard let sid = DJ.str(item["sticker_id"]) else { continue }
            let ok = updateSticker(sid) { s in
                s["album_order"] = DJ.orNull(DJ.int(item["order"]))
                s["album_size"] = DJ.orNull(DJ.str(item["size"]))
                s["album_x"] = DJ.orNull(DJ.num(item["x"]))
                s["album_y"] = DJ.orNull(DJ.num(item["y"]))
                s["album_scale"] = DJ.orNull(DJ.num(item["scale"]))
                s["album_rot"] = DJ.orNull(DJ.num(item["rot"]))
            }
            if ok { saved += 1 }
        }
        return ["saved": saved]
    }

    // MARK: - Review and stats

    private func gradeReview(_ data: [String: Any]) -> DemoResponse {
        let rid = DJ.str(data["review_id"]) ?? ""
        // The server (2026-10-15): a review row that no longer exists (its word was deleted mid-round) is no error.
        guard let review = first("reviews", id: rid) else {
            return .json(["result": ["gone": true, "score": NSNull(), "interval_days": NSNull()] as [String: Any]])
        }
        let correct = DJ.bool(data["correct"]) ?? false
        var ease = DJ.num(review["ease"]) ?? 2.5
        var interval = DJ.int(review["interval_days"]) ?? 0
        var reps = DJ.int(review["repetitions"]) ?? 0
        let score = correct ? 5 : 1
        if correct {
            reps += 1
            if reps == 1 {
                interval = 1
            } else if reps == 2 {
                interval = 3
            } else {
                interval = max(1, Int((Double(max(interval, 1)) * ease).rounded()))
            }
            ease = min(3.0, ease + 0.1)
        } else {
            reps = 0
            interval = 1
            ease = max(1.3, ease - 0.2)
        }
        let now = Date()
        let nowText = DJ.iso(now)
        let due = DJ.iso(now.addingTimeInterval(Double(interval) * 86_400))
        update("reviews", where: { DJ.str($0["id"]) == rid }) { row in
            row["ease"] = ease
            row["interval_days"] = interval
            row["repetitions"] = reps
            row["last_reviewed_at"] = nowText
            row["due_at"] = due
        }
        var h: [String: Any] = [:]
        h["id"] = DJ.uuid()
        h["user_id"] = Self.userId
        h["sticker_id"] = DJ.orNull(DJ.str(review["sticker_id"]))
        h["review_id"] = rid
        h["reviewed_at"] = nowText
        h["score"] = score
        h["interval_days_after"] = interval
        h["ease_after"] = ease
        insert("review_history", h)
        let result: [String: Any] = ["score": score, "interval_days": Double(interval), "ease": ease, "due_at": due]
        return .json(["result": result])
    }

    /// Consecutive days up to today (or up to yesterday when today has none yet).
    private func streak(_ days: Set<String>) -> Int {
        let calendar = Calendar.current
        var day = Date()
        if !days.contains(DJ.dayKey(day)) {
            guard let y = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var count = 0
        while days.contains(DJ.dayKey(day)) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    private func myStats() -> [String: Any] {
        let stickers = rows("stickers")
        let history = rows("review_history")
        let now = DJ.now()
        let today = DJ.dayKey(Date())
        let captureDays = Set(stickers.compactMap { DJ.str($0["taken_at"]).flatMap(SupabaseDate.parse).map(DJ.dayKey) })
        let reviewDays = Set(history.compactMap { DJ.str($0["reviewed_at"]).flatMap(SupabaseDate.parse).map(DJ.dayKey) })
        let due = rows("reviews").filter { (DJ.str($0["due_at"]) ?? "") <= now }.count
        let doneToday = history.filter { row in
            guard let d = DJ.str(row["reviewed_at"]).flatMap(SupabaseDate.parse) else { return false }
            return DJ.dayKey(d) == today
        }.count
        let xp = stickers.count * 20 + history.count * 5 + 40
        let level = Int(floor(sqrt(Double(xp) / 50))) + 1
        return [
            "xp": xp,
            "level": level,
            "capture_streak": streak(captureDays),
            "review_streak": streak(reviewDays),
            "captured_total": stickers.count,
            "reviews_due": due,
            "reviews_done_today": doneToday,
        ]
    }
}
#endif
