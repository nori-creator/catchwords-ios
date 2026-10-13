package com.rork.catchwordsandroid.ui.screens

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
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
import androidx.compose.material.icons.outlined.MenuBook
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.catchwordsandroid.data.AppGraph
import com.rork.catchwordsandroid.data.Candidate
import com.rork.catchwordsandroid.data.Category
import com.rork.catchwordsandroid.data.str
import com.rork.catchwordsandroid.data.tr
import com.rork.catchwordsandroid.ui.CaptureStage
import com.rork.catchwordsandroid.ui.components.PrimaryButton
import com.rork.catchwordsandroid.ui.components.StickerImage
import com.rork.catchwordsandroid.ui.components.pressable
import com.rork.catchwordsandroid.ui.components.readingOf
import com.rork.catchwordsandroid.ui.theme.CW
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/** The names the AI found: dots on the photo, and a list (one entry per object, other names as chips). */
@Composable
fun PickingStage(stage: CaptureStage.Picking, onPick: (Candidate) -> Unit, onBack: () -> Unit) {
    val main = remember(stage.candidates) { stage.candidates.distinctBy { it.group ?: it.key }.take(8) }
    Column(Modifier.fillMaxSize().statusBarsPadding().padding(bottom = 84.dp)) {
        TopBar(tr("どれをキャッチする？", "Which one will you catch?", "要收集哪一個？"), onBack)
        if (stage.photo != null) {
            BoxWithConstraints(
                Modifier.padding(horizontal = 16.dp).fillMaxWidth().aspectRatio(stage.photo.width.toFloat() / stage.photo.height.coerceAtLeast(1)).heightIn(max = 340.dp)
                    .clip(RoundedCornerShape(24.dp)),
            ) {
                Image(stage.photo.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                val pulse = rememberInfiniteTransition(label = "dot").animateFloat(0.8f, 1.25f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "p")
                main.forEachIndexed { i, c ->
                    val x = maxWidth * (c.point.first / 1000f).toFloat()
                    val y = maxHeight * (c.point.second / 1000f).toFloat()
                    Box(
                        Modifier.offset(x - 16.dp, y - 16.dp).size(32.dp).scale(pulse.value).clip(CircleShape)
                            .background(CW.primary.copy(alpha = 0.9f)).border(2.dp, Color.White, CircleShape).pressable { onPick(c) },
                        contentAlignment = Alignment.Center,
                    ) { Text("${i + 1}", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp) }
                }
            }
            Spacer(Modifier.height(12.dp))
        }
        LazyColumn(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            itemsIndexed(main, key = { _, c -> c.key }) { i, c ->
                val alts = stage.candidates.filter { it.group != null && it.group == c.group && it.key != c.key }
                CandidateRow(i + 1, c, alts, onPick)
            }
        }
    }
}

@Composable
private fun CandidateRow(index: Int, c: Candidate, alts: List<Candidate>, onPick: (Candidate) -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color(0x14FFFFFF)).border(1.dp, Color(0x1FFFFFFF), RoundedCornerShape(20.dp))
            .pressable(pressedScale = 0.98f) { onPick(c) }.padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(28.dp).clip(CircleShape).background(CW.primary), contentAlignment = Alignment.Center) {
                Text("$index", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(readingOf(c.zhuyin, c.pinyin), color = CW.cyan, fontSize = 12.sp)
                Text(c.headword, color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                if (c.meaning.isNotBlank()) Text(c.meaning, color = Color(0xCCFFFFFF), fontSize = 14.sp)
                if (c.distinction.isNotBlank()) Text(c.distinction, color = Color(0x99FFFFFF), fontSize = 12.sp)
            }
            if (AppGraph.dex.owned(c.headword) != null) {
                Text(tr("取得済み", "Caught", "已收集"), color = CW.gold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
        }
        if (alts.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(tr("ほかの言い方", "Also", "其他說法"), color = Color(0x99FFFFFF), fontSize = 12.sp, modifier = Modifier.align(Alignment.CenterVertically))
                alts.take(3).forEach { a ->
                    Text(
                        a.headword, color = Color.White, fontSize = 14.sp,
                        modifier = Modifier.clip(RoundedCornerShape(50)).background(Color(0x26FFFFFF)).pressable { onPick(a) }.padding(horizontal = 10.dp, vertical = 5.dp),
                    )
                }
            }
        }
    }
}

/** The card for the picked name: reading, meaning and example as soon as the server writes them, then 図鑑に追加. */
@Composable
fun CardStage(stage: CaptureStage.Card, onSave: (String) -> Unit, onBack: () -> Unit, onRetake: () -> Unit) {
    val c = stage.candidate
    val card = stage.card
    var caption by rememberSaveable(c.key) { mutableStateOf("") }
    val pop = remember { Animatable(0.85f) }
    LaunchedEffect(c.key) { pop.animateTo(1f, spring(dampingRatio = 0.5f, stiffness = Spring.StiffnessMediumLow)) }

    Column(Modifier.fillMaxSize().statusBarsPadding().imePadding().padding(bottom = 84.dp)) {
        TopBar(if (stage.owned != null) tr("再会！", "Met again!", "重逢！") else tr("新しい単語", "New word", "新單字"), onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            Column(
                Modifier.fillMaxWidth().scale(pop.value).shadow(24.dp, RoundedCornerShape(30.dp), spotColor = CW.primary).clip(RoundedCornerShape(30.dp)).background(CW.card).padding(18.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(22.dp)).background(Brush.radialGradient(listOf(Color.White, CW.accent))), contentAlignment = Alignment.Center) {
                    if (stage.photo != null) {
                        Image(stage.photo.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    } else {
                        Text(Category.emoji(card?.str("category_key") ?: c.categoryKey), fontSize = 80.sp)
                    }
                }
                Spacer(Modifier.height(14.dp))
                Text(readingOf(card?.str("reading_zhuyin") ?: c.zhuyin, card?.str("pinyin") ?: c.pinyin), color = CW.primaryInk, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(c.headword, fontSize = 46.sp, fontWeight = FontWeight.Black, color = CW.foreground)
                    Spacer(Modifier.width(8.dp))
                    Icon(
                        Icons.AutoMirrored.Outlined.VolumeUp, tr("発音を聞く", "Listen", "聆聽發音"), tint = CW.primary,
                        modifier = Modifier.size(40.dp).clip(CircleShape).background(CW.accent).pressable { AppGraph.speech.speak(c.headword, AppGraph.profile.target) }.padding(8.dp),
                    )
                }
                Text((card?.str("meaning_ja") ?: c.meaning), fontSize = 18.sp, color = CW.foreground, textAlign = TextAlign.Center)
                Spacer(Modifier.height(12.dp))
                when {
                    stage.owned != null -> Text(
                        tr("この単語はもう図鑑にあります。もう一度会えたことを記録しましょう。", "This word is already in your dex. Record that you met it again.", "這個單字已在圖鑑中，記錄這次的重逢吧。"),
                        fontSize = 14.sp, color = CW.muted, textAlign = TextAlign.Center,
                    )
                    card == null -> CardLoading()
                    else -> card.str("example_sentence")?.let { ex ->
                        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(CW.surface2).padding(14.dp)) {
                            Text(ex, fontSize = 17.sp, color = CW.foreground, fontWeight = FontWeight.Medium)
                            card.str("example_translation")?.let { Text(it, fontSize = 13.sp, color = CW.muted) }
                        }
                    }
                }
                if (stage.owned == null) {
                    Spacer(Modifier.height(12.dp))
                    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(CW.paper).border(1.dp, CW.paperEdge, RoundedCornerShape(14.dp)).padding(12.dp)) {
                        if (caption.isEmpty()) Text(tr("ひとこと（任意）", "A note (optional)", "備註（選填）"), fontFamily = CW.hand, color = CW.muted, fontSize = 17.sp)
                        BasicTextField(caption, { caption = it.take(80) }, textStyle = TextStyle(fontFamily = CW.hand, fontSize = 17.sp, color = CW.foreground), cursorBrush = SolidColor(CW.primary), modifier = Modifier.fillMaxWidth())
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
        }
        Column(Modifier.padding(horizontal = 16.dp)) {
            PrimaryButton(
                title = if (stage.owned != null) tr("再会を記録", "Record the meeting", "記錄重逢") else tr("図鑑に追加", "Add to dex", "加入圖鑑"),
                icon = Icons.Outlined.AutoAwesome,
                enabled = stage.owned != null || card != null,
                loading = stage.isSaving,
            ) { onSave(caption) }
            Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.Center) {
                Text(
                    tr("撮り直す", "Retake", "重拍"), color = Color(0xCCFFFFFF), fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.pressable(onClick = onRetake).padding(12.dp),
                )
            }
        }
    }
}

@Composable
private fun CardLoading() {
    val t = rememberInfiniteTransition(label = "card")
    val a by t.animateFloat(0.3f, 1f, infiniteRepeatable(tween(700), RepeatMode.Reverse), label = "a")
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(CW.surface2).padding(14.dp)) {
        Text(tr("例文を作っています…", "Writing an example…", "正在產生例句…"), color = CW.primaryInk, fontSize = 13.sp, modifier = Modifier.alpha(a))
        Spacer(Modifier.height(8.dp))
        Box(Modifier.fillMaxWidth().height(14.dp).clip(RoundedCornerShape(7.dp)).background(Color.White.copy(alpha = a)))
        Spacer(Modifier.height(6.dp))
        Box(Modifier.fillMaxWidth(0.6f).height(12.dp).clip(RoundedCornerShape(6.dp)).background(Color.White.copy(alpha = a)))
    }
}

/** The reward: the sticker pops in with a burst of confetti. */
@Composable
fun CaughtStage(stage: CaptureStage.Caught, onOpen: () -> Unit, onAgain: () -> Unit) {
    val haptic = LocalHapticFeedback.current
    val scale = remember { Animatable(0.2f) }
    val burst = remember { Animatable(0f) }
    LaunchedEffect(stage.sticker.id) {
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        scale.animateTo(1f, spring(dampingRatio = 0.45f, stiffness = Spring.StiffnessLow))
    }
    LaunchedEffect(stage.sticker.id) { burst.animateTo(1f, tween(1400, easing = LinearEasing)) }
    val spin = rememberInfiniteTransition(label = "rays").animateFloat(0f, 360f, infiniteRepeatable(tween(14000, easing = LinearEasing)), label = "spin")
    val pieces = remember { List(46) { Triple(Random.nextFloat() * 360f, 0.5f + Random.nextFloat() * 0.6f, Random.nextInt(5)) } }

    Box(Modifier.fillMaxSize().statusBarsPadding().padding(bottom = 84.dp)) {
        Canvas(Modifier.fillMaxSize()) {
            val center = Offset(size.width / 2, size.height * 0.38f)
            rotate(spin.value, center) {
                for (i in 0 until 12) {
                    val ang = Math.toRadians(i * 30.0)
                    drawLine(
                        Brush.linearGradient(listOf(CW.gold.copy(alpha = 0.25f), Color.Transparent), center, Offset(center.x + cos(ang).toFloat() * size.width, center.y + sin(ang).toFloat() * size.width)),
                        center, Offset(center.x + cos(ang).toFloat() * size.width, center.y + sin(ang).toFloat() * size.width), 60f,
                    )
                }
            }
            val colors = listOf(CW.gold, CW.cyan, Color(0xFFFF7EB6), Color(0xFF4ADE80), Color.White)
            pieces.forEach { (deg, speed, ci) ->
                val r = Math.toRadians(deg.toDouble())
                val d = burst.value * speed * size.width * 0.75f
                val p = Offset(center.x + cos(r).toFloat() * d, center.y + sin(r).toFloat() * d + burst.value * burst.value * 240f)
                drawCircle(colors[ci].copy(alpha = 1f - burst.value * 0.7f), radius = 7f, center = p)
            }
        }
        Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.height(40.dp))
            Text(
                if (stage.reencounter) tr("再会！", "Met again!", "重逢！") else tr("キャッチ！", "Caught!", "收集成功！"),
                color = CW.gold, fontSize = 40.sp, fontWeight = FontWeight.Black,
            )
            if (stage.reencounter && stage.count != null) {
                Text(tr("${stage.count}回目の出会い", "Encounter #${stage.count}", "第 ${stage.count} 次相遇"), color = Color(0xCCFFFFFF), fontSize = 15.sp)
            }
            Spacer(Modifier.height(24.dp))
            Column(
                Modifier.scale(scale.value).rotate(-3f).shadow(30.dp, RoundedCornerShape(10.dp), spotColor = CW.gold).background(Color.White, RoundedCornerShape(10.dp)).padding(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                StickerImage(stage.sticker, Modifier.size(210.dp).background(Color(0xFFF7F4EE)), contentScale = ContentScale.Crop, emojiSize = 90)
                Spacer(Modifier.height(6.dp))
                Text(stage.sticker.word?.headword.orEmpty(), fontFamily = CW.hand, fontSize = 34.sp, color = CW.foreground)
                Text(readingOf(stage.sticker.word?.readingZhuyin, stage.sticker.word?.pinyin), fontSize = 14.sp, color = CW.primaryInk)
            }
            Spacer(Modifier.weight(1f))
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

@Composable
private fun TopBar(title: String, onBack: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(44.dp).clip(CircleShape).background(Color(0x1FFFFFFF)).pressable(onClick = onBack), contentAlignment = Alignment.Center) {
            Icon(Icons.AutoMirrored.Outlined.ArrowBack, tr("戻る", "Back", "返回"), tint = Color.White)
        }
        Spacer(Modifier.width(12.dp))
        Text(title, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
    }
}

