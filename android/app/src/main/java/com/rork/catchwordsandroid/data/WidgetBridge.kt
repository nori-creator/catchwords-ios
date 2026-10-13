package com.rork.catchwordsandroid.data

import android.content.Context
import android.graphics.Bitmap
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.toBitmap
import com.rork.catchwordsandroid.ui.widget.TodayWordWidget
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Calendar

/** 「今日の単語」 for the home-screen widget: one word from the learner's own dex, with its picture (iOS WidgetBridge). */
object WidgetBridge {
    private const val KEY = "widget.today"

    data class Today(val stickerId: String, val headword: String, val reading: String, val meaning: String, val dueCount: Int)

    fun read(context: Context): Today? {
        val p = context.getSharedPreferences("cw.prefs", Context.MODE_PRIVATE)
        val raw = p.getString(KEY, null) ?: return null
        val parts = raw.split("\u001F")
        if (parts.size < 5) return null
        return Today(parts[0], parts[1], parts[2], parts[3], parts[4].toIntOrNull() ?: 0)
    }

    fun imageFile(context: Context) = File(context.filesDir, "widget-today.png")

    /** Picks today's word (the same all day), saves its picture and redraws the widgets. */
    suspend fun refresh(context: Context) {
        val st = AppGraph.dex.state.value
        val list = st.stickers.filter { it.word != null }
        val p = context.getSharedPreferences("cw.prefs", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val due = st.reviews.values.count { (it.dueAtMs ?: Long.MAX_VALUE) <= now }
        if (list.isEmpty()) {
            p.edit().remove(KEY).apply()
            imageFile(context).delete()
        } else {
            val day = Calendar.getInstance().get(Calendar.DAY_OF_YEAR) + Calendar.getInstance().get(Calendar.YEAR) * 366
            val s = list.sortedBy { it.id }[day % list.size]
            val w = s.word!!
            val reading = if (AppGraph.readingStyle == "pinyin") w.pinyin ?: w.readingZhuyin ?: "" else w.readingZhuyin ?: w.pinyin ?: ""
            val value = listOf(s.id, w.headword, reading, ReaderLanguage.gloss(w.meaning), due.toString()).joinToString("\u001F") { it.replace("\u001F", " ") }
            val changed = p.getString(KEY, null)?.substringBefore("\u001F") != s.id
            p.edit().putString(KEY, value).apply()
            val url = AppGraph.dex.url(s.heroPath)
            if (url != null && (changed || !imageFile(context).exists())) {
                withContext(Dispatchers.IO) {
                    runCatching {
                        val res = SingletonImageLoader.get(context).execute(ImageRequest.Builder(context).data(url).allowHardware(false).size(480).build())
                        val bmp = (res as? SuccessResult)?.image?.toBitmap() ?: return@runCatching
                        imageFile(context).outputStream().use { ImageTools.resized(bmp, 480).compress(Bitmap.CompressFormat.PNG, 100, it) }
                    }
                }
            }
        }
        runCatching { TodayWordWidget().updateAll(context) }
    }
}
