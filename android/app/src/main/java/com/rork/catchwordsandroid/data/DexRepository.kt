package com.rork.catchwordsandroid.data

import io.ktor.http.ContentType
import io.ktor.http.HttpMethod
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

data class DexState(
    val stickers: List<Sticker> = emptyList(),
    val reviews: Map<String, ReviewState> = emptyMap(),
    val signed: Map<String, String> = emptyMap(),
    val isLoading: Boolean = false,
    val hasLoaded: Boolean = false,
    val error: String? = null,
    val generating: Set<String> = emptySet(),
) {
    fun sticker(id: String): Sticker? = stickers.firstOrNull { it.id == id }

    fun memoryPercent(s: Sticker): Int? = reviews[s.id]?.retention(s.takenAtMs)

    /** Level index (0–5) counts for every sticker with a review — the memory bar. */
    val memoryLevelCounts: List<Int>
        get() {
            val out = IntArray(6)
            stickers.forEach { s -> memoryPercent(s)?.let { out[ReviewState.level(it)]++ } }
            return out.toList()
        }
}

/**
 * The learner's dex: every sticker of the learning language with its word (shown in the reader's language),
 * review states for the memory badges, signed photo links, and saving / deleting a catch through the web's functions.
 */
class DexRepository(
    private val client: SupabaseClient,
    private val api: NativeApi,
    private val profile: ProfileRepository,
) {
    private val _state = MutableStateFlow(DexState())
    val state: StateFlow<DexState> = _state.asStateFlow()

    private val sharedWords = mutableMapOf<String, Word>()
    private val explanations = mutableMapOf<String, Explanation?>()
    private val readerMeanings = mutableMapOf<String, String>()
    private var readerKey = ""

    private val optionalColumns = mutableListOf("hero_role", "placeholder_image_url", "placeholder_credit")
    private val baseColumns =
        "id,word_id,object_image_url,cutout_image_url,selfie_image_url,caption,location_name,lat,lng,taken_at,capture_type,shelf_key"

    private fun selectColumns(): String = (listOf(baseColumns) + optionalColumns + listOf("word:words(*)")).joinToString(",")

    /** Runs a stickers query; drops an optional column the server says it doesn't have and tries again. */
    private suspend fun selectStickers(query: (String) -> String): String {
        while (true) {
            try {
                return client.rest(HttpMethod.Get, query(selectColumns()))
            } catch (e: ApiException) {
                val missing = optionalColumns.firstOrNull { e.detail.contains(it) } ?: throw e
                optionalColumns.remove(missing)
            }
        }
    }

    fun reset() {
        _state.value = DexState()
        sharedWords.clear()
        explanations.clear()
        readerMeanings.clear()
    }

    suspend fun load() {
        val uid = client.userId ?: run { _state.update { it.copy(hasLoaded = true, error = null) }; return }
        _state.update { it.copy(isLoading = true) }
        try {
            val rows = mutableListOf<Sticker>()
            val pageSize = 500
            for (page in 0 until 40) {
                val text = selectStickers { "stickers?select=$it&order=taken_at.desc,id.desc&limit=$pageSize&offset=${page * pageSize}" }
                val chunk = (AppJson.parseToJsonElement(text) as? JsonArray)?.mapNotNull { (it as? JsonObject)?.let(Sticker::from) } ?: emptyList()
                rows += chunk
                if (chunk.size < pageSize) break
            }
            if (client.userId != uid) return
            val target = profile.target
            val mine = rows.filter { it.word?.matches(target) ?: true }
            mine.forEach { s -> s.word?.let { sharedWords[it.id] = it } }
            if (readerKey != L10n.current) {
                readerKey = L10n.current
                explanations.clear()
                readerMeanings.clear()
            }
            _state.update { it.copy(stickers = mine.map(::applyReader), hasLoaded = true, error = null, isLoading = false) }
            loadReviews()
            sign(mine.flatMap { it.allPaths })
            runCatching { Reminders.refresh(AppGraph.appContext) }
            runCatching { WidgetBridge.refresh(AppGraph.appContext) }
            loadReaderMeanings(mine.map { it.wordId }.distinct().filter { it.isNotEmpty() && !readerMeanings.containsKey(it) })
        } catch (e: Exception) {
            if (client.userId != uid) return
            _state.update {
                it.copy(isLoading = false, error = if (e is ApiException) e.userMessage else tr("図鑑を読み込めませんでした。", "Couldn't load your collection.", "無法載入圖鑑。"))
            }
        }
    }

    suspend fun loadReviews() {
        val uid = client.userId ?: return
        val rows = runCatching {
            client.restAll("reviews?select=id,sticker_id,ease,interval_days,repetitions,last_reviewed_at,due_at&order=id.asc")
        }.getOrNull() ?: return
        if (client.userId != uid) return
        val map = rows.mapNotNull(ReviewState.Parse::from).associateBy { it.stickerId }
        _state.update { it.copy(reviews = map) }
    }

    private fun applyReader(s: Sticker): Sticker {
        val shared = s.word?.let { sharedWords[it.id] ?: it } ?: return s
        return s.copy(word = ReaderLanguage.resolve(shared, explanations[shared.id], readerMeanings[shared.id], L10n.current))
    }

    private fun reapply(wordId: String? = null) {
        _state.update { st -> st.copy(stickers = st.stickers.map { if (wordId == null || it.wordId == wordId) applyReader(it) else it }) }
    }

    /** web `getReaderMeanings`: meanings written in the reader's language, 200 words at a time. */
    private suspend fun loadReaderMeanings(ids: List<String>) {
        val lang = L10n.current
        ids.chunked(200).forEach { chunk ->
            val got = runCatching {
                api.call("getReaderMeanings", jsonOf("word_ids" to chunk, "explain_lang" to lang), timeoutMs = 30_000) as? JsonObject
            }.getOrNull() ?: return@forEach
            if (lang != L10n.current) return
            chunk.forEach { id -> readerMeanings[id] = (got[id] as? JsonPrimitive)?.contentOrNull ?: "" }
        }
        reapply()
    }

    /**
     * web StickerSheet: reads this reader's explanation; when there is none for exactly this reader, writes one
     * (`generateCard` → `updateWordExtras`) in the background — only with the AI consent.
     */
    suspend fun loadExplanation(wordId: String, consentGranted: Boolean) {
        val lang = L10n.current
        val target = sharedWords[wordId]?.language ?: profile.target
        val l1 = ProfileRepository.readerL1(profile.profile.value.nativeLanguage, target)
        val res = runCatching {
            api.call("getWordExplanation", jsonOf("word_id" to wordId, "explain_lang" to lang, "l1" to l1), timeoutMs = 20_000) as? JsonObject
        }.getOrNull() ?: return
        if (lang != L10n.current) return
        val picked = Explanation.from(res.obj("picked"))
        explanations[wordId] = picked
        reapply(wordId)
        if (res.bool("unavailable") == true || !consentGranted) return
        val shared = sharedWords[wordId] ?: return
        if (!ReaderLanguage.needsGeneration(picked, lang, l1) || wordId in _state.value.generating) return
        _state.update { it.copy(generating = it.generating + wordId) }
        try {
            val card = runCatching {
                api.call("generateCard", jsonOf("headword" to shared.headword, "targetLanguage" to target), timeoutMs = 60_000) as? JsonObject
            }.getOrNull() ?: return
            val extras = card.obj("extras") ?: return
            val fields = mutableMapOf<String, Any?>("word_id" to wordId, "extras" to extras)
            val missing = listOf(shared.meaning, shared.readingZhuyin ?: shared.pinyin ?: "", shared.exampleSentence ?: "").any { it.isBlank() }
            if (missing) {
                val patch = listOf("reading_zhuyin", "pinyin", "part_of_speech", "example_sentence", "example_translation", "meaning_ja")
                    .mapNotNull { k -> card.str(k)?.let { k to it } }.toMap()
                if (patch.isNotEmpty()) fields["patch"] = patch
            }
            runCatching { api.call("updateWordExtras", toJson(fields) as JsonObject, timeoutMs = 30_000) }
            val again = runCatching {
                api.call("getWordExplanation", jsonOf("word_id" to wordId, "explain_lang" to lang, "l1" to l1), timeoutMs = 20_000) as? JsonObject
            }.getOrNull()
            Explanation.from(again?.obj("picked"))?.let {
                explanations[wordId] = it
                reapply(wordId)
            }
        } finally {
            _state.update { it.copy(generating = it.generating - wordId) }
        }
    }

    /** Signs photo paths in batches of 100; a failed batch is simply asked again on the next load. */
    suspend fun sign(paths: List<String>) {
        val todo = paths.distinct().filter { it !in _state.value.signed }
        todo.chunked(100).forEach { chunk ->
            val map = runCatching { client.signedUrls(chunk) }.getOrNull() ?: return@forEach
            _state.update { it.copy(signed = it.signed + map) }
        }
    }

    fun url(path: String?): String? = path?.let { _state.value.signed[it] }

    fun owned(headword: String): Sticker? = _state.value.stickers.firstOrNull { it.word?.headword == headword }

    // region Save / encounter / delete

    /** The `words` fields `saveSticker` gets for a catch (the picked name is the headword). */
    private fun wordFields(c: Candidate, card: JsonObject): Map<String, Any?> {
        fun text(key: String, fallback: String): String = card.str(key) ?: fallback
        val defaultPos = when (profile.target) { "en" -> "noun"; "ja" -> "名詞"; else -> "N" }
        val word = mutableMapOf<String, Any?>(
            "headword" to c.headword,
            "reading_zhuyin" to text("reading_zhuyin", c.zhuyin),
            "pinyin" to text("pinyin", c.pinyin),
            "meaning_ja" to text("meaning_ja", c.meaning.ifEmpty { c.headword }),
            "part_of_speech" to text("part_of_speech", c.pos.ifEmpty { defaultPos }),
            "category_key" to text("category_key", card.str("category_key") ?: "other"),
            "example_sentence" to text("example_sentence", ""),
            "example_translation" to text("example_translation", ""),
        )
        card.obj("extras")?.let { word["extras"] = it }
        word["level"] = card.str("level") ?: ""
        return word
    }

    /** Uploads a JPEG / PNG under `<uid>/<ts>-<kind>.<ext>`; nil when there is nothing to send. */
    private suspend fun uploadJpeg(bmp: android.graphics.Bitmap?, uid: String, ts: Long, kind: String): String? {
        bmp ?: return null
        val p = "$uid/$ts-$kind.jpg"
        client.upload(ImageTools.jpeg(bmp), p, ContentType.Image.JPEG)
        return p
    }

    private suspend fun uploadPng(bmp: android.graphics.Bitmap?, uid: String, ts: Long, kind: String, maxSide: Int = 1200): String? {
        bmp ?: return null
        val p = "$uid/$ts-$kind.png"
        return runCatching { client.upload(ImageTools.png(bmp, maxSide), p, ContentType.Image.PNG); p }.getOrNull()
    }

    /**
     * Saves a new catch through the web's `saveSticker`: the photo, the cut-out and the selfie are uploaded first in
     * parallel (a failed cut-out or selfie never blocks the catch), then the row with where it happened.
     */
    suspend fun save(
        candidate: Candidate,
        card: JsonObject,
        photo: android.graphics.Bitmap,
        cutout: android.graphics.Bitmap?,
        selfie: android.graphics.Bitmap?,
        caption: String,
        place: Place?,
    ): Sticker = kotlinx.coroutines.coroutineScope {
        val uid = client.userId ?: throw ApiException.Unauthorized
        val ts = System.currentTimeMillis()
        val obj = async { uploadJpeg(photo, uid, ts, "object") }
        val cut = async { uploadPng(cutout, uid, ts, "cutout") }
        val sel = async { runCatching { uploadJpeg(selfie, uid, ts, "selfie") }.getOrNull() }
        val objectPath = obj.await()
        val cutoutPath = cut.await()
        val selfiePath = sel.await()
        if (client.userId != uid) throw ApiException.Server(409, "account changed")
        val data = toJson(
            mapOf(
                "word" to wordFields(candidate, card),
                "new_shelf" to JsonNull,
                "language" to profile.target,
                "object_path" to objectPath,
                "cutout_path" to cutoutPath,
                "selfie_path" to selfiePath,
                "caption" to caption.trim().ifEmpty { null },
                "location_name" to place?.name,
                "lat" to place?.lat,
                "lng" to place?.lng,
            ),
        ) as JsonObject
        val saved = api.call("saveSticker", data, timeoutMs = 45_000, asUser = uid) as? JsonObject ?: throw ApiException.Decoding
        val id = saved.str("id") ?: throw ApiException.Decoding
        val fresh = runCatching {
            val text = selectStickers { "stickers?id=eq.$id&select=$it&limit=1" }
            (AppJson.parseToJsonElement(text) as? JsonArray)?.firstOrNull()?.let { (it as? JsonObject)?.let(Sticker::from) }
        }.getOrNull()
        val sticker = fresh ?: Sticker(
            id = id, wordId = saved.str("word_id") ?: "", objectImageUrl = objectPath, cutoutImageUrl = cutoutPath,
            selfieImageUrl = selfiePath, caption = caption.ifBlank { null }, locationName = place?.name, takenAtMs = System.currentTimeMillis(),
            captureType = "photo", word = Word.from(toJson(wordFields(candidate, card) + ("id" to (saved.str("word_id") ?: ""))) as JsonObject),
            lat = place?.lat, lng = place?.lng,
        )
        sticker.word?.let { sharedWords[it.id] = it }
        _state.update { st -> st.copy(stickers = listOf(applyReader(sticker)) + st.stickers.filter { it.id != id }) }
        sign(sticker.allPaths)
        loadReviews()
        sticker
    }

    /** The card that was still being written when the catch was saved fills the word's notes in (iOS fillCard). */
    suspend fun fillCard(sticker: Sticker, card: JsonObject) {
        val extras = card.obj("extras") ?: return
        val fields = mutableMapOf<String, Any?>("word_id" to sticker.wordId, "extras" to extras)
        val patch = listOf("reading_zhuyin", "pinyin", "part_of_speech", "level", "example_sentence", "example_translation", "meaning_ja")
            .mapNotNull { k -> card.str(k)?.takeIf { it.isNotBlank() }?.let { k to it } }.toMap()
        if (patch.isNotEmpty()) fields["patch"] = patch
        runCatching { api.call("updateWordExtras", toJson(fields) as JsonObject, timeoutMs = 30_000) }
        load()
    }

    /** A word already in the dex caught again: a re-encounter (`recordEncounter`), never a duplicate sticker. */
    suspend fun recordEncounter(stickerId: String, photo: android.graphics.Bitmap?, cutout: android.graphics.Bitmap?, place: Place?): Int? =
        kotlinx.coroutines.coroutineScope {
            val uid = client.userId ?: throw ApiException.Unauthorized
            val ts = System.currentTimeMillis()
            val img = async { runCatching { uploadJpeg(photo, uid, ts, "encounter") }.getOrNull() }
            val cut = async { uploadPng(cutout, uid, ts, "encounter-cutout", 800) }
            val res = api.call(
                "recordEncounter",
                toJson(
                    mapOf(
                        "sticker_id" to stickerId, "recalled" to null, "lat" to place?.lat, "lng" to place?.lng,
                        "location_name" to place?.name, "image_path" to img.await(), "cutout_path" to cut.await(),
                    ),
                ) as JsonObject,
                timeoutMs = 30_000, asUser = uid,
            ) as? JsonObject
            res?.int("encounter_count")
        }

    /** Past encounters of a sticker (web `encounters`): photos (cut-out first) and where. */
    suspend fun encounters(stickerId: String): List<Encounter> {
        val rows = runCatching {
            client.restAll("encounters?select=id,sticker_id,image_path,cutout_path,location_name,created_at&sticker_id=eq.$stickerId&order=created_at.desc,id.desc")
        }.getOrNull() ?: return emptyList()
        val list = rows.mapNotNull { o ->
            Encounter(
                id = o.str("id") ?: return@mapNotNull null,
                path = o.str("cutout_path")?.takeIf { it.isNotEmpty() } ?: o.str("image_path"),
                isCutout = !o.str("cutout_path").isNullOrEmpty(),
                locationName = o.str("location_name"),
                atMs = parseDate(o.str("created_at")),
            )
        }
        sign(list.mapNotNull { it.path })
        return list
    }

    /** Which picture shows this word on its page (web setStickerHeroRole; null = default order). */
    suspend fun setHeroRole(sticker: Sticker, role: String?) {
        val res = api.call("setStickerHeroRole", toJson(mapOf("sticker_id" to sticker.id, "hero_role" to role)) as JsonObject) as? JsonObject
        if (res?.bool("saved") == false) throw ApiException.Message(tr("まだ保存できません。サーバの更新を待ってください。", "Can't save this yet. Please wait for a server update.", "目前還無法儲存，請等待伺服器更新。"))
        _state.update { st -> st.copy(stickers = st.stickers.map { if (it.id == sticker.id) it.copy(heroRole = role) else it }) }
    }

    suspend fun updateCaption(sticker: Sticker, caption: String) {
        api.call("updateStickerCaption", jsonOf("sticker_id" to sticker.id, "caption" to caption.trim()))
        _state.update { st -> st.copy(stickers = st.stickers.map { if (it.id == sticker.id) it.copy(caption = caption.trim().ifEmpty { null }) else it }) }
    }

    suspend fun delete(sticker: Sticker) {
        api.call("deleteSticker", jsonOf("sticker_id" to sticker.id))
        _state.update { st -> st.copy(stickers = st.stickers.filter { it.id != sticker.id }, reviews = st.reviews - sticker.id) }
    }

    // endregion
}

/** One time a word was met again. */
data class Encounter(val id: String, val path: String?, val isCutout: Boolean, val locationName: String?, val atMs: Long?)
