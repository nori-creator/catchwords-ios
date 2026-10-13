package com.rork.catchwordsandroid.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Locale

/**
 * The display language (ja / en / zh-TW), like iOS `L10n`. It follows the account's `ui_language`
 * once the profile is read, else the device language.
 */
object L10n {
    private const val PREF_KEY = "ui.lang"
    private val _lang = MutableStateFlow("ja")
    val lang: StateFlow<String> = _lang.asStateFlow()
    private var prefs: android.content.SharedPreferences? = null

    val current: String get() = _lang.value

    fun init(context: Context) {
        prefs = context.getSharedPreferences("cw.prefs", Context.MODE_PRIVATE)
        val saved = prefs?.getString(PREF_KEY, null)
        _lang.value = saved ?: normalize(Locale.getDefault().toLanguageTag())
    }

    fun set(raw: String) {
        val v = normalize(raw)
        _lang.value = v
        prefs?.edit()?.putString(PREF_KEY, v)?.apply()
    }

    fun normalize(raw: String): String {
        val l = raw.lowercase()
        return when {
            l.startsWith("ja") -> "ja"
            l.startsWith("zh") -> "zh-TW"
            else -> "en"
        }
    }

    val locale: Locale
        get() = when (current) {
            "ja" -> Locale.JAPANESE
            "zh-TW" -> Locale.TRADITIONAL_CHINESE
            else -> Locale.ENGLISH
        }
}

/** A string in the display language. Traditional Chinese falls back to English when not given. */
fun tr(ja: String, en: String, zh: String? = null): String = when (L10n.current) {
    "ja" -> ja
    "zh-TW" -> zh ?: en
    else -> en
}
