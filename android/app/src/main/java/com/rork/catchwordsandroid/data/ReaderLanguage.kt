package com.rork.catchwordsandroid.data

import kotlinx.serialization.json.JsonObject

/** This reader's explanation of a word (`word_explanations`, written in the display language). */
data class Explanation(
    val explainLang: String,
    val l1: String,
    val meaning: String,
    val exampleTranslation: String?,
    val extras: JsonObject?,
) {
    /** web `hasExtrasContent`: anything beyond the language marks. */
    val hasContent: Boolean
        get() {
            val e = extras ?: return false
            return e.entries.any { (k, v) ->
                k != "explain_lang" && k != "explain_l1" && when (v) {
                    is kotlinx.serialization.json.JsonArray -> v.isNotEmpty()
                    is JsonObject -> v.isNotEmpty()
                    is kotlinx.serialization.json.JsonPrimitive -> v.isString && v.content.isNotBlank()
                    else -> false
                }
            }
        }

    companion object {
        fun from(o: JsonObject?): Explanation? {
            o ?: return null
            return Explanation(
                explainLang = o.str("explain_lang") ?: "",
                l1 = o.str("l1") ?: "",
                meaning = o.str("meaning") ?: "",
                exampleTranslation = o.str("example_translation"),
                extras = o.obj("extras"),
            )
        }
    }
}

/**
 * Server-written text shown only in the reader's language (port of the web's word-explanation.ts rules, simplified):
 * the reader's own explanation wins, then a meaning written for this reader, then the shared row where it reads right.
 */
object ReaderLanguage {
    private fun isKana(c: Char) = c in '\u3040'..'\u30FF'
    private fun isHan(c: Char) = Character.UnicodeScript.of(c.code) == Character.UnicodeScript.HAN
    private fun isHangul(c: Char) = Character.UnicodeScript.of(c.code) == Character.UnicodeScript.HANGUL

    /** True when the text is clearly in another language than the reader's. */
    fun looksWrong(text: String?, reader: String, hanOnlyOk: Boolean = true): Boolean {
        val t = text?.trim().orEmpty()
        if (t.isEmpty()) return false
        val kana = t.any(::isKana)
        val han = t.any(::isHan)
        val latin = t.any { it in 'a'..'z' || it in 'A'..'Z' }
        if (t.any(::isHangul)) return true
        return when (reader) {
            "ja" -> !kana && !(hanOnlyOk && han && !latin) && (latin || han)
            "zh-TW" -> kana || (!han && latin)
            else -> kana || han
        }
    }

    fun resolve(shared: Word, explanation: Explanation?, readerMeaning: String?, reader: String): Word {
        val meaning = listOfNotNull(explanation?.meaning, readerMeaning, shared.meaning)
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() && !looksWrong(it, reader) } ?: ""
        val translation = listOfNotNull(explanation?.exampleTranslation, shared.exampleTranslation)
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() && !looksWrong(it, reader, hanOnlyOk = false) }
        var extras = if (explanation != null) explanation.extras else shared.extras
        val mark = extras?.str("explain_lang")
        if (mark != null && mark != reader) extras = null
        return shared.copy(meaning = meaning, exampleTranslation = translation, extras = extras)
    }

    /** web `needsGeneration`: no explanation for exactly this reader yet (or it is empty). */
    fun needsGeneration(p: Explanation?, lang: String, l1: String): Boolean {
        p ?: return true
        if (p.explainLang != lang || p.l1 != l1) return true
        if (p.meaning.isBlank()) return true
        return !p.hasContent
    }

    /** A meaning as a short gloss for the quiz and tiles (display only). */
    fun gloss(text: String, limit: Int? = null): String {
        val t = text.trim()
        val latin = t.any { it.isLetter() && it.code < 128 } && t.none { it.code >= 0x3000 }
        val cap = limit ?: if (latin) 40 else 20
        if (t.length <= cap) return t
        val seps = if (latin) listOf("; ", ";", ". ", " (", "(", ": ", " - ", " — ", "\n")
        else listOf("。", "；", ";", "、", "，", ",", "／", "/", "（", "(", "：", ":", "\n", "．")
        var cut = t.length
        for (s in seps) {
            val i = t.indexOf(s)
            if (i in 1 until cut) cut = i
        }
        val first = t.substring(0, cut).trim()
        if (first.isNotEmpty() && first.length <= cap) return first
        return first.take(cap - 1).trim() + "…"
    }
}
