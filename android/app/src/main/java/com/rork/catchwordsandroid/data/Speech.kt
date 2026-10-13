package com.rork.catchwordsandroid.data

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.speech.tts.TextToSpeech
import com.rork.catchwordsandroid.R
import java.util.Locale

/** Reads words aloud in the learning language (device TTS) and plays the app's short sound effects. */
class Speech(context: Context) {
    private var ready = false
    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status -> ready = status == TextToSpeech.SUCCESS }

    private val pool: SoundPool = SoundPool.Builder()
        .setMaxStreams(3)
        .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
        .build()
    private val sounds: Map<Sfx, Int> = mapOf(
        Sfx.SHUTTER to pool.load(context, R.raw.cc_shutter, 1),
        Sfx.POP to pool.load(context, R.raw.cc_pop, 1),
        Sfx.CATCH to pool.load(context, R.raw.el_catch_impact, 1),
        Sfx.CELEBRATE to pool.load(context, R.raw.el_celebrate_sting, 1),
        Sfx.TICK to pool.load(context, R.raw.cc_tick, 1),
    )

    enum class Sfx { SHUTTER, POP, CATCH, CELEBRATE, TICK }

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
        sounds[sfx]?.let { pool.play(it, volume, volume, 1, 0, 1f) }
    }
}
