package com.rork.catchwordsandroid.ui.screens

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.BitmapDrawable
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.rork.catchwordsandroid.data.Sticker
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.ui.components.StickerImage
import com.rork.catchwordsandroid.ui.components.pressable
import com.rork.catchwordsandroid.ui.theme.CW
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline
import java.text.DateFormat
import java.util.Calendar
import java.util.Date

private fun dayStart(ms: Long): Long = Calendar.getInstance().apply {
    timeInMillis = ms
    set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
}.timeInMillis

/** The dex's map (iOS DexView map mode): one day at a time, a pin per catch, joined in the order they were caught. */
@Composable
fun DexMap(stickers: List<Sticker>, modifier: Modifier = Modifier, onOpenWord: (String) -> Unit) {
    val context = LocalContext.current
    val days = remember(stickers) { stickers.map { dayStart(it.takenAtMs) }.distinct().sortedDescending() }
    var day by rememberSaveable { mutableStateOf<Long?>(null) }
    LaunchedEffect(days) { if (day == null || day !in days) day = days.firstOrNull() }
    val items = remember(stickers, day) { stickers.filter { dayStart(it.takenAtMs) == day }.sortedBy { it.takenAtMs } }
    val located = remember(items) { items.filter { it.lat != null && it.lng != null } }
    var selected by remember { mutableStateOf<String?>(null) }

    val map = remember {
        Configuration.getInstance().userAgentValue = context.packageName
        MapView(context).apply {
            setTileSource(TileSourceFactory.MAPNIK)
            setMultiTouchControls(true)
            zoomController.setVisibility(org.osmdroid.views.CustomZoomButtonsController.Visibility.NEVER)
            controller.setZoom(4.0)
            controller.setCenter(GeoPoint(25.04, 121.56))
        }
    }
    DisposableEffect(Unit) {
        map.onResume()
        onDispose { map.onPause(); map.onDetach() }
    }
    LaunchedEffect(located) {
        map.overlays.clear()
        if (located.size >= 2) {
            map.overlays += Polyline(map).apply {
                setPoints(located.map { GeoPoint(it.lat!!, it.lng!!) })
                outlinePaint.color = android.graphics.Color.argb(170, 0, 131, 255)
                outlinePaint.strokeWidth = 8f
                outlinePaint.strokeCap = Paint.Cap.ROUND
            }
        }
        located.forEachIndexed { i, s ->
            map.overlays += Marker(map).apply {
                position = GeoPoint(s.lat!!, s.lng!!)
                title = s.word?.headword
                icon = BitmapDrawable(context.resources, pinBitmap(i + 1, context.resources.displayMetrics.density))
                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                setOnMarkerClickListener { _, _ -> selected = s.id; true }
            }
        }
        map.invalidate()
        when (located.size) {
            0 -> Unit
            1 -> { map.controller.setZoom(16.0); map.controller.setCenter(GeoPoint(located[0].lat!!, located[0].lng!!)) }
            else -> map.post {
                val box = BoundingBox.fromGeoPoints(located.map { GeoPoint(it.lat!!, it.lng!!) })
                runCatching { map.zoomToBoundingBox(box.increaseByScale(1.5f), false) }
            }
        }
    }

    Box(modifier) {
        AndroidView({ map }, Modifier.fillMaxSize())
        Column(Modifier.fillMaxWidth().align(Alignment.TopCenter)) {
            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(days) { d ->
                    val on = d == day
                    Text(
                        DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(d)),
                        color = if (on) Color.White else CW.foreground, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.shadow(4.dp, RoundedCornerShape(50)).clip(RoundedCornerShape(50)).background(if (on) CW.primary else CW.card)
                            .pressable { day = d; selected = null }.padding(horizontal = 14.dp, vertical = 9.dp),
                    )
                }
            }
            if (items.isNotEmpty() && located.isEmpty()) {
                Text(
                    tr("この日は場所の記録がありません", "No places recorded this day", "這天沒有地點紀錄"),
                    color = CW.foreground, fontSize = 14.sp, fontWeight = FontWeight.Medium,
                    modifier = Modifier.align(Alignment.CenterHorizontally).clip(RoundedCornerShape(50)).background(CW.card.copy(alpha = 0.95f)).padding(horizontal = 16.dp, vertical = 10.dp),
                )
            }
        }
        LazyRow(
            Modifier.align(Alignment.BottomCenter).padding(bottom = 96.dp),
            contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(items, key = { it.id }) { s ->
                val on = s.id == selected
                Column(
                    Modifier.width(112.dp).shadow(8.dp, RoundedCornerShape(18.dp)).clip(RoundedCornerShape(18.dp)).background(CW.card)
                        .border(2.dp, if (on) CW.primary else Color.Transparent, RoundedCornerShape(18.dp))
                        .pressable { if (on) onOpenWord(s.id) else { selected = s.id; s.lat?.let { la -> s.lng?.let { lo -> map.controller.animateTo(GeoPoint(la, lo)) } } } }
                        .padding(8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    StickerImage(s, Modifier.size(72.dp).clip(RoundedCornerShape(12.dp)).background(CW.surface2), contentScale = ContentScale.Fit, emojiSize = 30)
                    Spacer(Modifier.height(4.dp))
                    Text(s.word?.headword.orEmpty(), color = CW.foreground, fontSize = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                    Text(
                        DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(s.takenAtMs)),
                        color = CW.muted, fontSize = 11.sp, maxLines = 1,
                    )
                }
            }
        }
    }
}

/** A round blue pin with its order number. */
private fun pinBitmap(n: Int, density: Float): Bitmap {
    val size = (30 * density).toInt()
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val c = Canvas(bmp)
    val p = Paint(Paint.ANTI_ALIAS_FLAG)
    p.color = android.graphics.Color.WHITE
    c.drawCircle(size / 2f, size / 2f, size / 2f, p)
    p.color = android.graphics.Color.rgb(0, 131, 255)
    c.drawCircle(size / 2f, size / 2f, size / 2f - 3 * density, p)
    p.color = android.graphics.Color.WHITE
    p.textAlign = Paint.Align.CENTER
    p.textSize = 13 * density
    p.isFakeBoldText = true
    c.drawText("$n", size / 2f, size / 2f - (p.descent() + p.ascent()) / 2, p)
    return bmp
}
