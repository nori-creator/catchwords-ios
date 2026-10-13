package com.rork.catchwordsandroid.ui.widget

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.rork.catchwordsandroid.MainActivity
import com.rork.catchwordsandroid.data.L10n
import com.rork.catchwordsandroid.data.WidgetBridge

private val Accent = ColorProvider(Color(0xFF0083FF))
private val Ink = ColorProvider(Color(0xFF0B121A))
private val Sub = ColorProvider(Color(0xFF5C646F))

private fun t(ja: String, en: String, zh: String) = when (L10n.current) { "ja" -> ja; "zh-TW" -> zh; else -> en }

/** 「今日の単語」 — a word from the learner's own collection, with its photo (iOS TodayWordWidget). */
class TodayWordWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(DpSize(150.dp, 150.dp), DpSize(300.dp, 150.dp)))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val today = WidgetBridge.read(context)
        val file = WidgetBridge.imageFile(context)
        val bmp = if (file.exists()) runCatching { BitmapFactory.decodeFile(file.path) }.getOrNull() else null
        provideContent { Content(today, bmp) }
    }

    @Composable
    private fun Content(today: WidgetBridge.Today?, bmp: android.graphics.Bitmap?) {
        val wide = LocalSize.current.width >= 280.dp
        val link = Intent(Intent.ACTION_VIEW, Uri.parse(today?.let { "catchwords://word/${it.stickerId}" } ?: "catchwords://review"))
            .setClassName("com.nori.catchwords", MainActivity::class.java.name)
        Box(
            GlanceModifier.fillMaxSize().background(Color.White).cornerRadius(22.dp).padding(14.dp).clickable(actionStartActivity(link)),
        ) {
            if (today == null) {
                Column {
                    Text(t("今日の単語", "Today's word", "今日單字"), style = TextStyle(color = Accent, fontSize = 12.sp, fontWeight = FontWeight.Bold))
                    Spacer(GlanceModifier.height(8.dp))
                    Text(t("カメラで最初の単語を集めよう", "Catch your first word with the camera", "用相機收集第一個單字吧"), style = TextStyle(color = Ink, fontSize = 14.sp, fontWeight = FontWeight.Medium))
                }
            } else {
                Row(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    Column(GlanceModifier.defaultWeight()) {
                        Text(t("今日の単語", "Today's word", "今日單字"), style = TextStyle(color = Accent, fontSize = 12.sp, fontWeight = FontWeight.Bold))
                        Spacer(GlanceModifier.height(6.dp))
                        if (today.reading.isNotBlank()) Text(today.reading, style = TextStyle(color = Sub, fontSize = 11.sp), maxLines = 1)
                        Text(today.headword, style = TextStyle(color = Ink, fontSize = if (wide) 30.sp else 26.sp, fontWeight = FontWeight.Bold), maxLines = 1)
                        Text(today.meaning, style = TextStyle(color = Sub, fontSize = 12.sp), maxLines = 2)
                        if (today.dueCount > 0) {
                            Spacer(GlanceModifier.height(6.dp))
                            Text(t("復習 ${today.dueCount}枚", "${today.dueCount} to review", "待複習 ${today.dueCount} 張"), style = TextStyle(color = Accent, fontSize = 11.sp, fontWeight = FontWeight.Bold))
                        }
                    }
                    if (bmp != null) {
                        Spacer(GlanceModifier.width(8.dp))
                        Image(ImageProvider(bmp), contentDescription = today.headword, contentScale = ContentScale.Fit, modifier = GlanceModifier.size(if (wide) 110.dp else 64.dp))
                    }
                }
            }
        }
    }
}

class TodayWordWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodayWordWidget()
}
