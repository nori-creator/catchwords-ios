package com.rork.catchwordsandroid.ui.screens

import android.graphics.Bitmap
import android.os.Build
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.VolumeUp
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.MenuBook
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.catchwordsandroid.data.AppGraph
import com.rork.catchwordsandroid.data.Candidate
import com.rork.catchwordsandroid.data.OwnedWord
import com.rork.catchwordsandroid.data.ReaderLanguage
import com.rork.catchwordsandroid.data.Sticker
import com.rork.catchwordsandroid.data.str
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.ui.CaptureUiState
import com.rork.catchwordsandroid.ui.components.PrimaryButton
import com.rork.catchwordsandroid.ui.components.StickerImage
import com.rork.catchwordsandroid.ui.components.pressable
import com.rork.catchwordsandroid.ui.components.readingOf
import com.rork.catchwordsandroid.ui.theme.CW
import java.text.DateFormat
import java.util.Date
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/** A cut-out with a white sticker edge: its silhouette drawn white underneath, nudged round in a circle (iOS StickerCutout). */
@Composable
fun StickerCutout(image: Bitmap, modifier: Modifier = Modifier, edge: Dp = 7.dp) {
    val bmp = remember(image) { image.asImageBitmap() }
    Box(modifier.padding(edge).shadow(0.dp), contentAlignment = Alignment.Center) {
        Box(
            Modifier.graphicsLayer {
                shadowElevation = 0f
            },
        ) {
            for (i in 0 until 12) {
                val a = i / 12.0 * 2 * PI
                Image(
                    bmp, null, contentScale = ContentScale.Fit, colorFilter = ColorFilter.tint(Color.White),
                    modifier = Modifier.offset(x = edge * cos(a).toFloat(), y = edge * sin(a).toFloat()),
                )
            }
            Image(bmp, null, contentScale = ContentScale.Fit)
        }
    }
}

/** Slowly turning god-rays behind the sticker (reward stage). */
@Composable
fun LightRays(modifier: Modifier = Modifier) {
    val t = rememberInfiniteTransition(label = "rays")
    val spin by t.animateFloat(0f, (2 * PI).toFloat(), infiniteRepeatable(tween(104_000, easing = LinearEasing)), label = "spin")
    Canvas(modifier.then(if (Build.VERSION.SDK_INT >= 31) Modifier.blur(18.dp) else Modifier)) {
        val c = Offset(size.width / 2, size.height * 0.4f)
        val r = max(size.width, size.height) * 1.2f
        for (i in 0 until 14) {
            val a = i / 14.0 * 2 * PI + spin
            val w = 0.07 + 0.03 * sin(i * 1.7)
            val p = Path().apply {
                moveTo(c.x, c.y)
                lineTo(c.x + (cos(a - w) * r).toFloat(), c.y + (sin(a - w) * r).toFloat())
                lineTo(c.x + (cos(a + w) * r).toFloat(), c.y + (sin(a + w) * r).toFloat())
                close()
            }
            val color = if (i % 2 == 0) Color(0xFF7FD8FF) else Color(0xFF6FE3C8)
            drawPath(p, Brush.radialGradient(listOf(color.copy(alpha = 0f), color.copy(alpha = 0.28f), color.copy(alpha = 0f)), c, r * 0.7f))
        }
    }
}

/** Paper confetti that bursts once and flutters down (iOS Confetti). */
@Composable
fun Confetti(active: Boolean, modifier: Modifier = Modifier) {
    var start by remember { mutableLongStateOf(0L) }
    var now by remember { mutableLongStateOf(0L) }
    LaunchedEffect(active) {
        if (!active) return@LaunchedEffect
        start = withFrameMillis { it }
        while (true) {
            now = withFrameMillis { it }
            if (now - start > 3300) break
        }
    }
    val colors = remember { listOf(Color(0xFFF4B93C), Color(0xFF64E0FF), Color(0xFFFF7EB6), Color(0xFFA78BFA), Color(0xFF4ADE80), Color.White) }
    Canvas(modifier) {
        if (start == 0L) return@Canvas
        val t = (now - start) / 1000.0
        if (t >= 3.2 || t < 0) return@Canvas
        val dp = density
        for (i in 0 until 70) {
            val seed = i.toDouble()
            val ang = seed * 2.399
            val speed = 180 + (seed * 37) % 220
            val x0 = size.width / 2
            val y0 = size.height * 0.42f
            val vx = cos(ang) * speed
            val vy = sin(ang) * speed - 160
            val x = x0 + ((vx * t * 1.1 + sin(t * 3 + seed) * 12) * dp).toFloat()
            val y = y0 + ((vy * t + 260 * t * t) * dp).toFloat()
            val alpha = max(0.0, 1 - t / 3.2).toFloat()
            val w = (5 + seed % 4).toFloat() * dp
            val h = ((3 + seed % 3) * abs(cos(t * 6 + seed)) + 1).toFloat() * dp
            translate(x, y) {
                rotate(Math.toDegrees(t * (4 + seed % 5) + seed).toFloat(), Offset.Zero) {
                    drawRect(colors[i % colors.size].copy(alpha = alpha), Offset(-w / 2, -h / 2), Size(w, h))
                }
            }
        }
    }
}

/** The blurred, darkened photo behind the reward (the Stickr look): the sticker is the only sharp thing. */
@Composable
private fun Backdrop(photo: Bitmap?) {
    Box(Modifier.fillMaxSize().background(CW.navyDeep)) {
        if (photo != null) {
            Image(
                photo.asImageBitmap(), null, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().scale(1.1f).then(if (Build.VERSION.SDK_INT >= 31) Modifier.blur(28.dp) else Modifier.alpha(0.55f)),
            )
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.32f)))
        }
    }
}

/**
 * The word was chosen (iOS CatchCelebrationView): the object's cut-out as a white-edged sticker over the blurred photo,
 * the word with its reading and meaning, its voice played once, and 「図鑑に追加」.
 */
@Composable
fun CelebrateStage(ui: CaptureUiState, onBack: () -> Unit, onAdd: (String) -> Unit) {
    val c = ui.picked ?: return
    val haptic = LocalHapticFeedback.current
    val pop = remember { Animatable(0f) }
    var confetti by remember { mutableStateOf(false) }
    var caption by rememberSaveable(c.headword) { mutableStateOf("") }
    LaunchedEffect(c.headword) {
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        confetti = true
        pop.animateTo(1f, spring(dampingRatio = 0.68f, stiffness = Spring.StiffnessLow))
    }
    val busy = ui.isSaving
    Box(Modifier.fillMaxSize()) {
        Backdrop(ui.photo)
        LightRays(Modifier.fillMaxSize().alpha(0.55f * pop.value.coerceIn(0f, 1f)))
        Confetti(confetti, Modifier.fillMaxSize())
        BoxWithConstraints(Modifier.fillMaxSize().statusBarsPadding().padding(bottom = 84.dp)) {
            val side = minOf(maxWidth * 0.72f, 320.dp)
            Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
                    Row(
                        Modifier.height(44.dp).alpha(if (busy) 0.4f else 1f).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.14f))
                            .pressable(enabled = !busy, onClick = onBack).padding(horizontal = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, null, tint = Color.White, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(tr("戻る", "Back", "返回"), color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Box(
                        Modifier.graphicsLayer {
                            val s = 0.55f + 0.45f * pop.value
                            scaleX = s
                            scaleY = s
                            rotationZ = -10f + 7f * pop.value
                            alpha = pop.value.coerceIn(0f, 1f)
                        },
                    ) {
                        val cut = ui.cutout
                        if (cut != null) {
                            StickerCutout(cut, Modifier.sizeIn(maxWidth = side, maxHeight = side).shadow(0.dp))
                        } else if (ui.photo != null) {
                            Box(
                                Modifier.size(side * 0.86f + 14.dp).shadow(14.dp, RoundedCornerShape(30.dp)).clip(RoundedCornerShape(30.dp)).background(Color.White).padding(7.dp),
                            ) {
                                Image(ui.photo.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(24.dp)))
                                if (ui.isCutting) {
                                    Row(
                                        Modifier.align(Alignment.BottomCenter).padding(bottom = 16.dp).clip(RoundedCornerShape(50)).background(CW.toastInk.copy(alpha = 0.78f))
                                            .padding(horizontal = 12.dp, vertical = 6.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        CircularProgressIndicator(Modifier.size(12.dp), color = Color.White, strokeWidth = 2.dp)
                                        Spacer(Modifier.width(6.dp))
                                        Text(tr("切り抜いています", "Cutting out", "正在去背"), color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                                    }
                                }
                            }
                        } else {
                            Box(Modifier.size(side * 0.8f).clip(RoundedCornerShape(30.dp)).background(CW.brandGradient), contentAlignment = Alignment.Center) {
                                Text(c.headword, color = Color.White, fontSize = 64.sp, fontWeight = FontWeight.Black)
                            }
                        }
                    }
                }
                WordCard(ui, c, caption, { caption = it }, busy, Modifier.padding(horizontal = 12.dp).padding(bottom = 10.dp).graphicsLayer {
                    translationY = (1 - pop.value) * 40.dp.toPx()
                    alpha = pop.value.coerceIn(0f, 1f)
                }) { onAdd(caption) }
            }
        }
    }
}

@Composable
private fun WordCard(ui: CaptureUiState, c: Candidate, caption: String, onCaption: (String) -> Unit, busy: Boolean, modifier: Modifier, onAdd: () -> Unit) {
    val meaning = ReaderLanguage.shown(ui.card?.str("meaning_ja")?.trim().orEmpty(), c.meaning)
    Column(
        modifier.fillMaxWidth().shadow(20.dp, RoundedCornerShape(28.dp)).clip(RoundedCornerShape(28.dp)).background(CW.card).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(tr("新しいことばをキャッチ！", "New word caught!", "收集到新單字！"), color = CW.primaryInk, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(readingOf(ui.card?.str("reading_zhuyin") ?: c.zhuyin, ui.card?.str("pinyin") ?: c.pinyin), color = CW.primaryInk, fontSize = 14.sp)
                Text(c.headword, color = CW.foreground, fontSize = 36.sp, fontWeight = FontWeight.SemiBold)
            }
            PronounceCircle(c.headword, 48.dp)
        }
        Text(meaning, color = CW.muted, fontSize = 17.sp, fontWeight = FontWeight.Medium, maxLines = 3)
        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(CW.paper).border(1.dp, CW.paperEdge, RoundedCornerShape(14.dp)).padding(horizontal = 12.dp, vertical = 10.dp)) {
            if (caption.isEmpty()) Text(tr("ひとこと（任意）", "A note (optional)", "備註（選填）"), fontFamily = CW.hand, color = CW.muted, fontSize = 16.sp)
            BasicTextField(caption, { onCaption(it.take(80)) }, singleLine = true, textStyle = TextStyle(fontFamily = CW.hand, fontSize = 16.sp, color = CW.foreground), cursorBrush = SolidColor(CW.primary), modifier = Modifier.fillMaxWidth())
        }
        if (ui.place?.name != null) {
            Text("📍 ${ui.place.name}", color = CW.muted, fontSize = 12.sp)
        }
        PrimaryButton(tr("図鑑に追加", "Add to dex", "加入圖鑑"), icon = Icons.Outlined.Check, enabled = !busy, loading = busy, onClick = onAdd)
    }
}

@Composable
fun PronounceCircle(text: String, size: Dp = 42.dp) {
    Box(
        Modifier.size(max(size.value, 44f).dp).pressable(pressedScale = 0.9f) { AppGraph.speech.speak(text, AppGraph.profile.target) },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(size).shadow(6.dp, CircleShape, spotColor = CW.primary).clip(CircleShape).background(CW.primary), contentAlignment = Alignment.Center) {
            Icon(Icons.AutoMirrored.Outlined.VolumeUp, tr("発音を聞く", "Listen", "聆聽發音"), tint = Color.White, modifier = Modifier.size(size * 0.45f))
        }
    }
}

/** 再会！ — the word is already in the dex: this photo is added to it (recorded as soon as the screen opens). */
@Composable
fun ReencounterStage(ui: CaptureUiState, onSeeInDex: (String) -> Unit, onAgain: () -> Unit) {
    val o = ui.owned ?: return
    val pop = remember { Animatable(0.85f) }
    LaunchedEffect(o.stickerId) { pop.animateTo(1f, spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessMediumLow)) }
    Column(
        Modifier.fillMaxSize().background(CW.background).statusBarsPadding().verticalScroll(rememberScrollState()).padding(16.dp).padding(bottom = 110.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Column(
            Modifier.fillMaxWidth().scale(pop.value).shadow(10.dp, RoundedCornerShape(28.dp)).clip(RoundedCornerShape(28.dp)).background(CW.card).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(Modifier.fillMaxWidth().aspectRatio(4f / 3f).clip(RoundedCornerShape(24.dp)).background(CW.surface2)) {
                val img = ui.cutout ?: ui.photo
                if (img != null) {
                    if (ui.cutout != null) {
                        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(Color.White, CW.accent))), contentAlignment = Alignment.Center) {
                            StickerCutout(img, Modifier.fillMaxSize().padding(18.dp))
                        }
                    } else {
                        Image(img.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    }
                }
                Text(
                    tr("再会！", "Met again!", "重逢！"), color = CW.primaryInk, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.align(Alignment.BottomStart).padding(12.dp).clip(RoundedCornerShape(50)).background(CW.card.copy(alpha = 0.95f)).padding(horizontal = 14.dp, vertical = 8.dp),
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(readingOf(o.readingZhuyin, o.pinyin), color = CW.primaryInk, fontSize = 14.sp)
                    Text(o.headword, color = CW.foreground, fontSize = 34.sp, fontWeight = FontWeight.Bold)
                }
                PronounceCircle(o.headword, 44.dp)
            }
            Text(ReaderLanguage.shown(o.meaning), color = CW.foreground, fontSize = 20.sp, fontWeight = FontWeight.Medium)
            val first = o.takenAtMs?.let { DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(it)) }
            Text(
                listOfNotNull(
                    first?.let { tr("初めて出会った日: $it", "First met: $it", "初次相遇：$it") },
                    o.locationName?.let { tr("場所: $it", "At: $it", "地點：$it") },
                ).joinToString(" · "),
                color = CW.muted, fontSize = 13.sp,
            )
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(CW.accent).padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (ui.reencounterCount == null) {
                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = CW.primary)
                    Spacer(Modifier.width(8.dp))
                    Text(tr("この写真を記録しています…", "Saving this photo…", "正在記錄這張照片…"), color = CW.primaryInk, fontSize = 14.sp)
                } else {
                    Icon(Icons.Outlined.Check, null, tint = CW.ok, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(
                        tr("${ui.reencounterCount}回目の出会いを記録しました", "Encounter #${ui.reencounterCount} saved", "已記錄第 ${ui.reencounterCount} 次相遇"),
                        color = CW.primaryInk, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                    )
                }
            }
            PrimaryButton(tr("図鑑で見る", "See in dex", "在圖鑑中查看"), icon = Icons.Outlined.CollectionsBookmark) { onSeeInDex(o.stickerId) }
        }
        Row(
            Modifier.fillMaxWidth().height(50.dp).clip(RoundedCornerShape(50)).background(CW.card).border(1.dp, CW.border, RoundedCornerShape(50)).pressable(onClick = onAgain),
            horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Outlined.CameraAlt, null, tint = CW.foreground, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(tr("別のものを撮る", "Shoot something else", "拍其他東西"), color = CW.foreground, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

/** Analysis failed: the photo is kept in 「解析待ち」 (web offlineSaved). */
@Composable
fun FailedStage(ui: CaptureUiState, reason: String, offline: Boolean, onRetry: () -> Unit, onAnother: () -> Unit) {
    Column(Modifier.fillMaxSize().statusBarsPadding().padding(16.dp).padding(bottom = 84.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(24.dp)).background(Color.Black)) {
            ui.photo?.let { Image(it.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().alpha(0.55f)) }
        }
        Spacer(Modifier.height(16.dp))
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(CW.card).padding(18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(if (offline) Icons.Outlined.WifiOff else Icons.Outlined.AutoAwesome, null, tint = CW.primary, modifier = Modifier.size(34.dp))
            Spacer(Modifier.height(8.dp))
            Text(tr("写真は「解析待ち」に保存しました", "Photo kept in “Waiting”", "照片已存到「等待分析」"), color = CW.foreground, fontSize = 17.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
            Spacer(Modifier.height(4.dp))
            Text(reason, color = CW.muted, fontSize = 14.sp, textAlign = TextAlign.Center)
            Spacer(Modifier.height(14.dp))
            PrimaryButton(tr("いますぐもう一度試す", "Try again now", "立即重試"), icon = Icons.Outlined.Refresh, onClick = onRetry)
            Text(
                tr("もう一枚撮る", "Take another", "再拍一張"), color = CW.primaryInk, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 4.dp).pressable(onClick = onAnother).padding(12.dp),
            )
        }
    }
}

/** The catch landed in the dex: the sticker drops in and bounces, then the way to its page (iOS CatchLanding). */
@Composable
fun CaughtStage(sticker: Sticker, cutout: Bitmap?, onOpen: () -> Unit, onAgain: () -> Unit) {
    val haptic = LocalHapticFeedback.current
    val drop = remember { Animatable(-1f) }
    var confetti by remember { mutableStateOf(false) }
    LaunchedEffect(sticker.id) {
        drop.animateTo(0f, spring(dampingRatio = 0.42f, stiffness = Spring.StiffnessLow))
    }
    LaunchedEffect(sticker.id) {
        kotlinx.coroutines.delay(260)
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        confetti = true
    }
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(CW.navyTop, CW.navyDeep)))) {
        LightRays(Modifier.fillMaxSize().alpha(0.5f))
        Confetti(confetti, Modifier.fillMaxSize())
        Column(Modifier.fillMaxSize().statusBarsPadding().padding(24.dp).padding(bottom = 84.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.height(28.dp))
            Text(tr("図鑑に入りました！", "Added to your dex!", "已加入圖鑑！"), color = CW.gold, fontSize = 30.sp, fontWeight = FontWeight.Black)
            Spacer(Modifier.height(20.dp))
            Box(
                Modifier.weight(1f).fillMaxWidth().graphicsLayer { translationY = drop.value * 600.dp.toPx(); rotationZ = -3f + drop.value * 12f },
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    Modifier.rotate(-3f).shadow(30.dp, RoundedCornerShape(12.dp), spotColor = CW.gold).background(Color(0xFFFCF8F1), RoundedCornerShape(12.dp)).padding(14.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box(Modifier.size(220.dp), contentAlignment = Alignment.Center) {
                        if (cutout != null) StickerCutout(cutout, Modifier.fillMaxSize())
                        else StickerImage(sticker, Modifier.fillMaxSize().clip(RoundedCornerShape(8.dp)), contentScale = ContentScale.Crop, emojiSize = 90)
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(sticker.word?.headword.orEmpty(), fontFamily = CW.hand, fontSize = 34.sp, color = CW.foreground)
                    Text(readingOf(sticker.word?.readingZhuyin, sticker.word?.pinyin), fontSize = 14.sp, color = CW.primaryInk)
                    sticker.locationName?.let { Text("📍 $it", fontSize = 12.sp, color = CW.muted) }
                }
            }
            PrimaryButton(tr("単語のページを見る", "Open the word", "查看單字頁面"), icon = Icons.Outlined.MenuBook, onClick = onOpen)
            Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.CameraAlt, null, tint = Color(0xCCFFFFFF), modifier = Modifier.size(18.dp))
                Text(
                    tr("続けて撮る", "Catch another", "繼續拍攝"), color = Color(0xCCFFFFFF), fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.pressable(onClick = onAgain).padding(12.dp),
                )
            }
        }
    }
}
