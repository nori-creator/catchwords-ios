package com.rork.catchwordsandroid.data

import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

/** Row of the shared `words` table (same schema as the web and iOS apps). `extras` stays raw JSON. */
data class Word(
    val id: String,
    val headword: String,
    val readingZhuyin: String?,
    val pinyin: String?,
    val meaning: String,
    val partOfSpeech: String?,
    val categoryKey: String?,
    val exampleSentence: String?,
    val exampleTranslation: String?,
    val extras: JsonObject?,
    val language: String?,
) {
    /** Same rule as the web's `matchesTargetLanguage`: an empty language is 台湾華語. */
    fun matches(target: String): Boolean {
        val raw = language?.trim().orEmpty()
        return if (raw.isEmpty()) target == "zh-TW" else raw == target
    }

    companion object {
        fun from(o: JsonObject?): Word? {
            o ?: return null
            val id = o.str("id") ?: return null
            val head = o.str("headword") ?: return null
            return Word(
                id = id,
                headword = head,
                readingZhuyin = o.str("reading_zhuyin"),
                pinyin = o.str("pinyin"),
                meaning = o.str("meaning_ja") ?: "",
                partOfSpeech = o.str("part_of_speech"),
                categoryKey = o.str("category_key"),
                exampleSentence = o.str("example_sentence"),
                exampleTranslation = o.str("example_translation"),
                extras = o.obj("extras"),
                language = o.str("language"),
            )
        }
    }
}

/** Row of `stickers` with its joined word. */
data class Sticker(
    val id: String,
    val wordId: String,
    val objectImageUrl: String?,
    val cutoutImageUrl: String?,
    val selfieImageUrl: String?,
    val caption: String?,
    val locationName: String?,
    val takenAtMs: Long,
    val captureType: String?,
    val word: Word?,
    val shelfKey: String? = null,
    val heroRole: String? = null,
    val placeholderImageUrl: String? = null,
) {
    /** The word's own picture (photo-surface.ts): the learner's choice, else the cut-out, else the photo, else the stand-in. */
    val heroPath: String?
        get() = when (heroRole) {
            "object" -> objectImageUrl ?: cutoutImageUrl ?: placeholderImageUrl
            "selfie" -> selfieImageUrl ?: cutoutImageUrl ?: objectImageUrl ?: placeholderImageUrl
            "placeholder" -> placeholderImageUrl ?: cutoutImageUrl ?: objectImageUrl
            else -> cutoutImageUrl ?: objectImageUrl ?: placeholderImageUrl
        }

    val isCutout: Boolean get() = heroPath != null && heroPath == cutoutImageUrl

    /** The word's category: a built-in key kept in `shelf_key` first, else the AI's category. */
    val categoryKey: String
        get() = Category.key(shelfKey?.takeIf { Category.isBuiltin(it) } ?: word?.categoryKey)

    val allPaths: List<String> get() = listOfNotNull(objectImageUrl, cutoutImageUrl, selfieImageUrl, placeholderImageUrl)

    companion object {
        fun from(o: JsonObject): Sticker? {
            val id = o.str("id") ?: return null
            return Sticker(
                id = id,
                wordId = o.str("word_id") ?: "",
                objectImageUrl = o.str("object_image_url"),
                cutoutImageUrl = o.str("cutout_image_url"),
                selfieImageUrl = o.str("selfie_image_url"),
                caption = o.str("caption"),
                locationName = o.str("location_name"),
                takenAtMs = parseDate(o.str("taken_at")) ?: System.currentTimeMillis(),
                captureType = o.str("capture_type"),
                word = Word.from(o.obj("word")),
                shelfKey = o.str("shelf_key"),
                heroRole = o.str("hero_role"),
                placeholderImageUrl = o.str("placeholder_image_url"),
            )
        }
    }
}

/** Row of `reviews` (SM-2 state). The web owns the schedule; the app only reads it and asks `gradeReview`. */
data class ReviewState(
    val id: String?,
    val stickerId: String,
    val ease: Double,
    val intervalDays: Int,
    val repetitions: Int?,
    val lastReviewedAtMs: Long?,
    val dueAtMs: Long?,
) {
    /** srs.ts retentionNow / stabilityOf (origin = last review, else the catch). */
    fun retention(takenAtMs: Long, nowMs: Long = System.currentTimeMillis()): Int {
        val last = lastReviewedAtMs ?: takenAtMs
        val dt = (nowMs - last) / 86_400_000.0
        if (dt <= 0) return 100
        val k = 1.0 / (2.5 * Math.log(1 / 0.9))
        val stability = maxOf(0.5, intervalDays.coerceAtLeast(1).toDouble() * maxOf(1.0, ease) * k)
        return Math.round((100 * Math.exp(-dt / stability)).coerceIn(0.0, 100.0)).toInt()
    }

    companion object Levels {
        /** memory.ts 6 levels (<30, <50, <70, <85, <95, else). */
        fun level(percent: Int): Int = when {
            percent < 30 -> 0
            percent < 50 -> 1
            percent < 70 -> 2
            percent < 85 -> 3
            percent < 95 -> 4
            else -> 5
        }
    }

    object Parse {
        fun from(o: JsonObject): ReviewState? {
            val sid = o.str("sticker_id") ?: return null
            return ReviewState(
                id = o.str("id"),
                stickerId = sid,
                ease = o.double("ease") ?: 2.5,
                intervalDays = o.int("interval_days") ?: 0,
                repetitions = o.int("repetitions"),
                lastReviewedAtMs = parseDate(o.str("last_reviewed_at")),
                dueAtMs = parseDate(o.str("due_at")),
            )
        }
    }
}

/** A name the AI found for something in the photo (or a typed word), lenient like scan-detect-parse.ts. */
data class Candidate(
    val headword: String,
    val zhuyin: String,
    val pinyin: String,
    val meaning: String,
    val pos: String,
    val point: Pair<Double, Double>,
    val confidence: Double,
    val distinction: String,
    val register: String?,
    val group: Int?,
    val categoryKey: String?,
) {
    val key: String get() = "$headword|${group ?: -1}|${point.first.toInt()}"

    companion object {
        fun from(o: JsonObject): Candidate? {
            val head = o.str("headword") ?: return null
            val pts = o.arr("point")?.mapNotNull { (it as? kotlinx.serialization.json.JsonPrimitive)?.content?.toDoubleOrNull() } ?: emptyList()
            var p = if (pts.size >= 2) pts[0] to pts[1] else 500.0 to 500.0
            if (p.first <= 1 && p.second <= 1) p = p.first * 1000 to p.second * 1000
            var conf = o.double("confidence") ?: 0.8
            if (conf > 1) conf /= 100
            return Candidate(
                headword = head,
                zhuyin = o.str("zhuyin") ?: o.str("reading_zhuyin") ?: "",
                pinyin = o.str("pinyin") ?: "",
                meaning = o.str("meaning_ja") ?: "",
                pos = o.str("pos") ?: "",
                point = p.first.coerceIn(0.0, 1000.0) to p.second.coerceIn(0.0, 1000.0),
                confidence = conf.coerceIn(0.0, 1.0),
                distinction = o.str("distinction") ?: "",
                register = o.str("register"),
                group = o.int("group"),
                categoryKey = o.str("category_key"),
            )
        }
    }
}

/** Postgres timestamps come with 0–6 fractional digits and an offset (or none = UTC). */
fun parseDate(raw: String?): Long? {
    if (raw.isNullOrBlank()) return null
    var s = raw.trim().replace(' ', 'T')
    val hasZone = s.endsWith("Z") || s.substring(minOf(10, s.length)).let { it.contains('+') || it.contains('-') }
    if (!hasZone) s += "Z"
    return runCatching { OffsetDateTime.parse(s, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant().toEpochMilli() }.getOrNull()
        ?: runCatching { Instant.parse(s).toEpochMilli() }.getOrNull()
}

fun isoNow(): String = Instant.now().toString()
