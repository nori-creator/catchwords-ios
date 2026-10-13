package com.rork.catchwordsandroid.data

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.speech.tts.TextToSpeech
import com.rork.catchwordsandroid.R
import java.util.Locale

/** Reads words aloud in the learning language (device TTS) and plays the app's sound effects (the iOS set). */
class Speech(context: Context) {
    private var ready = false
    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status -> ready = status == TextToSpeech.SUCCESS }

    private val pool: SoundPool = SoundPool.Builder()
        .setMaxStreams(6)
        .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
        .build()

    /** Every sound with the iOS app's gain (SoundService.gain), capped to SoundPool's 0–1. */
    enum class Sfx(val res: Int, val gain: Float) {
        SHUTTER(R.raw.cc_shutter, 1f),
        POP(R.raw.cc_pop, 0.9f),
        TICK(R.raw.cc_tick, 0.9f),
        SCAN_START(R.raw.cc_scan_start, 0.9f),
        FOUND(R.raw.cc_found, 0.9f),
        REVEAL(R.raw.cc_reveal, 1f),
        TWINKLE(R.raw.cc_twinkle, 0.9f),
        LAND(R.raw.cc_land, 1f),
        CATCH(R.raw.el_catch_impact, 1f),
        CELEBRATE(R.raw.el_celebrate_sting, 1f),
        BOOK_OPEN(R.raw.el_book_open, 1f),
        SLIDE(R.raw.el_gallery_slide, 1f),
        JAR_CORK(R.raw.el_jar_cork, 0.9f),
        CUT_TRACE(R.raw.el_cut_trace, 0.7f),
        STICKER_LIFT(R.raw.el_sticker_lift, 0.8f),
        LAND_BOUNCE(R.raw.el_land_bounce, 1f),
        PON_OPEN(R.raw.pon_bubble_open, 0.9f),
        PON_BACK(R.raw.pon_bubble_back, 0.8f),
    }

    private val sounds: Map<Sfx, Int> = Sfx.entries.associateWith { pool.load(context, it.res, 1) }

    fun speak(text: String, target: String) {
        if (!ready || text.isBlank()) return
        tts.language = when (target) {
            "en" -> Locale.US
            "ja" -> Locale.JAPAN
            else -> Locale.TRADITIONAL_CHINESE
        }
        tts.setSpeechRate(0.9f)
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, text)
    }

    fun play(sfx: Sfx, volume: Float = 0.7f) {
        val v = (volume * sfx.gain).coerceIn(0f, 1f)
        sounds[sfx]?.let { pool.play(it, v, v, 1, 0, 1f) }
    }
}
